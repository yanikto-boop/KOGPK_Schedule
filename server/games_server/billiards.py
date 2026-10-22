# -*- coding: utf-8 -*-
"""Бильярд: физика, правила и бот. Сервер считает удар целиком и отдаёт
клиентам кадры — клиенты только проигрывают их и рисуют прицел.

Стол — вид сверху, x вдоль длинного борта (0..W), y поперёк (0..H), мм.
Борта — отрезки по краю сукна с разрывами у луз; концы отрезков работают как
губки лузы. Шар в лузе, когда его центр заехал за линию борта (там, где борта
нет, — то есть в разрыве).

Режимы:
  pool    — «восьмёрка»: 1–7 сплошные, 9–15 полосатые, 8 чёрный, 0 биток.
  pyramid — «американка»: 16 одинаковых шаров, после разбоя бить можно любым,
            каждый забитый (и свояк) — очко, до 8.
"""
import copy
import math
import random

SEAT_NONE = -1


class RuleError(Exception):
    """Удар против правил — клиенту уходит текст ошибки."""


class Table:
    def __init__(self, W, H, R, corner, side, vmax, decel, drag):
        self.W, self.H, self.R = W, H, R
        self.corner = corner * R      # разрыв борта у угловой лузы (вдоль каждого борта)
        self.side = side * R          # полуширина средней лузы
        self.kitchen = W * 0.25       # «дом» — линия разбоя
        self.foot = (W * 0.75, H / 2)
        self.head = (W * 0.25, H / 2)
        self.vmax, self.decel, self.drag = vmax, decel, drag
        c, s = self.corner, self.side
        self.rails = [
            (c, 0, W / 2 - s, 0), (W / 2 + s, 0, W - c, 0),
            (c, H, W / 2 - s, H), (W / 2 + s, H, W - c, H),
            (0, c, 0, H - c), (W, c, W, H - c),
        ]
        self.pockets = [(0, 0), (W / 2, 0), (W, 0), (0, H), (W / 2, H), (W, H)]

    def to_dict(self):
        return {"W": self.W, "H": self.H, "R": self.R, "corner": self.corner, "side": self.side,
                "kitchen": self.kitchen, "pockets": self.pockets}


TABLES = {
    # 9 футов, шар 57 мм, лузы пошире
    "pool": Table(2540, 1270, 28.5, corner=3.0, side=2.3, vmax=5600, decel=260, drag=0.6),
    # 10 футов, шар 68 мм; лузы шире настоящих, иначе на телефоне не забить
    "pyramid": Table(2840, 1420, 34.0, corner=1.85, side=1.5, vmax=6000, decel=280, drag=0.6),
}
MODES = tuple(TABLES)

FPS = 60
REC_EVERY = 2          # в кадры клиенту — каждый второй (30 к/с)
MAX_FRAMES = FPS * 25
E_BALL = 0.94          # упругость шар-шар
E_RAIL = 0.78          # упругость борта
RAIL_SLIP = 0.97       # потеря скорости вдоль борта
FOLLOW = 0.55          # накат/оттяжка после первого соударения
SPIN_KEEP = 0.985      # винт выдыхается за кадр
POT_IN = 0.2           # центр за линией борта глубже 0.2R — в лузе
STOP = 4.0             # мм/с — остановился


