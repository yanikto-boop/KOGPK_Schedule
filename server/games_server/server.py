# -*- coding: utf-8 -*-
"""Игровой сервер КОГПК: ники, таблицы лидеров, дурак и бильярд онлайн.

Отдельный сервис (127.0.0.1:8093, наружу — /gapi/ через nginx), к боту и
API расписания отношения не имеет. Комнаты и партии живут в памяти процесса —
рестарт сервиса обрывает идущие партии; аккаунты и рекорды — в SQLite.

Протокол WebSocket /ws?token=… — JSON-сообщения {"t": тип, ...}:
  клиент → rooms | create{players,deck,transfer,throw_all,private} | join{room}
           | leave | ready (= rematch) | throw{card} | defend{card,idx} | transfer{card}
           | take | pass | ping
  сервер → rooms{rooms} | room{room,game,deadline,result} | error{msg} | pong

Бильярд — отдельный WebSocket /pws?token=… (см. раздел «бильярд» ниже),
нарды — /nws?token=… (раздел «нарды»).
"""
import asyncio
import copy
import hashlib
import json
import urllib.request
import logging
import os
import random
import re
import secrets
import sqlite3
import string
import time

from fastapi import FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

import billiards
import durak
import nardy

BASE = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.environ.get("GAMES_DB", os.path.join(BASE, "games.db"))
TURN_SECONDS = 30
AFTER_PASS_SECONDS = 5   # главный атакующий сказал «бито» — остальным на подкидывание
READY_WAIT = 60          # кто не нажал «Готов» за минуту при полной комнате — выходит
DISCONNECT_GRACE = 60       # столько ждём вернувшегося игрока посреди партии
LOBBY_GRACE = 15            # в ожидающей комнате — меньше

logging.basicConfig(format="%(asctime)s [%(levelname)s] %(message)s", level=logging.INFO)
log = logging.getLogger("games")
app = FastAPI()


# ─── база ────────────────────────────────────────────────────────────────────
def db():
    con = sqlite3.connect(DB_FILE)
    con.row_factory = sqlite3.Row
    return con


def init_db():
    with db() as con:
        con.execute("""CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nick TEXT NOT NULL,
            nick_key TEXT NOT NULL UNIQUE,
            nick_key2 TEXT NOT NULL DEFAULT '',
            token_hash TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            bb_best INTEGER NOT NULL DEFAULT 0,
            bb_at TEXT,
            durak_games INTEGER NOT NULL DEFAULT 0,
            durak_wins INTEGER NOT NULL DEFAULT 0,
            durak_losses INTEGER NOT NULL DEFAULT 0
        )""")
        # тег у ника в таблице лидеров («Администратор»); ставится только руками в базе
        # группа, которую игрок сам выбрал тегом (только из настоящего списка групп)
        # tag и tag_color правятся из админки (admin.vpn-ornux.space → «Теги игроков»)
        for col in ("tag", "group_tag", "tag_color"):
            try:
                con.execute(f"ALTER TABLE users ADD COLUMN {col} TEXT NOT NULL DEFAULT ''")
            except sqlite3.OperationalError:
                pass
        # бильярд онлайн (с ботом не считается)
        for col in ("pool_games", "pool_wins", "nardy_games", "nardy_wins"):
            try:
                con.execute(f"ALTER TABLE users ADD COLUMN {col} INTEGER NOT NULL DEFAULT 0")
            except sqlite3.OperationalError:
                pass


init_db()


# ─── ники ────────────────────────────────────────────────────────────────────
# Латиница, похожая на кириллицу, и цифры-подмены — чтобы «Vasya» не прошёл
# рядом с «Васya», а «Пupa» рядом с «Пира».
_LOOK = str.maketrans({
    "a": "а", "b": "в", "c": "с", "e": "е", "h": "н", "k": "к", "m": "м", "o": "о",
    "p": "р", "t": "т", "x": "х", "y": "у", "u": "и", "n": "п", "r": "г", "ё": "е",
    "0": "о", "3": "з", "4": "ч", "6": "б", "1": "i", "l": "i", "|": "i",
})
NICK_RE = re.compile(r"^[A-Za-zА-Яа-яЁё0-9_\- ]{3,16}$")
_BAD = ("хуи", "хуе", "хуя", "пизд", "ебат", "ебан", "ебал", "еби", "ебу", "ебл", "бля", "сука", "суки",
        "мудак", "мудил", "пидор", "пидар", "гандон", "залуп", "шлюх", "дроч", "манда", "хер",
        "нигер", "нигга", "nigger", "nigga", "fuck", "shit", "админ", "аdмin", "модер", "кogпк")


# «еб» в начале слова, в том числе с приставкой: «Ебень», «Заебись», «Долбоеб».
# Слово целиком, а не подстрока ника — иначе пострадали бы «Небо», «Победа», «Себастьян».
_EB_PREFIX = ("", "за", "у", "вы", "по", "на", "про", "от", "отъ", "съ", "до", "раз", "въ", "под",
              "при", "об", "долбо", "недо", "пере", "из", "ни", "не")


def _obscene_word(word: str) -> bool:
    for k in {nick_key(word), nick_key2(word)}:
        if any(k.startswith(p + "еб") for p in _EB_PREFIX):
            return True
    return False


def nick_key(nick: str) -> str:
    k = nick.lower().translate(_LOOK).translate(str.maketrans("йы", "ии"))
    k = re.sub(r"[^0-9a-zа-я]", "", k)
    return re.sub(r"(.)\1+", r"\1", k)  # «вааася» = «вася»


_TRANSLIT = [("shch", "щ"), ("sch", "щ"), ("sh", "ш"), ("ch", "ч"), ("zh", "ж"), ("kh", "х"),
             ("ts", "ц"), ("ya", "я"), ("yu", "ю"), ("yo", "е"), ("ye", "е"), ("ja", "я"), ("ju", "ю")]
_TR1 = str.maketrans({"a": "а", "b": "б", "v": "в", "g": "г", "d": "д", "e": "е", "z": "з", "i": "и",
                      "j": "й", "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р",
                      "s": "с", "t": "т", "u": "у", "f": "ф", "h": "х", "c": "к", "y": "ы", "w": "в",
                      "x": "кс", "q": "к"})
_TR2 = str.maketrans("ёйы", "еии")  # вторым проходом: «huy», «хуй», «хуи» — одно


def nick_key2(nick: str) -> str:
    """Транслит латиницы: «Vasya», «Vася» и «Вася» — один ник."""
    k = nick.lower()
    for a, b in _TRANSLIT:
        k = k.replace(a, b)
    k = k.translate(_TR1).translate(_TR2)
    k = re.sub(r"[^0-9а-я]", "", k)
    return re.sub(r"(.)\1+", r"\1", k)


