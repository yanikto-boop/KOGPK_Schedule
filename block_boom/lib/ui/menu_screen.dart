import 'dart:math';

import 'package:flutter/material.dart';

import '../game/profile.dart';
import 'background.dart';
import 'blocks.dart';
import 'game_screen.dart';
import 'skins.dart';
import 'skins_screen.dart';
import 'widgets.dart';

Route<void> fadeRoute(Widget page) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(c), child: child),
        );
      },
    );

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key, required this.profile});

  final Profile profile;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _wave =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat();

  Profile get profile => widget.profile;

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    await Navigator.of(context).push(fadeRoute(GameScreen(profile: profile)));
    if (mounted) setState(() {});
  }

  void _openStats() {
    final l = profile.levelInfo;
    showPanel(context, (ctx) {
      Widget row(IconData icon, String label, String value) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(icon, color: Colors.white70, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, style: const TextStyle(fontFamily: 'Russo', fontSize: 17, color: Colors.white70)),
                ),
                Text(value, style: const TextStyle(fontFamily: 'Russo', fontSize: 20, color: Colors.white)),
              ],
            ),
          );
      return Panel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const OutlinedText('Статистика', size: 32),
            const SizedBox(height: 16),
            row(Icons.emoji_events_rounded, 'Рекорд', '${profile.best}'),
            row(Icons.star_rounded, 'Уровень', '${l.level}'),
            row(Icons.sports_esports_rounded, 'Сыграно игр', '${profile.games}'),
            row(Icons.grid_on_rounded, 'Собрано линий', '${profile.totalLines}'),
            row(Icons.local_fire_department_rounded, 'Лучшее комбо', '${profile.bestCombo}'),
            row(Icons.bolt_rounded, 'Всего очков', '${profile.xp}'),
            const SizedBox(height: 18),
            BigButton(label: 'Закрыть', width: double.infinity, height: 52, fontSize: 20, onTap: () => Navigator.pop(ctx)),
          ],
        ),
      );
    });
  }

  void _openSettings() {
    showPanel(context, (ctx) {
      return Panel(
        child: ListenableBuilder(
          listenable: profile,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OutlinedText('Настройки', size: 32),
              const SizedBox(height: 16),
              GameSwitch(label: 'Звук', icon: Icons.volume_up_rounded, value: profile.sound, onChanged: profile.setSound),
              const SizedBox(height: 10),
              GameSwitch(
                label: 'Вибрация',
                icon: Icons.vibration_rounded,
                value: profile.vibration,
                onChanged: profile.setVibration,
              ),
              const SizedBox(height: 18),
              BigButton(label: 'Готово', width: double.infinity, height: 52, fontSize: 20, onTap: () => Navigator.pop(ctx)),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Blocks.dpr = MediaQuery.devicePixelRatioOf(context);
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        final skin = profile.skin;
        final level = profile.levelInfo;
        final nextSkin = kSkins.where((s) => s.unlockLevel > level.level).firstOrNull;
        return Scaffold(
          backgroundColor: skin.bg.last,
          body: Stack(
            children: [
              Positioned.fill(child: Backdrop(skin: skin, floatingBlocks: true)),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _LevelChip(level: level.level),
                          const Spacer(),
                          SquareButton(icon: Icons.bar_chart_rounded, onTap: _openStats),
                          const SizedBox(width: 10),
                          SquareButton(icon: Icons.settings_rounded, onTap: _openSettings),
                        ],
                      ),
                      const Spacer(flex: 3),
                      _Logo(wave: _wave, skin: skin),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CrownIcon(size: 30),
                          const SizedBox(width: 10),
                          OutlinedText('${profile.best}', size: 30, colors: const [Color(0xFFFFF3A0), Color(0xFFFFC21A)]),
                        ],
                      ),
                      const Spacer(flex: 3),
                      AnimatedBuilder(
                        animation: _wave,
                        builder: (context, child) =>
                            Transform.scale(scale: 1 + 0.035 * sin(_wave.value * pi * 2 * 2), child: child),
                        child: BigButton(
                          label: profile.hasSavedGame ? 'Продолжить' : 'Играть',
                          icon: Icons.play_arrow_rounded,
                          width: 270,
                          height: 76,
                          fontSize: 30,
                          onTap: _play,
                        ),
                      ),
                      const SizedBox(height: 16),
                      BigButton(
                        label: 'Темы',
                        icon: Icons.palette_rounded,
                        color: const Color(0xFFA66BFF),
                        width: 270,
                        height: 56,
                        fontSize: 22,
                        onTap: () async {
                          await Navigator.of(context).push(fadeRoute(SkinsScreen(profile: profile)));
                          if (mounted) setState(() {});
                        },
                      ),
                      const Spacer(flex: 2),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Уровень ${level.level}',
                                    style: const TextStyle(fontFamily: 'Russo', fontSize: 16, color: Colors.white)),
                                const Spacer(),
                                Text('${level.into} / ${level.need}',
                                    style: const TextStyle(fontFamily: 'Russo', fontSize: 14, color: Colors.white60)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            XpBar(progress: level.progress),
                            if (nextSkin != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Тема «${nextSkin.name}» откроется на уровне ${nextSkin.unlockLevel}',
                                style: const TextStyle(fontFamily: 'Russo', fontSize: 13, color: Colors.white60),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFE27A), Color(0xFFFF9A2E)],
              ),
            ),
            child: OutlinedText('$level', size: 16, strokeWidth: 3),
          ),
          const SizedBox(width: 8),
          Text(Profile.rankFor(level), style: const TextStyle(fontFamily: 'Russo', fontSize: 15, color: Colors.white)),
        ],
      ),
    );
  }
}

