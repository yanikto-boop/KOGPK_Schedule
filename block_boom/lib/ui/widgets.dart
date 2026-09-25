import 'package:flutter/material.dart';

import '../audio/sfx.dart';
import 'blocks.dart';

const kInk = Color(0xFF1B0D3F);

/// Игровой текст: градиентная заливка, тёмная обводка и тень.
class OutlinedText extends StatelessWidget {
  const OutlinedText(
    this.text, {
    super.key,
    required this.size,
    this.colors = const [Colors.white, Color(0xFFE6E9FF)],
    this.stroke = kInk,
    this.strokeWidth,
    this.letterSpacing = 0,
  });

  final String text;
  final double size;
  final List<Color> colors;
  final Color stroke;
  final double? strokeWidth;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    final sw = strokeWidth ?? size * 0.16;
    TextStyle base(Paint p) => TextStyle(
          fontFamily: 'Russo',
          fontSize: size,
          height: 1.1,
          letterSpacing: letterSpacing,
          foreground: p,
        );
    return Stack(
      children: [
        Transform.translate(
          offset: Offset(0, size * 0.07),
          child: Text(text,
              style: base(Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = sw
                ..strokeJoin = StrokeJoin.round
                ..color = stroke)),
        ),
        Text(text,
            style: base(Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = sw
              ..strokeJoin = StrokeJoin.round
              ..color = stroke)),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ).createShader(r),
          child: Text(text, style: base(Paint()..color = Colors.white)),
        ),
      ],
    );
  }
}

/// Нажимаемый элемент: пружинит и щёлкает.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.sound = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool sound;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: enabled
          ? () {
              if (widget.sound) Sfx.play('tap');
              Sfx.haptic(0);
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.93 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Большая объёмная кнопка.
class BigButton extends StatelessWidget {
  const BigButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = const Color(0xFF3DDC84),
    this.icon,
    this.height = 64,
    this.fontSize = 26,
    this.width,
  });

  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;
  final double height;
  final double fontSize;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final depth = height * 0.1;
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        height: height + depth,
        child: Stack(
          children: [
            Positioned.fill(
              top: depth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: darken(color, 0.38),
                  borderRadius: BorderRadius.circular(height * 0.36),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 14, offset: const Offset(0, 6)),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              bottom: depth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(height * 0.36),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [lighten(color, 0.25), color],
                  ),
                  border: Border.all(color: lighten(color, 0.45), width: 2),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: height * 0.3,
                      right: height * 0.3,
                      top: height * 0.1,
                      height: height * 0.22,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(height),
                        ),
                      ),
                    ),
                    Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: height * 0.35),
                        child: FittedBox(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[
                                Icon(icon, color: Colors.white, size: fontSize * 1.15, shadows: const [
                                  Shadow(color: kInk, offset: Offset(0, 2), blurRadius: 0),
                                ]),
                                SizedBox(width: fontSize * 0.35),
                              ],
                              OutlinedText(label, size: fontSize, strokeWidth: fontSize * 0.14),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Квадратная полупрозрачная кнопка с иконкой.
class SquareButton extends StatelessWidget {
  const SquareButton({super.key, required this.icon, required this.onTap, this.size = 46, this.badge});

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: 0.24), Colors.white.withValues(alpha: 0.08)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.28), width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.56),
      ),
    );
  }
}

/// Карточка-панель для диалогов.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.accent = const Color(0xFF7C5CFF), this.padding});

  final Widget child;
  final Color accent;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(accent, const Color(0xFF2A1E6E), 0.55)!, const Color(0xFF1B1450)],
        ),
        border: Border.all(color: lighten(accent, 0.3).withValues(alpha: 0.7), width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 14)),
          BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 40),
        ],
      ),
      child: child,
    );
  }
}

/// Корона для рекорда.
class CrownIcon extends StatelessWidget {
  const CrownIcon({super.key, this.size = 26});
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size, size * 0.8), painter: _CrownPainter());
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final path = Path()
      ..moveTo(w * 0.08, h * 0.88)
      ..lineTo(w * 0.02, h * 0.28)
      ..lineTo(w * 0.3, h * 0.52)
      ..lineTo(w * 0.5, h * 0.08)
      ..lineTo(w * 0.7, h * 0.52)
      ..lineTo(w * 0.98, h * 0.28)
      ..lineTo(w * 0.92, h * 0.88)
      ..close();
    canvas.drawPath(path.shift(Offset(0, h * 0.08)), Paint()..color = kInk);
    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF3A0), Color(0xFFFFC21A), Color(0xFFF08A00)],
        ).createShader(Offset.zero & s),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF9A4A00),
    );
    for (final x in [0.02, 0.5, 0.98]) {
      canvas.drawCircle(Offset(w * x, h * (x == 0.5 ? 0.08 : 0.28)), w * 0.08, Paint()..color = const Color(0xFFFFF3A0));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Показывает панель поверх экрана с «пружинным» появлением.
Future<T?> showPanel<T>(BuildContext context, WidgetBuilder builder, {bool dismissible = true}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'close',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (ctx, a1, a2) => SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: Material(type: MaterialType.transparency, child: builder(ctx)),
        ),
      ),
    ),
    transitionBuilder: (ctx, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// Переключатель в стиле игры.
class GameSwitch extends StatelessWidget {
  const GameSwitch({super.key, required this.label, required this.icon, required this.value, required this.onChanged});

  final String label;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: const TextStyle(fontFamily: 'Russo', fontSize: 18, color: Colors.white)),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 32,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: value ? const Color(0xFF3DDC84) : Colors.white.withValues(alpha: 0.2),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutBack,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Шкала опыта.
class XpBar extends StatelessWidget {
  const XpBar({super.key, required this.progress, this.height = 16, this.color = const Color(0xFFFFCF33)});

  final double progress;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(height),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.5),
      ),
      padding: const EdgeInsets.all(2),
      child: LayoutBuilder(
        builder: (context, c) => Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: (c.maxWidth * progress.clamp(0.0, 1.0)).clamp(height - 4, c.maxWidth),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(height),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [lighten(color, 0.4), color, darken(color, 0.15)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
