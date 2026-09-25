import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/sfx.dart';
import '../game/board.dart';
import '../game/game_model.dart';
import '../game/profile.dart';
import 'background.dart';
import 'blocks.dart';
import 'effects.dart';
import 'game_over.dart';
import 'skins.dart';
import 'widgets.dart';

/// Геометрия экрана игры (в логических пикселях экрана).
class GameLayout {
  GameLayout(Size size, EdgeInsets pad) {
    final w = size.width;
    final h = size.height;
    topBar = Rect.fromLTWH(14, pad.top + 10, w - 28, 48);
    score = Rect.fromLTWH(14, topBar.bottom + 2, w - 28, 62);
    combo = Rect.fromLTWH(14, score.bottom, w - 28, 34);
    final availTop = combo.bottom + 8;
    final availH = h - pad.bottom - 10 - availTop;
    final boardSize = min(w - 20, availH / 1.42).clamp(200.0, 640.0);
    final trayH = boardSize * 0.37;
    final free = max(0.0, availH - boardSize - trayH);
    board = Rect.fromLTWH((w - boardSize) / 2, availTop + free * 0.3, boardSize, boardSize);
    grid = board.deflate(boardSize * 0.028);
    cell = grid.width / kN;
    trayCell = cell * 0.54;
    final trayTop = board.bottom + max(10.0, free * 0.35);
    tray = Rect.fromLTWH(0, trayTop, w, trayH);
    slots = List.generate(
      3,
      (i) => Rect.fromLTWH(board.left + i * board.width / 3, trayTop, board.width / 3, trayH),
    );
  }

  late final Rect topBar;
  late final Rect score;
  late final Rect combo;
  late final Rect board;
  late final Rect grid;
  late final double cell;
  late final double trayCell;
  late final Rect tray;
  late final List<Rect> slots;

  Rect cellRect(int i) =>
      Rect.fromLTWH(grid.left + (i % kN) * cell, grid.top + (i ~/ kN) * cell, cell, cell);
}

class _Repaint extends ChangeNotifier {
  void ping() => notifyListeners();
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late GameModel model;
  final fx = Effects();
  final _repaint = _Repaint();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastTick = Duration.zero;
  double time = 0;
  GameLayout? L;

  // перетаскивание
  int? dragSlot;
  int? _pointer;
  Offset dragPos = Offset.zero;
  double dragStart = 0;
  ({int r, int c})? target;
  Lines? preview;
  int? returnSlot;
  Rect returnFrom = Rect.zero;
  double returnStart = 0;

  final Map<int, double> popAt = {};
  double trayAnimStart = 0.1;
  double? gameOverStart;
  bool gameOverPending = false;
  bool showGameOver = false;
  late int startBest;
  bool recordCelebrated = false;
  bool showTutorial = false;

  Profile get profile => widget.profile;
  Skin get skin => profile.skin;

