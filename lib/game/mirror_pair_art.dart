import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 짝의 색과 실선·점선 표식을 보드, 범례, 포스트카드에서 공유한다.
abstract final class MirrorPairArt {
  static Color color(int pair) =>
      pair == 0 ? const Color(0xff68e5db) : const Color(0xffd9bcff);

  static void ring(
    Canvas canvas,
    Rect bounds,
    int pair, {
    required double stroke,
    double opacity = 1,
  }) {
    final paint = Paint()
      ..color = color(pair).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    if (pair == 0) {
      canvas.drawOval(bounds, paint);
      return;
    }
    const step = math.pi / 6;
    for (var i = 0; i < 12; i++) {
      canvas.drawArc(bounds, step * i, step * .42, false, paint);
    }
  }

  static void marker(
    Canvas canvas,
    Offset block,
    double cell,
    int pair, {
    double opacity = 1,
  }) {
    final bounds = Rect.fromCenter(
      center: block + Offset(0, cell * .31),
      width: cell * .88,
      height: cell * .30,
    );
    canvas.drawOval(
      bounds,
      Paint()..color = const Color(0xff112942).withValues(alpha: .65 * opacity),
    );
    ring(canvas, bounds, pair, stroke: cell * .029, opacity: opacity);
  }

  static void ripple(
    Canvas canvas,
    Offset block,
    double cell,
    int pair,
    double progress,
  ) {
    ring(
      canvas,
      Rect.fromCenter(
        center: block + Offset(0, cell * .25),
        width: cell * (.8 + .30 * progress),
        height: cell * (.26 + .32 * progress),
      ),
      pair,
      stroke: cell * .036,
      opacity: .72 * (1 - progress),
    );
  }

  static void arrow(
    Canvas canvas,
    Offset center,
    Offset direction,
    double extent,
    int pair, {
    double opacity = 1,
  }) {
    if (direction == Offset.zero) return;
    final axis = direction / direction.distance;
    final perpendicular = Offset(-axis.dy, axis.dx);
    final tip = center + axis * extent / 2;
    final base = tip - axis * extent * .33;
    final paint = Paint()
      ..color = color(pair).withValues(alpha: opacity)
      ..strokeWidth = extent * .12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center - axis * extent / 2, tip, paint);
    canvas.drawLine(base + perpendicular * extent * .24, tip, paint);
    canvas.drawLine(base - perpendicular * extent * .24, tip, paint);
  }

  static void blocked(Canvas canvas, Offset block, double cell, int pair) {
    final at = block + Offset(0, -cell * .29);
    final bounds = Rect.fromCenter(
      center: at,
      width: cell * .32,
      height: cell * .25,
    );
    canvas.drawOval(bounds, Paint()..color = const Color(0xe6243550));
    ring(canvas, bounds, pair, stroke: cell * .023);
    final paint = Paint()
      ..color = color(pair)
      ..strokeWidth = cell * .026
      ..strokeCap = StrokeCap.round;
    final r = cell * .043;
    canvas.drawLine(at - Offset(r, r), at + Offset(r, r), paint);
    canvas.drawLine(at - Offset(r, -r), at + Offset(r, -r), paint);
  }
}
