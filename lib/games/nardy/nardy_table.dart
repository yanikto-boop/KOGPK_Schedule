import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart';
import 'nardy_client.dart';

const _gold = Color(0xFFFFD166);
const _hl = Color(0xFFE2A93B);

/// Цвета шашек: [заливка, кант, цифра] — белые и чёрные.
const _ck = [
  [Color(0xFFF3EBDD), Color(0xFFBFAF92), Color(0xFF5B4A32)],
  [Color(0xFF2B2522), Color(0xFF0E0B0A), Color(0xFFE9DCC6)],
];

/// Геометрия доски: лоток · 6 пунктов · бар · 6 пунктов · лоток. Доска — в координатах
/// игрока: сверху пункты 0..11 справа налево (0 — голова), снизу 12..23 слева направо,
/// дом — справа снизу, 24 — выброшенные.
class _Geo {
  final double c, x0, y0, bw, bh;
  _Geo._(this.c, this.x0, this.y0, this.bw, this.bh);
  static const units = 0.8 + 6 + 0.6 + 6 + 0.8;
  factory _Geo.fit(Size s) {
    final c = math.min((s.width - 8) / units, (s.height - 8) / 13.2);
    final bw = units * c, bh = math.min(s.height - 8, 17 * c);
    return _Geo._(c, (s.width - bw) / 2, (s.height - bh) / 2, bw, bh);
  }

  double get fx => x0 + 0.8 * c;

  /// Центр пункта по x, край доски по y и направление стопки (1 — вниз).
  (double, double, int) col(int q) {
    final top = q < 12, k = top ? 11 - q : q - 12;
    final x = fx + (k + 0.5) * c + (k >= 6 ? 0.6 * c : 0);
    return (x, top ? y0 + c * 0.25 : y0 + bh - c * 0.25, top ? 1 : -1);
  }

  (double, double, int) tray(bool mine) =>
      mine ? (x0 + bw - 0.4 * c, y0 + bh - c * 0.25, -1) : (x0 + 0.4 * c, y0 + c * 0.25, 1);

  /// Центр k-й шашки в стопке из n: до пяти — вплотную, дальше сжимаем.
  Offset slot((double, double, int) base, int k, int n) {
    final d = c * 0.96, maxH = bh * 0.42;
    final step = n > 1 ? math.min(d, (maxH - d) / (n - 1)) : d;
    return Offset(base.$1, base.$2 + base.$3 * (d / 2 + k * step));
  }

  /// Пункт под пальцем: 0..23, 24 — свой лоток, null — мимо.
  int? hit(Offset p) {
    if (p.dx > x0 + bw - 0.8 * c - 2 && p.dy > y0 + bh / 2) return 24;
    final top = p.dy < y0 + bh / 2;
    var x = p.dx - fx;
    if (x < 0 || x > 12.6 * c) return null;
    if (x > 6 * c && x < 6.6 * c) return null;
    if (x >= 6.6 * c) x -= 0.6 * c;
    final k = math.min(11, (x / c).floor());
    return top ? 11 - k : 12 + k;
  }
}

class NardyTableScreen extends StatefulWidget {
  const NardyTableScreen({super.key});
  @override
  State<NardyTableScreen> createState() => _NardyTableScreenState();
}

class _NardyTableScreenState extends State<NardyTableScreen> with SingleTickerProviderStateMixin {
  final c = NardyClient.instance;
  StreamSubscription? _err;
  Timer? _tick;
  bool _popped = false;
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..addListener(() => setState(() {}));

  int _ver = -1;
  int? _sel;
  Map? _last; // едущая шашка {mine, from, to}
  String _note = '';
  DateTime _noteAt = DateTime(2000);
  _Geo? _geo;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
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
    _err?.cancel();
    _tick?.cancel();
    _anim.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get g => c.game;
  bool get _myTurn => g != null && g!['my_turn'] == true;

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

  /// Новое состояние: подсказка, анимация последнего шага, автовыбор единственной шашки.
  void _absorb() {
    final game = g;
    if (game == null) {
      _ver = -1;
      return;
    }
    final v = game['version'] as int;
    if (v != _ver) {
      final last = game['last'] as Map?;
      if (_ver >= 0 && v == _ver + 1 && last != null && game['finished'] != true) {
        _last = last;
        _anim.forward(from: 0).whenComplete(() {
          if (mounted) setState(() => _last = null);
        });
      } else {
        _last = null;
      }
      final note = game['note'] as String? ?? '';
      if (note.isNotEmpty) {
        _note = note;
        _noteAt = DateTime.now();
      }
      _ver = v;
      _sel = null;
    }
    if (_myTurn && _sel == null) {
      final src = _moves.map((m) => m.$1).toSet();
      if (src.length == 1) _sel = src.first;
    }
  }

