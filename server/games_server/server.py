# -*- coding: utf-8 -*-
"""Игровой сервер КОГПК: ники, таблицы лидеров, дурак онлайн.

Отдельный сервис (127.0.0.1:8093, наружу — /gapi/ через nginx), к боту и
API расписания отношения не имеет. Комнаты и партии живут в памяти процесса —
рестарт сервиса обрывает идущие партии; аккаунты и рекорды — в SQLite.

Протокол WebSocket /ws?token=… — JSON-сообщения {"t": тип, ...}:
  клиент → rooms | create{players,deck,transfer,throw_all,private} | join{room}
           | leave | ready (= rematch) | throw{card} | defend{card,idx} | transfer{card}
           | take | pass | ping
  сервер → rooms{rooms} | room{room,game,deadline,result} | error{msg} | pong
"""
import asyncio
import hashlib
import json
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

import durak

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
        try:
            con.execute("ALTER TABLE users ADD COLUMN tag TEXT NOT NULL DEFAULT ''")
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


@app.get("/check_nick")
def check_nick_free(nick: str):
    return {"free": not nick_taken(check_nick(nick))}


def _me(u):
    return {"id": u["id"], "nick": u["nick"], "bb_best": u["bb_best"],
            "durak_games": u["durak_games"], "durak_wins": u["durak_wins"],
            "durak_losses": u["durak_losses"], "tag": u["tag"]}


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
        rows = con.execute(f"SELECT id, nick, tag, {col} FROM users WHERE {where} ORDER BY {order} LIMIT ?",
                           (limit,)).fetchall()
        mine = None
        if uid:
            r = con.execute(f"SELECT * FROM users WHERE id=?", (uid,)).fetchone()
            if r:
                above = con.execute(f"SELECT COUNT(*) FROM users WHERE {where} AND ({order_key(order, r)})").fetchone()[0]
                mine = {"rank": above + 1, "nick": r["nick"], "tag": r["tag"], **{k: r[k] for k in col.split(", ")}}
    return [{"rank": i + 1, "nick": r["nick"], "tag": r["tag"], "me": r["id"] == uid, **{k: r[k] for k in col.split(", ")}}
            for i, r in enumerate(rows)], mine


def order_key(order: str, r) -> str:
    # «кто выше меня» для строки r при заданной сортировке
    if order.startswith("bb_best"):
        return f"bb_best > {int(r['bb_best'])} OR (bb_best = {int(r['bb_best'])} AND id < {int(r['id'])})"
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


@app.get("/health")
def health():
    return {"ok": True, "rooms": len(rooms), "online": len(conns)}


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


@app.on_event("startup")
async def _startup():
    asyncio.create_task(ticker())
