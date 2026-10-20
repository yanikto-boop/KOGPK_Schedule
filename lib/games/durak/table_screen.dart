import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'cards.dart';
import 'durak_client.dart';
import 'lobby_screen.dart';

const _feltLight = Color(0xFF2C77C4);
const _feltDark = Color(0xFF123C70);
const _gold = Color(0xFFFFD166);
const _avatarColors = [
  Color(0xFFE76F51), Color(0xFF2A9D8F), Color(0xFF8E7DBE), Color(0xFFF4A261),
  Color(0xFF3A86FF), Color(0xFFEF476F), Color(0xFF06A77D), Color(0xFFB5838D),
];

/// Летящая карта (card == null — рубашка): из from в to.
class _Flight {
  final String? card;
  final Rect from, to;
  final Duration delay, dur;
  final double turns;
  final bool hold; // до старта лежит на месте (карты со стола)
  final VoidCallback? onDone;
  Duration? start;
  _Flight(this.card, this.from, this.to,
      {this.delay = Duration.zero,
      this.dur = const Duration(milliseconds: 380),
      this.turns = 0,
      this.hold = false,
      this.onDone});
}

Duration _ms(int v) => Duration(milliseconds: v);
Rect _cardRect(Offset center, double w) => Rect.fromCenter(center: center, width: w, height: w * 1.45);

class DurakTableScreen extends StatefulWidget {
  const DurakTableScreen({super.key});
  @override
  State<DurakTableScreen> createState() => _DurakTableScreenState();
}

class _DurakTableScreenState extends State<DurakTableScreen> with SingleTickerProviderStateMixin {
  final c = DurakClient.instance;
  String? _sel;
  Timer? _tick;
  StreamSubscription? _err;
  bool _popped = false;

  // анимации: события сервера (events) превращаются в полёты карт
  late final Ticker _ticker = createTicker(_onFrame);
  Duration _now = Duration.zero;
  final _flights = <_Flight>[];
  final _hiddenTable = <String>{}; // карты соперника на столе, пока к ним летит копия
  final _hiddenHand = <String>{}; // мои новые карты, пока они летят в руку
  int _seenV = -1;
  List<String> _prevHand = const [];

