import 'dart:math';

import 'package:flutter/material.dart';

import 'blocks.dart';
import 'skins.dart';

enum _Kind { shard, spark, confetti }

class _Particle {
  _Particle(this.kind, this.p, this.v, this.size, this.color, this.life)
      : maxLife = life,
        rot = _rnd.nextDouble() * pi,
        vr = (_rnd.nextDouble() - 0.5) * 12,
        phase = _rnd.nextDouble() * pi * 2;
  final _Kind kind;
  Offset p;
  Offset v;
  final double size;
  final Color color;
  double life;
  final double maxLife;
  double rot;
  final double vr;
  double phase;
}

class _Clearing {
  _Clearing(this.rect, this.color, this.delay);
  final Rect rect;
  final Color color;
  final double delay;
  double t = 0;
  bool burst = false;
}

class _Label {
  _Label(this.stroke, this.fill, this.center, this.dur, this.rise, this.big);
  final TextPainter stroke;
  final TextPainter fill;
  final Offset center;
  final double dur;
  final double rise;
  final bool big;
  double t = 0;
  double delay = 0;
}

class _Ring {
  _Ring(this.center, this.color, this.maxR);
  final Offset center;
  final Color color;
  final double maxR;
  double t = 0;
}

final _rnd = Random();

/// Все «сочные» эффекты: разлёт осколков, вспышки, надписи, тряска.
/// Координаты — в системе экрана игры.
class Effects {
  final _particles = <_Particle>[];
  final _clearing = <_Clearing>[];
  final _labels = <_Label>[];
  final _rings = <_Ring>[];
  double shake = 0;
  BlockStyle style = BlockStyle.bevel;
  double cell = 40;

  bool get active =>
      _particles.isNotEmpty ||
      _clearing.isNotEmpty ||
      _labels.isNotEmpty ||
      _rings.isNotEmpty ||
      shake > 0.2;

  Offset get shakeOffset =>
      shake <= 0.2 ? Offset.zero : Offset((_rnd.nextDouble() - 0.5) * shake, (_rnd.nextDouble() - 0.5) * shake);

  void clearAll() {
    _particles.clear();
    _clearing.clear();
    _labels.clear();
    _rings.clear();
    shake = 0;
  }

  // ---------- Создание эффектов ----------

  void clearCell(Rect rect, Color color, double delay) => _clearing.add(_Clearing(rect, color, delay));

