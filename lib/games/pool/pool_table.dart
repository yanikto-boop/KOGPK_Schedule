import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'pool_client.dart';
import 'pool_lobby.dart';

const _gold = Color(0xFFFFD166);
const _poolColors = [
  Color(0xFFF7F4EA), Color(0xFFF2C230), Color(0xFF1F5BC6), Color(0xFFD62F2F), Color(0xFF6A3BB0),
  Color(0xFFF07C24), Color(0xFF1E8A4C), Color(0xFF8C2A2A), Color(0xFF141414),
];

Color ballColor(String mode, int i) =>
    mode == 'pyramid' ? (i == 0 ? const Color(0xFFF3C64B) : const Color(0xFFF1E9D2)) : _poolColors[i > 8 ? i - 8 : i];

/// Стол стоит вертикально: длинный борт — по высоте экрана, «дом» — внизу.
class _Geo {
  final double s, ox, oy, W, H, R;
  _Geo._(this.s, this.ox, this.oy, this.W, this.H, this.R);
  factory _Geo.fit(Size size, Map t) {
    final W = (t['W'] as num).toDouble(), H = (t['H'] as num).toDouble(), R = (t['R'] as num).toDouble();
    final s = math.min((size.width - 12) / (H + 5.2 * R), (size.height - 12) / (W + 5.2 * R));
    return _Geo._(s, (size.width - H * s) / 2, (size.height - W * s) / 2, W, H, R);
  }
  Offset scr(double x, double y) => Offset(ox + y * s, oy + (W - x) * s);
  List<double> tab(Offset p) => [W - (p.dy - oy) / s, (p.dx - ox) / s];
}

class _Aim {
  int k;
  double dx, dy;
  List<double>? place;
  _Aim(this.k, this.dx, this.dy, this.place);
}

class PoolTableScreen extends StatefulWidget {
  const PoolTableScreen({super.key});
  @override
  State<PoolTableScreen> createState() => _PoolTableScreenState();
}

class _PoolTableScreenState extends State<PoolTableScreen> with SingleTickerProviderStateMixin {
  final c = PoolClient.instance;
  StreamSubscription? _shotSub, _err;
  Timer? _tick;
  bool _popped = false;
  late final Ticker _ticker = createTicker(_onFrame);

  int _ver = -1;
  _Aim? _aim;
  double _power = 0, _spin = 0;
  String _note = '';
  DateTime _noteAt = DateTime(2000);
  _Geo? _geo;

