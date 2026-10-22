"""Бильярд через WebSocket: комната на двоих, удары, прицел, итог; игра с ботом."""
import json
import os
import subprocess
import sys
import tempfile
import time

import httpx
from websockets.sync.client import connect

PORT = 18094
env = dict(os.environ, GAMES_DB=tempfile.mktemp(suffix=".db"), GAMES_TEST="1")
srv = subprocess.Popen([sys.executable, "-m", "uvicorn", "server:app", "--port", str(PORT), "--log-level", "warning"],
                       env=env, cwd=os.path.dirname(os.path.abspath(__file__)))
c = httpx.Client(base_url=f"http://127.0.0.1:{PORT}")
for _ in range(50):
    try:
        c.get("/health")
        break
    except Exception:
        time.sleep(0.2)


class WS:
    def __init__(self, token):
        self.w = connect(f"ws://127.0.0.1:{PORT}/pws?token={token}")
    def send(self, m): self.w.send(json.dumps(m))
    def recv(self): return json.loads(self.w.recv(timeout=20))
    def close(self): self.w.close()


def until(ws, t, pred=lambda m: True, n=200):
    for _ in range(n):
        m = ws.recv()
        if m["t"] == t and pred(m):
            return m
        if m["t"] == "error":
            raise AssertionError(m)
    raise AssertionError("не дождались " + t)


def reg(nick):
    r = c.post("/register", json={"nick": nick})
    assert r.status_code == 200, r.text
    return r.json()


try:
    a, b = reg("Шулер"), reg("Кием")
    wa, wb = WS(a["token"]), WS(b["token"])
    until(wa, "rooms"), until(wb, "rooms")
    wa.send({"t": "create", "mode": "pool"})
    room = until(wa, "room")["room"]
    assert room["mode"] == "pool"
    assert until(wb, "rooms", lambda m: m["rooms"])["rooms"][0]["id"] == room["id"]
    wb.send({"t": "join", "room": room["id"]})
    wa.send({"t": "ready"})
    wb.send({"t": "ready"})
    st = {a["id"]: until(wa, "room", lambda m: m["game"]), b["id"]: until(wb, "room", lambda m: m["game"])}
    g = st[a["id"]]["game"]
    assert g["breaking"] and g["in_hand"] and len(g["balls"]) == 16
    turn_uid = st[a["id"]]["room"]["seats"][g["turn"]]["id"]
    ws_turn, ws_other = (wa, wb) if turn_uid == a["id"] else (wb, wa)
    # чужой удар — ошибка
    ws_other.send({"t": "shot", "dx": 1, "dy": 0, "power": 0.5})
    assert until(ws_other, "error", n=5)["msg"] == "Сейчас не ваш удар"
    # прицел доходит до соперника
    ws_turn.send({"t": "aim", "dx": 1, "dy": 0.1, "place": [500, 600]})
    assert until(ws_other, "aim")["place"] == [500, 600]
    # разбой с неправильным местом битка
    ws_turn.send({"t": "shot", "dx": 1, "dy": 0, "power": 1, "place": [1500, 600]})
    assert "дом" in until(ws_turn, "error", n=5)["msg"]
    ws_turn.send({"t": "shot", "dx": 1, "dy": 0.002, "power": 1, "place": [600, 635]})
    shot = until(ws_other, "shot")["shot"]
    assert len(shot["frames"]) > 10 and len(shot["frames"][0]) == 32
    after = until(ws_other, "room", lambda m: m["game"]["version"] == 1)
    assert not after["game"]["breaking"]
    print("пул на двоих: разбой ok, кадров", len(shot["frames"]), "забито", shot["potted"])
    # сдаться (выйти) — соперник выиграл, статистика записана
    ws_turn.send({"t": "leave"})
    m = until(ws_other, "room", lambda m: m["result"])
    assert m["result"]["winner"] == (b["id"] if ws_turn is wa else a["id"]), m["result"]
    me_a, me_b = c.get("/me", headers={"Authorization": "Bearer " + a["token"]}).json(), \
        c.get("/me", headers={"Authorization": "Bearer " + b["token"]}).json()
    assert me_a["pool_games"] == me_b["pool_games"] == 1 and me_a["pool_wins"] + me_b["pool_wins"] == 1
    top = c.get("/pool/top").json()["top"]
    assert top[0]["pool_wins"] == 1 and top[0]["pool_games"] == 1, top
    print("уход и таблица ok", [(r["nick"], r["pool_wins"]) for r in top])
    ws_other.send({"t": "leave"})
    until(ws_other, "rooms")
    until(ws_turn, "rooms")

    # с ботом: пирамида, бот тоже бьёт сам
    wa.send({"t": "bot", "mode": "pyramid", "level": 1})
    m = until(wa, "room", lambda m: m["game"])
    assert m["room"]["bot"] == 1 and m["room"]["private"]
    shots_seen = 0
    for _ in range(60):
        g = m["game"]
        if g["finished"]:
            break
        if g["my_turn"]:
            if g["breaking"]:
                wa.send({"t": "shot", "dx": 1, "dy": 0.003, "power": 0.9, "place": [700, 710]})
            else:
                # бьём ближайшим к центру шаром в любой другой
                live = [(i, p) for i, p in enumerate(g["balls"]) if p]
                (i, p), (j, q) = live[0], live[1]
                wa.send({"t": "shot", "dx": q[0] - p[0], "dy": q[1] - p[1], "power": 0.6, "ball": i})
        until(wa, "shot")
        shots_seen += 1
        m = until(wa, "room", lambda x: x["game"]["version"] > g["version"])
        if shots_seen >= 6 and any(x["t"] for x in [m]) and not m["game"]["my_turn"]:
            pass
        if shots_seen >= 8:
            break
    assert shots_seen >= 4, shots_seen
    assert c.get("/me", headers={"Authorization": "Bearer " + a["token"]}).json()["pool_games"] == 1  # бот не в зачёт
    print("пирамида с ботом ok, ударов", shots_seen, "счёт", m["game"]["scores"])
    wa.send({"t": "leave"})
    until(wa, "rooms")
    assert c.get("/health").json()["pool_rooms"] == 0
    wa.close(), wb.close()
    print("БИЛЬЯРД НА СЕРВЕРЕ: все тесты ok")
finally:
    srv.terminate()
