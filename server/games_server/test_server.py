import os, random, tempfile, json, subprocess, sys, time
import httpx
from websockets.sync.client import connect

PORT = 18093
env = dict(os.environ, GAMES_DB=tempfile.mktemp(suffix=".db"), GAMES_TEST="1")
srv = subprocess.Popen([sys.executable, "-m", "uvicorn", "server:app", "--port", str(PORT), "--log-level", "warning"],
                       env=env, cwd=os.path.dirname(os.path.abspath(__file__)))
c = httpx.Client(base_url=f"http://127.0.0.1:{PORT}")
for _ in range(50):
    try:
        c.get("/health"); break
    except Exception:
        time.sleep(0.2)


class WS:
    def __init__(self, token, v=2):
        self.w = connect(f"ws://127.0.0.1:{PORT}/ws?token={token}&v={v}")
    def send_json(self, m): self.w.send(json.dumps(m))
    def receive_json(self): return json.loads(self.w.recv(timeout=10))
    def close(self): self.w.close()


def reg(nick, code=200):
    r = c.post("/register", json={"nick": nick})
    assert r.status_code == code, (nick, r.status_code, r.text)
    return r.json()


a = reg("Вася Пупкин")
b = reg("Петя")
d = reg("Lena_07")
reg("вася пупкин", 409)            # регистр
reg("Vася Пупкин", 409)            # латиница-двойник
reg("Ваася  Пупкин", 409)          # повтор букв и пробелы
reg("Пётя", 409)                   # ё = е
reg("Vasya Pupkin", 409)           # транслит
reg("Petya", 409)
reg("Hujlo", 400)                  # мат транслитом
reg("huy228", 400)
reg("Ебень", 400)
reg("Ебень 2", 400)
reg("Заебись", 400)
reg("Dolboeb", 400)
reg("Небо", 200)
reg("Победа", 200)
reg("Себастьян", 200)
reg("Xуйло", 400)                  # мат через латиницу
reg("ab", 400)
reg("<script>", 400)
print("ники ok")

H = lambda u: {"Authorization": "Bearer " + u["token"]}
assert c.get("/me", headers=H(a)).json()["nick"] == "Вася Пупкин"
assert c.get("/me").status_code == 401
assert c.post("/bb/score", json={"score": 1200}, headers=H(a)).json()["best"] == 1200
assert c.post("/bb/score", json={"score": 900}, headers=H(a)).json()["best"] == 1200
c.post("/bb/score", json={"score": 5000}, headers=H(b))
assert c.post("/bb/score", json={"score": -1}, headers=H(b)).status_code == 400
top = c.get("/bb/top", headers=H(a)).json()
assert [t["nick"] for t in top["top"]] == ["Петя", "Вася Пупкин"], top
assert top["me"]["rank"] == 2
assert c.get("/bb/top", headers=H(d)).json()["me"] is None
import sqlite3 as _sq
_c = _sq.connect(env["GAMES_DB"]); _c.execute("UPDATE users SET tag='Администратор' WHERE id=?", (b["id"],)); _c.commit(); _c.close()
top = c.get("/bb/top").json()
assert top["top"][0]["tag"] == "Администратор" and top["top"][1]["tag"] == "", top
print("block boom ok")


def recv_until(ws, t, pred=lambda m: True, n=50):
    for _ in range(n):
        m = ws.receive_json()
        if m["t"] == t and pred(m):
            return m
        if m["t"] == "error":
            raise AssertionError(m)
    raise AssertionError("не дождались " + t)


def play_out(socks, rng):
    """Играем случайными разрешёнными ходами до конца партии."""
    last = {}
    for uid, ws in socks.items():
        last[uid] = recv_until(ws, "room", lambda m: m["game"])
    for _ in range(3000):
        g = next(iter(last.values()))["game"]
        if g["finished"]:
            return last
        # ходит первый из ожидающих
        uid = g["waiting"][0]
        me = last[uid]["game"]
        cando = me["can"]
        opts = []
        for card in me["hand"]:
            if cando["throw"]: opts.append({"t": "throw", "card": card})
            if cando["transfer"]: opts.append({"t": "transfer", "card": card})
            if cando["defend"]:
                for i, pr in enumerate(me["table"]):
                    if not pr[1]: opts.append({"t": "defend", "card": card, "idx": i})
        if cando["take"]: opts.append({"t": "take"})
        if cando["pass"]: opts.append({"t": "pass"})
        rng.shuffle(opts)
        ver = me["version"]
        for o in opts:
            socks[uid].send_json(o)
            m = socks[uid].receive_json()
            if m["t"] == "room":
                break
        else:
            raise AssertionError(("нет хода", me))
        for u, ws in socks.items():
            if u == uid:
                last[u] = m
            else:
                last[u] = recv_until(ws, "room", lambda x: x["game"] and x["game"]["version"] > ver)
    raise AssertionError("партия не закончилась")