  List<(int, int)> get _moves => ((g?['moves'] as List?) ?? const [])
      .map((m) => ((m['from'] as num).toInt(), (m['to'] as num).toInt()))
      .toList();

  List<int> get _targets => !_myTurn || _sel == null ? const [] : [for (final m in _moves) if (m.$1 == _sel) m.$2];

  void _onTap(TapUpDetails d) {
    final geo = _geo;
    if (geo == null || !_myTurn) return;
    final q = geo.hit(d.localPosition);
    if (q == null) {
      setState(() => _sel = null);
      return;
    }
    if (_sel != null && _targets.contains(q)) {
      HapticFeedback.selectionClick();
      c.move(_sel!, q);
      setState(() => _sel = null);
      return;
    }
    setState(() => _sel = _moves.any((m) => m.$1 == q) ? q : null);
  }

  String _seatNick(int i) {
    final seats = (c.room?['seats'] as List?) ?? const [];
    return i < seats.length ? '${seats[i]['nick']}' : '…';
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
        backgroundColor: const Color(0xFF1E1510),
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
          const Text('Длинные нарды', style: TextStyle(fontWeight: FontWeight.w600)),
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
              if (c.result?['winner_nick'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Победил ${c.result!['winner_nick']}'),
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
    final finished = game['finished'] == true && _last == null;
    final showNote = _note.isNotEmpty && DateTime.now().difference(_noteAt).inMilliseconds < 4500;
    final color = (game['color'] as num).toInt();
    final hint = game['finished'] == true
        ? ''
        : _myTurn
            ? (_sel == null ? 'Ваш ход · тапните шашку' : 'Тапните подсвеченный пункт')
            : 'Ходит ${_seatNick((game['turn'] as num).toInt())}…';
    return Stack(children: [
      Column(children: [
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
            child: Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: _leave),
              Expanded(child: _chip(1 - color, false)),
              const SizedBox(width: 6),
              Expanded(child: _chip(color, true)),
            ]),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (_, box) {
            _geo = _Geo.fit(box.biggest);
            return GestureDetector(
              onTapUp: _onTap,
              child: Stack(children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BoardPainter(
                      geo: _geo!,
                      game: game,
                      sel: _myTurn ? _sel : null,
                      targets: _targets,
                      movable: _myTurn ? _moves.map((m) => m.$1).toSet() : const {},
                      last: _last,
                      t: Curves.easeOut.transform(_anim.value),
                    ),
                  ),
                ),
                if (showNote)
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
                              BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(10)),
                          child: Text(_note,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ),
                  ),
              ]),
            );
          }),
        ),
        Container(
          color: const Color(0xFF2A1E16),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
              child: Row(children: [
                Expanded(child: Text(hint, style: const TextStyle(fontSize: 13, color: Colors.white70))),
                FilledButton.tonalIcon(
                  onPressed: game['can_undo'] == true
                      ? () {
                          setState(() => _sel = null);
                          c.undo();
                        }
                      : null,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('Отменить'),
                ),
              ]),
            ),
          ),
        ),
      ]),
      if (finished) _over(game),
    ]);
  }

  Widget _chip(int seat, bool mine) {
    final game = g!;
    final on = game['finished'] != true && game['turn'] == seat;
    final left = _left;
    final k = mine ? 0 : 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: on ? _gold.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: on ? _gold : Colors.transparent, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: _ck[seat][0], border: Border.all(color: Colors.white54)),
          ),
          Expanded(
            child: Text('${mine ? '🫵 ' : ''}${_seatNick(seat)}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (on && left != null) Text('$left', style: const TextStyle(color: _gold, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 2),
        Text('пипсов ${(game['pips'] as List)[k]} · выброшено ${(game['off'] as List)[k]}/15',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
      ]),
    );
  }

  Widget _over(Map game) {
    final win = game['winner'] == game['me'];
    final title = '${win ? '🏆 Победа!' : 'Поражение'}${game['mars'] == true ? ' · марс' : ''}';
    final waiting = ((c.room?['seats'] as List?) ?? const []).any((s) => s['id'] == c.me && s['ready'] == true);
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        alignment: Alignment.center,
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: const Color(0xFF2E2119), borderRadius: BorderRadius.circular(18)),
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