def nick_taken(nick: str, me: int | None = None) -> bool:
    k1, k2 = nick_key(nick), nick_key2(nick)
    with db() as con:
        return bool(con.execute(
            "SELECT 1 FROM users WHERE (nick_key IN (?,?) OR nick_key2 IN (?,?)) AND id IS NOT ?",
            (k1, k2, k1, k2, me)).fetchone())


def check_nick(nick: str) -> str:
    nick = re.sub(r"\s+", " ", (nick or "").strip())
    if not NICK_RE.match(nick):
        raise HTTPException(400, "Ник: 3–16 символов, буквы, цифры, пробел, _ и -")
    key = nick_key(nick)
    if len(key) < 3:
        raise HTTPException(400, "Слишком короткий ник")
    loose = key.replace("i", "и")
    if any(b in k for b in _BAD for k in (key, loose, nick_key2(nick))) or \
            any(_obscene_word(w) for w in re.split(r"[^A-Za-zА-Яа-яЁё0-9|]+", nick) if w):
        raise HTTPException(400, "Такой ник нельзя")
    return nick


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def user_by_token(token: str | None):
    if not token:
        return None
    with db() as con:
        return con.execute("SELECT * FROM users WHERE token_hash=?", (_hash(token),)).fetchone()


def auth(authorization: str | None):
    tok = (authorization or "").removeprefix("Bearer ").strip()
    u = user_by_token(tok)
    if not u:
        raise HTTPException(401, "Нужен ник")
    return u


_rate: dict = {}


def rate_limit(key: str, per_seconds: float, burst: int = 1):
    if os.environ.get("GAMES_TEST"):
        return
    now = time.monotonic()
    hits = [t for t in _rate.get(key, []) if now - t < per_seconds]
    if len(hits) >= burst:
        raise HTTPException(429, "Слишком часто, попробуйте позже")
    hits.append(now)
    _rate[key] = hits


class NickIn(BaseModel):
    nick: str


class ScoreIn(BaseModel):
    score: int


def _ip(req: Request) -> str | None:
    """Настоящий IP клиента или None. За xray+nginx (unix-сокет) его может не быть."""
    ip = (req.headers.get("x-real-ip") or "").strip()
    if ip and ip not in ("unix:", "127.0.0.1", "::1") and not ip.startswith("unix"):
        return ip
    return None


@app.get("/whoami")
def whoami(req: Request):
    return {"ip": _ip(req), "x_real_ip": req.headers.get("x-real-ip"),
            "xff": req.headers.get("x-forwarded-for")}


@app.post("/register")
def register(body: NickIn, req: Request):
    # Попытки (в т.ч. «занят»/«нельзя») — мягко, от перебора; в лимит 5 в час
    # идут только созданные аккаунты: в колледже многие за одним Wi-Fi.
    ip = _ip(req) or "unknown"
    rate_limit("try:" + ip, 600, burst=30)
    ok_key = "reg:" + ip
    now = time.monotonic()
    if len([t for t in _rate.get(ok_key, []) if now - t < 3600]) >= 5:
        raise HTTPException(429, "Слишком много новых ников с этой сети, попробуйте позже")
    nick = check_nick(body.nick)
    token = secrets.token_urlsafe(32)
    if nick_taken(nick):
        raise HTTPException(409, "Такой ник уже занят")
    try:
        with db() as con:
            cur = con.execute("INSERT INTO users (nick, nick_key, nick_key2, token_hash) VALUES (?,?,?,?)",
                              (nick, nick_key(nick), nick_key2(nick), _hash(token)))
            uid = cur.lastrowid
    except sqlite3.IntegrityError:
        raise HTTPException(409, "Такой ник уже занят")
    rate_limit(ok_key, 3600, burst=6)  # засчитываем созданный аккаунт
    log.info("register %s %s ip=%s", uid, nick, ip)
    return {"id": uid, "nick": nick, "token": token}


@app.post("/rename")
def rename(body: NickIn, authorization: str | None = Header(None)):
    u = auth(authorization)
    rate_limit(f"ren:{u['id']}", 600, burst=3)
    nick = check_nick(body.nick)
    if nick_taken(nick, u["id"]):
        raise HTTPException(409, "Такой ник уже занят")
    try:
        with db() as con:
            con.execute("UPDATE users SET nick=?, nick_key=?, nick_key2=? WHERE id=?",
                        (nick, nick_key(nick), nick_key2(nick), u["id"]))
    except sqlite3.IntegrityError:
        raise HTTPException(409, "Такой ник уже занят")
    return {"id": u["id"], "nick": nick}


# ─── тег-группа ──────────────────────────────────────────────────────────────
GROUPS_URL = os.environ.get("GAMES_GROUPS_URL", "http://127.0.0.1:8092/groups")
_groups_cache: dict = {"at": 0.0, "names": set()}


def college_groups() -> set:
    """Названия групп из API расписания, кэш на час. GAMES_GROUPS — список для тестов."""
    if os.environ.get("GAMES_GROUPS"):
        return set(os.environ["GAMES_GROUPS"].split(","))
    if time.time() - _groups_cache["at"] > 3600 or not _groups_cache["names"]:
        try:
            with urllib.request.urlopen(GROUPS_URL, timeout=5) as r:
                names = {g["name"] for g in json.loads(r.read())["groups"]}
            if names:
                _groups_cache.update(at=time.time(), names=names)
        except Exception:
            log.warning("groups list unavailable")
    return _groups_cache["names"]


class GroupIn(BaseModel):
    group: str


@app.post("/group_tag")
def group_tag(body: GroupIn, authorization: str | None = Header(None)):
    u = auth(authorization)
    rate_limit(f"gt:{u['id']}", 3)
    g = body.group.strip()
    if g and g not in college_groups():
        raise HTTPException(400, "Такой группы нет")
    with db() as con:
        con.execute("UPDATE users SET group_tag=? WHERE id=?", (g, u["id"]))
    return {"group": g}


@app.get("/check_nick")
def check_nick_free(nick: str):
    return {"free": not nick_taken(check_nick(nick))}


def _me(u):
    return {"id": u["id"], "nick": u["nick"], "bb_best": u["bb_best"],
            "durak_games": u["durak_games"], "durak_wins": u["durak_wins"],
            "durak_losses": u["durak_losses"], "pool_games": u["pool_games"], "pool_wins": u["pool_wins"],
            "nardy_games": u["nardy_games"], "nardy_wins": u["nardy_wins"],
            "tag": u["tag"], "tag_color": u["tag_color"], "group": u["group_tag"]}


@app.get("/me")
def me(authorization: str | None = Header(None)):
    return _me(auth(authorization))


# ─── Block Boom ──────────────────────────────────────────────────────────────
BB_MAX = 5_000_000   # выше — явно подделка