def simulate(t: Table, pos: list, k: int, vx: float, vy: float, spin: float = 0.0, record: bool = True):
    """Катит шары до остановки. pos меняется на месте (None — шар в лузе).

    Возвращает (кадры, события, итог). Итог: first — в какой шар первым попал
    биток k; potted — забитые по порядку; rail — после первого касания кто-то
    коснулся борта; rails — сколько разных шаров касалось борта.
    """
    R = t.R
    n = len(pos)
    vel = [[0.0, 0.0] for _ in range(n)]
    vel[k] = [vx, vy]
    first = None
    potted = []
    rail_after = False
    railed = set()
    frames, events = [], []
    two_r2 = 4 * R * R
    dt_f = 1.0 / FPS
    lo, hi_x, hi_y = R + 1, t.W - R - 1, t.H - R - 1
    pot_lo, pot_hx, pot_hy = POT_IN * R, t.W - POT_IN * R, t.H - POT_IN * R
    if record:
        frames.append(_frame(pos))
    for f in range(MAX_FRAMES):
        vmax = 0.0
        for i in range(n):
            v = vel[i]
            if v[0] or v[1]:
                s = math.sqrt(v[0] * v[0] + v[1] * v[1])
                if s > vmax:
                    vmax = s
        if vmax == 0.0:
            break
        steps = int(vmax * dt_f / (0.4 * R)) + 1
        dt = dt_f / steps
        for _ in range(steps):
            moving = []
            for i in range(n):
                p = pos[i]
                if p is None:
                    continue
                v = vel[i]
                if v[0] or v[1]:
                    p[0] += v[0] * dt
                    p[1] += v[1] * dt
                    moving.append(i)
            if not moving:
                break
            # шар-шар: пара проверяется, если хоть один из двух катится
            mv = set(moving)
            for i in range(n):
                pi = pos[i]
                if pi is None:
                    continue
                for j in range(i + 1, n):
                    pj = pos[j]
                    if pj is None or (i not in mv and j not in mv):
                        continue
                    dx = pj[0] - pi[0]
                    dy = pj[1] - pi[1]
                    d2 = dx * dx + dy * dy
                    if d2 >= two_r2 or d2 <= 1e-9:
                        continue
                    d = math.sqrt(d2)
                    nx, ny = dx / d, dy / d
                    vi, vj = vel[i], vel[j]
                    rel = (vi[0] - vj[0]) * nx + (vi[1] - vj[1]) * ny
                    if rel > 0:
                        kick = first is None and k in (i, j)
                        if kick:
                            first = j if i == k else i
                            pre = (vel[k][0], vel[k][1])
                        jimp = (1 + E_BALL) * 0.5 * rel
                        vi[0] -= jimp * nx
                        vi[1] -= jimp * ny
                        vj[0] += jimp * nx
                        vj[1] += jimp * ny
                        if record:
                            events.append({"f": len(frames), "hit": round(rel)})
                        if kick and spin:
                            # винт срабатывает один раз — на первом соударении битка
                            vel[k][0] += spin * FOLLOW * pre[0]
                            vel[k][1] += spin * FOLLOW * pre[1]
                            spin = 0.0
                    over = (2 * R - d) * 0.5
                    pi[0] -= nx * over
                    pi[1] -= ny * over
                    pj[0] += nx * over
                    pj[1] += ny * over
                    mv.add(i)
                    mv.add(j)
            # борта и лузы
            for i in mv:
                p = pos[i]
                if p is None:
                    continue
                x, y = p
                if lo < x < hi_x and lo < y < hi_y:
                    continue
                v = vel[i]
                for ax, ay, bx, by in t.rails:
                    ex, ey = bx - ax, by - ay
                    tt = ((x - ax) * ex + (y - ay) * ey) / (ex * ex + ey * ey)
                    tt = 0.0 if tt < 0 else 1.0 if tt > 1 else tt
                    cx, cy = ax + tt * ex, ay + tt * ey
                    dx, dy = x - cx, y - cy
                    d2 = dx * dx + dy * dy
                    if d2 >= R * R or d2 <= 1e-9:
                        continue
                    d = math.sqrt(d2)
                    nx, ny = dx / d, dy / d
                    x, y = cx + nx * R, cy + ny * R
                    vn = v[0] * nx + v[1] * ny
                    if vn < 0:
                        tx, ty = v[0] - vn * nx, v[1] - vn * ny
                        v[0] = tx * RAIL_SLIP - E_RAIL * vn * nx
                        v[1] = ty * RAIL_SLIP - E_RAIL * vn * ny
                        railed.add(i)
                        if first is not None:
                            rail_after = True
                        if record:
                            events.append({"f": len(frames), "rail": round(-vn)})
                p[0], p[1] = x, y
                if x < pot_lo or x > pot_hx or y < pot_lo or y > pot_hy:
                    pos[i] = None
                    vel[i] = [0.0, 0.0]
                    potted.append(i)
                    if record:
                        events.append({"f": len(frames), "pot": i, "pocket": _nearest_pocket(t, x, y)})
            # трение: постоянное + пропорциональное скорости
            for i in moving:
                v = vel[i]
                if pos[i] is None:
                    continue
                s = math.sqrt(v[0] * v[0] + v[1] * v[1])
                if s == 0:
                    continue
                s2 = s - (t.decel + t.drag * s) * dt
                if s2 <= STOP:
                    v[0] = v[1] = 0.0
                else:
                    v[0] *= s2 / s
                    v[1] *= s2 / s
        spin *= SPIN_KEEP
        if record and f % REC_EVERY == REC_EVERY - 1:
            frames.append(_frame(pos))
    if record:
        frames.append(_frame(pos))
    return frames, events, {"first": first, "potted": potted, "rail": rail_after, "rails": len(railed)}


