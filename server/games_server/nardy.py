# -*- coding: utf-8 -*-
"""Длинные нарды: правила, ходы и бот. Сервер-авторитетный — клиент шлёт
одну шашку на одну кость (from → to), сервер проверяет и сам бросает кости.

Координаты — у каждого игрока свои: 0 — его «голова», дальше по ходу до 23,
дом — 18..23, 24 — «выброшена». Пункт q одного игрока — это пункт (q + 12) % 24
другого (головы стоят напротив). Бить нельзя, на пункт соперника не встать.

Правила:
  • с головы за ход — одна шашка; в первом ходу при 6:6, 4:4, 3:3 — две;
  • дубль — четыре хода; надо сыграть как можно больше костей, а если
    получается только одна из двух — бóльшую;
  • нельзя строить заграждение из 6 пунктов подряд, если впереди него нет
    ни одной шашки соперника;
  • выбрасывать — когда все 15 в доме; точной костью или бóльшей, если
    дальше от выхода шашек нет;
  • кто первым выбросил все — победил; у соперника ни одной выброшенной — марс.
"""
import random

HEAD_DOUBLES = (3, 4, 6)    # в первом ходу эти дубли снимают с головы две шашки
OFF = 24


class RuleError(Exception):
    """Ход против правил — клиенту уходит текст ошибки."""


def _fence_ok(my, opp, opp_off):
    """Нет ли у меня 6 пунктов подряд без шашки соперника впереди. Считаем
    в координатах соперника — это его путь."""
    occ = [False] * 24
    for q in range(24):
        if my[q]:
            occ[(q + 12) % 24] = True
    run = 0
    for o in range(24):
        run = run + 1 if occ[o] else 0
        if run >= 6:
            # заграждение o-5..o: впереди — пункты соперника дальше o (или уже выброшенные)
            if not opp_off and not any(opp[o2] for o2 in range(o + 1, 24)):
                return False
    return True


def _home(my):
    return not any(my[q] for q in range(18))


def _step(my, opp, off, p, d, head_left):
    """Одна шашка с p на кость d → (новое my, новое off) или None."""
    if not my[p] or (p == 0 and head_left <= 0):
        return None
    to = p + d
    if to < 24:
        if opp[(to + 12) % 24]:
            return None
        n = list(my)
        n[p] -= 1
        n[to] += 1
        return tuple(n), off
    if not _home(my):
        return None
    if to > 24 and any(my[q] for q in range(18, p)):
        return None     # бóльшей костью — только самую дальнюю от выхода
    n = list(my)
    n[p] -= 1
    return tuple(n), off + 1


class Turn:
    """Разбор одного хода: какие шаги допустимы с учётом «сыграть максимум»,
    «бóльшую кость» и заграждения. Соперник за мой ход не двигается."""

    def __init__(self, my, opp, opp_off, off, dice, head_limit):
        self.opp, self.opp_off = opp, opp_off
        self.memo = {}
        self.fence = True
        start = (my, off, tuple(sorted(dice)), head_limit)
        self.total = self._best(*start)
        if self.total < 0:
            # любой ход строит заграждение — тогда правило не действует (почти не бывает)
            self.fence = False
            self.memo.clear()
            self.total = self._best(*start)
        # одна кость из двух разных — обязательно бóльшая, если ею можно
        self.need_die = None
        if self.total == 1 and len(dice) == 2 and dice[0] != dice[1]:
            big = max(dice)
            if any(d == big for _, d in self._firsts(my, off, tuple(sorted(dice)), head_limit, 0)):
                self.need_die = big

    def _moves(self, my, off, dice, head_left):
        seen = set()
        for i, d in enumerate(dice):
            if d in seen:
                continue
            seen.add(d)
            rest = dice[:i] + dice[i + 1:]
            for p in range(24):
                r = _step(my, self.opp, off, p, d, head_left)
                if r:
                    yield p, d, r[0], r[1], rest, head_left - (p == 0)

    def _best(self, my, off, dice, head_left):
        """Сколько ещё костей можно сыграть так, чтобы в конце не было заграждения
        (-1 — никак)."""
        key = (my, off, dice, head_left)
        if key in self.memo:
            return self.memo[key]
        best = -1
        if off < 15:
            for _, _, m2, o2, rest, h2 in self._moves(my, off, dice, head_left):
                b = self._best(m2, o2, rest, h2)
                if b >= 0:
                    best = max(best, b + 1)
                    if best == len(dice):
                        break
        if best < 0 and (not self.fence or _fence_ok(my, self.opp, self.opp_off)):
            best = 0
        self.memo[key] = best
        return best

    def _firsts(self, my, off, dice, head_left, played):
        need = self.total - played
        if need <= 0 or off >= 15:
            return []
        out = []
        for p, d, m2, o2, rest, h2 in self._moves(my, off, dice, head_left):
            if self._best(m2, o2, rest, h2) == need - 1:
                out.append((p, d))
        return out

    def steps(self, my, off, dice, head_left, played):
        out = self._firsts(my, off, tuple(sorted(dice)), head_left, played)
        if self.need_die and played == 0:
            out = [(p, d) for p, d in out if d == self.need_die]
        return out