  @override
  void initState() {
    super.initState();
    model = profile.loadGame() ?? GameModel();
    _resetRunState();
    profile.saveGame(model);
    _kick();
    if (model.noMoves) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _startGameOver(delay: 300));
    }
  }

  void _resetRunState() {
    startBest = profile.best;
    recordCelebrated = startBest == 0 || model.score > startBest;
    showTutorial = !profile.tutorialDone && model.placements == 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // ---------- Время и анимации ----------

  bool get _animating =>
      fx.active ||
      dragSlot != null ||
      returnSlot != null ||
      preview != null ||
      time - trayAnimStart < 0.8 ||
      popAt.isNotEmpty ||
      (gameOverStart != null && time - gameOverStart! < 1.2);

  void _kick() {
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    time += dt;
    fx.update(dt);
    popAt.removeWhere((_, t) => time - t > 0.3);
    if (returnSlot != null && time - returnStart > 0.2) returnSlot = null;
    _repaint.ping();
    if (!_animating) {
      _ticker.stop();
      _lastTick = Duration.zero;
    }
  }

  // ---------- Геометрия фигур ----------

  Rect _trayRect(int slot, TrayPiece p) {
    final s = L!.slots[slot];
    final c = L!.trayCell;
    return Rect.fromCenter(center: s.center, width: p.shape.cols * c, height: p.shape.rows * c);
  }

  /// Фигура под пальцем: полноразмерная и приподнятая, чтобы палец её не закрывал.
  Rect _liftedRect(TrayPiece p) {
    final c = L!.cell;
    final w = p.shape.cols * c;
    final h = p.shape.rows * c;
    return Rect.fromCenter(center: dragPos - Offset(0, h / 2 + c * 1.3), width: w, height: h);
  }

  Rect _dragRectNow(TrayPiece p) {
    final lifted = _liftedRect(p);
    final k = ((time - dragStart) / 0.1).clamp(0.0, 1.0);
    if (k >= 1) return lifted;
    return Rect.lerp(_trayRect(dragSlot!, p), lifted, Curves.easeOut.transform(k))!;
  }

  // ---------- Касания ----------

  bool get _inputLocked => showGameOver || gameOverPending;

  void _onDown(PointerDownEvent e) {
    if (_inputLocked || dragSlot != null || L == null) return;
    for (var i = 0; i < 3; i++) {
      if (model.tray[i] == null || returnSlot == i) continue;
      if (!L!.slots[i].inflate(6).contains(e.localPosition)) continue;
      dragSlot = i;
      _pointer = e.pointer;
      dragPos = e.localPosition;
      dragStart = time;
      _updateTarget();
      Sfx.play('pick');
      Sfx.haptic(0);
      if (showTutorial) setState(() => showTutorial = false);
      _kick();
      return;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _pointer || dragSlot == null) return;
    dragPos = e.localPosition;
    _updateTarget();
    _kick();
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _pointer || dragSlot == null) return;
    _drop();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _pointer || dragSlot == null) return;
    target = null;
    _drop();
  }

  void _updateTarget() {
    final p = model.tray[dragSlot!]!;
    final lay = L!;
    final rect = _liftedRect(p);
    final fx0 = (rect.left - lay.grid.left) / lay.cell;
    final fy0 = (rect.top - lay.grid.top) / lay.cell;
    final c0 = fx0.round();
    final r0 = fy0.round();
    ({int r, int c})? best;
    var bestD = double.infinity;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        final r = r0 + dr;
        final c = c0 + dc;
        if ((r - fy0).abs() > 0.8 || (c - fx0).abs() > 0.8) continue;
        if (!model.board.canPlace(p.shape, r, c)) continue;
        final d = pow(r - fy0, 2) + pow(c - fx0, 2).toDouble();
        if (d < bestD) {
          bestD = d;
          best = (r: r, c: c);
        }
      }
    }
    if (best != target) {
      target = best;
      preview = best == null ? null : model.board.linesIfPlaced(p.shape, best.r, best.c);
      if (preview != null && preview!.isEmpty) preview = null;
    }
  }

  void _drop() {
    final slot = dragSlot!;
    final t = target;
    final piece = model.tray[slot]!;
    final from = _dragRectNow(piece);
    dragSlot = null;
    _pointer = null;
    target = null;
    preview = null;
    if (t != null) {
      _place(slot, t.r, t.c);
    } else {
      returnSlot = slot;
      returnFrom = from;
      returnStart = time;
      if (from.center.dy < L!.tray.top) Sfx.play('bad', volume: 0.7);
    }
    _kick();
  }

  // ---------- Ход ----------

  void _place(int slot, int r, int c) {
    final lay = L!;
    final piece = model.tray[slot]!;
    final res = model.place(slot, r, c);
    profile.markTutorialDone();

    for (final i in res.placement.placed) {
      popAt[i] = time;
    }
    Sfx.play('place');
    Sfx.haptic(1);

    if (res.lines > 0) _celebrate(res, piece, lay);

    if (res.trayRefilled) {
      trayAnimStart = time + (res.lines > 0 ? 0.25 : 0.08);
      Future.delayed(Duration(milliseconds: res.lines > 0 ? 250 : 80), () {
        if (mounted) Sfx.play('deal', volume: 0.8);
      });
    }

    if (!recordCelebrated && model.score > startBest) {
      recordCelebrated = true;
      fx.banner('Новый рекорд!', lay.board.center + Offset(0, -lay.cell * 1.5), lay.cell * 0.72,
          const [Color(0xFFFFF6B0), Color(0xFFFFB300)],
          delay: res.lines >= 2 ? 1.0 : 0.2);
      Future.delayed(Duration(milliseconds: res.lines >= 2 ? 1000 : 200), () {
        if (!mounted) return;
        Sfx.play('record');
        fx.confetti(Rect.fromLTWH(0, 0, lay.board.right + lay.board.left, lay.board.top), skin.palette, 70);
        _kick();
      });
    }

    profile.saveGame(model);
    if (res.gameOver) _startGameOver();
    setState(() {});
  }

  void _celebrate(MoveResult res, TrayPiece piece, GameLayout lay) {
    final color = skin.palette[piece.color];
    final placedCenter = res.placement.placed
            .map((i) => lay.cellRect(i).center)
            .reduce((a, b) => a + b) /
        res.placement.placed.length.toDouble();
    var clearCenter = Offset.zero;
    for (final i in res.placement.cleared.keys) {
      final rect = lay.cellRect(i);
      clearCenter += rect.center;
      final delay = (rect.center - placedCenter).distance / lay.cell * 0.028;
      fx.clearCell(rect, color, delay);
    }
    clearCenter /= res.placement.cleared.length.toDouble();

    final lines = res.lines;
    final streak = res.streak;
    Sfx.clear(streak);
    Sfx.haptic(lines >= 3 || streak >= 5 ? 3 : 2);

    // Если будет большая надпись по центру — очки ниже неё, комбо выше.
    final hasBanner = res.boardCleared || lines >= 2 || (streak >= 5 && streak % 5 == 0);
    final scoreAt = hasBanner
        ? lay.board.center + Offset(0, lay.cell * 1.45)
        : Offset(clearCenter.dx.clamp(lay.board.left + lay.cell * 2, lay.board.right - lay.cell * 2),
            clearCenter.dy.clamp(lay.board.top + lay.cell * 1.5, lay.board.bottom - lay.cell));
    final comboAt = hasBanner
        ? lay.board.center - Offset(0, lay.cell * 1.35)
        : scoreAt - Offset(0, lay.cell * 0.85);
    fx.floatText('+${res.gained}', scoreAt, lay.cell * 0.78,
        delay: hasBanner ? 0.25 : 0.1, rise: hasBanner ? -lay.cell * 0.5 : null);
    if (streak >= 2) {
      fx.floatText('Комбо $streak', comboAt, lay.cell * 0.5,
          colors: const [Color(0xFFFFE08A), Color(0xFFFF8A1F)], delay: 0.05);
    }
    fx.sparks(clearCenter, 12 + lines * 6, color: lighten(color, 0.5), speed: 1.2);

    const praise = ['', '', 'Хорошо!', 'Отлично!', 'Супер!', 'Потрясающе!', 'Невероятно!'];
    const praiseColors = [
      [Color(0xFFFFFFFF), Color(0xFFBFE9FF)],
      [Color(0xFFFFFFFF), Color(0xFFBFE9FF)],
      [Color(0xFFD9FFE0), Color(0xFF3DDC84)],
      [Color(0xFFFFF6B0), Color(0xFFFFB300)],
      [Color(0xFFFFE0F0), Color(0xFFFF4FA0)],
      [Color(0xFFE8DDFF), Color(0xFFA66BFF)],
      [Color(0xFFFFF0C0), Color(0xFFFF5A36)],
    ];
    if (res.boardCleared) {
      fx.banner('Чистое поле!', lay.board.center, lay.cell * 0.8, const [Color(0xFFFFFFFF), Color(0xFF6FE3FF)]);
      fx.ring(lay.board.center, Colors.white, lay.board.width * 0.8);
      fx.confetti(Rect.fromLTWH(0, 0, lay.board.right + lay.board.left, lay.board.top + 40), skin.palette, 90);
      fx.shake = lay.cell * 0.4;
      Future.delayed(const Duration(milliseconds: 150), () => Sfx.play('great'));
    } else if (lines >= 2) {
      final k = min(lines, 6);
      fx.banner(praise[k], lay.board.center, lay.cell * (0.72 + 0.04 * k), praiseColors[k]);
      fx.ring(clearCenter, lighten(color, 0.3), lay.board.width * (0.4 + 0.08 * lines));
      Future.delayed(const Duration(milliseconds: 120), () => Sfx.play('great', volume: 0.85));
      if (lines >= 3) fx.shake = lay.cell * (0.18 + 0.05 * lines);
    } else if (streak >= 5 && streak % 5 == 0) {
      fx.banner('Серия ×$streak!', lay.board.center, lay.cell * 0.75, praiseColors[4]);
    }
  }

  // ---------- Конец игры ----------

  void _startGameOver({int delay = 650}) {
    if (gameOverPending || showGameOver) return;
    gameOverPending = true;
    Future.delayed(Duration(milliseconds: delay), () {
      if (!mounted) return;
      gameOverStart = time;
      Sfx.play('over');
      Sfx.haptic(2);
      final lay = L!;
      fx.banner('Нет места!', lay.board.center, lay.cell * 0.8, const [Color(0xFFFFFFFF), Color(0xFFFF6B7D)]);
      _kick();
      Future.delayed(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => showGameOver = true);
      });
    });
  }

  void _revive() {
    final lay = L!;
    final cleared = model.revive();
    for (final e in cleared.entries) {
      final rect = lay.cellRect(e.key);
      fx.clearCell(rect, skin.palette[e.value], (rect.center - lay.board.center).distance / lay.cell * 0.03);
    }
    fx.banner('Второй шанс!', lay.board.center, lay.cell * 0.75, const [Color(0xFFE0FFE8), Color(0xFF3DDC84)]);
    Sfx.play('great');
    Sfx.haptic(3);
    setState(() {
      showGameOver = false;
      gameOverPending = false;
      gameOverStart = null;
      trayAnimStart = time + 0.3;
    });
    profile.saveGame(model);
    _kick();
    if (model.noMoves) _startGameOver();
  }

  void _newGame() {
    setState(() {
      model = GameModel();
      fx.clearAll();
      popAt.clear();
      gameOverStart = null;
      gameOverPending = false;
      showGameOver = false;
      dragSlot = null;
      returnSlot = null;
      target = null;
      preview = null;
      trayAnimStart = time + 0.1;
      _resetRunState();
    });
    profile.saveGame(model);
    Sfx.play('deal');
    _kick();
  }

  void _restart() {
    if (model.placements > 0) profile.recordGame(model);
    _newGame();
  }

  void _toMenu() {
    if (!showGameOver) profile.saveGame(model);
    Navigator.of(context).pop();
  }

  void _openPause() {
    showPanel(context, (ctx) {
      return Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OutlinedText('Пауза', size: 36),
            const SizedBox(height: 18),
            ListenableBuilder(
              listenable: profile,
              builder: (context, _) => Column(
                children: [
                  GameSwitch(
                    label: 'Звук',
                    icon: Icons.volume_up_rounded,
                    value: profile.sound,
                    onChanged: profile.setSound,
                  ),
                  const SizedBox(height: 10),
                  GameSwitch(
                    label: 'Вибрация',
                    icon: Icons.vibration_rounded,
                    value: profile.vibration,
                    onChanged: profile.setVibration,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            BigButton(
              label: 'Продолжить',
              icon: Icons.play_arrow_rounded,
              width: double.infinity,
              onTap: () => Navigator.of(ctx).pop(),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BigButton(
                    label: 'Заново',
                    icon: Icons.refresh_rounded,
                    color: const Color(0xFFFF9A2E),
                    height: 52,
                    fontSize: 19,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _restart();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigButton(
                    label: 'Меню',
                    icon: Icons.home_rounded,
                    color: const Color(0xFF4A7BFF),
                    height: 52,
                    fontSize: 19,
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _toMenu();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }

  // ---------- Сборка ----------

  @override
  Widget build(BuildContext context) {
    Blocks.dpr = MediaQuery.devicePixelRatioOf(context);
    final pad = MediaQuery.paddingOf(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !showGameOver) profile.saveGame(model);
      },
      child: Scaffold(
        backgroundColor: skin.bg.last,
        body: LayoutBuilder(builder: (context, box) {
          final lay = L = GameLayout(Size(box.maxWidth, box.maxHeight), pad);
          fx
            ..cell = lay.cell
            ..style = skin.style;
          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onCancel,
            child: Stack(
              children: [
                Positioned.fill(child: Backdrop(skin: skin)),
                Positioned.fromRect(rect: lay.topBar, child: _topBar()),
                Positioned.fromRect(rect: lay.score, child: Center(child: ScoreText(value: model.score))),
                Positioned.fromRect(rect: lay.combo, child: Center(child: _comboMeter())),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GamePainter(this)),
                  ),
                ),
                if (showTutorial)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: _TutorialHint(
                        from: lay.slots[1].center,
                        to: lay.board.center,
                        textAt: Offset(lay.board.center.dx, lay.combo.top),
                      ),
                    ),
                  ),
                if (showGameOver)
                  Positioned.fill(
                    child: GameOverOverlay(
                      model: model,
                      profile: profile,
                      onRevive: _revive,
                      onRestart: _newGame,
                      onMenu: _toMenu,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _topBar() {
    final best = max(profile.best, model.score);
    final beating = model.score > startBest && startBest > 0;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: beating ? const Color(0xFFFFCF33) : Colors.white.withValues(alpha: 0.15),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CrownIcon(size: 26),
              const SizedBox(width: 8),
              OutlinedText('$best', size: 20, colors: const [Color(0xFFFFF3A0), Color(0xFFFFC21A)]),
            ],
          ),
        ),
        const Spacer(),
        SquareButton(icon: Icons.pause_rounded, onTap: _inputLocked ? null : _openPause),
      ],
    );
  }

  Widget _comboMeter() {
    final show = model.streak >= 2;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      transitionBuilder: (child, a) => ScaleTransition(
        scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
        child: FadeTransition(opacity: a, child: child),
      ),
      child: show
          ? _ComboPill(key: ValueKey(model.streak), streak: model.streak, left: model.comboMovesLeft)
          : const SizedBox.shrink(key: ValueKey(0)),
    );
  }
}

class _ComboPill extends StatelessWidget {
  const _ComboPill({super.key, required this.streak, required this.left});

  final int streak;
  final int left;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 12, 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [Color(0xFFFF7A1F), Color(0xFFFF3D6E)]),
        border: Border.all(color: const Color(0xFFFFD08A), width: 1.5),
        boxShadow: [BoxShadow(color: const Color(0xFFFF6A00).withValues(alpha: 0.5), blurRadius: 14)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFFF1A8), size: 20),
          const SizedBox(width: 4),
          OutlinedText('КОМБО ×$streak', size: 16, strokeWidth: 3),
          const SizedBox(width: 8),
          for (var i = 0; i < kComboWindow; i++)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < left ? Colors.white : Colors.white.withValues(alpha: 0.25),
              ),
            ),
        ],
      ),
    );
  }
}

