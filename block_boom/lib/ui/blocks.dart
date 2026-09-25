import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game/shapes.dart';
import 'skins.dart';

Color lighten(Color c, double t) => Color.lerp(c, Colors.white, t)!;
Color darken(Color c, double t) => Color.lerp(c, Colors.black, t)!;

Color grayOf(Color c) =>
    HSLColor.fromColor(c).withSaturation(0.1).withLightness(0.42).toColor();

/// Рисование блоков. Готовый блок кэшируется картинкой: поле из 64 клеток
/// со свечением и бликами рисуется за доли миллисекунды.
class Blocks {
  Blocks._();

  static double dpr = 2;
  static const double _pad = 0.3; // запас под свечение и тень
  static final Map<(BlockStyle, int, int, bool), ui.Image> _cache = {};

  /// Рисует блок в [rect]. [scale] масштабирует от центра без пересборки кэша.
  static void draw(
    Canvas canvas,
    Rect rect,
    Color color,
    BlockStyle style, {
    double opacity = 1,
    double scale = 1,
    bool gray = false,
  }) {
    if (opacity <= 0 || scale <= 0) return;
    final px = (rect.width * dpr).round().clamp(4, 600);
    final key = (style, color.toARGB32(), px, gray);
    final img = _cache[key] ??= _render(px, gray ? grayOf(color) : color, style);
    final w = rect.width * scale;
    final dst = Rect.fromCenter(center: rect.center, width: w, height: w).inflate(w * _pad);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1) paint.color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      dst,
      paint,
    );
  }

  static void drawPiece(
    Canvas canvas,
    Shape shape,
    Offset topLeft,
    double cell,
    Color color,
    BlockStyle style, {
    double opacity = 1,
    bool gray = false,
  }) {
    for (final p in shape.cells) {
      draw(
        canvas,
        Rect.fromLTWH(topLeft.dx + p.c * cell, topLeft.dy + p.r * cell, cell, cell),
        color,
        style,
        opacity: opacity,
        gray: gray,
      );
    }
  }

  static ui.Image _render(int px, Color color, BlockStyle style) {
    if (_cache.length > 400) _cache.clear();
    final s = px / dpr;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(dpr);
    paintDirect(c, Rect.fromLTWH(s * _pad, s * _pad, s, s), color, style);
    final pic = rec.endRecording();
    final size = (px * (1 + 2 * _pad)).ceil();
    final img = pic.toImageSync(size, size);
    pic.dispose();
    return img;
  }

  /// Рисует блок напрямую (для кэша и превью).
  static void paintDirect(Canvas c, Rect r, Color col, BlockStyle style) {
    switch (style) {
      case BlockStyle.bevel:
        _bevel(c, r, col, bevel: 0.15, radius: 0.13, lights: const [0.4, 0.17, -0.14, -0.32]);
        _shine(c, r, col);
      case BlockStyle.gem:
        _gem(c, r, col);
      case BlockStyle.metal:
        _metal(c, r, col);
      case BlockStyle.neon:
        _neon(c, r, col);
      case BlockStyle.jelly:
        _jelly(c, r, col);
    }
  }

  static Color _shade(Color c, double k) => k >= 0 ? lighten(c, k) : darken(c, -k);

  /// Блок с фаской: четыре трапеции по краям и плоская середина.
  /// [lights] — осветление верх/лево/право/низ (минус — затемнение).
  static Rect _bevel(Canvas c, Rect r, Color col,
      {required double bevel, required double radius, required List<double> lights}) {
    final w = r.width;
    final b = w * bevel;
    final rr = RRect.fromRectAndRadius(r.deflate(w * 0.02), Radius.circular(w * radius));
    c.save();
    c.clipRRect(rr);
    c.drawRect(r, Paint()..color = col);
    final l = r.left, t = r.top, rt = r.right, bt = r.bottom;
    void poly(List<Offset> pts, double k) =>
        c.drawPath(Path()..addPolygon(pts, true), Paint()..color = _shade(col, k));
    poly([Offset(l, t), Offset(rt, t), Offset(rt - b, t + b), Offset(l + b, t + b)], lights[0]);
    poly([Offset(l, t), Offset(l + b, t + b), Offset(l + b, bt - b), Offset(l, bt)], lights[1]);
    poly([Offset(rt, t), Offset(rt, bt), Offset(rt - b, bt - b), Offset(rt - b, t + b)], lights[2]);
    poly([Offset(l, bt), Offset(l + b, bt - b), Offset(rt - b, bt - b), Offset(rt, bt)], lights[3]);
    final inner = Rect.fromLTRB(l + b, t + b, rt - b, bt - b);
    c.drawRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lighten(col, 0.14), col],
        ).createShader(inner),
    );
    c.restore();
    return inner;
  }

  static void _shine(Canvas c, Rect r, Color col) {
    final w = r.width;
    final b = w * 0.15;
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(r.left + b * 1.3, r.top + b * 1.3, w * 0.22, w * 0.09),
        Radius.circular(w * 0.045),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.6),
    );
  }

  static void _gem(Canvas c, Rect r, Color col) {
    final w = r.width;
    final inner = _bevel(c, r, col, bevel: 0.25, radius: 0.08, lights: const [0.5, 0.2, -0.2, -0.42]);
    c.drawRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lighten(col, 0.35), col, darken(col, 0.1)],
        ).createShader(inner),
    );
    // диагональный отблеск на грани
    c.drawPath(
      Path()
        ..moveTo(inner.left, inner.top)
        ..lineTo(inner.left + inner.width * 0.55, inner.top)
        ..lineTo(inner.left, inner.top + inner.height * 0.55)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    _sparkle(c, Offset(r.left + w * 0.24, r.top + w * 0.24), w * 0.14, 0.95);
  }

  static void _metal(Canvas c, Rect r, Color col) {
    final w = r.width;
    final inner = _bevel(c, r, col, bevel: 0.13, radius: 0.12, lights: const [0.6, 0.3, -0.25, -0.45]);
    c.drawRect(
      inner,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            lighten(col, 0.6),
            lighten(col, 0.1),
            darken(col, 0.3),
            lighten(col, 0.35),
            darken(col, 0.15),
          ],
          stops: const [0, 0.28, 0.5, 0.72, 1],
        ).createShader(inner),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(r.deflate(w * 0.02), Radius.circular(w * 0.12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.025
        ..color = darken(col, 0.55),
    );
    _sparkle(c, Offset(r.left + w * 0.72, r.top + w * 0.28), w * 0.13, 0.9);
  }

  static void _neon(Canvas c, Rect r, Color col) {
    final w = r.width;
    final rr = RRect.fromRectAndRadius(r.deflate(w * 0.1), Radius.circular(w * 0.2));
    c.drawRRect(rr, Paint()..color = Color.lerp(col, const Color(0xFF05030F), 0.8)!);
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.12
        ..color = col.withValues(alpha: 0.85)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.12),
    );
    c.drawRRect(
      rr.deflate(w * 0.12),
      Paint()
        ..shader = RadialGradient(
          colors: [col.withValues(alpha: 0.55), col.withValues(alpha: 0.1)],
        ).createShader(rr.outerRect),
    );
    c.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.065
        ..color = lighten(col, 0.45),
    );
    c.drawCircle(Offset(r.left + w * 0.3, r.top + w * 0.3), w * 0.045,
        Paint()..color = Colors.white.withValues(alpha: 0.9));
  }

  static void _jelly(Canvas c, Rect r, Color col) {
    final w = r.width;
    final body = RRect.fromRectAndRadius(r.deflate(w * 0.04), Radius.circular(w * 0.3));
    c.drawRRect(body.shift(Offset(0, w * 0.05)), Paint()..color = darken(col, 0.45));
    c.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lighten(col, 0.32), col, darken(col, 0.12)],
          stops: const [0, 0.55, 1],
        ).createShader(body.outerRect),
    );
    final gloss = RRect.fromRectAndRadius(
      Rect.fromLTWH(r.left + w * 0.15, r.top + w * 0.1, w * 0.7, w * 0.36),
      Radius.circular(w * 0.18),
    );
    c.drawRRect(
      gloss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.75), Colors.white.withValues(alpha: 0.04)],
        ).createShader(gloss.outerRect),
    );
    c.drawCircle(Offset(r.left + w * 0.27, r.top + w * 0.24), w * 0.06, Paint()..color = Colors.white);
    c.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..color = darken(col, 0.28),
    );
  }

  /// Четырёхлучевая звёздочка-блик.
  static void _sparkle(Canvas c, Offset o, double size, double alpha) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final rad = i.isEven ? size : size * 0.22;
      final a = -pi / 2 + i * pi / 4;
      final p = o + Offset(cos(a) * rad, sin(a) * rad);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    c.drawPath(path, Paint()..color = Colors.white.withValues(alpha: alpha));
  }
}