def _frame(pos):
    out = []
    for p in pos:
        if p is None:
            out += [None, None]
        else:
            out += [round(p[0]), round(p[1])]
    return out


def _nearest_pocket(t: Table, x, y):
    return min(range(6), key=lambda i: (t.pockets[i][0] - x) ** 2 + (t.pockets[i][1] - y) ** 2)


# ─── расстановка ─────────────────────────────────────────────────────────────
def rack(mode: str, rng: random.Random):
    t = TABLES[mode]
    R = t.R
    gap = 0.05
    row_dx = (2 * R + gap) * math.sqrt(3) / 2
    spots = []
    for row in range(5):
        for j in range(row + 1):
            spots.append([t.foot[0] + row * row_dx, t.foot[1] + (j - row / 2) * (2 * R + gap)])
    pos = [None] * 16
    pos[0] = [t.head[0], t.head[1]]
    if mode == "pool":
        # 8 в центре, в задних углах — сплошной и полосатый, остальное вперемешку
        solids, stripes = [1, 2, 3, 4, 5, 6, 7], [9, 10, 11, 12, 13, 14, 15]
        rng.shuffle(solids)
        rng.shuffle(stripes)
        corners = [solids.pop(), stripes.pop()]
        rng.shuffle(corners)
        rest = solids + stripes
        rng.shuffle(rest)
        order = [None] * 15
        order[4] = 8
        order[10], order[14] = corners
        for idx in range(15):
            if order[idx] is None:
                order[idx] = rest.pop()
        for idx, b in enumerate(order):
            pos[b] = spots[idx][:]
    else:
        nums = list(range(1, 16))
        rng.shuffle(nums)
        for idx, b in enumerate(nums):
            pos[b] = spots[idx][:]
    return pos


def free_spot(t: Table, pos, x, y, skip=-1):
    """Ближайшее свободное место на линии от (x, y) к короткому борту и обратно."""
    for sign in (1, -1):
        cx = x
        while t.R <= cx <= t.W - t.R:
            if all(p is None or i == skip or (p[0] - cx) ** 2 + (p[1] - y) ** 2 >= (2 * t.R + 0.5) ** 2
                   for i, p in enumerate(pos)):
                return [cx, y]
            cx += sign * t.R * 0.5
    return [x, t.R]  # совсем некуда — к борту (практически не бывает)


# ─── правила ─────────────────────────────────────────────────────────────────
SOLIDS = frozenset(range(1, 8))
STRIPES = frozenset(range(9, 16))
PYRAMID_WIN = 8
MAX_TIMEOUTS = 3