  // анимация удара
  Map<String, dynamic>? _shot;
  double _f = 0;
  int _ev = 0;
  Duration? _t0;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _shotSub = c.shots.stream.listen(_play);
    _err = c.errors.stream.listen((e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(e), duration: const Duration(seconds: 2)));
      }
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _absorb();
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _shotSub?.cancel();
    _err?.cancel();
    _tick?.cancel();
    _ticker.dispose();
    if (c.animating) c.animDone();
    super.dispose();
  }

  Map<String, dynamic>? get g => c.game;
  bool get _myTurn => g != null && g!['my_turn'] == true && _shot == null;

  void _onChange() {
    if (!mounted) return;
    if (c.room == null && !_popped) {
      _popped = true;
      Navigator.pop(context);
      return;
    }
    _absorb();
    setState(() {});
  }

  /// Новое состояние партии: подсказка о последнем ударе, прицел заново.
  void _absorb() {
    final game = g;
    if (game == null) {
      _ver = -1;
      return;
    }
    final v = game['version'] as int;
    if (v == _ver) return;
    _ver = v;
    final note = game['note'] as String? ?? '';
    if (note.isNotEmpty) {
      final by = game['last_by'] as int?;
      _note = (by != null && by != game['me'] ? '${_seatNick(by)}: ' : '') + note;
      _noteAt = DateTime.now();
    }
    _resetAim();
  }

  List<List<double>?> get _balls => (g!['balls'] as List)
      .map((p) => p == null ? null : [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
      .toList();

  void _resetAim() {
    final game = g!;
    final t = game['table'] as Map;
    final balls = _balls;
    var k = 0;
    if (game['can_pick'] == true && balls[0] == null) k = balls.indexWhere((p) => p != null);
    if (k < 0) return;
    final K = balls[k] ?? [(t['W'] as num) / 4.0, (t['H'] as num) / 2.0];
    final targets = (game['targets'] as List?)?.cast<int>();
    List<double>? best;
    var bd = double.infinity;
    for (var i = 0; i < balls.length; i++) {
      final p = balls[i];
      if (p == null || i == k) continue;
      if (targets != null && game['can_pick'] != true && !targets.contains(i)) continue;
      final d = math.pow(p[0] - K[0], 2) + math.pow(p[1] - K[1], 2);
      if (d < bd) {
        bd = d.toDouble();
        best = p;
      }
    }
    var dx = best == null ? 1.0 : best[0] - K[0], dy = best == null ? 0.0 : best[1] - K[1];
    final l = math.sqrt(dx * dx + dy * dy);
    if (l > 0) {
      dx /= l;
      dy /= l;
    }
    _aim = _Aim(k, dx, dy, game['in_hand'] == true && balls[0] != null ? List.of(balls[0]!) : null);
    _power = 0;
    _spin = 0;
  }

  String _seatNick(int i) {
    final seats = (c.room?['seats'] as List?) ?? const [];
    return i < seats.length ? seats[i]['nick'] as String? ?? '…' : '…';
  }

  // ── удар: кадры ──
  void _play(Map<String, dynamic> shot) {
    _shot = shot;
    _f = 0;
    _ev = 0;
    _t0 = null;
    if (!_ticker.isActive) _ticker.start();
    setState(() {});
  }

  void _onFrame(Duration now) {
    final shot = _shot;
    if (shot == null) return;
    _t0 ??= now;
    _f = (now - _t0!).inMicroseconds / 1e6 * 30;
    final evs = shot['events'] as List;
    while (_ev < evs.length && (evs[_ev]['f'] as num) <= _f) {
      final e = evs[_ev++] as Map;
      if (e['pot'] != null) HapticFeedback.mediumImpact();
    }
    if (_f >= (shot['frames'] as List).length - 1) {
      _ticker.stop();
      _shot = null;
      c.animDone(); // → _onChange с новым состоянием
      if (mounted) setState(() {});
      return;
    }
    setState(() {});
  }

  List<double>? _animPos(int i) {
    final fr = _shot!['frames'] as List;
    final f0 = _f.floor().clamp(0, fr.length - 1), k = _f - f0;
    final a = fr[f0] as List, b = fr[math.min(f0 + 1, fr.length - 1)] as List;
    if (a[2 * i] == null) return null;
    final ax = (a[2 * i] as num).toDouble(), ay = (a[2 * i + 1] as num).toDouble();
    if (b[2 * i] == null) return [ax, ay];
    return [ax + ((b[2 * i] as num) - ax) * k, ay + ((b[2 * i + 1] as num) - ay) * k];
  }

  List<List<double>?> _positions() {
    if (_shot != null) return List.generate(16, _animPos);
    final balls = _balls;
    if (_myTurn && _aim?.place != null) balls[0] = _aim!.place;
    final opp = c.oppAim;
    if (!_myTurn && opp != null && opp['place'] is List) {
      balls[0] = [(opp['place'][0] as num).toDouble(), (opp['place'][1] as num).toDouble()];
    }
    return balls;
  }

  // ── ввод ──
  String? _drag; // 'place' | 'aim'
  Offset _down = Offset.zero;
  bool _moved = false;
  DateTime _aimSent = DateTime(2000);

  void _sendAim({bool force = false}) {
    final a = _aim;
    if (a == null) return;
    final now = DateTime.now();
    if (!force && now.difference(_aimSent).inMilliseconds < 120) return;
    _aimSent = now;
    c.send({'t': 'aim', 'dx': a.dx, 'dy': a.dy, 'ball': a.k, 'power': _power, 'place': a.place});
  }

  void _onDown(PointerDownEvent e) {
    if (!_myTurn || _geo == null || _aim == null) return;
    _down = e.localPosition;
    _moved = false;
    final p = _aim!.place;
    if (p != null && (e.localPosition - _geo!.scr(p[0], p[1])).distance < math.max(26, _geo!.R * _geo!.s * 2.2)) {
      _drag = 'place';
    } else {
      _drag = 'aim';
      _aimAt(e.localPosition);
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (_drag == null) return;
    if ((e.localPosition - _down).distance > 6) _moved = true;
    if (_drag == 'place') {
      _placeAt(e.localPosition);
    } else if (_moved) {
      _aimAt(e.localPosition);
    }
  }

  void _onUp(PointerUpEvent e) {
    if (_drag == 'aim' && !_moved && g?['can_pick'] == true) {
      // тап по шару в американке — бить этим шаром
      final t = _geo!.tab(e.localPosition);
      final balls = _balls;
      for (var i = 0; i < balls.length; i++) {
        final p = balls[i];
        if (p != null && i != _aim!.k && math.sqrt(math.pow(p[0] - t[0], 2) + math.pow(p[1] - t[1], 2)) < _geo!.R * 1.6) {
          setState(() => _aim!.k = i);
          _sendAim(force: true);
          break;
        }
      }
    }
    _drag = null;
  }

  void _aimAt(Offset at) {
    final K = _positions()[_aim!.k];
    if (K == null) return;
    final t = _geo!.tab(at);
    final dx = t[0] - K[0], dy = t[1] - K[1], l = math.sqrt(dx * dx + dy * dy);
    if (l < 1) return;
    setState(() {
      _aim!.dx = dx / l;
      _aim!.dy = dy / l;
    });
    _sendAim();
  }

  void _placeAt(Offset at) {
    final game = g!, t = game['table'] as Map, R = _geo!.R;
    final p = _geo!.tab(at);
    final maxX = game['kitchen'] == true ? (t['kitchen'] as num).toDouble() : _geo!.W - R;
    final x = p[0].clamp(R, maxX), y = p[1].clamp(R, _geo!.H - R);
    final balls = _balls;
    for (var i = 1; i < balls.length; i++) {
      final b = balls[i];
      if (b != null && math.sqrt(math.pow(b[0] - x, 2) + math.pow(b[1] - y, 2)) < 2 * R) return;
    }
    setState(() => _aim!.place = [x, y]);
    _sendAim();
  }

  void _fine(double dxPx) {
    if (!_myTurn || _aim == null) return;
    final a = dxPx * 0.06 * math.pi / 180, dx = _aim!.dx, dy = _aim!.dy;
    setState(() {
      _aim!.dx = dx * math.cos(a) - dy * math.sin(a);
      _aim!.dy = dx * math.sin(a) + dy * math.cos(a);
    });
    _sendAim();
  }

  void _shoot() {
    final a = _aim, game = g;
    if (a == null || game == null) return;
    HapticFeedback.lightImpact();
    c.send({
      't': 'shot',
      'dx': a.dx,
      'dy': a.dy,
      'power': _power,
      'spin': _spin,
      if (game['in_hand'] == true && a.place != null) 'place': a.place!.map((v) => (v * 10).round() / 10).toList(),
      if (game['can_pick'] == true) 'ball': a.k,
    });
  }

  bool get _playing => g != null && g!['finished'] != true;

  Future<void> _leave() async {
    if (_playing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Выйти из партии?'),
          content: const Text('Засчитается поражение.'),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1A14),
        body: c.room == null ? const SizedBox() : (g == null ? _waiting() : _table()),
      ),
    );
  }

  Widget _waiting() {
    final r = c.room!;
    final seats = (r['seats'] as List).cast<Map>();
    final me = seats.where((s) => s['id'] == c.me).firstOrNull;
    final full = seats.length == 2;
    return SafeArea(
      child: Column(children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
          Text(poolModes[r['mode']] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(r['private'] == true ? 'Код комнаты — продиктуйте другу' : 'Комната в общем списке. Код:',
                  style: const TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 6),
              SelectableText('${r['id']}',
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4)),
              const SizedBox(height: 18),
              for (final s in seats)
                Text('${s['ready'] == true ? '✅' : '⏳'} ${s['nick']}${s['online'] == true ? '' : ' (нет связи)'}'),
              if (!full)
                const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('ждём соперника…', style: TextStyle(color: AppColors.textDim))),
              if (c.result != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(c.result!['winner_nick'] != null ? 'Победил ${c.result!['winner_nick']}' : 'Ничья'),
                ),
              const SizedBox(height: 16),
              if (full && me != null && me['ready'] != true)
                FilledButton(onPressed: c.ready, child: const Padding(padding: EdgeInsets.all(10), child: Text('Готов')))
              else if (full)
                const Text('ждём, пока соперник нажмёт «Готов»', style: TextStyle(color: AppColors.textDim)),
            ]),
          ),
        ),
      ]),
    );
  }

  int? get _left => c.deadline == null ? null : c.deadline!.difference(DateTime.now()).inSeconds.clamp(0, 99);

  Widget _table() {
    final game = g!;
    final finished = game['finished'] == true && _shot == null;
    final showNote = _note.isNotEmpty && DateTime.now().difference(_noteAt).inMilliseconds < 4500;
    final hint = showNote
        ? _note
        : _myTurn
            ? (game['in_hand'] == true
                ? 'Ваш удар · биток можно передвинуть'
                : game['can_pick'] == true
                    ? 'Ваш удар · тапните шар, которым бить'
                    : 'Ваш удар')
            : '';
    return Stack(children: [
      Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
              Expanded(child: _chip(0)),
              const SizedBox(width: 6),
              Expanded(child: _chip(1)),
            ]),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            _geo = _Geo.fit(box.biggest, game['table'] as Map);
            return Listener(
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: _onUp,
              child: Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TablePainter(
                      geo: _geo!,
                      game: game,
                      balls: _positions(),
                      aim: _shot != null
                          ? null
                          : _myTurn
                              ? _aim
                              : (c.oppAim != null && game['my_turn'] != true)
                                  ? _Aim((c.oppAim!['ball'] as num? ?? 0).toInt(), (c.oppAim!['dx'] as num).toDouble(),
                                      (c.oppAim!['dy'] as num).toDouble(), null)
                                  : null,
                      power: _myTurn ? _power : (c.oppAim?['power'] as num? ?? 0).toDouble(),
                    ),
                  ),
                ),
                if (hint.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 10,
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration:
                              BoxDecoration(color: Colors.black.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(10)),
                          child: Text(hint,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
              ]),
            );
          }),
        ),
        _controls(),
      ]),
      if (finished) _over(game),
    ]);
  }

  Widget _chip(int i) {
    final game = g!;
    final on = game['finished'] != true && game['turn'] == i;
    final left = _left;
    Widget balls;
    if (game['mode'] == 'pool') {
      final grp = (game['groups'] as List)[i];
      final set = grp == 'solid' ? [1, 2, 3, 4, 5, 6, 7] : grp == 'stripe' ? [9, 10, 11, 12, 13, 14, 15] : <int>[];
      final bl = game['balls'] as List;
      balls = set.isEmpty
          ? const Text('группа не выбрана', style: TextStyle(fontSize: 11, color: Colors.white60))
          : Wrap(spacing: 2, children: [
              for (final b in set)
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bl[b] != null ? ballColor('pool', b) : Colors.transparent,
                    border: Border.all(color: ballColor('pool', b), width: 1.5),
                  ),
                ),
            ]);
    } else {
      balls = Text('${(game['scores'] as List)[i]} из ${game['need']}', style: const TextStyle(fontSize: 12));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: on ? _gold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: on ? _gold : Colors.transparent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${i == game['me'] ? '🫵 ' : ''}${_seatNick(i)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (on && left != null) Text('$left', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 3),
        SizedBox(height: 14, child: balls),
      ]),
    );
  }

  Widget _controls() {
    final on = _myTurn;
    return Container(
      color: const Color(0xFF16241B),
      padding: EdgeInsets.fromLTRB(10, 8, 10, 10 + MediaQuery.of(context).padding.bottom),
      child: Opacity(
        opacity: on ? 1 : 0.35,
        child: IgnorePointer(
          ignoring: !on,
          child: Row(children: [
            // винт: тап выше центра — накат, ниже — оттяжка
            GestureDetector(
              onTapDown: (d) {
                final v = -((d.localPosition.dy / 50) - 0.5) * 2;
                setState(() => _spin = v.abs() < 0.25 ? 0 : ((v * 2).round() / 2).clamp(-1.0, 1.0));
              },
              child: SizedBox(
                width: 58,
                child: Column(children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                          center: Alignment(-0.3, -0.4), colors: [Colors.white, Color(0xFFDDDDDD), Color(0xFFAAAAAA)]),
                    ),
                    child: Align(
                      alignment: Alignment(0, -_spin * 0.7),
                      child: Container(
                          width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.red)),
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text('Винт', style: TextStyle(fontSize: 11, color: Colors.white70)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(children: [
                GestureDetector(
                  onHorizontalDragUpdate: (d) => _fine(d.delta.dx),
                  child: Container(
                    height: 30,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                    child: CustomPaint(
                      painter: _TicksPainter(),
                      child: const Center(
                        child: Text('‹ точная наводка ›',
                            style: TextStyle(fontSize: 11, color: Colors.white60)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                LayoutBuilder(builder: (_, box) {
                  void setP(double x) => setState(() => _power = (x / box.maxWidth).clamp(0.0, 1.0));
                  return GestureDetector(
                    onHorizontalDragStart: (d) => setP(d.localPosition.dx),
                    onHorizontalDragUpdate: (d) {
                      setP(d.localPosition.dx);
                      _sendAim();
                    },
                    onHorizontalDragEnd: (_) {
                      if (_power >= 0.03) _shoot();
                      setState(() => _power = 0);
                    },
                    onHorizontalDragCancel: () => setState(() => _power = 0),
                    child: Container(
                      height: 44,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
                      child: Stack(children: [
                        FractionallySizedBox(
                          widthFactor: _power,
                          child: Container(
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(colors: [Color(0xFF2DBE60), _gold, Color(0xFFE5484D)])),
                          ),
                        ),
                        Center(
                          child: Text(_power > 0 ? '${(_power * 100).round()}%' : 'Сила: потяни вправо и отпусти',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                        ),
                      ]),
                    ),
                  );
                }),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _over(Map game) {
    final w = game['winner'];
    final title = w == null ? 'Ничья' : w == game['me'] ? '🏆 Победа!' : 'Поражение';
    final waiting = ((c.room?['seats'] as List?) ?? const []).any((s) => s['id'] == c.me && s['ready'] == true);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: const Color(0xFF1B2A20), borderRadius: BorderRadius.circular(18)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(game['note'] as String? ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: waiting ? null : c.ready,
              child: Padding(padding: const EdgeInsets.all(10), child: Text(waiting ? 'Ждём соперника…' : 'Ещё партию')),
            ),
            TextButton(onPressed: c.leave, child: const Text('Выйти')),
          ]),
        ),
      ),
    );
  }
}

class _TicksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 2;
    for (var x = 6.0; x < size.width; x += 12) {
      canvas.drawLine(Offset(x, 6), Offset(x, size.height - 6), p);
    }
  }

  @override
  bool shouldRepaint(_TicksPainter old) => false;
}

class _TablePainter extends CustomPainter {
  final _Geo geo;
  final Map game;
  final List<List<double>?> balls;
  final _Aim? aim;
  final double power;
  _TablePainter({required this.geo, required this.game, required this.balls, this.aim, this.power = 0});

  static final _labels = <String, TextPainter>{};

  @override
  void paint(Canvas c, Size size) {
    final t = game['table'] as Map;
    final R = geo.R, s = geo.s, W = geo.W, H = geo.H;
    final pool = game['mode'] == 'pool';
    final o = geo.scr(W, 0), fr = R * 2.6 * s;
    final cloth = Rect.fromLTWH(o.dx, o.dy, H * s, W * s);
    c.drawRRect(RRect.fromRectAndRadius(cloth.inflate(fr), Radius.circular(fr * 0.6)), Paint()..color = const Color(0xFF5A3418));
    c.drawRect(cloth.inflate(R * s * 0.9), Paint()..color = pool ? const Color(0xFF14603A) : const Color(0xFF0E5A4A));
    c.drawRect(
        cloth,
        Paint()
          ..shader = RadialGradient(
                  colors: pool ? const [Color(0xFF23935A), Color(0xFF18744A)] : const [Color(0xFF1C8A70), Color(0xFF126A57)])
              .createShader(cloth.inflate(cloth.height * 0.2)));
    final pockets = (t['pockets'] as List).cast<List>();
    for (var i = 0; i < pockets.length; i++) {
      final side = i == 1 || i == 4;
      final r = (side ? (t['side'] as num) * 0.95 : (t['corner'] as num) * 0.62) * s + R * s * 0.25;
      c.drawCircle(geo.scr((pockets[i][0] as num).toDouble(), (pockets[i][1] as num).toDouble()), r,
          Paint()..color = const Color(0xFF0B0B0B));
    }
    final dot = Paint()..color = const Color(0xFFE8D7A8);
    for (var k = 1; k < 8; k++) {
      if (k == 4) continue;
      final a = geo.scr(W * k / 8, 0), b = geo.scr(W * k / 8, H);
      c.drawCircle(a.translate(-fr * 0.55, 0), 2, dot);
      c.drawCircle(b.translate(fr * 0.55, 0), 2, dot);
    }
    if (game['kitchen'] == true || game['breaking'] == true) {
      final kx = (t['kitchen'] as num).toDouble();
      final a = geo.scr(kx, 0), b = geo.scr(kx, H);
      final p = Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..strokeWidth = 1;
      for (var x = a.dx; x < b.dx; x += 12) {
        c.drawLine(Offset(x, a.dy), Offset(math.min(x + 6, b.dx), a.dy), p);
      }
    }
    final a = aim;
    if (a != null && a.k < balls.length && balls[a.k] != null) {
      c.save();
      c.clipRect(cloth.inflate(fr));
      _guide(c, a, size);
      c.restore();
    }
    for (var i = 0; i < balls.length; i++) {
      final p = balls[i];
      if (p != null) _ball(c, i, geo.scr(p[0], p[1]), R * s, pool, a != null && a.k == i && game['can_pick'] == true);
    }
  }

  void _ball(Canvas c, int i, Offset at, double r, bool pool, bool sel) {
    final col = ballColor(pool ? 'pool' : 'pyramid', i);
    c.drawCircle(at.translate(r * 0.15, r * 0.2), r, Paint()..color = Colors.black.withValues(alpha: 0.35));
    c.save();
    c.clipPath(Path()..addOval(Rect.fromCircle(center: at, radius: r)));
    if (pool && i > 8) {
      c.drawRect(Rect.fromCircle(center: at, radius: r), Paint()..color = _poolColors[0]);
      c.drawRect(Rect.fromLTWH(at.dx - r, at.dy - r * 0.55, 2 * r, r * 1.1), Paint()..color = col);
    } else {
      c.drawRect(Rect.fromCircle(center: at, radius: r), Paint()..color = col);
    }
    if (i > 0 && r >= 5) {
      if (pool) c.drawCircle(at, r * 0.5, Paint()..color = Colors.white);
      final fs = math.max(7.0, r * 0.72);
      final key = '$i@${fs.toStringAsFixed(1)}';
      final tp = _labels.putIfAbsent(
          key,
          () => TextPainter(
                text: TextSpan(
                    text: '$i', style: TextStyle(color: const Color(0xFF111111), fontSize: fs, fontWeight: FontWeight.bold)),
                textDirection: TextDirection.ltr,
              )..layout());
      tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
    } else if (i == 0 && pool) {
      c.drawCircle(at, r * 0.18, Paint()..color = const Color(0xFFD62F2F));
    }
    c.drawRect(
        Rect.fromCircle(center: at, radius: r),
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.45),
            radius: 1.1,
            colors: [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0.08), Colors.black.withValues(alpha: 0.35)],
            stops: const [0, 0.25, 1],
          ).createShader(Rect.fromCircle(center: at, radius: r)));
    c.restore();
    if (sel) {
      c.drawCircle(
          at,
          r + 3,
          Paint()
            ..color = _gold
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  /// Луч от шара до первого шара или борта, «призрак» в точке удара, куда
  /// пойдёт прицельный (красным — если это чужой шар) и куда — биток.
  void _guide(Canvas c, _Aim a, Size size) {
    final R = geo.R, s = geo.s, W = geo.W, H = geo.H;
    final K = balls[a.k]!, dx = a.dx, dy = a.dy;
    var tHit = double.infinity;
    var hitI = -1;
    for (var i = 0; i < balls.length; i++) {
      final p = balls[i];
      if (p == null || i == a.k) continue;
      final fx = p[0] - K[0], fy = p[1] - K[1], b = fx * dx + fy * dy, d2 = fx * fx + fy * fy - b * b;
      if (b <= 0 || d2 >= 4 * R * R) continue;
      final tt = b - math.sqrt(4 * R * R - d2);
      if (tt < tHit) {
        tHit = tt;
        hitI = i;
      }
    }
    final tx = dx > 0 ? (W - R - K[0]) / dx : dx < 0 ? (R - K[0]) / dx : double.infinity;
    final ty = dy > 0 ? (H - R - K[1]) / dy : dy < 0 ? (R - K[1]) / dy : double.infinity;
    final tRail = math.max(0.0, math.min(tx, ty));
    final tt = math.min(tHit, tRail);
    final G = [K[0] + dx * tt, K[1] + dy * tt];
    final ks = geo.scr(K[0], K[1]), gs = geo.scr(G[0], G[1]);
    final dir = gs - ks;
    final u = dir.distance > 0 ? dir / dir.distance : const Offset(0, 1);
    final back = (R * 1.4 + power * R * 6) * s, len = math.min(size.height * 0.55, 1300 * s);
    final stick = Paint()
      ..color = const Color(0xFFC8A26B)
      ..strokeWidth = math.max(3, R * s * 0.45)
      ..strokeCap = StrokeCap.round;
    c.drawLine(ks - u * back, ks - u * (back + len), stick);
    c.drawLine(ks - u * back, ks - u * (back + 6), stick..color = const Color(0xFF2B2B2B));
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    c.drawLine(ks, gs, line);
    c.drawCircle(gs, R * s, line);
    if (tHit <= tRail && hitI >= 0) {
      final B = balls[hitI]!;
      final nx0 = B[0] - G[0], ny0 = B[1] - G[1], nl = math.max(1e-9, math.sqrt(nx0 * nx0 + ny0 * ny0));
      final nx = nx0 / nl, ny = ny0 / nl, cos = nx * dx + ny * dy, L = 260 + 700 * cos;
      final targets = (game['targets'] as List?)?.cast<int>();
      final bad = game['mode'] == 'pool' && targets != null && !targets.contains(hitI) && game['breaking'] != true;
      final bs = geo.scr(B[0], B[1]);
      c.drawLine(bs, geo.scr(B[0] + nx * L, B[1] + ny * L), line..color = bad ? AppColors.red : _gold);
      final tx2 = dx - cos * nx, ty2 = dy - cos * ny;
      if (math.sqrt(tx2 * tx2 + ty2 * ty2) > 0.05) {
        c.drawLine(gs, geo.scr(G[0] + tx2 * 200, G[1] + ty2 * 200), line..color = Colors.white.withValues(alpha: 0.45));
      }
      if (bad) c.drawCircle(bs, R * s + 3, line..color = AppColors.red);
    } else {
      final rx = tx <= ty ? -dx : dx, ry = tx <= ty ? dy : -dy;
      c.drawLine(gs, geo.scr(G[0] + rx * 300, G[1] + ry * 300), line..color = Colors.white.withValues(alpha: 0.4));
    }
  }

  @override
  bool shouldRepaint(_TablePainter old) => true;
}