/// Логотип: прыгающие буквы и взрыв за словом BOOM.
class _Logo extends StatelessWidget {
  const _Logo({required this.wave, required this.skin});

  final Animation<double> wave;
  final Skin skin;

  @override
  Widget build(BuildContext context) {
    const top = 'BLOCK';
    const bottom = 'BOOM';
    return AnimatedBuilder(
      animation: wave,
      builder: (context, _) {
        final t = wave.value * pi * 2;
        return Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < top.length; i++)
                  Transform.translate(
                    offset: Offset(0, sin(t + i * 0.7) * 5),
                    child: Transform.rotate(
                      angle: sin(t + i) * 0.05,
                      child: OutlinedText(
                        top[i],
                        size: 62,
                        strokeWidth: 10,
                        colors: [lighten(skin.palette[i], 0.45), skin.palette[i]],
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Transform.rotate(
                    angle: t / 6,
                    child: Transform.scale(
                      scale: 1 + 0.06 * sin(t * 2),
                      child: const CustomPaint(size: Size(310, 150), painter: _BurstPainter()),
                    ),
                  ),
                  Transform.scale(
                    scale: 1 + 0.04 * sin(t * 2),
                    child: const OutlinedText(
                      bottom,
                      size: 80,
                      strokeWidth: 12,
                      letterSpacing: 2,
                      colors: [Color(0xFFFFF6B0), Color(0xFFFFB300), Color(0xFFFF6A00)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  const _BurstPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    Path star(double rx, double ry, double inner, int n, double rot) {
      final p = Path();
      for (var i = 0; i < n * 2; i++) {
        final k = i.isEven ? 1.0 : inner;
        final a = rot + i * pi / n;
        final o = c + Offset(cos(a) * rx * k, sin(a) * ry * k);
        if (i == 0) {
          p.moveTo(o.dx, o.dy);
        } else {
          p.lineTo(o.dx, o.dy);
        }
      }
      return p..close();
    }

    canvas.drawPath(
      star(size.width / 2, size.height / 2, 0.62, 12, 0),
      Paint()
        ..color = const Color(0xFFFF3D6E).withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawPath(star(size.width * 0.42, size.height * 0.42, 0.6, 12, 0.26), Paint()..color = const Color(0xFFFF7A1F));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