class Game:
    def __init__(self, mode: str, seats: list, rng: random.Random | None = None):
        if mode not in TABLES:
            raise RuleError("Неизвестный вид бильярда")
        self.mode = mode
        self.t = TABLES[mode]
        self.seats = list(seats)
        self.rng = rng or random.Random()
        self.balls = rack(mode, self.rng)
        self.turn = self.rng.randrange(2)
        self.breaking = True
        self.in_hand = True        # можно поставить биток (на разбое — только в «дом»)
        self.groups = [None, None]  # pool: "solid"/"stripe"
        self.scores = [0, 0]        # pyramid: очки
        self.timeouts = [0, 0]
        self.finished = False
        self.winner = None          # индекс места; None при finished — ничья
        self.note = ""
        self.last_by = None         # чей был последний удар — к подсказке
        self.version = 0

    # ── доступ ──
    def seat_of(self, uid):
        return self.seats.index(uid) if uid in self.seats else SEAT_NONE

    def _need_turn(self, uid):
        if self.finished:
            raise RuleError("Партия окончена")
        if self.seat_of(uid) != self.turn:
            raise RuleError("Сейчас не ваш удар")

    def group_balls(self, seat):
        g = self.groups[seat]
        return SOLIDS if g == "solid" else STRIPES if g == "stripe" else frozenset()

    def cleared(self, seat):
        g = self.group_balls(seat)
        return bool(g) and all(self.balls[b] is None for b in g)

    def legal_targets(self, seat):
        """pool: в какие шары можно попасть первым."""
        if self.breaking or self.groups[seat] is None:
            return [b for b in range(1, 16) if b != 8 and self.balls[b] is not None] or [8]
        if self.cleared(seat):
            return [8]
        return [b for b in self.group_balls(seat) if self.balls[b] is not None]

    # ── удар ──
    def check_place(self, x, y, k=0):
        t = self.t
        if not (t.R <= x <= t.W - t.R and t.R <= y <= t.H - t.R):
            raise RuleError("Биток за пределами стола")
        if self.breaking and x > t.kitchen:
            raise RuleError("На разбое биток ставится только в «дом»")
        for i, p in enumerate(self.balls):
            if i != k and p is not None and (p[0] - x) ** 2 + (p[1] - y) ** 2 < (2 * t.R) ** 2 - 1:
                raise RuleError("Биток нельзя ставить на другой шар")

    def shoot(self, uid, dx, dy, power, spin=0.0, place=None, ball=None, record=True):
        self._need_turn(uid)
        dx, dy, power, spin = float(dx), float(dy), float(power), float(spin)
        if not all(math.isfinite(v) for v in (dx, dy, power, spin)):
            raise RuleError("Некорректный удар")
        d = math.sqrt(dx * dx + dy * dy)
        if d < 1e-6:
            raise RuleError("Не задано направление")
        power = min(1.0, max(0.03, power))
        spin = min(1.0, max(-1.0, spin))
        k = 0
        if self.mode == "pyramid" and not self.breaking and ball is not None:
            k = int(ball)
        if not 0 <= k < 16 or self.balls[k] is None:
            raise RuleError("Этого шара нет на столе")
        if place is not None:
            if not self.in_hand or k != 0:
                raise RuleError("Биток сейчас не переставить")
            x, y = float(place[0]), float(place[1])
            self.check_place(x, y)
            self.balls[0] = [x, y]
        if self.balls[k] is None:
            raise RuleError("Сначала поставьте биток")
        seat = self.turn
        # что разрешено — по столу ДО удара (забитый свой шар не должен стать «чужим»)
        before = {"targets": self.legal_targets(seat), "cleared": self.cleared(seat)}
        speed = self.t.vmax * power
        frames, events, info = simulate(self.t, self.balls, k, dx / d * speed, dy / d * speed, spin, record)
        self.timeouts[seat] = 0
        self.last_by = seat
        if self.mode == "pool":
            self._resolve_pool(seat, info, before)
        else:
            self._resolve_pyramid(seat, k, info)
        self.version += 1
        return {"by": seat, "ball": k, "frames": frames, "events": events, "final": _frame(self.balls),
                "potted": info["potted"]}

    def _pass(self):
        self.turn = 1 - self.turn

    def _resolve_pool(self, me, info, before):
        first, potted = info["first"], info["potted"]
        was_breaking = self.breaking
        self.breaking = False
        foul = ""
        if 0 in potted:
            foul = "биток в лузе"
        elif first is None:
            foul = "биток ни во что не попал"
        elif not was_breaking and first not in before["targets"]:
            foul = "первым задет чужой шар" if first != 8 else "первым задет чёрный"
        elif not was_breaking and not potted and not info["rail"]:
            foul = "после удара ни один шар не коснулся борта"
        cleared_before = before["cleared"]
        if 8 in potted:
            if was_breaking:
                self.balls[8] = free_spot(self.t, self.balls, *self.t.foot)
                potted = [b for b in potted if b != 8]
            else:
                self.finished = True
                if foul or not cleared_before:
                    self.winner = 1 - me
                    self.note = "Чёрный шар забит раньше времени" if not foul else f"Чёрный в лузе с фолом: {foul}"
                else:
                    self.winner = me
                    self.note = "Чёрный шар в лузе — победа"
                if self.balls[0] is None:
                    self.balls[0] = free_spot(self.t, self.balls, *self.t.head)
                return
        if self.balls[0] is None:
            self.balls[0] = free_spot(self.t, self.balls, *self.t.head)
        balls_in = [b for b in potted if b != 0]
        if foul:
            self._pass()
            self.in_hand = True
            self.note = "Фол: " + foul + ". Шар в руке у соперника"
            return
        self.in_hand = False
        note = ""
        if not was_breaking and self.groups[me] is None and balls_in:
            g = "solid" if balls_in[0] in SOLIDS else "stripe"
            self.groups[me] = g
            self.groups[1 - me] = "stripe" if g == "solid" else "solid"
            note = "Группа: " + ("сплошные" if g == "solid" else "полосатые") + ". "
        mine = self.group_balls(me)
        keep = any(b in mine for b in balls_in) if mine and not was_breaking else bool(balls_in)
        if not keep:
            self._pass()
        self.note = note + ("Ещё удар" if keep else "")

    def _resolve_pyramid(self, me, k, info):
        first, potted = info["first"], info["potted"]
        was_breaking = self.breaking
        self.breaking = False
        self.in_hand = False
        foul = ""
        if first is None:
            foul = "шар ни во что не попал"
        elif not potted and not info["rail"] and not was_breaking:
            foul = "ни один шар не коснулся борта"
        if foul:
            self.scores[me] += len(potted) - 1
            self._pass()
            self.note = f"Фол: {foul}. Штраф −1"
        elif potted:
            self.scores[me] += len(potted)
            self.note = f"+{len(potted)}. Ещё удар"
        else:
            self._pass()
            self.note = ""
        if self.scores[me] >= PYRAMID_WIN:
            self.finished, self.winner = True, me
            self.note = "8 шаров — победа"
            return
        if sum(p is not None for p in self.balls) < 2:
            self.finished = True
            a, b = self.scores
            self.winner = None if a == b else (0 if a > b else 1)
            self.note = "Шары кончились"

    def timeout(self):
        """Не ударил вовремя: ход сопернику (в пуле — с шаром в руке, в пирамиде — штраф)."""
        me = self.turn
        self.last_by = me
        self.timeouts[me] += 1
        if self.timeouts[me] >= MAX_TIMEOUTS:
            self.finished, self.winner = True, 1 - me
            self.note = "Три пропуска подряд — поражение"
        elif self.mode == "pool":
            self.breaking = False
            self.in_hand = True
            self._pass()
            self.note = "Время вышло. Шар в руке у соперника"
        else:
            self.breaking = False
            self.scores[me] -= 1
            self._pass()
            self.note = "Время вышло. Штраф −1"
        self.version += 1

    def resign(self, uid):
        s = self.seat_of(uid)
        if s == SEAT_NONE or self.finished:
            return
        self.finished, self.winner = True, 1 - s
        self.note = "Соперник сдался"
        self.version += 1

    def view(self, uid):
        me = self.seat_of(uid)
        return {
            "mode": self.mode, "table": self.t.to_dict(),
            "balls": [None if p is None else [round(p[0], 1), round(p[1], 1)] for p in self.balls],
            "turn": self.turn, "me": me, "my_turn": me == self.turn and not self.finished,
            "breaking": self.breaking, "in_hand": self.in_hand, "kitchen": self.breaking,
            "can_pick": self.mode == "pyramid" and not self.breaking,
            "groups": self.groups, "scores": self.scores, "need": PYRAMID_WIN,
            "targets": self.legal_targets(self.turn) if self.mode == "pool" else None,
            "finished": self.finished, "winner": self.winner, "note": self.note, "last_by": self.last_by, "version": self.version,
        }