class _BoardPainter extends CustomPainter {
  final _Geo geo;
  final Map game;
  final int? sel;
  final List<int> targets;
  final Set<int> movable;
  final Map? last;
  final double t;
  _BoardPainter(
      {required this.geo,
      required this.game,
      required this.sel,
      required this.targets,
      required this.movable,
      required this.last,
      required this.t});

  static final _labels = <String, TextPainter>{};

  @override
  void paint(Canvas cv, Size size) {
    final C = geo.c;
    final color = (game['color'] as num).toInt();
    // рама, поле, бар, лотки
    cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(geo.x0 - 4, geo.y0 - 4, geo.bw + 8, geo.bh + 8), const Radius.circular(10)),
        Paint()..color = const Color(0xFF6B3F1F));
    cv.drawRect(Rect.fromLTWH(geo.fx, geo.y0, 12.6 * C, geo.bh), Paint()..color = const Color(0xFFE9D2A6));
    cv.drawRect(Rect.fromLTWH(geo.fx + 6 * C, geo.y0, 0.6 * C, geo.bh), Paint()..color = const Color(0xFF5A3418));
    final tray = Paint()..color = const Color(0xFF4A2C15);
    cv.drawRect(Rect.fromLTWH(geo.x0, geo.y0, 0.8 * C, geo.bh), tray);
    cv.drawRect(Rect.fromLTWH(geo.x0 + geo.bw - 0.8 * C, geo.y0, 0.8 * C, geo.bh), tray);
    // треугольники
    for (var q = 0; q < 24; q++) {
      final (x, y, dir) = geo.col(q);
      final h = geo.bh * 0.42;
      final path = Path()
        ..moveTo(x - C / 2 + 1, y - dir * C * 0.25)
        ..lineTo(x + C / 2 - 1, y - dir * C * 0.25)
        ..lineTo(x, y + dir * h)
        ..close();
      cv.drawPath(
          path,
          Paint()
            ..color = targets.contains(q)
                ? _hl
                : q.isOdd
                    ? const Color(0xFF8E3B2A)
                    : const Color(0xFF3E5E4A));
    }
    // шашки; едущая рисуется отдельно, на пункте назначения её пока нет
    final board = [for (final v in game['board'] as List) (v as num).toInt()];
    final off = [for (final v in game['off'] as List) (v as num).toInt()];
    final a = last;
    if (a != null) {
      final to = (a['to'] as num).toInt(), mine = a['mine'] == true;
      if (to == 24) {
        off[mine ? 0 : 1] -= 1;
      } else {
        board[to] += mine ? -1 : 1;
      }
    }
    for (var q = 0; q < 24; q++) {
      final n = board[q].abs();
      if (n == 0) continue;
      final seat = board[q] > 0 ? color : 1 - color;
      final base = geo.col(q);
      for (var k = 0; k < n; k++) {
        final top = k == n - 1;
        _checker(cv, geo.slot(base, k, n), C * 0.46, seat, top && n > 5 ? n : 0,
            top && board[q] > 0 ? (sel == q ? 2 : movable.contains(q) ? 1 : 0) : 0);
      }
    }
    // выброшенные — плашками в лотках
    for (final mine in [true, false]) {
      final n = off[mine ? 0 : 1];
      final (tx, ty, dir) = geo.tray(mine);
      final seat = mine ? color : 1 - color;
      final hh = math.min(C * 0.24, geo.bh * 0.42 / 15);
      for (var k = 0; k < n; k++) {
        final y = ty + dir * (k * hh) - (dir < 0 ? hh : 0);
        final r = Rect.fromLTWH(tx - C * 0.3, y, C * 0.6, hh - 1);
        cv.drawRect(r, Paint()..color = _ck[seat][0]);
        cv.drawRect(r, Paint()
          ..color = _ck[seat][1]
          ..style = PaintingStyle.stroke);
      }
    }
    if (targets.contains(24)) {
      final (tx, _, _) = geo.tray(true);
      cv.drawRect(
          Rect.fromLTWH(tx - C * 0.38, geo.y0 + geo.bh * 0.55, C * 0.76, geo.bh * 0.45 - 2),
          Paint()
            ..color = _hl
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3);
    }
    if (game['finished'] != true) _dice(cv, color);
    // едущая шашка
    if (a != null) {
      final from = (a['from'] as num).toInt(), to = (a['to'] as num).toInt(), mine = a['mine'] == true;
      final seat = mine ? color : 1 - color;
      final fromN = board[from].abs() + 1;
      final p1 = geo.slot(geo.col(from), fromN - 1, fromN);
      Offset p2;
      if (to == 24) {
        final (tx, ty, dir) = geo.tray(mine);
        p2 = Offset(tx, ty + dir * C);
      } else {
        final n = board[to].abs() + 1;
        p2 = geo.slot(geo.col(to), n - 1, n);
      }
      final p = Offset.lerp(p1, p2, t)! - Offset(0, math.sin(t * math.pi) * C * 0.6);
      _checker(cv, p, C * 0.46, seat, 0, 0);
    }
  }

  void _checker(Canvas cv, Offset p, double r, int seat, int label, int hl) {
    final ck = _ck[seat];
    cv.drawCircle(p + Offset(r * 0.08, r * 0.14), r, Paint()..color = Colors.black.withValues(alpha: 0.3));
    cv.drawCircle(
        p,
        r,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.35, -0.35),
            colors: [seat == 1 ? const Color(0xFF4A403B) : Colors.white, ck[0]],
          ).createShader(Rect.fromCircle(center: p, radius: r)));
    cv.drawCircle(p, r, Paint()
      ..color = ck[1]
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    cv.drawCircle(
        p,
        r * 0.62,
        Paint()
          ..color = (seat == 1 ? Colors.white : Colors.black).withValues(alpha: 0.12)
          ..style = PaintingStyle.stroke);
    if (label > 0) {
      final key = '$label/$seat/${r.round()}';
      final tp = _labels.putIfAbsent(
          key,
          () => TextPainter(
                text: TextSpan(
                    text: '$label',
                    style: TextStyle(color: ck[2], fontSize: math.max(9, r * 0.9), fontWeight: FontWeight.w700)),
                textDirection: TextDirection.ltr,
              )..layout());
      tp.paint(cv, p - Offset(tp.width / 2, tp.height / 2));
    }
    if (hl > 0) {
      cv.drawCircle(
          p,
          r + 2,
          Paint()
            ..color = hl == 2 ? _gold : _gold.withValues(alpha: 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = hl == 2 ? 3 : 1.5);
    }
  }

  static const _pips = {
    1: [(.5, .5)],
    2: [(.27, .27), (.73, .73)],
    3: [(.27, .27), (.5, .5), (.73, .73)],
    4: [(.27, .27), (.73, .27), (.27, .73), (.73, .73)],
    5: [(.27, .27), (.73, .27), (.5, .5), (.27, .73), (.73, .73)],
    6: [(.27, .25), (.73, .25), (.27, .5), (.73, .5), (.27, .75), (.73, .75)],
  };

  /// Кости — на половине того, кто ходит; сыгранные — бледнее.
  void _dice(Canvas cv, int color) {
    final C = geo.c, s = C * 0.9;
    final dice = [for (final v in game['dice'] as List) (v as num).toInt()];
    final left = [for (final v in game['left'] as List) (v as num).toInt()];
    final dbl = dice[0] == dice[1];
    final faces = dbl ? List.filled(4, dice[0]) : dice;
    final used = [for (var i = 0; i < faces.length; i++) dbl ? i >= left.length : !left.contains(faces[i])];
    final mine = game['turn'] == color;
    final cx = geo.fx + (mine ? 9.6 : 3) * C, cy = geo.y0 + geo.bh / 2;
    final gap = s * 0.25, w = faces.length * s + (faces.length - 1) * gap;
    for (var i = 0; i < faces.length; i++) {
      final x = cx - w / 2 + i * (s + gap), y = cy - s / 2;
      final a = used[i] ? 0.35 : 1.0;
      final rr = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, s, s), Radius.circular(s * 0.18));
      cv.drawRRect(rr, Paint()..color = const Color(0xFFFFFDF7).withValues(alpha: a));
      cv.drawRRect(rr, Paint()
        ..color = Colors.black.withValues(alpha: 0.35 * a)
        ..style = PaintingStyle.stroke);
      for (final (px, py) in _pips[faces[i]] ?? const <(double, double)>[]) {
        cv.drawCircle(Offset(x + px * s, y + py * s), s * 0.085, Paint()..color = const Color(0xFF1B1B1B).withValues(alpha: a));
      }
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}