/// Счёт, который «докручивается» до нового значения и подпрыгивает.
class ScoreText extends StatefulWidget {
  const ScoreText({super.key, required this.value, this.size = 50});

  final int value;
  final double size;

  @override
  State<ScoreText> createState() => _ScoreTextState();
}

class _ScoreTextState extends State<ScoreText> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  late int _from = widget.value;

  @override
  void didUpdateWidget(ScoreText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _current;
      _c.forward(from: 0);
    }
  }

  int get _current => (_from + (widget.value - _from) * Curves.easeOut.transform(_c.value)).round();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final bump = widget.value - _from > 0 ? sin(_c.value * pi) * 0.14 : 0.0;
        return Transform.scale(
          scale: 1 + bump,
          child: OutlinedText('$_current', size: widget.size, strokeWidth: widget.size * 0.14),
        );
      },
    );
  }
}

/// Подсказка для первой игры: рука тянет фигуру на поле.
class _TutorialHint extends StatefulWidget {
  const _TutorialHint({required this.from, required this.to, required this.textAt});

  final Offset from;
  final Offset to;
  final Offset textAt;

  @override
  State<_TutorialHint> createState() => _TutorialHintState();
}

class _TutorialHintState extends State<_TutorialHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final move = Curves.easeInOut.transform(((t - 0.15) / 0.5).clamp(0.0, 1.0));
        final pos = Offset.lerp(widget.from, widget.to, move)!;
        final opacity = t < 0.1 ? t / 0.1 : (t > 0.85 ? (1 - t) / 0.15 : 1.0);
        final pressed = t > 0.1 && t < 0.7;
        return Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: widget.textAt.dy,
              child: const Center(
                child: OutlinedText('Перетащи фигуру на поле', size: 19, strokeWidth: 4),
              ),
            ),
            Positioned(
              left: pos.dx - 14,
              top: pos.dy - 6,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: pressed ? 0.88 : 1,
                  child: const Icon(
                    Icons.touch_app_rounded,
                    size: 64,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 4))],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Рисует поле, лоток, перетаскиваемую фигуру и эффекты.
