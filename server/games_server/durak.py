# -*- coding: utf-8 -*-
"""Правила дурака — сервер решает всё, клиенты только шлют намерения.

Подкидной и переводной, 2–6 игроков, колоды 24/36/52, подкидывают все или
только соседи. Карта — строка «ранг+масть»: "6S", "10H", "QD", "AC".
Масти: S ♠, C ♣, D ♦, H ♥.

Ход раунда («отбоя»):
  * открывает главный атакующий (attacker), отбивается defender;
  * подкидывать можно карты рангов, что уже на столе, всего атакующих карт
    не больше лимита: 6 (в первом отбое 5) и не больше карт у защитника на
    начало отбоя;
  * в переводном защитник, пока не отбил ни одной карты, может положить карту
    того же ранга, что все карты на столе, — защищается следующий игрок;
  * «Беру»: атакующие ещё могут подкинуть до лимита, потом защитник забирает
    стол и пропускает ход;
  * отбой заканчивается, только когда всё побито (или защитник берёт) и все,
    кто может подкидывать, сами нажали «Бито»/«Пас» — автоматики нет, чтобы
    было видно, куда уходят карты (молчуна дожимает таймер сервера);
  * добор до 6: сначала главный атакующий, потом остальные по кругу,
    защитник последним.
Кто остался с картами, когда у остальных они кончились и колода пуста, — дурак.
"""
import random

SUITS = "SCDH"
RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A"]
DECK_RANKS = {24: RANKS[7:], 36: RANKS[4:], 52: RANKS}
HAND = 6


class RuleError(Exception):
    """Ход против правил — клиенту уходит текст ошибки."""


def rank(card: str) -> str:
    return card[:-1]


def suit(card: str) -> str:
    return card[-1]


def rank_value(card: str) -> int:
    return RANKS.index(rank(card))


