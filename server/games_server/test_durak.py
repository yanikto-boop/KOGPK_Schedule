import random, itertools
from durak import Game, Rules, RuleError, rank, suit

def total(g):
    return sum(len(h) for h in g.hands.values()) + len(g.deck) + g.discard + sum(1 for pr in g.table for c in pr if c)

def legal_moves(g):
    mv = []
    for p in g.seats:
        if g.finished: break
        for c in g.hands[p]:
            if g.can_throw(p, c): mv.append(("throw", p, c))
            if g.can_transfer(p, c): mv.append(("transfer", p, c))
            if p == g.defender and not g.taking:
                for i, pr in enumerate(g.table):
                    if not pr[1] and g.beats(c, pr[0]): mv.append(("defend", p, c, i))
        v = g.view(p)["can"]
        if v["take"]: mv.append(("take", p))
        if v["pass"]: mv.append(("pass", p))
    return mv

def play(g, rng, max_steps=5000):
    N = total(g)
    for step in range(max_steps):
        if g.finished: return step
        mv = legal_moves(g)
        assert mv, f"нет ходов: {g.view(g.seats[0])}"
        # ожидающие действия должны быть среди возможных
        w = g.waiting_on()
        assert w, "никого не ждём, а игра идёт"
        m = rng.choice(mv)
        getattr(g, {"throw":"throw","transfer":"transfer","defend":"defend","take":"take","pass":"pass_"}[m[0]])(*m[1:])
        assert total(g) == N, "карты потерялись"
        assert len(g.table) <= g.limit
        for pr in g.table:
            if pr[1]: assert g.beats(pr[1], pr[0])
    raise AssertionError("игра не закончилась")

def auto_play(g, steps=400):
    """Таймер за любого ожидаемого игрока всегда двигает игру и не ломает правила."""
    N = total(g)
    for _ in range(steps):
        if g.finished: return
        v = g.version; g.auto(g.waiting_on()[0])
        assert g.version != v, "auto не сделал ход"
        assert total(g) == N

rng = random.Random(1)
games = 0
for deck, players, transfer, throw_all in itertools.product((24, 36, 52), range(2, 7), (False, True), (False, True)):
    try: r = Rules(players, deck, transfer, throw_all)
    except RuleError: continue
    for i in range(60):
        g = Game(list(range(100, 100 + players)), r, random.Random(rng.random()))
        assert total(g) == deck
        play(g, rng); games += 1
        assert g.finished and (g.loser is None or g.loser in g.seats)
        g2 = Game(list(range(players)), r, random.Random(i)); auto_play(g2); games += 1
print("random games ok:", games)

# ── сценарии ──
r = Rules(2, 36)
g = Game([1, 2], r, random.Random(5))
g.hands = {1: ["6S","6H","7S","8C","9D","QH"], 2: ["7C","10S","JS","KD","AH","6D"]}
g.trump = "H"; g.attacker, g.defender = 1, 2; g.first_bout = True; g._new_limit()
assert g.limit == 5
try: g.throw(2, "7C"); raise SystemExit("защитник не должен ходить")
except RuleError: pass
g.throw(1, "6S")
try: g.throw(1, "7S"); raise SystemExit("7 нельзя подкинуть к 6")
except RuleError: pass
try: g.defend(2, "6D", 0); raise SystemExit("6D не бьёт 6S")
except RuleError: pass
g.defend(2, "10S", 0)
g.throw(1, "6H")          # подкинул шестёрку
g.defend(2, "AH", 1)      # козырем
assert g.table and g.waiting_on() == [1]   # автоматики нет: ждём «Бито»
g.pass_(1)
assert not g.table and g.discard == 4 and g.attacker == 2 and g.defender == 1
g = Game([1, 2], Rules(2, 36), random.Random(5))
g.hands = {1: ["6S","10C","7S","8C","9D","QH"], 2: ["7C","10S","JS","KD","AH","6D"]}
g.trump = "H"; g.attacker, g.defender = 1, 2; g.first_bout = False; g._new_limit()
g.throw(1, "6S"); g.defend(2, "10S", 0)
assert g.table and g.waiting_on() == [1]   # у 1 есть 10C — ждём его
g.pass_(1); assert not g.table and g.attacker == 2
# «беру» + вдогонку
g.hands = {1: ["6S","6C","7S","8C","9D","QH"], 2: ["7C","10S","JS","KD","AH","6D"]}
g.attacker, g.defender = 1, 2; g._new_limit(); g.throw(1, "6S"); g.take(2)
g.throw(1, "6C"); assert g.table           # шестёрок больше нет, но ждём «Пас»
g.pass_(1)
assert len(g.hands[2]) == 8 and g.attacker == 1
print("подкидной сценарий ok")

r = Rules(3, 36, transfer=True)
g = Game([1, 2, 3], r, random.Random(7))
g.hands = {1: ["6S","8C","9D","QH","KS","AS"], 2: ["6C","7C","10S","JS","KD","AH"], 3: ["7D","8D","9C","10C","JC","QC"]}
g.trump = "H"; g.attacker, g.defender = 1, 2; g.first_bout = False; g._new_limit()
g.throw(1, "6S")
assert g.can_transfer(2, "6C")
g.transfer(2, "6C")
assert g.attacker == 2 and g.defender == 3 and len(g.table) == 2
assert not g.can_transfer(3)
g.take(3)
assert g.table and set(g.waiting_on()) == {1, 2}  # оба подкидывающих жмут «Пас»
g.pass_(1); g.pass_(2)
assert not g.table and len(g.hands[3]) == 8, g.hands[3]
assert g.attacker == 1 and g.defender == 2, (g.attacker, g.defender)
print("переводной сценарий ok")

# соседи: в 4 игроках подкидывают только атакующий и игрок после защитника
r = Rules(4, 36, throw_all=False)
g = Game([1, 2, 3, 4], r, random.Random(3))
g.attacker, g.defender = 1, 2; g._new_limit()
assert set(g.throwers()) == {1, 3}, g.throwers()
r = Rules(4, 36, throw_all=True)
g = Game([1, 2, 3, 4], r, random.Random(3)); g.attacker, g.defender = 1, 2
assert set(g.throwers()) == {1, 3, 4}
try: Rules(5, 24); raise SystemExit("5 игроков на 24 карты нельзя")
except RuleError: pass
# события для анимаций
g = Game([1, 2], Rules(2, 36), random.Random(5))
assert g.events[0]["type"] == "deal" and g.events[0]["v"] == 0
a = g.attacker; d = g.defender
c = sorted(g.hands[a])[0]; g.throw(a, c)
assert g.events[-1] == {"type": "play", "v": g.version, "who": a, "card": c}
g.take(d); g.pass_(a)
kinds = [e["type"] for e in g.events if e["v"] == g.version]
assert kinds[:2] == ["take", "draw"], kinds
print("события ok")
print("все тесты ok")