# ─── бот ─────────────────────────────────────────────────────────────────────
BOT_LEVELS = {1: (2.6, 3), 2: (1.0, 6), 3: (0.3, 10)}   # разброс прицела в градусах, сколько вариантов считать


def _clear(pos, ax, ay, bx, by, R, skip):
    """Нет ли шаров на пути шара от a до b (кроме skip)."""
    ex, ey = bx - ax, by - ay
    L2 = ex * ex + ey * ey
    if L2 == 0:
        return True
    for i, p in enumerate(pos):
        if p is None or i in skip:
            continue
        tt = ((p[0] - ax) * ex + (p[1] - ay) * ey) / L2
        if tt < 0 or tt > 1:
            continue
        cx, cy = ax + tt * ex, ay + tt * ey
        if (p[0] - cx) ** 2 + (p[1] - cy) ** 2 < (2 * R) ** 2:
            return False
    return True


def _aim_points(t: Table):
    """Куда целиться в каждой лузе — чуть глубже створа."""
    R, W, H = t.R, t.W, t.H
    return [(R * 0.2, R * 0.2), (W / 2, -R * 0.3), (W - R * 0.2, R * 0.2),
            (R * 0.2, H - R * 0.2), (W / 2, H + R * 0.3), (W - R * 0.2, H - R * 0.2)]


