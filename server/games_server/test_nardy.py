# -*- coding: utf-8 -*-
"""Проверка движка нард: случайные партии ботов разных уровней + точечные правила.
Запуск: venv/bin/python test_nardy.py"""
import random
import sys
import time

import nardy


def check_invariants(g):
    for s in (0, 1):
        assert all(n >= 0 for n in g.pos[s]), g.pos
        assert sum(g.pos[s]) + g.off[s] == 15, (s, g.pos[s], g.off[s])
    for q in range(24):
        assert not (g.pos[0][q] and g.pos[1][(q + 12) % 24]), f"две масти на пункте {q}"


def play(seed, lv=(2, 2)):
    rng = random.Random(seed)
    g = nardy.Game([1, 2], rng)
    steps = 0
    while not g.finished:
        s = g.turn
        uid = g.seats[s]
        legal = g.legal()
        assert legal, "ход без допустимых шагов"
        if rng.random() < 0.3:
            frm, d = rng.choice(legal)
            g.move(uid, frm, frm + d)
            if not g.finished and g.turn == s and g.played and rng.random() < 0.1:
                g.undo(uid)
        else:
            for frm, d in nardy.bot_plan(g, lv[s], rng):
                g.move(uid, frm, min(frm + d, 24))
        check_invariants(g)
        steps += 1
        assert steps < 3000, "партия не кончается"
    return g


def rules():
    g = nardy.Game([1, 2], random.Random(1))
    # первый ход 6:6 — две шашки с головы, дальше стоп (12 — голова соперника)
    g.turn, g.moved_first = 0, [False, False]
    g.pos = [[15] + [0] * 23, [15] + [0] * 23]
    g.dice, g.left = [6, 6], [6] * 4
    g.head_limit = g.head_left = 2
    g.played = 0
    g.t = nardy.Turn(tuple(g.pos[0]), tuple(g.pos[1]), 0, 0, g.left, 2)
    assert g.t.total == 2, g.t.total
    assert set(g.legal()) == {(0, 6)}
    g.move(1, 0, 6)
    assert set(g.legal()) == {(0, 6)}, g.legal()   # 6→12 занято головой соперника
    g.move(1, 0, 6)
    assert g.turn == 1 and g.pos[0][6] == 2
    # не первый ход: с головы одна
    t = nardy.Turn((13, 0, 0, 0, 0, 0, 2) + (0,) * 17, (15,) + (0,) * 23, 0, 0, [3, 3, 3, 3], 1)
    assert sum(1 for p, d in t.steps((13, 0, 0, 0, 0, 0, 2) + (0,) * 17, 0, [3, 3, 3, 3], 1, 0) if p == 0) == 1
    # бóльшая кость: можно сыграть только одну
    my = [0] * 24; my[2] = 1     # одна шашка: 2→3 или 2→7, дальше 8 занят
    opp = [0] * 24
    for q in range(3, 24):
        if q not in (3, 7):
            opp[(q + 12) % 24] = 1
    t = nardy.Turn(tuple(my), tuple(opp), 0, 0, [1, 5], 1)
    st = t.steps(tuple(my), 0, [1, 5], 1, 0)
    assert t.total == 1 and st == [(2, 5)], (t.total, st)
    # выброс большей костью — только самой дальней шашкой
    my = [0] * 24; my[20] = 1; my[22] = 14
    t = nardy.Turn(tuple(my), (0,) * 24, 0, 0, [6, 1], 1)
    st = set(t.steps(tuple(my), 0, [6, 1], 1, 0))
    assert (20, 6) in st and (22, 6) not in st, st
    # заграждение из 6 без шашек соперника впереди нельзя
    my = [0] * 24
    for q in (1, 2, 3, 4, 5):
        my[q] = 2
    my[0] = 5; my[8] = 1
    opp = [0] * 24; opp[0] = 15    # все шашки соперника на голове (мой пункт 12) — впереди забора никого
    t = nardy.Turn(tuple(my), tuple(opp), 0, 0, [2, 5], 1)   # 8→... нет; 0+6? кости 2,5: 0→2? 4→6 строит 1..6
    for p, d in t.steps(tuple(my), 0, [2, 5], 1, 0):
        m2, _ = nardy._step(tuple(my), tuple(opp), 0, p, d, 1)
        # если после всего хода получится забор — шаг не должен быть единственным путём к нему
    assert nardy._fence_ok(tuple([0, 1, 1, 1, 1, 1, 1] + [0] * 17), tuple(opp), 0) is False
    opp2 = list(opp); opp2[0] = 14; opp2[(10 + 12) % 24] = 1   # шашка соперника на моём 10 — впереди забора
    assert nardy._fence_ok(tuple([0, 1, 1, 1, 1, 1, 1] + [0] * 17), tuple(opp2), 0) is True
    print("правила — ок")


if __name__ == "__main__":
    rules()
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    t0 = time.time()
    wins = {}
    mars = 0
    for i in range(n):
        lv = random.Random(i).choice([(1, 3), (3, 1), (2, 3), (3, 2), (2, 2), (1, 2)])
        g = play(i, lv)
        w = lv[g.winner]
        wins[(lv, w)] = wins.get((lv, w), 0) + 1
        mars += g.mars
    print(f"{n} партий за {time.time() - t0:.1f} с, марсов {mars}")
    for k in sorted(wins):
        print(" уровни", k[0], "победил уровень", k[1], "—", wins[k])