class _GamePainter extends CustomPainter {
  _GamePainter(this.s) : super(repaint: s._repaint);

  final _GameScreenState s;

  static ui.Picture? _boardPic;
  static Object? _boardKey;

  @override
  void paint(Canvas canvas, Size size) {
    final lay = s.L;
    if (lay == null) return;
    final skin = s.skin;
    final model = s.model;
    final time = s.time;

    canvas.save();
    final shake = s.fx.shakeOffset;
    canvas.translate(shake.dx, shake.dy);

    _paintBoardBg(canvas, lay, skin);

    // блоки на поле
    final drag = s.dragSlot != null ? model.tray[s.dragSlot!] : null;
    final preview = s.preview;
    final previewColor = drag != null ? skin.palette[drag.color] : null;
    final go = s.gameOverStart;
    for (var i = 0; i < kN * kN; i++) {
      final v = model.board.cells[i];
      if (v < 0) continue;
      final inPreview = preview != null && preview.containsCell(i);
      final color = inPreview ? previewColor! : skin.palette[v];
      var scale = 1.0;
      final p = s.popAt[i];
      if (p != null) {
        final k = ((time - p) / 0.25).clamp(0.0, 1.0);
        scale = 1 + 0.16 * sin(pi * k);
      }
      final gray = go != null && time - go > (kN - 1 - i ~/ kN) * 0.06;
      Blocks.draw(canvas, lay.cellRect(i), color, skin.style, scale: scale, gray: gray);
    }

    // тень будущей позиции и подсветка линий
    final t = s.target;
    if (drag != null && t != null) {
      if (preview != null) {
        final glow = Paint()
          ..color = Colors.white.withValues(alpha: 0.14 + 0.08 * sin(time * 9))
          ..blendMode = BlendMode.plus;
        for (final r in preview.rows) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(lay.grid.left, lay.grid.top + r * lay.cell, lay.grid.width, lay.cell),
              Radius.circular(lay.cell * 0.2),
            ),
            glow,
          );
        }
        for (final c in preview.cols) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(lay.grid.left + c * lay.cell, lay.grid.top, lay.cell, lay.grid.height),
              Radius.circular(lay.cell * 0.2),
            ),
            glow,
          );
        }
      }
      for (final cell in drag.shape.cells) {
        final i = (t.r + cell.r) * kN + t.c + cell.c;
        Blocks.draw(canvas, lay.cellRect(i), previewColor!, skin.style, opacity: preview != null ? 0.75 : 0.45);
      }
    }

    // лоток
    for (var i = 0; i < 3; i++) {
      final p = model.tray[i];
      if (p == null || i == s.dragSlot || i == s.returnSlot) continue;
      final k = ((time - s.trayAnimStart - i * 0.08) / 0.42).clamp(0.0, 1.0);
      if (k <= 0) continue;
      final scale = Curves.easeOutBack.transform(k);
      final rect = s._trayRect(i, p);
      final center = rect.center + Offset((1 - k) * lay.cell * 2, 0);
      final fits = model.board.fitsAnywhere(p.shape);
      final c = lay.trayCell;
      for (final cell in p.shape.cells) {
        final cc = Offset(rect.left + (cell.c + 0.5) * c, rect.top + (cell.r + 0.5) * c);
        Blocks.draw(
          canvas,
          Rect.fromCenter(center: center + (cc - rect.center) * scale, width: c, height: c),
          skin.palette[p.color],
          skin.style,
          scale: scale,
          opacity: fits ? 1 : 0.5,
          gray: !fits,
        );
      }
    }

    s.fx.paintBelow(canvas);

    // возвращающаяся в лоток фигура
    if (s.returnSlot != null && model.tray[s.returnSlot!] != null) {
      final p = model.tray[s.returnSlot!]!;
      final k = Curves.easeOutCubic.transform(((time - s.returnStart) / 0.2).clamp(0.0, 1.0));
      final rect = Rect.lerp(s.returnFrom, s._trayRect(s.returnSlot!, p), k)!;
      _paintPiece(canvas, p, rect, skin, lay, shadow: false);
    }

    // фигура под пальцем
    if (drag != null) {
      _paintPiece(canvas, drag, s._dragRectNow(drag), skin, lay, shadow: true);
    }

    s.fx.paintAbove(canvas);
    canvas.restore();
  }

  void _paintPiece(Canvas canvas, TrayPiece p, Rect rect, Skin skin, GameLayout lay, {required bool shadow}) {
    final c = rect.width / p.shape.cols;
    if (shadow) {
      final path = Path();
      for (final cell in p.shape.cells) {
        path.addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left + cell.c * c, rect.top + cell.r * c + c * 0.3, c, c).deflate(c * 0.06),
          Radius.circular(c * 0.18),
        ));
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.32)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, c * 0.18),
      );
    }
    // спрайт берём полного размера клетки поля и масштабируем
    final k = c / lay.cell;
    for (final cell in p.shape.cells) {
      final center = Offset(rect.left + (cell.c + 0.5) * c, rect.top + (cell.r + 0.5) * c);
      Blocks.draw(
        canvas,
        Rect.fromCenter(center: center, width: lay.cell, height: lay.cell),
        skin.palette[p.color],
        skin.style,
        scale: k,
      );
    }
  }

  void _paintBoardBg(Canvas canvas, GameLayout lay, Skin skin) {
    final key = (skin.id, lay.board);
    if (_boardKey != key || _boardPic == null) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final b = lay.board;
      final rr = RRect.fromRectAndRadius(b, Radius.circular(b.width * 0.045));
      c.drawRRect(
        rr.shift(const Offset(0, 10)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      c.drawRRect(
        rr,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [lighten(skin.board, 0.08), skin.board],
          ).createShader(b),
      );
      c.drawRRect(
        rr.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white.withValues(alpha: 0.13),
      );
      final radius = Radius.circular(lay.cell * 0.14);
      final dark = Paint()..color = darken(skin.cell, 0.35);
      final light = Paint()..color = skin.cell;
      for (var i = 0; i < kN * kN; i++) {
        final r = lay.cellRect(i).deflate(lay.cell * 0.045);
        c.drawRRect(RRect.fromRectAndRadius(r, radius), dark);
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTRB(r.left, r.top + lay.cell * 0.07, r.right, r.bottom), radius),
          light,
        );
      }
      _boardPic = rec.endRecording();
      _boardKey = key;
    }
    canvas.drawPicture(_boardPic!);
  }

  @override
  bool shouldRepaint(_GamePainter old) => true;
}