def _candidates(g: Game, pos, strikers, targets):
    t = g.t
    R = t.R
    out = []
    for k in strikers:
        K = pos[k]
        if K is None:
            continue
        for tb in targets:
            T = pos[tb]
            if tb == k or T is None:
                continue
            for P in _aim_points(t):
                ux, uy = P[0] - T[0], P[1] - T[1]
                lp = math.hypot(ux, uy)
                if lp < 1:
                    continue
                ux, uy = ux / lp, uy / lp
                Gx, Gy = T[0] - ux * 2 * R, T[1] - uy * 2 * R
                if not (R <= Gx <= t.W - R and R <= Gy <= t.H - R):
                    continue
                vx, vy = Gx - K[0], Gy - K[1]
                lk = math.hypot(vx, vy)
                if lk < 1:
                    continue
                cos = (vx * ux + vy * uy) / lk
                if cos < 0.3:
                    continue
                if not _clear(pos, K[0], K[1], Gx, Gy, R, {k, tb}) or not _clear(pos, T[0], T[1], P[0], P[1], R, {tb, k}):
                    continue
                score = cos * cos / (1 + (lk + lp) / 1800)
                # сила: хватило бы докатить прицельный до лузы с запасом
                need = (lk + lp / max(cos, 0.3) * 1.3) / 2600
                out.append((score, k, vx / lk, vy / lk, min(1.0, max(0.25, need))))
    out.sort(key=lambda c: -c[0])
    return out


def _place_options(g: Game, targets):
    """Шар в руке: прямые удары — биток на продолжении линии луза → шар."""
    t = g.t
    R = t.R
    pos = g.balls
    opts = []
    for tb in targets:
        T = pos[tb]
        if T is None:
            continue
        for P in _aim_points(t):
            ux, uy = T[0] - P[0], T[1] - P[1]
            lp = math.hypot(ux, uy)
            if lp < 1:
                continue
            ux, uy = ux / lp, uy / lp
            for back in (5 * R, 9 * R):
                x, y = T[0] + ux * (2 * R + back), T[1] + uy * (2 * R + back)
                try:
                    g.check_place(x, y)
                except RuleError:
                    continue
                if _clear(pos, x, y, T[0], T[1], R, {0, tb}) and _clear(pos, T[0], T[1], P[0], P[1], R, {tb, 0}):
                    opts.append((1 / (1 + lp / 1800), [x, y]))
                    break
    opts.sort(key=lambda o: -o[0])
    return [o[1] for o in opts[:4]]


def _value(g: Game, seat):
    if g.finished:
        return 1000 if g.winner == seat else -1000
    v = 0
    if g.turn == seat:
        v += 100
    elif g.in_hand:
        v -= 150
    if g.mode == "pyramid":
        v += 60 * g.scores[seat]
    else:
        v += 25 * sum(1 for b in g.group_balls(seat) if g.balls[b] is None)
    return v


