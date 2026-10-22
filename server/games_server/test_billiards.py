"""Бот против бота: партии доходят до конца, шары не слипаются и не вылетают."""
import random
import sys
import time

import billiards as b


def check_table(g):
    t = g.t
    live = [p for p in g.balls if p is not None]
    for p in live:
        assert -0.01 <= p[0] <= t.W + 0.01 and -0.01 <= p[1] <= t.H + 0.01, p
    for i in range(len(live)):
        for j in range(i + 1, len(live)):
            d2 = (live[i][0] - live[j][0]) ** 2 + (live[i][1] - live[j][1]) ** 2
            assert d2 >= (2 * t.R - 0.5) ** 2, (live[i], live[j])


def play(mode, seed, lv=(2, 2)):
    rng = random.Random(seed)
    g = b.Game(mode, [101, 202], rng)
    shots = 0
    while not g.finished and shots < 400:
        plan = b.bot_shot(g, lv[g.turn], rng)
        uid = g.seats[g.turn]
        try:
            g.shoot(uid, plan["dx"], plan["dy"], plan["power"], plan.get("spin", 0), plan.get("place"),
                    plan.get("ball"), record=shots < 3)
        except b.RuleError as e:
            raise AssertionError(f"бот ударил против правил: {e} {plan}")
        check_table(g)
        if g.mode == "pool" and not g.finished:
            assert g.balls[0] is not None
        shots += 1
    return g, shots


def physics_checks():
    t = b.TABLES["pool"]
    # прямой удар в шар у лузы — забит
    pos = [None] * 16
    pos[0] = [600.0, 300.0]
    pos[1] = [300.0, 150.0]
    frames, ev, info = b.simulate(t, pos, 0, -300 * 2, -150 * 2 * 1.0, 0)
    assert info["first"] == 1, info
    # шар катится вдоль борта в угол — в лузе
    pos = [None] * 16
    pos[0] = [1500.0, t.R]
    _, _, info = b.simulate(t, pos, 0, -3000, 0)
    assert info["potted"] == [0], info
    # в борт под прямым углом — отскок, не в лузу
    pos = [None] * 16
    pos[0] = [700.0, 600.0]
    _, _, info = b.simulate(t, pos, 0, 0, -2500)
    assert not info["potted"] and pos[0][1] > t.R, (info, pos[0])
    # оттяжка: прямой удар с винтом -1 — биток едет назад
    pos = [None] * 16
    pos[0] = [800.0, 635.0]
    pos[1] = [1200.0, 635.0]
    b.simulate(t, pos, 0, 3000, 0, -1)
    assert pos[0] is not None and pos[0][0] < 800, pos[0]
    # накат: биток идёт следом
    pos = [None] * 16
    pos[0] = [800.0, 635.0]
    pos[1] = [1200.0, 635.0]
    b.simulate(t, pos, 0, 2000, 0, 1)
    assert pos[0] is not None and pos[0][0] > 1200, pos[0]
    print("физика ok")


def rules_checks():
    g = b.Game("pool", [1, 2], random.Random(1))
    g.turn = 0
    try:
        g.shoot(2, 1, 0, 0.5)
        raise AssertionError("чужой ход прошёл")
    except b.RuleError:
        pass
    try:
        g.shoot(1, 1, 0, 0.5, place=[t_w := b.TABLES["pool"].W * 0.5, 600])
        raise AssertionError("биток за домом на разбое")
    except b.RuleError:
        pass
    # 8 в лузу раньше времени — проигрыш
    g = b.Game("pool", [1, 2], random.Random(2))
    g.breaking = False
    g.in_hand = False
    g.turn = 0
    g.balls = [None] * 16
    g.balls[0] = [1000.0, 635.0]
    g.balls[8] = [2309.0, 1174.75]
    g.balls[3] = [1500.0, 300.0]
    g.groups = ["solid", "stripe"]
    g.shoot(1, 1540, 635, 0.6)
    assert g.finished and g.winner == 1, (g.note, g.winner)
    # 8 в лузу после своих — победа
    g = b.Game("pool", [1, 2], random.Random(2))
    g.breaking = g.in_hand = False
    g.turn = 0
    g.balls = [None] * 16
    g.balls[0] = [1000.0, 635.0]
    g.balls[8] = [2309.0, 1174.75]
    g.groups = ["solid", "stripe"]
    g.balls[9] = [500.0, 300.0]
    g.shoot(1, 1540, 635, 0.6)
    assert g.finished and g.winner == 0, (g.note, g.winner)
    # забил свой шар, в который попал первым, — не фол, удар продолжается
    g = b.Game("pool", [1, 2], random.Random(2))
    g.breaking = g.in_hand = False
    g.turn = 0
    g.balls = [None] * 16
    g.balls[0] = [1000.0, 635.0]
    g.balls[3] = [2309.0, 1174.75]
    g.balls[9] = [500.0, 300.0]
    g.balls[8] = [500.0, 900.0]
    g.groups = ["solid", "stripe"]
    g.shoot(1, 1540, 635, 0.6)
    assert not g.finished and g.turn == 0 and g.balls[3] is None, g.note
    # последний свой и чёрный одним ударом — проигрыш (группа не была очищена до удара)
    g.balls = [None] * 16
    g.balls[0] = [1000.0, 635.0]
    g.balls[3] = [1800.0, 965.0]
    g.balls[8] = [2309.0, 1174.75]
    g.balls[9] = [500.0, 300.0]
    g.shoot(1, 1540, 635, 1.0)
    if g.balls[3] is None and g.balls[8] is None:
        assert g.finished and g.winner == 1, g.note
    # пирамида: промах — штраф
    g = b.Game("pyramid", [1, 2], random.Random(3))
    g.breaking = g.in_hand = False
    g.turn = 0
    g.shoot(1, 0, 1, 0.3, ball=0) if False else None
    g.balls = [None] * 16
    g.balls[5] = [1000.0, 700.0]
    g.balls[6] = [2000.0, 300.0]
    g.shoot(1, 0, 1, 0.1, ball=5)
    assert g.scores[0] == -1 and g.turn == 1, (g.scores, g.note)
    print("правила ok")


if __name__ == "__main__":
    physics_checks()
    rules_checks()
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    for mode in b.MODES:
        t0 = time.time()
        total = 0
        wins = [0, 0, 0]
        for s in range(n):
            g, shots = play(mode, s, lv=(3, 1))
            assert g.finished, (mode, s, "не доиграли", g.scores, g.groups)
            total += shots
            wins[2 if g.winner is None else g.winner] += 1
        dt = time.time() - t0
        print(f"{mode}: {n} партий, ударов {total}, {dt / total * 1000:.0f} мс на удар бота, "
              f"сильный/слабый/ничьи {wins}")
