import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'blocks.dart';
import 'skins.dart';

/// Живой фон: градиент темы, мягкие световые пятна и мерцающие звёзды.
/// С [floatingBlocks] ещё и медленно всплывающие блоки (для меню).
class Backdrop extends StatefulWidget {
  const Backdrop({super.key, required this.skin, this.floatingBlocks = false});

  final Skin skin;
  final bool floatingBlocks;

  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop> with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  late final Ticker _ticker = createTicker((e) => _time.value = e.inMicroseconds / 1e6)..start();

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BackdropPainter(widget.skin, _time, widget.floatingBlocks),
        size: Size.infinite,
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter(this.skin, this.time, this.blocks) : super(repaint: time);

  final Skin skin;
  final ValueListenable<double> time;
  final bool blocks;

  static double _hash(int i, int k) {
    final x = sin(i * 127.1 + k * 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: skin.bg,
        ).createShader(rect),
    );

    // световые пятна
    for (var i = 0; i < 5; i++) {
      final cx = size.width * (0.5 + 0.48 * sin(t * 0.07 * (0.6 + _hash(i, 1)) + i * 2.1));
      final cy = size.height * (0.5 + 0.45 * cos(t * 0.05 * (0.6 + _hash(i, 2)) + i * 1.3));
      final r = size.width * (0.45 + 0.25 * _hash(i, 3));
      final col = skin.palette[(i * 3) % skin.palette.length];
      final c = Offset(cx, cy);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [col.withValues(alpha: 0.16), col.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    // звёзды
    final star = Paint();
    for (var i = 0; i < 40; i++) {
      final x = _hash(i, 4) * size.width;
      final y = ((_hash(i, 5) - t * 0.004 * (0.3 + _hash(i, 6))) % 1.0) * size.height;
      final a = 0.1 + 0.4 * (0.5 + 0.5 * sin(t * (0.8 + _hash(i, 7) * 1.5) + i));
      star.color = Colors.white.withValues(alpha: a);
      canvas.drawCircle(Offset(x, y), 0.8 + _hash(i, 8) * 1.6, star);
    }

    if (blocks) {
      for (var i = 0; i < 14; i++) {
        final s = 22 + _hash(i, 9) * 34;
        final speed = 0.012 + _hash(i, 10) * 0.02;
        final y = (1.15 - ((_hash(i, 11) + t * speed) % 1.3)) * size.height;
        final x = _hash(i, 12) * size.width + sin(t * 0.3 + i) * 14;
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(sin(t * 0.2 + i * 1.7) * 0.6);
        Blocks.draw(
          canvas,
          Rect.fromCenter(center: Offset.zero, width: 44, height: 44),
          skin.palette[i % skin.palette.length],
          skin.style,
          scale: s / 44,
          opacity: 0.22 + _hash(i, 13) * 0.18,
        );
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.skin != skin || old.blocks != blocks;
}