  final _stackKey = GlobalKey();
  final _deckKey = GlobalKey();
  final _discardKey = GlobalKey();
  final _handKey = GlobalKey();
  final _tableKeys = <String, GlobalKey>{};
  final _avatarKeys = <int, GlobalKey>{};
  double _tableW = 60, _handW = 70;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _err = c.errors.stream.listen((e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 2)));
      }
    });
    final g = c.game;
    if (g != null && g['version'] != 0) {
      _seenV = g['version'] as int; // зашли посреди партии — без раздачи
      _prevHand = _hand(g);
    } else {
      _absorb();
    }
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _tick?.cancel();
    _err?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  List<String> _hand(Map g) => (g['hand'] as List).cast<String>();

  void _onChange() {
    if (!mounted) return;
    if (c.room == null && !_popped) {
      _popped = true;
      Navigator.pop(context);
      return;
    }
    final hand = c.game == null ? const <String>[] : _hand(c.game!);
    if (_sel != null && !hand.contains(_sel)) _sel = null;
    _absorb();
    setState(() {});
  }

  /// Новое состояние: какие события ещё не показаны → что спрятать до приземления.
  void _absorb() {
    final g = c.game;
    if (g == null) {
      _seenV = -1;
      _prevHand = const [];
      return;
    }
    final v = g['version'] as int;
    if (v < _seenV) _seenV = -1; // новая партия
    final evs = ((g['events'] as List?) ?? const [])
        .cast<Map>()
        .where((e) => (e['v'] as int) > _seenV && (e['v'] as int) <= v)
        .toList();
    _seenV = v;
    final hand = _hand(g);
    final fresh = hand.where((x) => !_prevHand.contains(x)).toList();
    _prevHand = hand;
    if (evs.isEmpty) return;
    // откуда улетают карты со стола — пока старые виджеты ещё на месте
    final old = <String, Rect>{};
    for (final e in _tableKeys.entries) {
      final r = _rect(e.value);
      if (r != null) old[e.key] = r;
    }
    final me = c.me;
    var mineArrive = false;
    for (final e in evs) {
      switch (e['type']) {
        case 'play' when e['who'] != me:
          _hiddenTable.add(e['card'] as String);
        case 'deal':
          mineArrive = true;
        case 'take' when e['who'] == me:
          mineArrive = true;
        case 'draw' when (e['draws'] as List).any((d) => d[0] == me):
          mineArrive = true;
      }
    }
    if (mineArrive) _hiddenHand.addAll(fresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _animate(evs, old, fresh);
    });
  }

  Rect? _rect(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    final root = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || root == null || !box.attached || !box.hasSize || !root.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: root) & box.size;
  }

  void _animate(List<Map> evs, Map<String, Rect> old, List<String> fresh) {
    final me = c.me;
    final root = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (root == null || !root.hasSize) {
      _reveal();
      return;
    }
    final center = root.size.center(Offset.zero);
    final deck = _rect(_deckKey)?.center ?? Offset(40, center.dy);
    final discard = _rect(_discardKey)?.center ?? Offset(root.size.width + 40, center.dy);
    final hand = _rect(_handKey);
    // мои новые карты открываются по одной, по мере прилёта
    final queue = fresh.where(_hiddenHand.contains).toList();
    void revealOne() => _hiddenHand.remove(queue.isEmpty ? null : queue.removeAt(0));
    Rect seat(int p, double w) {
      if (p == me && hand != null) return _cardRect(hand.center, w);
      final a = _avatarKeys[p] == null ? null : _rect(_avatarKeys[p]!);
      return _cardRect(a?.center ?? Offset(center.dx, 0), w * 0.45);
    }

    final fs = <_Flight>[];
    var at = 0;
    for (final e in evs) {
      switch (e['type']) {
        case 'deal':
          final order = (e['order'] as List).cast<int>();
          var k = 0;
          for (var r = 0; r < (e['n'] as int); r++) {
            for (final p in order) {
              fs.add(_Flight(null, _cardRect(deck, _tableW), seat(p, _handW),
                  delay: _ms(at + 75 * k++), dur: _ms(330), onDone: p == me ? revealOne : null));
            }
          }
          at += 75 * k + 200;
        case 'play':
          final card = e['card'] as String;
          if (e['who'] == me) continue; // свою карту игрок положил сам
          final key = _tableKeys[card];
          final to = key == null ? null : _rect(key);
          if (to == null) {
            _hiddenTable.remove(card);
            continue;
          }
          fs.add(_Flight(card, seat(e['who'] as int, _tableW), to,
              delay: _ms(at), dur: _ms(340), turns: -0.03, onDone: () => _hiddenTable.remove(card)));
          at += 200;
        case 'bito':
          final cards = (e['cards'] as List).cast<String>();
          for (var i = 0; i < cards.length; i++) {
            final from = old[cards[i]] ?? _cardRect(center, _tableW);
            fs.add(_Flight(cards[i], from, _cardRect(discard + Offset(0, (i % 3 - 1) * 6.0), _tableW),
                delay: _ms(at + 40 * i), dur: _ms(460), turns: 0.22 + 0.04 * (i % 3), hold: true));
          }
          at += 400 + 40 * cards.length;
        case 'take':
          final who = e['who'] as int;
          final cards = (e['cards'] as List).cast<String>();
          for (var i = 0; i < cards.length; i++) {
            final card = cards[i];
            final from = old[card] ?? _cardRect(center, _tableW);
            fs.add(_Flight(card, from, seat(who, who == me ? _handW : _tableW),
                delay: _ms(at + 40 * i),
                dur: _ms(440),
                hold: true,
                onDone: who == me
                    ? () {
                        queue.remove(card);
                        _hiddenHand.remove(card);
                      }
                    : null));
          }
          at += 400 + 40 * cards.length;
        case 'draw':
          var k = 0;
          for (final d in (e['draws'] as List)) {
            final p = d[0] as int;
            for (var j = 0; j < (d[1] as int); j++) {
              fs.add(_Flight(null, _cardRect(deck, _tableW), seat(p, _handW),
                  delay: _ms(at + 90 * k++), dur: _ms(340), onDone: p == me ? revealOne : null));
            }
          }
          at += 90 * k + 150;
      }
    }
    if (fs.isEmpty) {
      _reveal();
      return;
    }
    _flights.addAll(fs);
    if (!_ticker.isActive) _ticker.start();
    setState(() {});
  }

  void _reveal() {
    if (_hiddenHand.isEmpty && _hiddenTable.isEmpty) return;
    setState(() {
      _hiddenHand.clear();
      _hiddenTable.clear();
    });
  }

  void _onFrame(Duration now) {
    _now = now;
    for (final f in List.of(_flights)) {
      f.start ??= now;
      if (now - f.start! >= f.delay + f.dur) {
        _flights.remove(f);
        f.onDone?.call();
      }
    }
    if (_flights.isEmpty) {
      _ticker.stop();
      _hiddenHand.clear();
      _hiddenTable.clear();
    }
    setState(() {});
  }

  bool get _playing => c.game != null && c.game!['finished'] != true;

  Future<void> _leave() async {
    if (_playing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Выйти из партии?'),
          content: const Text('Партия закончится, и дураком будете вы.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
          ],
        ),
      );
      if (ok != true) return;
    }
    c.leave();
  }

  Map? _seat(int id) {
    for (final s in (c.room?['seats'] as List?) ?? const []) {
      if (s['id'] == id) return s as Map;
    }
    return null;
  }

  String _nick(int id) => _seat(id)?['nick'] as String? ?? '?';

  int? get _left =>
      c.deadline == null ? null : c.deadline!.difference(DateTime.now()).inSeconds.clamp(0, 99);

  @override
  Widget build(BuildContext context) {
    final room = c.room;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: _feltDark,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
                center: Alignment(0, -0.1), radius: 1.1, colors: [_feltLight, _feltDark]),
          ),
          child: room == null
              ? const SizedBox()
              : Stack(key: _stackKey, children: [
                  Column(children: [
                    SafeArea(bottom: false, child: _topBar(room)),
                    Expanded(child: c.game == null ? _waiting(room) : _table(room, c.game!)),
                    _bottomBar(room, c.game),
                  ]),
                  for (final f in _flights) ?_flightWidget(f),
                  if (c.game?['finished'] == true && _flights.isEmpty) _result(room),
                ]),
        ),
      ),
    );
  }

  Widget? _flightWidget(_Flight f) {
    final el = f.start == null ? -f.delay : _now - f.start! - f.delay;
    var t = el.inMicroseconds / f.dur.inMicroseconds;
    if (t < 0 && !f.hold) return null;
    t = Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
    final r = Rect.lerp(f.from, f.to, t)!;
    return Positioned(
      left: r.left,
      top: r.top,
      child: IgnorePointer(
        child: Transform.rotate(
            angle: f.turns * 2 * math.pi * t, child: PlayingCard(f.card, width: r.width)),
      ),
    );
  }

  Widget _topBar(Map room) => SizedBox(
        height: 44,
        child: Row(children: [
          IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: _leave),
          Expanded(
            child: Text('Комната ${room['id']} · ${rulesLabel(room['rules'] as Map)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          IconButton(
            tooltip: 'Скопировать код',
            icon: const Icon(Icons.copy, color: Colors.white70, size: 20),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: room['id'] as String));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Код скопирован')));
            },
          ),
        ]),
      );

  // ── аватарки ──
  Widget _avatar(int p, {required double size, bool turn = false, bool ready = false}) {
    final nick = _nick(p);
    final letter = nick.isEmpty ? '?' : nick.characters.first.toUpperCase();
    final left = _left;
    final online = _seat(p)?['online'] != false;
    return SizedBox(
      width: size + 10,
      height: size + 10,
      child: Stack(alignment: Alignment.center, children: [
        if (turn && left != null)
          SizedBox(
            width: size + 10,
            height: size + 10,
            child: CircularProgressIndicator(
              value: (left / c.deadlineTotal).clamp(0.0, 1.0),
              strokeWidth: 4,
              color: left <= 5 ? Colors.redAccent : _gold,
              backgroundColor: Colors.white24,
            ),
          ),
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: online ? _avatarColors[p % _avatarColors.length] : Colors.blueGrey,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Text(letter,
              style: TextStyle(color: Colors.white, fontSize: size * 0.46, fontWeight: FontWeight.w800)),
        ),
        if (ready)
          const Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
                radius: 10,
                backgroundColor: Color(0xFF2DBE60),
                child: Icon(Icons.check, size: 14, color: Colors.white)),
          ),
      ]),
    );
  }

  Widget _opponent(int p, Map g) {
    final n = ((g['counts'] as Map)['$p'] as int?) ?? 0;
    final out = (g['out'] as List).contains(p);
    final waiting = (g['waiting'] as List).contains(p);
    final role = p == g['attacker'] ? '⚔' : p == g['defender'] ? '🛡' : null;
    final fan = math.min(n, 6);
    return SizedBox(
      width: 86,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          height: 82,
          width: 86,
          child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
            // веер рубашек за аватаркой
            for (var k = 0; k < fan; k++)
              Positioned(
                top: 0,
                child: Transform.rotate(
                  angle: (k - (fan - 1) / 2) * 0.2,
                  alignment: Alignment.bottomCenter,
                  origin: const Offset(0, 20),
                  child: const PlayingCard(null, width: 26),
                ),
              ),
            Positioned(
                bottom: 0,
                child: KeyedSubtree(
                    key: _avatarKeys.putIfAbsent(p, GlobalKey.new),
                    child: _avatar(p, size: 48, turn: waiting))),
            if (!out)
              Positioned(right: 4, top: 26, child: _badge('$n', Colors.black54)),
            if (role != null) Positioned(left: 4, top: 26, child: _badge(role, Colors.black38)),
          ]),
        ),
        const SizedBox(height: 2),
        Text(out ? '${_nick(p)} ✓' : _nick(p),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _badge(String s, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  // ── ожидание игроков ──
  Widget _waiting(Map room) {
    final seats = (room['seats'] as List).cast<Map>();
    final max = (room['rules'] as Map)['players'] as int;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(seats.length < max ? 'Ждём игроков: ${seats.length} из $max' : 'Все в сборе',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 20),
          Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
            for (final s in seats)
              SizedBox(
                width: 76,
                child: Column(children: [
                  _avatar(s['id'] as int, size: 56, ready: s['ready'] == true),
                  const SizedBox(height: 4),
                  Text(s['nick'] as String,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            for (var k = seats.length; k < max; k++)
              SizedBox(
                width: 76,
                child: Column(children: [
                  Container(
                    width: 66,
                    height: 66,
                    margin: const EdgeInsets.all(0),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, border: Border.all(color: Colors.white38, width: 2)),
                    child: const Icon(Icons.person_add_alt, color: Colors.white38),
                  ),
                  const SizedBox(height: 4),
                  const Text('свободно', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ),
          ]),
          const SizedBox(height: 24),
          Text('Код комнаты: ${room['id']}',
              style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 2)),
          const SizedBox(height: 6),
          const Text('Партия начнётся, когда все нажмут «Готов»',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]),
      ),
    );
  }

  // ── стол ──
  Widget _table(Map room, Map g) {
    final me = c.me!;
    final seats = (g['seats'] as List).cast<int>();
    final table = (g['table'] as List).map((p) => (p as List).cast<String?>()).toList();
    final i = seats.indexOf(me);
    final others = [for (var k = 1; k < seats.length; k++) seats[(i + k) % seats.length]];
    final hand = _hand(g);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      _tableW = (w / 6.4).clamp(50.0, 78.0);
      _handW = (w / 4.8).clamp(58.0, 96.0);
      return Column(children: [
        SizedBox(
          height: 104,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            for (final p in others) _opponent(p, g),
          ]),
        ),
        Expanded(
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(child: _tableArea(g, table)),
            Positioned(left: 6, top: 0, bottom: 0, child: Center(child: _deck(g))),
            Positioned(right: -_tableW * 0.5, top: 0, bottom: 0, child: Center(child: _discard(g))),
          ]),
        ),
        _handFan(hand, w),
      ]);
    });
  }

  Widget _tableArea(Map g, List<List<String?>> table) {
    final sel = _sel;
    return DragTarget<String>(
      onAcceptWithDetails: (d) => _drop(d.data, null),
      builder: (context, hover, _) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: sel == null ? null : () => _drop(sel, null),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: EdgeInsets.symmetric(horizontal: _tableW * 1.25, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: hover.isNotEmpty ? 0.08 : 0),
          ),
          child: Center(
            child: Wrap(
              spacing: _tableW * 0.3,
              runSpacing: _tableW * 0.25,
              alignment: WrapAlignment.center,
              children: [for (var k = 0; k < table.length; k++) _pair(table[k], k, sel)],
            ),
          ),
        ),
      ),
    );
  }

  /// Колода слева: стопка рубашек, из-под неё торчит козырь. Пустая — крупная масть козыря.
  Widget _deck(Map g) {
    final n = g['deck'] as int;
    final w = _tableW;
    final trump = g['trump'] as String;
    return SizedBox(
      width: w * 1.5,
      height: w * 1.45 + 8,
      child: Stack(clipBehavior: Clip.none, children: [
        if (n > 0)
          Positioned(
            left: w * 0.62,
            top: w * 0.2,
            child: Transform.rotate(angle: math.pi / 2, child: PlayingCard(g['trump_card'] as String, width: w)),
          )
        else
          Positioned.fill(
            child: Center(
              child: Text(suitSymbol(trump),
                  style: TextStyle(
                      fontSize: w * 0.9,
                      color: ('DH'.contains(trump) ? const Color(0xFFFF6B6B) : Colors.black)
                          .withValues(alpha: 0.55))),
            ),
          ),
        for (var k = 0; k < math.min(3, n - 1); k++)
          Positioned(left: k * 1.5, top: 4 - k * 1.5, child: PlayingCard(null, width: w)),
        Positioned(left: 0, top: 4, child: SizedBox(key: _deckKey, width: w, height: w * 1.45)),
        if (n > 0)
          Positioned(
            left: 0,
            top: 4,
            width: w,
            height: w * 1.45,
            child: Center(child: _badge('$n', Colors.black54)),
          ),
      ]),
    );
  }

  /// Отбой справа, наполовину за краем.
  Widget _discard(Map g) {
    final n = math.min(g['discard'] as int, 6);
    final w = _tableW;
    return SizedBox(
      key: _discardKey,
      width: w,
      height: w * 1.45,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var k = 0; k < n; k++)
          Transform.rotate(angle: 0.35 + (k * 37 % 11 - 5) * 0.06, child: PlayingCard(null, width: w)),
      ]),
    );
  }

  /// Пара на столе; на неотбитую карту бросают карту для защиты.
  Widget _pair(List<String?> p, int k, String? sel) {
    final w = _tableW;
    Widget card(String x, {VoidCallback? onTap}) => KeyedSubtree(
          key: _tableKeys.putIfAbsent(x, GlobalKey.new),
          child: Visibility(
            visible: !_hiddenTable.contains(x),
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: PlayingCard(x, width: w, onTap: onTap),
          ),
        );
    return SizedBox(
      width: w * 1.25,
      height: w * 1.45 + w * 0.3,
      child: Stack(children: [
        DragTarget<String>(
          onWillAcceptWithDetails: (_) => p[1] == null,
          onAcceptWithDetails: (d) => _drop(d.data, k),
          builder: (_, hover, _) => AnimatedScale(
            scale: hover.isNotEmpty ? 1.08 : 1,
            duration: const Duration(milliseconds: 120),
            child: card(p[0]!, onTap: sel != null && p[1] == null ? () => _drop(sel, k) : null),
          ),
        ),
        if (p[1] != null)
          Positioned(
              left: w * 0.22,
              top: w * 0.28,
              child: Transform.rotate(angle: 0.12, child: card(p[1]!))),
      ]),
    );
  }

  /// Рука веером: карты внахлёст по дуге, тянуть вверх — на стол.
  Widget _handFan(List<String> hand, double width) {
    final n = hand.length;
    final cw = _handW;
    final step = n <= 1 ? 0.0 : math.min(cw * 0.62, (width - 24 - cw) / (n - 1));
    final x0 = (width - (step * (n - 1) + cw)) / 2;
    final spread = n <= 1 ? 0.0 : math.min(0.07, 0.55 / n);
    return SizedBox(
      key: _handKey,
      height: cw * 1.45 + 34,
      width: width,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < n; i++)
          Builder(builder: (_) {
            final rel = i - (n - 1) / 2;
            final x = hand[i];
            return Positioned(
              left: x0 + step * i,
              top: 20 + math.min(26.0, rel * rel * 1.3),
              child: Transform.rotate(
                angle: rel * spread,
                child: Visibility(
                  visible: !_hiddenHand.contains(x),
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Draggable<String>(
                    data: x,
                    affinity: Axis.vertical,
                    onDragStarted: () => setState(() => _sel = null),
                    feedback: Material(
                      type: MaterialType.transparency,
                      child: Transform.rotate(angle: -0.06, child: PlayingCard(x, width: cw * 1.05)),
                    ),
                    childWhenDragging: SizedBox(width: cw, height: cw * 1.45),
                    child: PlayingCard(x,
                        width: cw,
                        selected: x == _sel,
                        onTap: () => setState(() => _sel = _sel == x ? null : x)),
                  ),
                ),
              ),
            );
          }),
      ]),
    );
  }

  // ── нижняя панель: одна большая кнопка, статус и моя аватарка ──
  Widget _bottomBar(Map room, Map? g) {
    final me = c.me;
    String status = '';
    (String, Color, VoidCallback)? action;
    var waitingMe = false;
    if (g == null) {
      final seats = (room['seats'] as List).cast<Map>();
      final mine = seats.firstWhere((s) => s['id'] == me, orElse: () => const {});
      if (mine['ready'] == true) {
        status = 'Ждём остальных…';
      } else {
        status = 'Нажмите, когда готовы';
        action = ('Готов', const Color(0xFF2DBE60), c.ready);
      }
    } else if (g['finished'] != true) {
      final can = (g['can'] as Map).cast<String, dynamic>();
      final waiting = (g['waiting'] as List).cast<int>();
      final table = g['table'] as List;
      waitingMe = waiting.contains(me);
      if ((g['out'] as List).contains(me)) {
        status = 'Вы вышли из игры 🎉';
      } else if (me == g['defender'] && waitingMe) {
        status = 'Ваша защита';
      } else if (me == g['attacker'] && table.isEmpty) {
        status = 'Ваш ход';
      } else if (waitingMe) {
        status = g['taking'] == true ? 'Берёт — можно подкинуть' : 'Можно подкинуть';
      } else if (waiting.isNotEmpty) {
        status = 'Ходит ${waiting.map(_nick).join(', ')}';
      }
      if (can['take'] == true) {
        action = ('Беру', const Color(0xFFE0A030), () => _do('take'));
      } else if (can['pass'] == true) {
        action = (g['taking'] == true ? 'Пас' : 'Бито', const Color(0xFF2DBE60), () => _do('pass'));
      }
    }
    final a = action;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(children: [
            const SizedBox(width: 12),
            SizedBox(
              width: 128,
              height: 48,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: a == null
                    ? const SizedBox()
                    : FilledButton(
                        key: ValueKey(a.$1),
                        style: FilledButton.styleFrom(
                            backgroundColor: a.$2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: a.$3,
                        child: Text(a.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      ),
              ),
            ),
            Expanded(
              child: Text(status,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: const TextStyle(color: Color(0xFF1B2A41), fontWeight: FontWeight.w600)),
            ),
            if (me != null)
              KeyedSubtree(
                  key: _avatarKeys.putIfAbsent(me, GlobalKey.new),
                  child: _avatar(me, size: 44, turn: waitingMe)),
            const SizedBox(width: 10),
          ]),
        ),
      ),
    );
  }

  /// Карта брошена на стол (idx == null) или на карту стола idx.
  /// Что это значит — решает роль; правильность хода проверяет сервер.
  void _drop(String card, int? idx) {
    final g = c.game;
    if (g == null) return;
    final defender = g['defender'] == c.me;
    final table = g['table'] as List;
    if (defender && idx != null && (table[idx] as List)[1] == null) {
      _do('defend', card: card, idx: idx);
    } else if (defender && idx == null) {
      _do('transfer', card: card);
    } else if (!defender) {
      _do('throw', card: card);
    }
  }

  void _do(String t, {String? card, int? idx}) {
    c.act(t, card: card, idx: idx);
    setState(() => _sel = null);
  }

  Widget _result(Map room) {
    final res = c.result ?? const {};
    final loser = res['loser'];
    final me = c.me;
    final seats = (room['seats'] as List);
    final ready = seats.where((s) => s['ready'] == true).length;
    final full = seats.length == (room['rules'] as Map)['players'];
    final meReady = seats.any((s) => s['id'] == me && s['ready'] == true);
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.all(28),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
              loser == null
                  ? 'Ничья!'
                  : loser == me
                      ? 'Вы дурак 🙈'
                      : 'Победа! 🎉',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (loser != null && loser != me)
            Text('Дурак: ${res['loser_nick']}', style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          if (full)
            FilledButton(
                onPressed: meReady ? null : c.ready, child: Text('Ещё раз ($ready/${seats.length})'))
          else
            const Text('Кто-то вышел — ждём нового игрока', style: TextStyle(color: AppColors.textDim)),
          TextButton(onPressed: c.leave, child: const Text('Выйти')),
        ]),
      ),
    );
  }
}
