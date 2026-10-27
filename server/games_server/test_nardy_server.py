"""Нарды через WebSocket: комната на двоих — партия до конца, статистика; игра с ботом."""
import json
import os
import subprocess
import sys
import tempfile
import time

import httpx
from websockets.sync.client import connect

PORT = 18095
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
        self.w = connect(f"ws://127.0.0.1:{PORT}/nws?token={token}")
    def send(self, m): self.w.send(json.dumps(m))
    def recv(self): return json.loads(self.w.recv(timeout=20))
    def close(self): self.w.close()


def until(ws, t, pred=lambda m: True, n=400):
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
    a, b = reg("Зарик"), reg("Шешбеш")
    wa, wb = WS(a["token"]), WS(b["token"])
    until(wa, "rooms"), until(wb, "rooms")
    wa.send({"t": "create"})
    room = until(wa, "room")["room"]
    assert until(wb, "rooms", lambda m: m["rooms"])["rooms"][0]["id"] == room["id"]
    wb.send({"t": "join", "room": room["id"]})
    wa.send({"t": "ready"})
    wb.send({"t": "ready"})
    last = {a["id"]: until(wa, "room", lambda m: m["game"]), b["id"]: until(wb, "room", lambda m: m["game"])}
    g = last[a["id"]]["game"]
    assert g["board"][0] == 15 and g["board"][12] == -15, g["board"]
    assert last[b["id"]]["game"]["color"] == 1 - g["color"]
    socks = {a["id"]: wa, b["id"]: wb}
    # чужой ход — ошибка
    other = b["id"] if g["my_turn"] else a["id"]
    socks[other].send({"t": "move", "from": 0, "to": 3})
    assert until(socks[other], "error", n=20)["msg"] == "Сейчас не ваш ход"
    # отмена
    mover = a["id"] if g["my_turn"] else b["id"]
    mv = last[mover]["game"]["moves"][0]
    socks[mover].send({"t": "move", **mv})
    m = until(socks[mover], "room", lambda m: m["game"]["version"] == 1)
    if m["game"]["can_undo"]:
        socks[mover].send({"t": "undo"})
        m = until(socks[mover], "room", lambda m: m["game"]["version"] == 2)
        assert m["game"]["board"][0] == 15 and not m["game"]["can_undo"]
        print("отмена ок")
    # доигрываем: кто ходит — первый допустимый ход
    steps = 0
    ver = m["game"]["version"]
    while True:
        m = until(socks[mover], "room", lambda x: x["game"]["version"] >= ver) if steps else m
        g = m["game"]
        if g["finished"]:
            break
        if not g["my_turn"]:
            # ход перешёл — берём состояние у второго
            mover = b["id"] if mover == a["id"] else a["id"]
            m = until(socks[mover], "room", lambda x: x["game"]["version"] >= g["version"])
            g = m["game"]
            if g["finished"]:
                break
            assert g["my_turn"], g
        mv = max(g["moves"], key=lambda x: (x["to"], -x["from"]))
        socks[mover].send({"t": "move", **mv})
        ver = g["version"] + 1
        steps += 1
        assert steps < 2000
    print("партия на двоих доиграна, шагов", steps, "—", g["note"])
    time.sleep(0.3)
    me_a = c.get("/me", headers={"Authorization": "Bearer " + a["token"]}).json()
    me_b = c.get("/me", headers={"Authorization": "Bearer " + b["token"]}).json()
    assert me_a["nardy_games"] == me_b["nardy_games"] == 1 and me_a["nardy_wins"] + me_b["nardy_wins"] == 1
    top = c.get("/nardy/top").json()["top"]
    assert top[0]["nardy_wins"] == 1, top
    print("таблица ок", [(r["nick"], r["nardy_wins"], r["nardy_games"]) for r in top])
    wa.send({"t": "leave"}); wb.send({"t": "leave"})
    until(wa, "rooms"); until(wb, "rooms")

    # с ботом — до конца, бот ходит сам
    wa.send({"t": "bot", "level": 3})
    m = until(wa, "room", lambda m: m["game"])
    assert m["room"]["bot"] == 3 and m["room"]["private"]
    mine = bots = 0
    while not m["game"]["finished"]:
        g = m["game"]
        if g["my_turn"]:
            mv = max(g["moves"], key=lambda x: (x["to"], -x["from"]))
            wa.send({"t": "move", **mv})
            mine += 1
        m = until(wa, "room", lambda x: x["game"]["version"] > g["version"] or x["game"]["finished"])
        if m["game"]["last"] and not m["game"]["last"]["mine"]:
            bots += 1
        assert mine < 2000
    print("с ботом доиграно: моих шагов", mine, "бота", bots, "—", m["game"]["note"])
    assert c.get("/me", headers={"Authorization": "Bearer " + a["token"]}).json()["nardy_games"] == 1  # бот не в зачёт
    wa.send({"t": "leave"})
    until(wa, "rooms")
    assert c.get("/health").json()["nardy_rooms"] == 0
    wa.close(), wb.close()
    print("НАРДЫ НА СЕРВЕРЕ: все тесты ok")
finally:
    srv.terminate()
