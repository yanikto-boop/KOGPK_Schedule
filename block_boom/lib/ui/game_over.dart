import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../audio/sfx.dart';
import '../game/game_model.dart';
import '../game/profile.dart';
import 'effects.dart';
import 'widgets.dart';

/// Конец партии: сначала предложение «второго шанса», потом итоги.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.model,
    required this.profile,
    required this.onRevive,
    required this.onRestart,
    required this.onMenu,
  });

  final GameModel model;
  final Profile profile;
  final VoidCallback onRevive;
  final VoidCallback onRestart;
  final VoidCallback onMenu;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> with TickerProviderStateMixin {
  static const _reviveSeconds = 7;

  late final AnimationController _countdown =
      AnimationController(vsync: this, duration: const Duration(seconds: _reviveSeconds));
  late final AnimationController _reveal =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  final _confetti = Effects();
  final _confettiTime = ValueNotifier<int>(0);
  late final Ticker _confettiTicker = createTicker(_tickConfetti);
  Duration _last = Duration.zero;

  GameRecord? _record;
  bool _levelSoundPlayed = false;

  @override
  void initState() {
    super.initState();
    if (widget.model.reviveUsed) {
      _showResults();
    } else {
      _countdown.forward().whenComplete(() {
        if (mounted && _record == null) _showResults();
      });
    }
    _reveal.addListener(_onReveal);
  }

  @override
  void dispose() {
    _countdown.dispose();
    _reveal.dispose();
    _pulse.dispose();
    _confettiTicker.dispose();
    _confettiTime.dispose();
    super.dispose();
  }

  void _tickConfetti(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = e;
    _confetti.update(dt);
    _confettiTime.value++;
    if (!_confetti.active) {
      _confettiTicker.stop();
      _last = Duration.zero;
    }
  }

  void _showResults() {
    _countdown.stop();
    final rec = widget.profile.recordGame(widget.model);
    setState(() => _record = rec);
    _reveal.forward(from: 0);
    if (rec.newBest) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        Sfx.play('record');
        Sfx.haptic(3);
        final size = MediaQuery.sizeOf(context);
        _confetti.confetti(Rect.fromLTWH(0, 0, size.width, size.height * 0.3), const [
          Color(0xFFFF4D5E),
          Color(0xFFFFCF33),
          Color(0xFF3DDC84),
          Color(0xFF2EC4F1),
          Color(0xFFA66BFF),
          Color(0xFFFF6FB5),
        ], 150);
        if (!_confettiTicker.isActive) _confettiTicker.start();
      });
    }
  }

  void _onReveal() {
    final rec = _record;
    if (rec == null || _levelSoundPlayed) return;
    if (rec.after.level > rec.before.level && _reveal.value >= 0.62) {
      _levelSoundPlayed = true;
      Sfx.play('levelup');
      Sfx.haptic(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            builder: (context, v, _) => ColoredBox(color: Colors.black.withValues(alpha: 0.6 * v)),
          ),
        ),
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
                ),
                child: _record == null ? _revivePanel() : _resultsPanel(_record!),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ConfettiPainter(_confetti, _confettiTime)),
          ),
        ),
      ],
    );
  }

  Widget _revivePanel() {
    final m = widget.model;
    final best = widget.profile.best;
    final toBest = best - m.score;
    final close = best > 0 && toBest > 0 && toBest <= max(300, best * 0.35);
    return Panel(
      key: const ValueKey('revive'),
      accent: const Color(0xFFFF4D6D),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const OutlinedText('Нет ходов!', size: 38, colors: [Colors.white, Color(0xFFFFC2CC)]),
          const SizedBox(height: 10),
          Text('Счёт: ${m.score}',
              style: const TextStyle(fontFamily: 'Russo', fontSize: 20, color: Colors.white70)),
          if (close) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFCF33).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CrownIcon(size: 20),
                  const SizedBox(width: 8),
                  Text('До рекорда всего $toBest!',
                      style: const TextStyle(fontFamily: 'Russo', fontSize: 16, color: Color(0xFFFFE27A))),
                ],
              ),
            ),
          ],
          const SizedBox(height: 22),
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) => Transform.scale(scale: 1 + 0.035 * _pulse.value, child: child),
            child: BigButton(
              label: 'Второй шанс',
              icon: Icons.bolt_rounded,
              color: const Color(0xFF3DDC84),
              width: double.infinity,
              onTap: () {
                _countdown.stop();
                widget.onRevive();
              },
            ),
          ),
          const SizedBox(height: 12),
          AnimatedBuilder(
            animation: _countdown,
            builder: (context, _) => XpBar(
              progress: 1 - _countdown.value,
              height: 10,
              color: const Color(0xFF3DDC84),
            ),
          ),
          const SizedBox(height: 16),
          Pressable(
            onTap: _showResults,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Text('Нет, спасибо',
                  style: TextStyle(fontFamily: 'Russo', fontSize: 17, color: Colors.white60)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsPanel(GameRecord rec) {
    final m = widget.model;
    return Panel(
      key: const ValueKey('results'),
      accent: rec.newBest ? const Color(0xFFFFB300) : const Color(0xFF7C5CFF),
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (context, _) {
          final v = _reveal.value;
          final scoreK = Curves.easeOutCubic.transform((v / 0.4).clamp(0.0, 1.0));
          final levelUp = rec.after.level > rec.before.level;
          double barProgress;
          int shownLevel;
          if (!levelUp) {
            barProgress = rec.before.progress +
                (rec.after.progress - rec.before.progress) * Curves.easeOut.transform(((v - 0.35) / 0.4).clamp(0, 1));
            shownLevel = rec.before.level;
          } else if (v < 0.62) {
            barProgress = rec.before.progress + (1 - rec.before.progress) * ((v - 0.35) / 0.27).clamp(0, 1);
            shownLevel = rec.before.level;
          } else {
            barProgress = rec.after.progress * Curves.easeOut.transform(((v - 0.62) / 0.3).clamp(0, 1));
            shownLevel = rec.after.level;
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (rec.newBest)
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, child) => Transform.scale(scale: 1 + 0.05 * _pulse.value, child: child),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CrownIcon(size: 34),
                      SizedBox(width: 10),
                      OutlinedText('Новый рекорд!', size: 30, colors: [Color(0xFFFFF6B0), Color(0xFFFFB300)]),
                    ],
                  ),
                )
              else
                const OutlinedText('Игра окончена', size: 30),
              const SizedBox(height: 6),
              OutlinedText('${(rec.score * scoreK).round()}', size: 64, strokeWidth: 9),
              Text(
                rec.newBest ? 'Прошлый рекорд: ${rec.oldBest}' : 'Рекорд: ${max(rec.oldBest, rec.score)}',
                style: const TextStyle(fontFamily: 'Russo', fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _stat(Icons.grid_on_rounded, 'Линии', '${m.linesCleared}')),
                  const SizedBox(width: 10),
                  Expanded(child: _stat(Icons.local_fire_department_rounded, 'Макс. комбо', '${m.bestStreak}')),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: _levelBadge(shownLevel),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              levelUp && v >= 0.62 ? 'Уровень повышен!' : 'Опыт',
                              style: TextStyle(
                                fontFamily: 'Russo',
                                fontSize: 15,
                                color: levelUp && v >= 0.62 ? const Color(0xFFFFE27A) : Colors.white70,
                              ),
                            ),
                            const Spacer(),
                            Text('+${rec.score}',
                                style: const TextStyle(fontFamily: 'Russo', fontSize: 15, color: Color(0xFF7CF0A8))),
                          ],
                        ),
                        const SizedBox(height: 6),
                        XpBar(progress: barProgress, height: 16),
                      ],
                    ),
                  ),
                ],
              ),
              if (rec.unlocked.isNotEmpty && v > 0.7) ...[
                const SizedBox(height: 14),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutBack,
                  builder: (context, k, child) => Transform.scale(scale: k, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFA66BFF), Color(0xFFFF6FB5)]),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.palette_rounded, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Новая тема: «${rec.unlocked.map((s) => s.name).join('», «')}»',
                            style: const TextStyle(fontFamily: 'Russo', fontSize: 15, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Transform.scale(scale: 1 + 0.03 * _pulse.value, child: child),
                child: BigButton(
                  label: 'Ещё раз',
                  icon: Icons.replay_rounded,
                  width: double.infinity,
                  onTap: widget.onRestart,
                ),
              ),
              const SizedBox(height: 12),
              BigButton(
                label: 'Меню',
                icon: Icons.home_rounded,
                color: const Color(0xFF4A7BFF),
                height: 50,
                fontSize: 19,
                width: double.infinity,
                onTap: widget.onMenu,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _levelBadge(int level) {
    return Container(
      key: ValueKey(level),
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE27A), Color(0xFFFF9A2E)],
        ),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: const Color(0xFFFFB300).withValues(alpha: 0.5), blurRadius: 12)],
      ),
      child: OutlinedText('$level', size: 22, strokeWidth: 4),
    );
  }

  Widget _stat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontFamily: 'Russo', fontSize: 12, color: Colors.white60)),
                Text(value, style: const TextStyle(fontFamily: 'Russo', fontSize: 20, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.fx, Listenable repaint) : super(repaint: repaint);
  final Effects fx;

  @override
  void paint(Canvas canvas, Size size) => fx.paintBelow(canvas);

  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}
