"""
Schedule API — тонкий read-only слой над кэшем бота расписания.
Лежит в /root/schedule_bot, чтобы переиспользовать groups.py и journal.py.
Запускается как systemd-сервис schedule_api.service на 127.0.0.1:8092,
наружу проксируется nginx: https://vpn-ornux.space/sapi/
"""
import os
import re
import json
import asyncio
import subprocess
from datetime import datetime

from fastapi import FastAPI, HTTPException, Header, Body
from fastapi.middleware.cors import CORSMiddleware

from groups import GROUPS, ID_TO_NAME
import journal

CACHE_DIR = "/root/schedule_bot/cache"
ADMIN_PASSWORD = os.environ.get("SAPI_ADMIN_PASSWORD", "kogpk2026")

app = FastAPI(title="Schedule API", docs_url="/docs", root_path="/sapi")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

RU_MONTHS = {
    "января": 1, "февраля": 2, "марта": 3, "апреля": 4, "мая": 5, "июня": 6,
    "июля": 7, "августа": 8, "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12,
}


# ─── helpers ─────────────────────────────────────────────────────────────────
def _load(path: str):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except Exception:
        return None


def _week_keys():
    """ISO-ключи текущей и следующей недели, как пишет cache_updater."""
    now = datetime.now()
    from datetime import timedelta
    nxt = now + timedelta(days=7)
    a = now.isocalendar()
    b = nxt.isocalendar()
    return f"{a[0]}-{a[1]:02d}", f"{b[0]}-{b[1]:02d}"


def _iso_date(day_title: str) -> str | None:
    """'08 июня 2026, понедельник' -> '2026-06-08'."""
    m = re.match(r"^\s*(\d{1,2})\s+([А-Яа-яЁё]+)\s+(\d{4})", day_title)
    if not m:
        return None
    d, mon, y = int(m.group(1)), m.group(2).lower(), int(m.group(3))
    month = RU_MONTHS.get(mon)
    if not month:
        return None
    return f"{y:04d}-{month:02d}-{d:02d}"


def _days_to_list(day_map: dict) -> list:
    """{date_title: [lessons]} -> sorted list [{title, date, lessons}]."""
    out = []
    for title, lessons in (day_map or {}).items():
        out.append({"title": title, "date": _iso_date(title), "lessons": lessons or []})
    out.sort(key=lambda x: (x["date"] or x["title"]))
    return out


def _resolve_group(group: str):
    """Принимает имя ('РН-24') или id ('106465'). Возвращает (id, name)."""
    if group in GROUPS:
        return GROUPS[group], group
    if group in ID_TO_NAME:
        return group, ID_TO_NAME[group]
    return None, None


# ─── public ──────────────────────────────────────────────────────────────────
@app.get("/health")
def health():
    return {"ok": True, "time": datetime.now().isoformat()}


@app.get("/groups")
def groups():
    items = [{"name": n, "id": i} for n, i in GROUPS.items()]
    items.sort(key=lambda x: x["name"])
    return {"groups": items}


@app.get("/schedule")
def schedule(group: str):
    gid, gname = _resolve_group(group)
    if not gid:
        raise HTTPException(404, "group not found")
    wk0, wk1 = _week_keys()
    days = []
    # текущая неделя (slot 0) + следующая (slot 1)
    for wk, slot in ((wk0, 0), (wk1, 1)):
        data = _load(os.path.join(CACHE_DIR, f"{wk}-{slot}.json")) or {}
        gdata = data.get(gid)
        if gdata:
            days.extend(_days_to_list(gdata))
    days.sort(key=lambda x: (x["date"] or x["title"]))
    return {"group_id": gid, "group_name": gname, "days": days}


@app.get("/teachers")
def teachers():
    lst = _load(os.path.join(CACHE_DIR, "teachers_list.json")) or []
    return {"teachers": lst}


@app.get("/teacher")
def teacher(name: str):
    wk0, wk1 = _week_keys()
    days = []
    found = False
    for wk in (wk0, wk1):
        data = _load(os.path.join(CACHE_DIR, f"teachers_{wk}.json")) or {}
        tdata = data.get(name)
        if tdata is not None:
            found = True
            days.extend(_days_to_list(tdata))
    if not found:
        raise HTTPException(404, "teacher not found")
    days.sort(key=lambda x: (x["date"] or x["title"]))
    return {"teacher": name, "days": days}


@app.post("/journal")
async def journal_grades(ticket_id: str = Body(..., embed=True)):
    ticket_id = str(ticket_id).strip()
    if not re.match(r"^\d{1,12}$", ticket_id):
        raise HTTPException(400, "bad ticket_id")
    # живой забор с сайта (он же кэширует), при сбое — отдаём кэш если есть
    data = None
    try:
        data = await asyncio.wait_for(journal.fetch_grades(ticket_id), timeout=20)
    except Exception:
        data = None
    if not data:
        data = journal.load_journal_cache(ticket_id)
    if not data:
        raise HTTPException(502, "journal unavailable")
    return data


# ─── admin ───────────────────────────────────────────────────────────────────
def _check_admin(password: str | None):
    if not password or password != ADMIN_PASSWORD:
        raise HTTPException(401, "unauthorized")


def _file_age(path: str):
    try:
        return round((datetime.now().timestamp() - os.path.getmtime(path)) / 60, 1)
    except OSError:
        return None


@app.post("/admin/login")
def admin_login(password: str = Body(..., embed=True)):
    _check_admin(password)
    return {"ok": True}


@app.get("/admin/status")
def admin_status(x_admin_password: str | None = Header(default=None)):
    _check_admin(x_admin_password)
    wk0, wk1 = _week_keys()
    groups_status = _load(os.path.join(CACHE_DIR, "updater_status.json"))
    teachers_status = _load(os.path.join(CACHE_DIR, "teachers_status.json"))
    return {
        "groups_updater": groups_status,
        "teachers_updater": teachers_status,
        "cache_age_min": {
            "groups_week0": _file_age(os.path.join(CACHE_DIR, f"{wk0}-0.json")),
            "groups_week1": _file_age(os.path.join(CACHE_DIR, f"{wk1}-1.json")),
            "teachers_week0": _file_age(os.path.join(CACHE_DIR, f"teachers_{wk0}.json")),
        },
        "groups_total": len(GROUPS),
    }


@app.post("/admin/refresh")
def admin_refresh(target: str = Body("groups", embed=True),
                  x_admin_password: str | None = Header(default=None)):
    _check_admin(x_admin_password)
    svc = {
        "groups": "schedule_cache_updater.service",
        "teachers": "schedule_teachers_updater.service",
    }.get(target)
    if not svc:
        raise HTTPException(400, "bad target")
    try:
        subprocess.run(["systemctl", "restart", svc], check=True, timeout=15)
    except Exception as e:
        raise HTTPException(500, f"restart failed: {e}")
    return {"ok": True, "restarted": svc}