class Game:
    def __init__(self, seats: list, rng: random.Random | None = None):
        self.seats = list(seats)                 # [белые, чёрные]
        self.rng = rng or random.Random()
        self.pos = [[0] * 24, [0] * 24]
        self.pos[0][0] = self.pos[1][0] = 15
        self.off = [0, 0]
        self.moved_first = [False, False]       # первый ход уже был — для правила дублей с головы
        self.finished = False
        self.winner = None
        self.mars = False
        self.version = 0
        self.note = ""
        self.last_by = None
        self.last = None                         # последний шаг {by, from, to}
        self.timeouts = [0, 0]
        # розыгрыш первого хода: по одной кости, у кого больше — тот ходит
        while True:
            a, b = self.rng.randint(1, 6), self.rng.randint(1, 6)
            if a != b:
                break
        self.turn = 0 if a > b else 1
        self.opening = [a, b]
        self.note = f"Первыми ходят {'белые' if self.turn == 0 else 'чёрные'} ({a}:{b})"
        self._roll()

    # ── служебное ──
    def seat_of(self, uid):
        return self.seats.index(uid) if uid in self.seats else None

    def _roll(self):
        a, b = self.rng.randint(1, 6), self.rng.randint(1, 6)
        self.dice = [a, b]
        self.left = [a] * 4 if a == b else [a, b]
        s = self.turn
        self.head_limit = 2 if (not self.moved_first[s] and a == b and a in HEAD_DOUBLES) else 1
        self.played = 0
        self.head_left = self.head_limit
        self.start = (tuple(self.pos[s]), self.off[s], list(self.left), self.head_left)
        self.t = Turn(tuple(self.pos[s]), tuple(self.pos[1 - s]), self.off[1 - s], self.off[s],
                      self.left, self.head_limit)

    def legal(self):
        s = self.turn
        if self.finished:
            return []
        return self.t.steps(tuple(self.pos[s]), self.off[s], self.left, self.head_left, self.played)

    def _end_turn(self, note=""):
        s = self.turn
        self.moved_first[s] = True
        if self.off[s] == 15:
            self.finished = True
            self.winner = s
            self.mars = self.off[1 - s] == 0
            self.note = "Марс! Все шашки выброшены" if self.mars else "Все шашки выброшены"
            return
        for _ in range(20):
            self.turn = 1 - self.turn
            self._roll()
            if self.legal():
                break
            # хода нет — кости пропадают
            self.moved_first[self.turn] = True
            note = f"{'Белым' if self.turn == 0 else 'Чёрным'} нечем ходить ({self.dice[0]}:{self.dice[1]})"
        self.note = note

    def _need_turn(self, uid):
        if self.finished:
            raise RuleError("Партия окончена")
        s = self.seat_of(uid)
        if s is None:
            raise RuleError("Вы не за столом")
        if s != self.turn:
            raise RuleError("Сейчас не ваш ход")
        return s

    # ── ходы ──
    def move(self, uid, frm, to):
        s = self._need_turn(uid)
        frm, to = int(frm), int(to)
        to = min(to, OFF)
        opts = sorted(d for p, d in self.legal() if p == frm and min(frm + d, OFF) == to)
        if not opts:
            raise RuleError("Так ходить нельзя")
        self._apply(s, frm, opts[0])
        return True

    def _apply(self, s, frm, d):
        r = _step(tuple(self.pos[s]), tuple(self.pos[1 - s]), self.off[s], frm, d, self.head_left)
        self.pos[s] = list(r[0])
        self.off[s] = r[1]
        self.left.remove(d)
        self.played += 1
        if frm == 0:
            self.head_left -= 1
        self.last = {"by": s, "from": frm, "to": min(frm + d, OFF)}
        self.last_by = s
        self.version += 1
        self.note = ""
        self.timeouts[s] = 0
        if not self.legal():
            self._end_turn()

    def step(self, uid, frm, d):
        """Шаг конкретной костью (для бота)."""
        s = self._need_turn(uid)
        if (frm, d) not in self.legal():
            raise RuleError("Так ходить нельзя")
        self._apply(s, frm, d)

    def undo(self, uid):
        s = self._need_turn(uid)
        if not self.played:
            raise RuleError("Нечего отменять")
        my, off, left, head = self.start
        self.pos[s], self.off[s], self.left, self.head_left = list(my), off, list(left), head
        self.played = 0
        self.last = None
        self.version += 1
        self.note = ""

    def timeout(self):
        """Время вышло — доиграть ход за игрока «средним ботом». Три раза подряд —
        поражение."""
        if self.finished:
            return
        s = self.turn
        self.timeouts[s] += 1
        if self.timeouts[s] >= 3:
            self._lose(s, f"{'Белые' if s == 0 else 'Чёрные'} три хода подряд не ходили")
            return
        missed = self.timeouts[s]
        for frm, d in bot_plan(self, 2, self.rng):
            self._apply(s, frm, d)
        self.timeouts[s] = missed      # _apply обнуляет счётчик — ходы за игрока не в счёт
        if not self.finished:
            self.note = "Время вышло — сходили за вас"
        self.version += 1

    def _lose(self, s, note):
        self.finished = True
        self.winner = 1 - s
        self.mars = False
        self.note = note
        self.version += 1

    def resign(self, uid):
        s = self.seat_of(uid)
        if s is None or self.finished:
            return
        self._lose(s, "Соперник сдался")

    def pips(self, s):
        return sum(n * (24 - q) for q, n in enumerate(self.pos[s]))

    def view(self, uid):
        me = self.seat_of(uid)
        s = 0 if me is None else me
        o = 1 - s
        board = [self.pos[s][q] - self.pos[o][(q + 12) % 24] for q in range(24)]
        last = None
        if self.last:
            b, f, t = self.last["by"], self.last["from"], self.last["to"]
            if b != s:
                f, t = (f + 12) % 24, (t if t == OFF else (t + 12) % 24)
            last = {"mine": b == s, "from": f, "to": t}
        mine = me is not None and me == self.turn and not self.finished
        return {
            "board": board, "off": [self.off[s], self.off[o]], "pips": [self.pips(s), self.pips(o)],
            "color": s, "turn": self.turn, "me": me, "my_turn": mine,
            "dice": self.dice, "left": self.left,
            "moves": [{"from": p, "to": min(p + d, OFF)} for p, d in self.legal()] if mine else [],
            "can_undo": mine and self.played > 0,
            "finished": self.finished, "winner": self.winner, "mars": self.mars,
            "note": self.note, "last_by": self.last_by, "last": last, "version": self.version,
        }