def max_players(deck: int) -> int:
    return min(6, deck // HAND)


class Rules:
    def __init__(self, players=2, deck=36, transfer=False, throw_all=True):
        if deck not in DECK_RANKS:
            raise RuleError("Колода бывает 24, 36 или 52 карты")
        if not 2 <= players <= max_players(deck):
            raise RuleError(f"Для колоды {deck} — от 2 до {max_players(deck)} игроков")
        self.players, self.deck = players, deck
        self.transfer, self.throw_all = bool(transfer), bool(throw_all)

    def to_dict(self):
        return {"players": self.players, "deck": self.deck,
                "transfer": self.transfer, "throw_all": self.throw_all}


class Game:
    def __init__(self, seats: list, rules: Rules, rng: random.Random | None = None):
        """seats — id игроков по кругу (по часовой)."""
        if len(seats) < 2:
            raise RuleError("Нужно хотя бы 2 игрока")
        self.rules = rules
        self.seats = list(seats)
        rng = rng or random.Random()
        deck = [r + s for r in DECK_RANKS[rules.deck] for s in SUITS]
        rng.shuffle(deck)
        self.hands = {p: [] for p in self.seats}
        for _ in range(HAND):
            for p in self.seats:
                if deck:
                    self.hands[p].append(deck.pop())
        # козырь — нижняя карта колоды, её берут последней; без колоды — последняя розданная
        self.deck = deck
        self.trump_card = deck[0] if deck else self.hands[self.seats[-1]][-1]
        self.trump = suit(self.trump_card)
        self.discard = 0
        self.table: list[list] = []          # [атакующая, отбивающая|None]
        self.taking = False
        self.passed: set = set()
        self.out: list = []                  # вышли, по порядку
        self.finished = False
        self.loser = None                    # None при ничьей
        self.first_bout = True
        self.version = 0                     # растёт с каждым изменением
        # события для анимаций клиентов: раздача, ход, бито, взял, добор
        self.events: list[dict] = []
        self.attacker = self._lowest_trump_holder()
        self.defender = self._next_active(self.attacker)
        self._new_limit()
        self.events.append({"type": "deal", "v": 0, "order": self.seats, "n": HAND})

    # ── круг ──
    def active(self, p) -> bool:
        return p not in self.out

    def _next_active(self, p):
        i = self.seats.index(p)
        for k in range(1, len(self.seats) + 1):
            q = self.seats[(i + k) % len(self.seats)]
            if self.active(q) and q != p:
                return q
        return p

    def _lowest_trump_holder(self):
        best, who = None, self.seats[0]
        for p in self.seats:
            for c in self.hands[p]:
                if suit(c) == self.trump and (best is None or rank_value(c) < best):
                    best, who = rank_value(c), p
        return who

    def _new_limit(self):
        self.limit = min(5 if self.first_bout else HAND, len(self.hands[self.defender]))

    def throwers(self) -> list:
        """Кто сейчас может подкидывать (у кого есть карты)."""
        if self.rules.throw_all:
            cand = [p for p in self.seats if p != self.defender and self.active(p)]
        else:
            other = self._next_active(self.defender)
            cand = [self.attacker] + ([other] if other not in (self.attacker, self.defender) else [])
        return [p for p in cand if self.hands[p]]

    # ── проверки ──
    def beats(self, d: str, a: str) -> bool:
        if suit(d) == suit(a):
            return rank_value(d) > rank_value(a)
        return suit(d) == self.trump

    def attack_count(self) -> int:
        return len(self.table)

    def all_beaten(self) -> bool:
        return all(pair[1] for pair in self.table)

    def table_ranks(self) -> set:
        return {rank(c) for pair in self.table for c in pair if c}

    def can_throw(self, p, card=None) -> bool:
        if self.finished or p == self.defender or p not in self.throwers():
            return False
        if self.attack_count() >= self.limit:
            return False
        if not self.table:
            ok = p == self.attacker and not self.taking
        else:
            ok = True
        if not ok:
            return False
        if card is None:
            return any(self._fits(c) for c in self.hands[p])
        return card in self.hands[p] and self._fits(card)

    def _fits(self, card) -> bool:
        return not self.table or rank(card) in self.table_ranks()

    def can_transfer(self, p, card=None) -> bool:
        if not self.rules.transfer or self.finished or p != self.defender or self.taking:
            return False
        if not self.table or any(pair[1] for pair in self.table):
            return False
        r = rank(self.table[0][0])
        if any(rank(pair[0]) != r for pair in self.table):
            return False
        nxt = self._next_active(self.defender)
        if len(self.hands[nxt]) < len(self.table) + 1:
            return False
        if card is None:
            return any(rank(c) == r for c in self.hands[p])
        return card in self.hands[p] and rank(card) == r

    # ── действия ──
    def _touch(self):
        self.version += 1

    def _event(self, kind: str, **data):
        # событие помечается версией, в которой его надо показать
        self.events.append({"type": kind, "v": self.version + 1, **data})
        del self.events[:-20]

    def throw(self, p, card):
        """Первый ход или подкидывание."""
        if not self.can_throw(p, card):
            raise RuleError("Эту карту сейчас нельзя положить")
        self.hands[p].remove(card)
        self.table.append([card, None])
        self.passed.clear()
        self._event("play", who=p, card=card)
        self._touch()
        self._maybe_end_bout()  # подкинул последнюю карту, а защитник уже берёт

    def defend(self, p, card, idx):
        if self.finished or p != self.defender or self.taking:
            raise RuleError("Сейчас не ваша защита")
        if not 0 <= idx < len(self.table) or self.table[idx][1]:
            raise RuleError("Эта карта уже побита")
        if card not in self.hands[p] or not self.beats(card, self.table[idx][0]):
            raise RuleError("Этой картой не побить")
        self.hands[p].remove(card)
        self.table[idx][1] = card
        self.passed.clear()  # на столе новый ранг — снова можно подкидывать
        self._event("play", who=p, card=card)
        self._touch()
        self._maybe_end_bout()  # подкидывать некому — отбой сразу

    def transfer(self, p, card):
        if not self.can_transfer(p, card):
            raise RuleError("Перевести нельзя")
        self.hands[p].remove(card)
        self.table.append([card, None])
        self._event("play", who=p, card=card)
        self.attacker = p
        self.defender = self._next_active(p)
        self.limit = min(5 if self.first_bout else HAND,
                         len(self.hands[self.defender]))
        self.limit = max(self.limit, len(self.table))
        self.passed.clear()
        self._touch()

    def take(self, p):
        if self.finished or p != self.defender or self.taking or not self.table:
            raise RuleError("Сейчас нельзя взять")
        if self.all_beaten():
            raise RuleError("Всё побито — брать нечего")
        self.taking = True
        self.passed.clear()
        self._touch()
        self._maybe_end_bout()

    def pass_(self, p):
        """«Пас»/«Бито»: больше не подкидываю."""
        if self.finished or p == self.defender or not self.table:
            raise RuleError("Сейчас нечего пасовать")
        if not (self.taking or self.all_beaten()):
            raise RuleError("Защитник ещё отбивается")
        if p not in self.throwers():
            raise RuleError("Вы не подкидываете в этом отбое")
        self.passed.add(p)
        self._touch()
        self._maybe_end_bout()

    def waiting_on(self) -> list:
        """Чьего действия ждём — для таймера и подсветки."""
        if self.finished:
            return []
        if not self.table:
            return [self.attacker]
        if not self.taking and not self.all_beaten():
            return [self.defender]
        return [p for p in self.throwers() if p not in self.passed]

    def auto(self, p):
        """Истёк таймер: самое безопасное действие за игрока."""
        if p not in self.waiting_on():
            return
        if not self.table and p == self.attacker:
            hand = sorted(self.hands[p], key=lambda c: (suit(c) == self.trump, rank_value(c)))
            self.throw(p, hand[0])
        elif p == self.defender:
            self.take(p)
        else:
            self.pass_(p)

    def _maybe_end_bout(self):
        if not self.table:
            return
        if not (self.taking or self.all_beaten()):
            return
        if [p for p in self.throwers() if p not in self.passed]:
            return
        self._end_bout()

    def _end_bout(self):
        cards = [c for pair in self.table for c in pair if c]
        took = self.taking
        if took:
            self.hands[self.defender].extend(cards)
            self._event("take", who=self.defender, cards=cards)
        else:
            self.discard += len(cards)
            self._event("bito", cards=cards)
        self.table = []
        self.taking = False
        self.passed.clear()
        # добор: главный атакующий, остальные по кругу, защитник последним
        order = [self.attacker]
        i = self.seats.index(self.attacker)
        for k in range(1, len(self.seats)):
            q = self.seats[(i + k) % len(self.seats)]
            if q not in (self.attacker, self.defender) and self.active(q):
                order.append(q)
        order.append(self.defender)
        draws = []
        for p in order:
            n = 0
            while len(self.hands[p]) < HAND and self.deck:
                self.hands[p].append(self.deck.pop())
                n += 1
            if n:
                draws.append([p, n])
        if draws:
            self._event("draw", draws=draws)
        if not self.deck:
            for p in self.seats:
                if self.active(p) and not self.hands[p]:
                    self.out.append(p)
        alive = [p for p in self.seats if self.active(p)]
        self.first_bout = False
        if len(alive) <= 1:
            self.finished = True
            self.loser = alive[0] if alive else None
            self._touch()
            return
        nxt = self._next_active(self.defender) if took else self.defender
        if not self.active(nxt):
            nxt = self._next_active(nxt)
        self.attacker = nxt
        self.defender = self._next_active(nxt)
        self._new_limit()
        self._touch()

    def resign(self, p):
        """Игрок ушёл посреди партии — он и дурак, партия окончена."""
        if self.finished:
            return
        self.finished = True
        self.loser = p
        self._touch()

    # ── что видит игрок ──
    def view(self, me) -> dict:
        def can(fn):
            try:
                return fn()
            except RuleError:
                return False
        return {
            "rules": self.rules.to_dict(),
            "seats": self.seats,
            "hand": sorted(self.hands.get(me, []),
                           key=lambda c: (suit(c) == self.trump, SUITS.index(suit(c)), rank_value(c))),
            "counts": {str(p): len(self.hands[p]) for p in self.seats},
            "table": self.table,
            "trump": self.trump,
            "trump_card": self.trump_card,
            "deck": len(self.deck),
            "discard": self.discard,
            "attacker": self.attacker,
            "defender": self.defender,
            "taking": self.taking,
            "passed": list(self.passed),
            "limit": self.limit,
            "out": self.out,
            "waiting": self.waiting_on(),
            "finished": self.finished,
            "loser": self.loser,
            "version": self.version,
            "events": self.events[-8:],
            "can": {
                "throw": can(lambda: self.can_throw(me)),
                "transfer": can(lambda: self.can_transfer(me)),
                "take": me == self.defender and not self.finished and bool(self.table)
                        and not self.taking and not self.all_beaten(),
                "pass": me in self.throwers() and me != self.defender and bool(self.table)
                        and (self.taking or self.all_beaten()) and me not in self.passed,
                "defend": me == self.defender and not self.taking and not self.all_beaten(),
            },
        }