  void shards(Offset at, Color color, int n, {double speed = 1}) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * pi * 2;
      final s = (140 + _rnd.nextDouble() * 320) * speed;
      _particles.add(_Particle(
        _Kind.shard,
        at,
        Offset(cos(a) * s, sin(a) * s - 260 * speed),
        cell * (0.16 + _rnd.nextDouble() * 0.2),
        color,
        0.55 + _rnd.nextDouble() * 0.45,
      ));
    }
  }

  void sparks(Offset at, int n, {Color color = Colors.white, double speed = 1}) {
    for (var i = 0; i < n; i++) {
      final a = _rnd.nextDouble() * pi * 2;
      final s = (60 + _rnd.nextDouble() * 380) * speed;
      _particles.add(_Particle(
        _Kind.spark,
        at,
        Offset(cos(a) * s, sin(a) * s),
        cell * (0.05 + _rnd.nextDouble() * 0.08),
        color,
        0.35 + _rnd.nextDouble() * 0.5,
      ));
    }
  }

  void confetti(Rect area, List<Color> colors, int n) {
    for (var i = 0; i < n; i++) {
      final x = area.left + _rnd.nextDouble() * area.width;
      final y = area.top - _rnd.nextDouble() * area.height * 0.4;
      _particles.add(_Particle(
        _Kind.confetti,
        Offset(x, y),
        Offset((_rnd.nextDouble() - 0.5) * 220, 80 + _rnd.nextDouble() * 260),
        6 + _rnd.nextDouble() * 7,
        colors[_rnd.nextInt(colors.length)],
        2.2 + _rnd.nextDouble() * 1.6,
      ));
    }
  }

  void ring(Offset center, Color color, double maxR) => _rings.add(_Ring(center, color, maxR));

  /// Всплывающая надпись («+120», «Комбо 3»).
  void floatText(String text, Offset center, double size,
      {List<Color> colors = const [Colors.white, Colors.white], double delay = 0, double? rise}) {
    final l = _label(text, center, size, colors, dur: 1.0, rise: rise ?? size * 1.6, big: false);
    l.delay = delay;
    _labels.add(l);
  }

  /// Большая хвалебная надпись по центру поля («Отлично!»).
  void banner(String text, Offset center, double size, List<Color> colors, {double delay = 0}) {
    final l = _label(text, center, size, colors, dur: 1.35, rise: size * 0.8, big: true);
    l.delay = delay;
    _labels.add(l);
  }

  _Label _label(String text, Offset center, double size, List<Color> colors,
      {required double dur, required double rise, required bool big}) {
    final stroke = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Russo',
          fontSize: size,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * (big ? 0.2 : 0.16)
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFF1B0D3F),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final bounds = Rect.fromLTWH(0, 0, stroke.width, stroke.height);
    final fill = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'Russo',
          fontSize: size,
          foreground: Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
            ).createShader(bounds),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return _Label(stroke, fill, center, dur, rise, big);
  }

  // ---------- Шаг симуляции ----------

  void update(double dt) {
    for (final c in _clearing) {
      c.t += dt;
      if (!c.burst && c.t >= c.delay + 0.12) {
        c.burst = true;
        shards(c.rect.center, c.color, 4);
        sparks(c.rect.center, 2, color: lighten(c.color, 0.6), speed: 0.8);
      }
    }
    _clearing.removeWhere((c) => c.t > c.delay + 0.34);

    for (final p in _particles) {
      p.life -= dt;
      switch (p.kind) {
        case _Kind.shard:
          p.v = Offset(p.v.dx * (1 - dt * 0.8), p.v.dy + 1500 * dt);
        case _Kind.spark:
          p.v = p.v * (1 - dt * 3.5);
        case _Kind.confetti:
          p.phase += dt * 7;
          p.v = Offset(p.v.dx * (1 - dt * 1.2) + sin(p.phase * 0.7) * 40 * dt, min(p.v.dy + 300 * dt, 240));
      }
      p.p += p.v * dt;
      p.rot += p.vr * dt;
    }
    _particles.removeWhere((p) => p.life <= 0);

    for (final l in _labels) {
      if (l.delay > 0) {
        l.delay -= dt;
      } else {
        l.t += dt;
      }
    }
    _labels.removeWhere((l) => l.t > l.dur);

    for (final r in _rings) {
      r.t += dt;
    }
    _rings.removeWhere((r) => r.t > 0.55);

    shake *= exp(-dt * 10);
  }

  // ---------- Отрисовка ----------

  void paintBelow(Canvas canvas) {
    for (final c in _clearing) {
      final t = c.t - c.delay;
      if (t < 0) {
        Blocks.draw(canvas, c.rect, c.color, style);
        continue;
      }
      if (t < 0.12) {
        final k = t / 0.12;
        final s = 1 + 0.14 * k;
        Blocks.draw(canvas, c.rect, c.color, style, scale: s);
        final w = c.rect.width * s;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c.rect.center, width: w * 0.94, height: w * 0.94),
            Radius.circular(w * 0.15),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.75 * k),
        );
      } else {
        final k = ((t - 0.12) / 0.22).clamp(0.0, 1.0);
        final s = 1.14 * (1 - Curves.easeIn.transform(k));
        final w = c.rect.width * s;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: c.rect.center, width: w, height: w),
            Radius.circular(w * 0.2),
          ),
          Paint()..color = Colors.white.withValues(alpha: 0.85 * (1 - k)),
        );
      }
    }

    for (final r in _rings) {
      final k = r.t / 0.55;
      final e = Curves.easeOutCubic.transform(k);
      canvas.drawCircle(
        r.center,
        r.maxR * e,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (1 - k) * cell * 0.35 + 1
          ..color = r.color.withValues(alpha: 0.7 * (1 - k)),
      );
    }

    final glow = Paint()..blendMode = BlendMode.plus;
    for (final p in _particles) {
      final a = (p.life / p.maxLife).clamp(0.0, 1.0);
      switch (p.kind) {
        case _Kind.shard:
          canvas.save();
          canvas.translate(p.p.dx, p.p.dy);
          canvas.rotate(p.rot);
          Blocks.draw(
            canvas,
            Rect.fromCenter(center: Offset.zero, width: cell, height: cell),
            p.color,
            style,
            scale: p.size / cell,
            opacity: min(1, a * 1.6),
          );
          canvas.restore();
        case _Kind.spark:
          glow.color = p.color.withValues(alpha: a);
          canvas.drawCircle(p.p, p.size * (0.6 + a * 0.6), glow);
        case _Kind.confetti:
          canvas.save();
          canvas.translate(p.p.dx, p.p.dy);
          canvas.rotate(p.rot * 0.3);
          canvas.scale(1, cos(p.phase).abs() * 0.8 + 0.2);
          canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
            Paint()..color = p.color.withValues(alpha: min(1, a * 3)),
          );
          canvas.restore();
      }
    }
  }

  void paintAbove(Canvas canvas) {
    for (final l in _labels) {
      if (l.delay > 0) continue;
      final t = l.t;
      double scale;
      double alpha;
      double dy;
      if (l.big) {
        scale = t < 0.35 ? Curves.elasticOut.transform((t / 0.35).clamp(0, 1)) : 1;
        scale = 0.3 + 0.7 * scale;
        alpha = t < l.dur - 0.3 ? 1 : (l.dur - t) / 0.3;
        dy = t < l.dur - 0.35 ? 0 : -l.rise * (t - (l.dur - 0.35)) / 0.35;
      } else {
        scale = t < 0.15 ? 0.6 + 0.55 * (t / 0.15) : (t < 0.25 ? 1.15 - 0.15 * ((t - 0.15) / 0.1) : 1);
        alpha = t < l.dur * 0.55 ? 1 : (l.dur - t) / (l.dur * 0.45);
        dy = -l.rise * Curves.easeOut.transform(t / l.dur);
      }
      alpha = alpha.clamp(0.0, 1.0);
      if (alpha <= 0) continue;
      final w = l.fill.width;
      final h = l.fill.height;
      canvas.save();
      canvas.translate(l.center.dx, l.center.dy + dy);
      canvas.scale(scale);
      canvas.translate(-w / 2, -h / 2);
      if (alpha < 1) {
        canvas.saveLayer(Rect.fromLTWH(-w * 0.2, -h * 0.2, w * 1.4, h * 1.4),
            Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      }
      // тень
      canvas.save();
      canvas.translate(0, h * 0.07);
      l.stroke.paint(canvas, Offset.zero);
      canvas.restore();
      l.stroke.paint(canvas, Offset.zero);
      l.fill.paint(canvas, Offset.zero);
      if (alpha < 1) canvas.restore();
      canvas.restore();
    }
  }
}