def bot_shot(g: Game, level: int = 2, rng: random.Random | None = None):
    """Удар бота: {dx, dy, power, spin, place?, ball?}. Ход считается за g.turn."""
    rng = rng or random.Random()
    noise, width = BOT_LEVELS.get(level, BOT_LEVELS[2])
    seat = g.turn
    uid = g.seats[seat]
    t = g.t
    if g.breaking:
        place = [t.head[0], t.head[1] + rng.uniform(-3, 3) * t.R]
        apex = g.balls[max(range(1, 16), key=lambda b: -g.balls[b][0])]
        dx, dy = apex[0] - place[0], apex[1] - place[1]
        return _noisy({"dx": dx, "dy": dy, "power": 0.95, "spin": 0, "place": place}, noise, rng)
    if g.mode == "pool":
        targets = g.legal_targets(seat)
        strikers = [0]
    else:
        targets = [b for b in range(16) if g.balls[b] is not None]
        strikers = targets
    places = [None]
    if g.in_hand and g.mode == "pool":
        places = _place_options(g, targets) or [None]
    plans = []
    for place in places:
        pos = copy.deepcopy(g.balls)
        if place is not None:
            pos[0] = place
        for c in _candidates(g, pos, strikers, targets)[:width]:
            _, k, ux, uy, pw = c
            for p in (pw, min(1.0, pw * 1.5)):
                plans.append({"dx": ux, "dy": uy, "power": p, "spin": 0, "place": place, "ball": k})
    scored = [(_try(g, uid, p, seat), p) for p in plans]
    best_v = max((v for v, _ in scored), default=-10 ** 9)
    if best_v < 0:
        # нечего забить — просто аккуратно попасть, чтобы не было фола
        safe = _safety(g, uid, seat, targets, strikers, rng)
        if safe is not None:
            scored.append((_try(g, uid, safe, seat), safe))
            best_v = max(best_v, scored[-1][0])
    if best_v < -100:
        # прямо не попасть — перебор направлений (в том числе через борт)
        for plan in _sweep(g, strikers, places[0]):
            scored.append((_try(g, uid, plan, seat), plan))
    if not scored:
        k = strikers[0]
        T = g.balls[targets[0]] if targets[0] != k else g.balls[targets[-1]]
        K = g.balls[k]
        return _noisy({"dx": T[0] - K[0], "dy": T[1] - K[1], "power": 0.4, "spin": 0, "ball": k}, noise, rng)
    # лучшие варианты — ещё раз со сдвигом прицела: тонкий удар, который от
    # малейшей ошибки становится фолом, хуже надёжного
    scored.sort(key=lambda s: -s[0])
    spread = max(noise, 0.25)
    best, best_v = None, -10 ** 9
    for v0, plan in scored[:6]:
        vs = [v0] + [_try(g, uid, _turn(plan, a), seat) for a in (0.05, -0.05, spread, -spread)]
        v = sum(vs) / len(vs) - 30 * plan["power"]   # лишняя сила — лишний хаос
        if v > best_v:
            best, best_v = plan, v
    return _noisy(best, noise, rng)


def _try(g: Game, uid, plan, seat):
    sim = copy.copy(g)
    sim.balls = copy.deepcopy(g.balls)
    sim.groups = list(g.groups)
    sim.scores = list(g.scores)
    sim.timeouts = list(g.timeouts)
    try:
        sim.shoot(uid, plan["dx"], plan["dy"], plan["power"], plan.get("spin", 0), plan.get("place"),
                  plan.get("ball"), record=False)
    except RuleError:
        return -10 ** 6
    # относительно «сейчас мой ход»: чистая передача хода ≈ −100, фол ≈ −250
    return _value(sim, seat) - _value(g, seat)


def _safety(g: Game, uid, seat, targets, strikers, rng):
    best, best_v = None, -10 ** 9
    for k in strikers[:6]:
        K = g.balls[k]
        for tb in targets[:6]:
            T = g.balls[tb]
            if tb == k or T is None or K is None:
                continue
            if not _clear(g.balls, K[0], K[1], T[0], T[1], g.t.R, {k, tb}):
                continue
            for p in (0.3, 0.5):
                plan = {"dx": T[0] - K[0], "dy": T[1] - K[1], "power": p, "spin": 0, "ball": k}
                if g.in_hand and g.mode == "pool":
                    plan["place"] = None
                v = _try(g, uid, plan, seat)
                if v > best_v:
                    best, best_v = plan, v
    return best


def _sweep(g: Game, strikers, place):
    k = strikers[0]
    for a in range(48):
        ang = a * math.pi / 24
        for p in (0.35, 0.65):
            yield {"dx": math.cos(ang), "dy": math.sin(ang), "power": p, "spin": 0, "ball": k, "place": place}


def _turn(plan, deg):
    a = math.radians(deg)
    p = dict(plan)
    p["dx"] = plan["dx"] * math.cos(a) - plan["dy"] * math.sin(a)
    p["dy"] = plan["dx"] * math.sin(a) + plan["dy"] * math.cos(a)
    return p


def _noisy(plan, noise_deg, rng):
    a = math.radians(rng.gauss(0, noise_deg))
    dx, dy = plan["dx"], plan["dy"]
    plan = dict(plan)
    plan["dx"] = dx * math.cos(a) - dy * math.sin(a)
    plan["dy"] = dx * math.sin(a) + dy * math.cos(a)
    plan["power"] = min(1.0, max(0.05, plan["power"] * (1 + rng.gauss(0, noise_deg / 40))))
    return plan