# ─── бот ─────────────────────────────────────────────────────────────────────
def _all_turns(g: Game):
    """Все допустимые доигровки текущего хода: {итоговая позиция: шаги}."""
    s = g.turn
    t = g.t
    out = {}

    def rec(my, off, left, head, played, path):
        steps = t.steps(my, off, left, head, played)
        if not steps:
            key = (my, off)
            if key not in out:
                out[key] = path
            return
        seen = set()
        for p, d in steps:
            if (p, d) in seen:
                continue
            seen.add((p, d))
            m2, o2 = _step(my, t.opp, off, p, d, head)
            l2 = list(left)
            l2.remove(d)
            rec(m2, o2, l2, head - (p == 0), played + 1, path + [(p, d)])

    rec(tuple(g.pos[s]), g.off[s], list(g.left), g.head_left, g.played, [])
    return out


def _eval(my, off, opp, w):
    """Оценка позиции после моего хода (больше — лучше)."""
    pip = sum(n * (24 - q) for q, n in enumerate(my))
    score = -pip * w["pip"] + off * w["off"]
    # шашки, застрявшие на голове, и груды на одном пункте
    score -= max(0, my[0] - 1) * w["head"] * (1 if sum(my[1:]) + off > 4 else 0.3)
    score -= sum(max(0, n - 3) ** 2 for n in my[1:]) * w["stack"]
    # пункты подряд у соперника на пути, перед его отстающими шашками
    opp_back = min((o for o in range(24) if opp[o]), default=24)   # самая отсталая в его координатах
    run, blocks = 0, 0
    for o in range(24):
        if my[(o + 12) % 24]:
            run += 1
            if o > opp_back:
                blocks += run
        else:
            run = 0
    score += blocks * w["block"]
    # занятые пункты в своей «зоне разгона» (вторая и третья четверть) — гибкость
    score += sum(1 for q in range(6, 18) if my[q]) * w["spread"]
    # ворота у соперника в доме — мешаем ему заходить
    score += sum(1 for q in range(6, 12) if my[q]) * w["gate"]
    return score


WEIGHTS = {
    2: {"pip": 1.0, "off": 6, "head": 2.0, "stack": 0.8, "block": 1.2, "spread": 1.5, "gate": 1.0},
    3: {"pip": 1.0, "off": 8, "head": 3.0, "stack": 1.2, "block": 2.0, "spread": 2.0, "gate": 2.0},
}


def bot_plan(g: Game, level: int = 2, rng: random.Random | None = None):
    """Шаги (from, die) для оставшейся части хода."""
    rng = rng or random.Random()
    turns = _all_turns(g)
    if not turns:
        return []
    items = list(turns.items())
    if level <= 1 and rng.random() < 0.6:
        return rng.choice(items)[1]
    w = WEIGHTS.get(level, WEIGHTS[2])
    opp = tuple(g.pos[1 - g.turn])
    noise = {1: 6.0, 2: 2.0}.get(level, 0.0)
    best, bv = None, None
    for (my, off), path in items:
        v = _eval(my, off, opp, w) + (rng.uniform(-noise, noise) if noise else 0)
        if bv is None or v > bv:
            best, bv = path, v
    return best