try:
    bad = WS("bad"); assert bad.receive_json()["auth"] is False
    wa, wb, wd = WS(a["token"]), WS(b["token"]), WS(d["token"])
    for w in (wa, wb, wd):
        recv_until(w, "rooms")
    wa.send_json({"t": "create", "players": 3, "deck": 36, "transfer": True, "throw_all": True})
    room = recv_until(wa, "room")["room"]
    lst = recv_until(wb, "rooms")["rooms"]
    assert lst[0]["id"] == room["id"] and lst[0]["status"] == "waiting"
    wb.send_json({"t": "join", "room": room["id"]})
    wd.send_json({"t": "join", "room": room["id"].lower()})
    m = recv_until(wa, "room", lambda x: len(x["room"]["seats"]) == 3)
    assert m["game"] is None                       # полная комната сама не стартует
    for w in (wa, wb, wd):
        w.send_json({"t": "ready"})
    socks = {a["id"]: wa, b["id"]: wb, d["id"]: wd}
    last = play_out(socks, random.Random(3))
    g = last[a["id"]]["game"]
    res = last[a["id"]]["result"]
    print("партия на троих ok, дурак:", res["loser_nick"])
    me = c.get("/me", headers=H(a)).json()
    assert me["durak_games"] == 1
    total_l = sum(c.get("/me", headers=H(u)).json()["durak_losses"] for u in (a, b, d))
    assert total_l == (1 if res["loser"] else 0)
    # реванш: все жмут — новая партия
    for w in (wa, wb, wd):
        w.send_json({"t": "rematch"})
    m = recv_until(wa, "room", lambda x: x["game"] and not x["game"]["finished"] and x["game"]["version"] == 0)
    # уход посреди партии — ушедший дурак
    wb.send_json({"t": "leave"})
    m = recv_until(wa, "room", lambda x: x["result"] is not None)
    assert m["result"]["loser_nick"] == "Петя", m["result"]
    assert c.get("/me", headers=H(b)).json()["durak_losses"] >= 1
    print("реванш и уход ok")
    top = c.get("/durak/top", headers=H(a)).json()
    assert len(top["top"]) == 3 and top["me"]
    print("таблица дурака ok", [(t["nick"], t["durak_wins"], t["durak_games"]) for t in top["top"]])
    # приватная комната не в списке, но по коду заходится
    wa.send_json({"t": "leave"}); wd.send_json({"t": "leave"})
    recv_until(wa, "rooms"); recv_until(wd, "rooms")
    wa.send_json({"t": "create", "players": 2, "deck": 24, "private": True})
    pr = recv_until(wa, "room")["room"]
    wd.send_json({"t": "rooms"})
    assert all(r["id"] != pr["id"] for r in recv_until(wd, "rooms")["rooms"])
    wd.send_json({"t": "join", "room": pr["id"]})
    wa.send_json({"t": "ready"}); wd.send_json({"t": "ready"})
    m = recv_until(wd, "room", lambda x: x["game"])
    assert m["game"]["rules"]["deck"] == 24 and len(m["game"]["hand"]) == 6
    # чужие карты не утекают
    assert "hands" not in m["game"] and set(m["game"]["counts"]) == {str(a["id"]), str(d["id"])}
    print("приватная комната ok")
    # старый клиент (без «Готов») — готов сразу, партия стартует
    wd.send_json({"t": "leave"}); recv_until(wd, "rooms")
    wl = WS(b["token"], v=1); recv_until(wl, "rooms")
    wl.send_json({"t": "join", "room": pr["id"]})
    m = recv_until(wa, "room", lambda x: len(x["room"]["seats"]) == 2)
    assert m["game"] is None or m["game"]["finished"] is False
    wa.send_json({"t": "ready"})
    recv_until(wl, "room", lambda x: x["game"] and not x["game"]["finished"])
    print("совместимость со старым клиентом ok")
    for w in (wa, wd, wl):
        w.close()
    print("СЕРВЕР: все тесты ok")
finally:
    srv.terminate()