@app.post("/bb/score")
def bb_score(body: ScoreIn, authorization: str | None = Header(None)):
    u = auth(authorization)
    rate_limit(f"bb:{u['id']}", 5)
    if not 0 <= body.score <= BB_MAX:
        raise HTTPException(400, "Странный счёт")
    with db() as con:
        con.execute("UPDATE users SET bb_best=?, bb_at=datetime('now') WHERE id=? AND bb_best<?",
                    (body.score, u["id"], body.score))
        best = con.execute("SELECT bb_best FROM users WHERE id=?", (u["id"],)).fetchone()[0]
    return {"best": best}


def _top(col: str, order: str, limit: int, uid, where: str):
    limit = max(1, min(limit, 100))
    with db() as con:
        rows = con.execute(f"SELECT id, nick, tag, tag_color, group_tag, {col} FROM users WHERE {where} ORDER BY {order} LIMIT ?",
                           (limit,)).fetchall()
        mine = None
        if uid:
            r = con.execute(f"SELECT * FROM users WHERE id=?", (uid,)).fetchone()
            if r:
                above = con.execute(f"SELECT COUNT(*) FROM users WHERE {where} AND ({order_key(order, r)})").fetchone()[0]
                mine = {"rank": above + 1, "nick": r["nick"], "tag": r["tag"], "tag_color": r["tag_color"],
                        "group": r["group_tag"], **{k: r[k] for k in col.split(", ")}}
    return [{"rank": i + 1, "nick": r["nick"], "tag": r["tag"], "tag_color": r["tag_color"], "group": r["group_tag"],
             "me": r["id"] == uid, **{k: r[k] for k in col.split(", ")}}
            for i, r in enumerate(rows)], mine


def order_key(order: str, r) -> str:
    # «кто выше меня» для строки r при заданной сортировке
    if order.startswith("bb_best"):
        return f"bb_best > {int(r['bb_best'])} OR (bb_best = {int(r['bb_best'])} AND id < {int(r['id'])})"
    if order.startswith("nardy_wins"):
        return (f"nardy_wins > {int(r['nardy_wins'])} OR (nardy_wins = {int(r['nardy_wins'])} AND "
                f"(nardy_games < {int(r['nardy_games'])} OR (nardy_games = {int(r['nardy_games'])} AND id < {int(r['id'])})))")
    if order.startswith("pool_wins"):
        return (f"pool_wins > {int(r['pool_wins'])} OR (pool_wins = {int(r['pool_wins'])} AND "
                f"(pool_games < {int(r['pool_games'])} OR (pool_games = {int(r['pool_games'])} AND id < {int(r['id'])})))")
    return (f"durak_wins > {int(r['durak_wins'])} OR (durak_wins = {int(r['durak_wins'])} AND "
            f"(durak_games < {int(r['durak_games'])} OR (durak_games = {int(r['durak_games'])} AND id < {int(r['id'])})))")


@app.get("/bb/top")
def bb_top(limit: int = 50, authorization: str | None = Header(None)):
    u = user_by_token((authorization or "").removeprefix("Bearer ").strip())
    top, mine = _top("bb_best", "bb_best DESC, id ASC", limit, u["id"] if u else None, "bb_best > 0")
    if mine and not u["bb_best"]:
        mine = None
    return {"top": top, "me": mine}


@app.get("/durak/top")
def durak_top(limit: int = 50, authorization: str | None = Header(None)):
    u = user_by_token((authorization or "").removeprefix("Bearer ").strip())
    top, mine = _top("durak_wins, durak_games, durak_losses", "durak_wins DESC, durak_games ASC, id ASC",
                     limit, u["id"] if u else None, "durak_games > 0")
    if mine and not u["durak_games"]:
        mine = None
    return {"top": top, "me": mine}


@app.get("/pool/top")
def pool_top(limit: int = 50, authorization: str | None = Header(None)):
    u = user_by_token((authorization or "").removeprefix("Bearer ").strip())
    top, mine = _top("pool_wins, pool_games", "pool_wins DESC, pool_games ASC, id ASC",
                     limit, u["id"] if u else None, "pool_games > 0")
    if mine and not u["pool_games"]:
        mine = None
    return {"top": top, "me": mine}


@app.get("/nardy/top")
def nardy_top(limit: int = 50, authorization: str | None = Header(None)):
    u = user_by_token((authorization or "").removeprefix("Bearer ").strip())
    top, mine = _top("nardy_wins, nardy_games", "nardy_wins DESC, nardy_games ASC, id ASC",
                     limit, u["id"] if u else None, "nardy_games > 0")
    if mine and not u["nardy_games"]:
        mine = None
    return {"top": top, "me": mine}


@app.get("/health")
def health():
    return {"ok": True, "rooms": len(rooms), "online": len(conns),
            "pool_rooms": len(prooms), "pool_online": len(pconns),
            "nardy_rooms": len(nrooms), "nardy_online": len(nconns)}


# ─── комнаты ─────────────────────────────────────────────────────────────────
class Room:
    def __init__(self, owner: int, rules: durak.Rules, private: bool):
        self.id = "".join(random.choices(string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789", k=5))
        self.owner = owner
        self.rules = rules
        self.private = private
        self.seats: list[int] = [owner]
        self.ready: set[int] = set()
        self.game: durak.Game | None = None
        self.result = None
        self.deadline = 0.0
        self.ready_since = 0.0
        self.seen_version = -1
        self.created = time.time()

    @property
    def status(self):
        if self.game and not self.game.finished:
            return "playing"
        return "finished" if self.result else "waiting"

    def summary(self):
        return {"id": self.id, "owner": nicks.get(self.owner, "?"), "rules": self.rules.to_dict(),
                "players": [nicks.get(p, "?") for p in self.seats], "status": self.status,
                "private": self.private}


rooms: dict[str, Room] = {}
user_room: dict[int, str] = {}
conns: dict[int, WebSocket] = {}
nicks: dict[int, str] = {}
gone_since: dict[int, float] = {}
proto: dict[int, int] = {}   # 1 — старый клиент без кнопки «Готов»: он готов сразу
lock = asyncio.Lock()


async def send(uid: int, msg: dict):
    ws = conns.get(uid)
    if not ws:
        return
    try:
        await ws.send_text(json.dumps(msg, ensure_ascii=False))
    except Exception:
        pass


def lobby_list():
    order = {"waiting": 0, "playing": 1, "finished": 2}
    rs = sorted((r for r in rooms.values() if not r.private), key=lambda r: (order[r.status], -r.created))
    return [r.summary() for r in rs][:100]


async def push_lobby():
    msg = {"t": "rooms", "rooms": lobby_list()}
    for uid in list(conns):
        if uid not in user_room:
            await send(uid, msg)


async def push_room(room: Room):
    left = max(0, int(room.deadline - time.time())) if room.status == "playing" else None
    info = {**room.summary(), "seats": [{"id": p, "nick": nicks.get(p, "?"), "online": p in conns,
                                          "ready": p in room.ready} for p in room.seats],
            "owner_id": room.owner}
    for uid in room.seats:
        await send(uid, {"t": "room", "room": info, "me": uid,
                         "game": room.game.view(uid) if room.game else None,
                         "deadline": left, "result": room.result})


def finish_stats(room: Room):
    g = room.game
    loser = g.loser
    with db() as con:
        for p in g.seats:
            con.execute("UPDATE users SET durak_games=durak_games+1, durak_wins=durak_wins+?, "
                        "durak_losses=durak_losses+? WHERE id=?",
                        (1 if loser is not None and p != loser else 0, 1 if p == loser else 0, p))
    room.result = {"loser": loser, "loser_nick": nicks.get(loser) if loser else None,
                   "out": [nicks.get(p, "?") for p in g.out]}
    room.ready.clear()
    log.info("room %s finished, loser=%s", room.id, loser)


async def after_change(room: Room):
    g = room.game
    if g and g.version != room.seen_version:
        room.seen_version = g.version
        room.deadline = time.time() + TURN_SECONDS
        if g.attacker in g.passed and not g.finished:
            room.deadline = time.time() + AFTER_PASS_SECONDS
        if g.finished and room.result is None:
            finish_stats(room)
    await push_room(room)


def start_game(room: Room):
    random.shuffle(room.seats)
    room.game = durak.Game(room.seats, room.rules)
    room.result = None
    room.ready.clear()
    room.seen_version = -1
    log.info("room %s start %s", room.id, room.seats)


async def legacy_ready(room: Room):
    for p in room.seats:
        if proto.get(p, 1) < 2:
            room.ready.add(p)
    if len(room.seats) == room.rules.players and room.ready >= set(room.seats):
        start_game(room)
        await after_change(room)


async def leave_room(uid: int):
    rid = user_room.pop(uid, None)
    room = rooms.get(rid)
    if not room:
        return
    if room.game and not room.game.finished:
        room.game.resign(uid)
        await after_change(room)
    room.seats.remove(uid)
    room.ready.discard(uid)
    if not room.seats:
        rooms.pop(room.id, None)
    else:
        if room.owner == uid:
            room.owner = room.seats[0]
        # итог партии остаётся на экране; новый игрок, зайдя, сбросит его
        await push_room(room)
    await send(uid, {"t": "rooms", "rooms": lobby_list()})
    await push_lobby()


async def handle(uid: int, m: dict):
    t = m.get("t")
    if t == "ping":
        await send(uid, {"t": "pong"})
        return
    if t == "rooms":
        await send(uid, {"t": "rooms", "rooms": lobby_list()})
        return
    if t == "create":
        if uid in user_room:
            raise durak.RuleError("Вы уже в комнате")
        rules = durak.Rules(int(m.get("players", 2)), int(m.get("deck", 36)),
                            bool(m.get("transfer")), m.get("throw_all", True) is not False)
        room = Room(uid, rules, bool(m.get("private")))
        while room.id in rooms:
            room.id = Room(uid, rules, room.private).id
        rooms[room.id] = room
        user_room[uid] = room.id
        if proto.get(uid, 1) < 2:
            room.ready.add(uid)
        await push_room(room)
        await push_lobby()
        return
    if t == "join":
        rid = str(m.get("room", "")).upper().strip()
        room = rooms.get(rid)
        if not room:
            raise durak.RuleError("Комната не найдена")
        if user_room.get(uid) == rid:
            await push_room(room)
            return
        if uid in user_room:
            raise durak.RuleError("Сначала выйдите из своей комнаты")
        if room.status == "playing" or len(room.seats) >= room.rules.players:
            raise durak.RuleError("Комната заполнена")
        room.seats.append(uid)
        user_room[uid] = rid
        room.ready_since = time.time()  # новичку — полная минута на «Готов»
        await legacy_ready(room)
        room.game, room.result = (None, None) if room.status == "finished" else (room.game, room.result)
        await push_room(room)
        await push_lobby()
        return
    room = rooms.get(user_room.get(uid, ""))
    if not room:
        raise durak.RuleError("Вы не в комнате")
    if t == "leave":
        await leave_room(uid)
        return
    if t in ("ready", "rematch"):
        if room.status == "playing":
            raise durak.RuleError("Партия ещё идёт")
        if not room.ready:
            room.ready_since = time.time()
        room.ready.add(uid)
        if len(room.seats) == room.rules.players and room.ready >= set(room.seats):
            start_game(room)
            await after_change(room)
            await push_lobby()
        else:
            await push_room(room)
        return
    g = room.game
    if not g or g.finished:
        raise durak.RuleError("Партия не идёт")
    card = str(m.get("card", ""))
    if t == "throw":
        g.throw(uid, card)
    elif t == "defend":
        g.defend(uid, card, int(m.get("idx", -1)))
    elif t == "transfer":
        g.transfer(uid, card)
    elif t == "take":
        g.take(uid)
    elif t == "pass":
        g.pass_(uid)
    else:
        raise durak.RuleError("Неизвестная команда")
    await after_change(room)
    if g.finished:
        await push_lobby()


@app.websocket("/ws")
async def ws_endpoint(ws: WebSocket, token: str = "", v: int = 1):
    u = user_by_token(token)
    await ws.accept()
    if not u:
        await ws.send_text(json.dumps({"t": "error", "msg": "Нужен ник", "auth": False}, ensure_ascii=False))
        await ws.close()
        return
    uid = u["id"]
    nicks[uid] = u["nick"]
    proto[uid] = v
    old = conns.get(uid)
    conns[uid] = ws
    gone_since.pop(uid, None)
    if old:
        try:
            await old.close()
        except Exception:
            pass
    async with lock:
        room = rooms.get(user_room.get(uid, ""))
        if room:
            await push_room(room)
        else:
            await send(uid, {"t": "rooms", "rooms": lobby_list()})
    stamps: list[float] = []
    try:
        while True:
            raw = await ws.receive_text()
            now = time.monotonic()
            stamps = [s for s in stamps if now - s < 2] + [now]
            if len(stamps) > 20 and not os.environ.get("GAMES_TEST"):
                continue  # флуд — молча отбрасываем
            try:
                m = json.loads(raw)
            except ValueError:
                continue
            async with lock:
                try:
                    await handle(uid, m)
                except durak.RuleError as e:
                    await send(uid, {"t": "error", "msg": str(e)})
                except (ValueError, TypeError):
                    await send(uid, {"t": "error", "msg": "Некорректная команда"})
    except WebSocketDisconnect:
        pass
    finally:
        if conns.get(uid) is ws:
            conns.pop(uid, None)
            gone_since[uid] = time.time()
            async with lock:
                room = rooms.get(user_room.get(uid, ""))
                if room:
                    await push_room(room)


async def ticker():
    """Таймер хода и уход отключившихся."""
    while True:
        await asyncio.sleep(1)
        try:
            async with lock:
                now = time.time()
                for uid, since in list(gone_since.items()):
                    room = rooms.get(user_room.get(uid, ""))
                    if not room:
                        gone_since.pop(uid, None)
                        continue
                    grace = DISCONNECT_GRACE if room.status == "playing" else LOBBY_GRACE
                    if now - since > grace:
                        gone_since.pop(uid, None)
                        await leave_room(uid)
                for room in list(rooms.values()):
                    if (room.status != "playing" and room.ready and len(room.seats) == room.rules.players
                            and now - room.ready_since > READY_WAIT):
                        for p in [p for p in room.seats if p not in room.ready]:
                            await send(p, {"t": "error", "msg": "Вы не нажали «Готов»"})
                            await leave_room(p)
                        continue
                    g = room.game
                    if g and not g.finished and now > room.deadline:
                        for p in list(g.waiting_on()):
                            try:
                                g.auto(p)
                            except durak.RuleError:
                                pass
                        await after_change(room)
                        if g.finished:
                            await push_lobby()
        except Exception:
            log.exception("ticker")


# ─── бильярд ─────────────────────────────────────────────────────────────────
# WebSocket /pws?token=… — JSON {"t": тип, ...}:
#   клиент → rooms | create{mode,private} | bot{mode,level} | join{room} | leave | ready
#            | shot{dx,dy,power,spin,place?,ball?} | aim{dx,dy,ball?,place?,power?} | ping
#   сервер → rooms{rooms} | room{room,game,deadline,result} | shot{shot} | aim{...}
#            | error{msg} | pong
# Удар считает сервер (billiards.simulate) и шлёт «shot» с кадрами, следом «room»
# с итоговым столом — клиент проигрывает кадры и только потом показывает «room».
SHOT_SECONDS = 45
BOT_NAMES = {1: "Бот · лёгкий", 2: "Бот · средний", 3: "Бот · сильный"}


class PoolRoom:
    def __init__(self, owner: int, mode: str, private: bool, bot_level: int = 0):
        self.id = "".join(random.choices(string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789", k=5))
        self.owner = owner
        self.mode = mode
        self.private = private
        self.bot = bot_level            # 0 — живой соперник
        self.seats: list[int] = [owner] + ([-bot_level] if bot_level else [])
        self.ready: set[int] = set()
        self.game: billiards.Game | None = None
        self.result = None
        self.deadline = 0.0
        self.ready_since = 0.0
        self.seen_version = -1
        self.created = time.time()
        self.bot_for = -1               # версия партии, на которую бот уже думает

    @property
    def status(self):
        if self.game and not self.game.finished:
            return "playing"
        return "finished" if self.result else "waiting"

    def summary(self):
        return {"id": self.id, "owner": pnick(self.owner), "mode": self.mode,
                "players": [pnick(p) for p in self.seats], "status": self.status,
                "private": self.private, "bot": self.bot}


prooms: dict[str, PoolRoom] = {}
puser_room: dict[int, str] = {}
pconns: dict[int, WebSocket] = {}
pgone_since: dict[int, float] = {}
plock = asyncio.Lock()


def pnick(uid: int) -> str:
    return BOT_NAMES.get(-uid, "Бот") if uid < 0 else nicks.get(uid, "?")


async def psend(uid: int, msg: dict):
    ws = pconns.get(uid)
    if not ws:
        return
    try:
        await ws.send_text(json.dumps(msg, ensure_ascii=False, separators=(",", ":")))
    except Exception:
        pass


def plobby_list():
    order = {"waiting": 0, "playing": 1, "finished": 2}
    rs = sorted((r for r in prooms.values() if not r.private and not r.bot),
                key=lambda r: (order[r.status], -r.created))
    return [r.summary() for r in rs][:100]


async def ppush_lobby():
    msg = {"t": "rooms", "rooms": plobby_list()}
    for uid in list(pconns):
        if uid not in puser_room:
            await psend(uid, msg)


async def ppush_room(room: PoolRoom):
    left = max(0, int(room.deadline - time.time())) if room.status == "playing" else None
    if room.game and room.game.seats[room.game.turn] < 0:
        left = None   # бот думает без таймера
    info = {**room.summary(), "seats": [{"id": p, "nick": pnick(p), "online": p < 0 or p in pconns,
                                          "ready": p < 0 or p in room.ready} for p in room.seats],
            "owner_id": room.owner}
    for uid in room.seats:
        if uid > 0:
            await psend(uid, {"t": "room", "room": info, "me": uid,
                              "game": room.game.view(uid) if room.game else None,
                              "deadline": left, "result": room.result})


def pfinish(room: PoolRoom):
    g = room.game
    win = g.seats[g.winner] if g.winner is not None else None
    if not room.bot:
        with db() as con:
            for p in g.seats:
                con.execute("UPDATE users SET pool_games=pool_games+1, pool_wins=pool_wins+? WHERE id=?",
                            (1 if p == win else 0, p))
    room.result = {"winner": win, "winner_nick": pnick(win) if win is not None else None, "note": g.note}
    room.ready.clear()
    log.info("pool %s finished, winner=%s", room.id, win)


async def pafter_change(room: PoolRoom):
    g = room.game
    if g and g.version != room.seen_version:
        room.seen_version = g.version
        room.deadline = time.time() + SHOT_SECONDS
        if g.finished and room.result is None:
            pfinish(room)
    await ppush_room(room)
    if g and not g.finished and g.seats[g.turn] < 0 and room.bot_for != g.version:
        room.bot_for = g.version
        asyncio.create_task(bot_move(room))


async def bot_move(room: PoolRoom):
    """Ход бота: пауза «подумать», расчёт в потоке на копии, применение под замком."""
    try:
        await asyncio.sleep(0.6 if os.environ.get("GAMES_TEST") else 1.4)
        g = room.game
        if not g or g.finished:
            return
        version = g.version
        snap = copy.deepcopy(g)
        plan = await asyncio.to_thread(billiards.bot_shot, snap, room.bot, random.Random())
        async with plock:
            if room.game is not g or g.version != version or g.finished:
                return
            uid = g.seats[g.turn]
            # прицел бота — пусть человек видит, куда он целится
            aim = {"t": "aim", "dx": plan["dx"], "dy": plan["dy"], "ball": plan.get("ball") or 0,
                   "place": plan.get("place"), "power": plan["power"]}
            for p in room.seats:
                if p > 0:
                    await psend(p, aim)
        await asyncio.sleep(0.9)
        async with plock:
            if room.game is not g or g.version != version or g.finished:
                return
            try:
                shot = g.shoot(uid, plan["dx"], plan["dy"], plan["power"], plan.get("spin", 0),
                               plan.get("place"), plan.get("ball"))
            except billiards.RuleError:
                g.timeout()
                shot = None
            if shot:
                for p in room.seats:
                    if p > 0:
                        await psend(p, {"t": "shot", "shot": shot})
            await pafter_change(room)
    except Exception:
        log.exception("bot_move")
        # бот сломался — ход переходит человеку, чтобы партия не встала
        async with plock:
            g = room.game
            if g and not g.finished and g.seats[g.turn] < 0:
                g.timeout()
                await pafter_change(room)


def pstart(room: PoolRoom):
    room.game = billiards.Game(room.mode, room.seats)
    room.result = None
    room.ready.clear()
    room.seen_version = -1
    log.info("pool %s start %s %s", room.id, room.mode, room.seats)


async def pleave(uid: int):
    rid = puser_room.pop(uid, None)
    room = prooms.get(rid)
    if not room:
        return
    if room.game and not room.game.finished:
        room.game.resign(uid)
        await pafter_change(room)
    room.seats.remove(uid)
    room.ready.discard(uid)
    if not [p for p in room.seats if p > 0]:
        prooms.pop(room.id, None)
    else:
        if room.owner == uid:
            room.owner = room.seats[0]
        await ppush_room(room)
    await psend(uid, {"t": "rooms", "rooms": plobby_list()})
    await ppush_lobby()


def _mode(m):
    mode = str(m.get("mode", "pool"))
    if mode not in billiards.MODES:
        raise billiards.RuleError("Неизвестный вид бильярда")
    return mode


async def phandle(uid: int, m: dict):
    t = m.get("t")
    if t == "ping":
        await psend(uid, {"t": "pong"})
        return
    if t == "rooms":
        await psend(uid, {"t": "rooms", "rooms": plobby_list()})
        return
    if t in ("create", "bot"):
        if uid in puser_room:
            raise billiards.RuleError("Вы уже в комнате")
        level = 0
        if t == "bot":
            level = int(m.get("level", 2))
            if level not in BOT_NAMES:
                raise billiards.RuleError("Уровень бота: 1, 2 или 3")
        room = PoolRoom(uid, _mode(m), bool(m.get("private")) or bool(level), level)
        while room.id in prooms:
            room.id = PoolRoom(uid, room.mode, room.private).id
        prooms[room.id] = room
        puser_room[uid] = room.id
        if level:
            pstart(room)
            await pafter_change(room)
        else:
            await ppush_room(room)
            await ppush_lobby()
        return
    if t == "join":
        rid = str(m.get("room", "")).upper().strip()
        room = prooms.get(rid)
        if not room or room.bot:
            raise billiards.RuleError("Комната не найдена")
        if puser_room.get(uid) == rid:
            await ppush_room(room)
            return
        if uid in puser_room:
            raise billiards.RuleError("Сначала выйдите из своей комнаты")
        if room.status == "playing" or len(room.seats) >= 2:
            raise billiards.RuleError("Комната заполнена")
        room.seats.append(uid)
        puser_room[uid] = rid
        room.ready_since = time.time()
        if room.status == "finished":
            room.game, room.result = None, None
        await ppush_room(room)
        await ppush_lobby()
        return
    room = prooms.get(puser_room.get(uid, ""))
    if not room:
        raise billiards.RuleError("Вы не в комнате")
    if t == "leave":
        await pleave(uid)
        return
    if t == "ready":
        if room.status == "playing":
            raise billiards.RuleError("Партия ещё идёт")
        if room.bot:
            pstart(room)
            await pafter_change(room)
            return
        if not room.ready:
            room.ready_since = time.time()
        room.ready.add(uid)
        if len(room.seats) == 2 and room.ready >= set(room.seats):
            pstart(room)
            await pafter_change(room)
            await ppush_lobby()
        else:
            await ppush_room(room)
        return
    g = room.game
    if not g or g.finished:
        raise billiards.RuleError("Партия не идёт")
    if t == "aim":
        if g.seat_of(uid) != g.turn:
            return
        msg = {"t": "aim", "dx": float(m.get("dx", 0)), "dy": float(m.get("dy", 0)),
               "ball": int(m.get("ball") or 0), "power": float(m.get("power") or 0)}
        pl = m.get("place")
        if isinstance(pl, list) and len(pl) == 2:
            msg["place"] = [float(pl[0]), float(pl[1])]
        for p in room.seats:
            if p > 0 and p != uid:
                await psend(p, msg)
        return
    if t == "shot":
        place = m.get("place")
        if place is not None and not (isinstance(place, list) and len(place) == 2):
            raise billiards.RuleError("Некорректное место битка")
        shot = g.shoot(uid, m.get("dx"), m.get("dy"), m.get("power"), m.get("spin") or 0, place, m.get("ball"))
        for p in room.seats:
            if p > 0:
                await psend(p, {"t": "shot", "shot": shot})
        await pafter_change(room)
        if g.finished:
            await ppush_lobby()
        return
    raise billiards.RuleError("Неизвестная команда")


@app.websocket("/pws")
async def pws_endpoint(ws: WebSocket, token: str = ""):
    u = user_by_token(token)
    await ws.accept()
    if not u:
        await ws.send_text(json.dumps({"t": "error", "msg": "Нужен ник", "auth": False}, ensure_ascii=False))
        await ws.close()
        return
    uid = u["id"]
    nicks[uid] = u["nick"]
    old = pconns.get(uid)
    pconns[uid] = ws
    pgone_since.pop(uid, None)
    if old:
        try:
            await old.close()
        except Exception:
            pass
    async with plock:
        room = prooms.get(puser_room.get(uid, ""))
        if room:
            await ppush_room(room)
        else:
            await psend(uid, {"t": "rooms", "rooms": plobby_list()})
    stamps: list[float] = []
    try:
        while True:
            raw = await ws.receive_text()
            now = time.monotonic()
            stamps = [s for s in stamps if now - s < 2] + [now]
            if len(stamps) > 30 and not os.environ.get("GAMES_TEST"):
                continue  # флуд (прицел шлётся часто, поэтому порог выше, чем у дурака)
            try:
                m = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(m, dict):
                continue
            async with plock:
                try:
                    await phandle(uid, m)
                except billiards.RuleError as e:
                    await psend(uid, {"t": "error", "msg": str(e)})
                except (ValueError, TypeError):
                    await psend(uid, {"t": "error", "msg": "Некорректная команда"})
    except WebSocketDisconnect:
        pass
    finally:
        if pconns.get(uid) is ws:
            pconns.pop(uid, None)
            pgone_since[uid] = time.time()
            async with plock:
                room = prooms.get(puser_room.get(uid, ""))
                if room:
                    await ppush_room(room)


async def pool_ticker():
    """Таймер удара, «Готов» и уход отключившихся — как у дурака."""
    while True:
        await asyncio.sleep(1)
        try:
            async with plock:
                now = time.time()
                for uid, since in list(pgone_since.items()):
                    room = prooms.get(puser_room.get(uid, ""))
                    if not room:
                        pgone_since.pop(uid, None)
                        continue
                    grace = DISCONNECT_GRACE if room.status == "playing" else LOBBY_GRACE
                    if room.bot:
                        grace = 300   # с ботом можно свернуть приложение подольше
                    if now - since > grace:
                        pgone_since.pop(uid, None)
                        await pleave(uid)
                for room in list(prooms.values()):
                    if (room.status != "playing" and not room.bot and room.ready and len(room.seats) == 2
                            and now - room.ready_since > READY_WAIT):
                        for p in [p for p in room.seats if p not in room.ready]:
                            await psend(p, {"t": "error", "msg": "Вы не нажали «Готов»"})
                            await pleave(p)
                        continue
                    g = room.game
                    if g and not g.finished and g.seats[g.turn] > 0 and now > room.deadline:
                        g.timeout()
                        await pafter_change(room)
                        if g.finished:
                            await ppush_lobby()
        except Exception:
            log.exception("pool_ticker")


# ─── нарды ───────────────────────────────────────────────────────────────────
# WebSocket /nws?token=… — длинные нарды 1×1 или с ботом, JSON {"t": тип, ...}:
#   клиент → rooms | create{private} | bot{level} | join{room} | leave | ready
#            | move{from,to} | undo | ping
#   сервер → rooms{rooms} | room{room,game,deadline,result} | error{msg} | pong
# Ход — одна шашка на одну кость; кости бросает сервер. Доска в «game» — в
# координатах того, кому она отправлена (0 — его голова, 24 — выброшенные).
NARDY_STEP_SECONDS = 40


class NardyRoom:
    def __init__(self, owner: int, private: bool, bot_level: int = 0):
        self.id = "".join(random.choices(string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789", k=5))
        self.owner = owner
        self.private = private
        self.bot = bot_level            # 0 — живой соперник
        self.seats: list[int] = [owner] + ([-bot_level] if bot_level else [])
        self.ready: set[int] = set()
        self.game: nardy.Game | None = None
        self.result = None
        self.deadline = 0.0
        self.ready_since = 0.0
        self.seen_version = -1
        self.created = time.time()
        self.bot_for = -1               # версия партии, на которую бот уже ходит

    @property
    def status(self):
        if self.game and not self.game.finished:
            return "playing"
        return "finished" if self.result else "waiting"

    def summary(self):
        return {"id": self.id, "owner": pnick(self.owner),
                "players": [pnick(p) for p in self.seats], "status": self.status,
                "private": self.private, "bot": self.bot}


nrooms: dict[str, NardyRoom] = {}
nuser_room: dict[int, str] = {}
nconns: dict[int, WebSocket] = {}
ngone_since: dict[int, float] = {}
nlock = asyncio.Lock()


async def nsend(uid: int, msg: dict):
    ws = nconns.get(uid)
    if not ws:
        return
    try:
        await ws.send_text(json.dumps(msg, ensure_ascii=False, separators=(",", ":")))
    except Exception:
        pass


def nlobby_list():
    order = {"waiting": 0, "playing": 1, "finished": 2}
    rs = sorted((r for r in nrooms.values() if not r.private and not r.bot),
                key=lambda r: (order[r.status], -r.created))
    return [r.summary() for r in rs][:100]


async def npush_lobby():
    msg = {"t": "rooms", "rooms": nlobby_list()}
    for uid in list(nconns):
        if uid not in nuser_room:
            await nsend(uid, msg)


async def npush_room(room: NardyRoom):
    left = max(0, int(room.deadline - time.time())) if room.status == "playing" else None
    if room.game and room.game.seats[room.game.turn] < 0:
        left = None   # бот ходит без таймера
    info = {**room.summary(), "seats": [{"id": p, "nick": pnick(p), "online": p < 0 or p in nconns,
                                          "ready": p < 0 or p in room.ready} for p in room.seats],
            "owner_id": room.owner}
    for uid in room.seats:
        if uid > 0:
            await nsend(uid, {"t": "room", "room": info, "me": uid,
                              "game": room.game.view(uid) if room.game else None,
                              "deadline": left, "result": room.result})


def nfinish(room: NardyRoom):
    g = room.game
    win = g.seats[g.winner] if g.winner is not None else None
    if not room.bot:
        with db() as con:
            for p in g.seats:
                con.execute("UPDATE users SET nardy_games=nardy_games+1, nardy_wins=nardy_wins+? WHERE id=?",
                            (1 if p == win else 0, p))
    room.result = {"winner": win, "winner_nick": pnick(win) if win is not None else None,
                   "note": g.note, "mars": g.mars}
    room.ready.clear()
    log.info("nardy %s finished, winner=%s mars=%s", room.id, win, g.mars)


async def nafter_change(room: NardyRoom):
    g = room.game
    if g and g.version != room.seen_version:
        room.seen_version = g.version
        room.deadline = time.time() + NARDY_STEP_SECONDS
        if g.finished and room.result is None:
            nfinish(room)
    await npush_room(room)
    if g and not g.finished and g.seats[g.turn] < 0 and room.bot_for != g.version:
        room.bot_for = g.version
        asyncio.create_task(nbot_move(room))


async def nbot_move(room: NardyRoom):
    """Ход бота: пауза, расчёт на копии в потоке, потом шашки по одной — чтобы было видно."""
    fast = bool(os.environ.get("GAMES_TEST"))
    try:
        await asyncio.sleep(0.3 if fast else 1.1)
        g = room.game
        if not g or g.finished:
            return
        version = g.version
        snap = copy.deepcopy(g)
        plan = await asyncio.to_thread(nardy.bot_plan, snap, room.bot, random.Random())
        for k, (frm, d) in enumerate(plan):
            if k:
                await asyncio.sleep(0.15 if fast else 0.65)
            async with nlock:
                if room.game is not g or g.version != version or g.finished:
                    return
                g.step(g.seats[g.turn], frm, d)
                version = g.version
                if k < len(plan) - 1:
                    room.bot_for = version   # ход ещё не доигран — вторую задачу не запускать
                await nafter_change(room)
    except Exception:
        log.exception("nbot_move")
        # бот сломался — доиграть его ход «по таймеру», чтобы партия не встала
        async with nlock:
            g = room.game
            if g and not g.finished and g.seats[g.turn] < 0:
                g.timeout()
                await nafter_change(room)


def nstart(room: NardyRoom):
    # белые (первое место) — по очереди: в следующей партии цвета меняются
    seats = list(room.seats)
    if room.game is not None:
        seats = list(reversed(room.game.seats)) if set(room.game.seats) == set(seats) else seats
    room.game = nardy.Game(seats)
    room.result = None
    room.ready.clear()
    room.seen_version = -1
    room.bot_for = -1
    log.info("nardy %s start %s", room.id, seats)


async def nleave(uid: int):
    rid = nuser_room.pop(uid, None)
    room = nrooms.get(rid)
    if not room:
        return
    if room.game and not room.game.finished:
        room.game.resign(uid)
        await nafter_change(room)
    room.seats.remove(uid)
    room.ready.discard(uid)
    if not [p for p in room.seats if p > 0]:
        nrooms.pop(room.id, None)
    else:
        if room.owner == uid:
            room.owner = room.seats[0]
        await npush_room(room)
    await nsend(uid, {"t": "rooms", "rooms": nlobby_list()})
    await npush_lobby()


async def nhandle(uid: int, m: dict):
    t = m.get("t")
    if t == "ping":
        await nsend(uid, {"t": "pong"})
        return
    if t == "rooms":
        await nsend(uid, {"t": "rooms", "rooms": nlobby_list()})
        return
    if t in ("create", "bot"):
        if uid in nuser_room:
            raise nardy.RuleError("Вы уже в комнате")
        level = 0
        if t == "bot":
            level = int(m.get("level", 2))
            if level not in BOT_NAMES:
                raise nardy.RuleError("Уровень бота: 1, 2 или 3")
        room = NardyRoom(uid, bool(m.get("private")) or bool(level), level)
        while room.id in nrooms or room.id in prooms:
            room.id = NardyRoom(uid, room.private).id
        nrooms[room.id] = room
        nuser_room[uid] = room.id
        if level:
            nstart(room)
            await nafter_change(room)
        else:
            await npush_room(room)
            await npush_lobby()
        return
    if t == "join":
        rid = str(m.get("room", "")).upper().strip()
        room = nrooms.get(rid)
        if not room or room.bot:
            raise nardy.RuleError("Комната не найдена")
        if nuser_room.get(uid) == rid:
            await npush_room(room)
            return
        if uid in nuser_room:
            raise nardy.RuleError("Сначала выйдите из своей комнаты")
        if room.status == "playing" or len(room.seats) >= 2:
            raise nardy.RuleError("Комната заполнена")
        room.seats.append(uid)
        nuser_room[uid] = rid
        room.ready_since = time.time()
        if room.status == "finished":
            room.game, room.result = None, None
        await npush_room(room)
        await npush_lobby()
        return
    room = nrooms.get(nuser_room.get(uid, ""))
    if not room:
        raise nardy.RuleError("Вы не в комнате")
    if t == "leave":
        await nleave(uid)
        return
    if t == "ready":
        if room.status == "playing":
            raise nardy.RuleError("Партия ещё идёт")
        if room.bot:
            nstart(room)
            await nafter_change(room)
            return
        if not room.ready:
            room.ready_since = time.time()
        room.ready.add(uid)
        if len(room.seats) == 2 and room.ready >= set(room.seats):
            nstart(room)
            await nafter_change(room)
            await npush_lobby()
        else:
            await npush_room(room)
        return
    g = room.game
    if not g or g.finished:
        raise nardy.RuleError("Партия не идёт")
    if t == "move":
        g.move(uid, m.get("from"), m.get("to"))
    elif t == "undo":
        g.undo(uid)
    else:
        raise nardy.RuleError("Неизвестная команда")
    await nafter_change(room)
    if g.finished:
        await npush_lobby()


@app.websocket("/nws")
async def nws_endpoint(ws: WebSocket, token: str = ""):
    u = user_by_token(token)
    await ws.accept()
    if not u:
        await ws.send_text(json.dumps({"t": "error", "msg": "Нужен ник", "auth": False}, ensure_ascii=False))
        await ws.close()
        return
    uid = u["id"]
    nicks[uid] = u["nick"]
    old = nconns.get(uid)
    nconns[uid] = ws
    ngone_since.pop(uid, None)
    if old:
        try:
            await old.close()
        except Exception:
            pass
    async with nlock:
        room = nrooms.get(nuser_room.get(uid, ""))
        if room:
            await npush_room(room)
        else:
            await nsend(uid, {"t": "rooms", "rooms": nlobby_list()})
    stamps: list[float] = []
    try:
        while True:
            raw = await ws.receive_text()
            now = time.monotonic()
            stamps = [s for s in stamps if now - s < 2] + [now]
            if len(stamps) > 20 and not os.environ.get("GAMES_TEST"):
                continue  # флуд
            try:
                m = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(m, dict):
                continue
            async with nlock:
                try:
                    await nhandle(uid, m)
                except nardy.RuleError as e:
                    await nsend(uid, {"t": "error", "msg": str(e)})
                except (ValueError, TypeError):
                    await nsend(uid, {"t": "error", "msg": "Некорректная команда"})
    except WebSocketDisconnect:
        pass
    finally:
        if nconns.get(uid) is ws:
            nconns.pop(uid, None)
            ngone_since[uid] = time.time()
            async with nlock:
                room = nrooms.get(nuser_room.get(uid, ""))
                if room:
                    await npush_room(room)


async def nardy_ticker():
    """Таймер хода, «Готов» и уход отключившихся — как у бильярда."""
    while True:
        await asyncio.sleep(1)
        try:
            async with nlock:
                now = time.time()
                for uid, since in list(ngone_since.items()):
                    room = nrooms.get(nuser_room.get(uid, ""))
                    if not room:
                        ngone_since.pop(uid, None)
                        continue
                    grace = DISCONNECT_GRACE if room.status == "playing" else LOBBY_GRACE
                    if room.bot:
                        grace = 300   # с ботом можно свернуть приложение подольше
                    if now - since > grace:
                        ngone_since.pop(uid, None)
                        await nleave(uid)
                for room in list(nrooms.values()):
                    if (room.status != "playing" and not room.bot and room.ready and len(room.seats) == 2
                            and now - room.ready_since > READY_WAIT):
                        for p in [p for p in room.seats if p not in room.ready]:
                            await nsend(p, {"t": "error", "msg": "Вы не нажали «Готов»"})
                            await nleave(p)
                        continue
                    g = room.game
                    if g and not g.finished and g.seats[g.turn] > 0 and now > room.deadline:
                        g.timeout()
                        await nafter_change(room)
                        if g.finished:
                            await npush_lobby()
        except Exception:
            log.exception("nardy_ticker")


@app.on_event("startup")
async def _startup():
    asyncio.create_task(ticker())
    asyncio.create_task(pool_ticker())
    asyncio.create_task(nardy_ticker())
