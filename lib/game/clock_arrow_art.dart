import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 시곗바늘 칸과 범례가 함께 쓰는 놋쇠 시계판.
abstract final class ClockArrowArt {
  static const _brass = Color(0xffd5a461);
  static const _face = Color(0xff382619);
  static const handColor = Color(0xffffe2a2);
  static const ghostColor = Color(0x7adeb784);

  static void draw(
    Canvas canvas,
    Offset center,
    double diameter, {
    required double angle,
    double? previewAngle,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(diameter);
    final paint = Paint()..color = const Color(0xa21e1511);
    canvas.drawCircle(const Offset(0, .04), .5, paint);
    canvas.drawCircle(Offset.zero, .49, paint..color = _brass);
    canvas.drawCircle(Offset.zero, .405, paint..color = _face);

    paint
      ..color = _brass
      ..strokeWidth = .045
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      canvas.drawLine(const Offset(.31, 0), const Offset(.36, 0), paint);
      canvas.rotate(math.pi / 2);
    }
    if (previewAngle != null) _hand(canvas, paint, previewAngle, ghostColor);
    _hand(canvas, paint, angle, handColor);
    canvas.drawCircle(Offset.zero, .055, paint);
    canvas.restore();
  }

  static void _hand(Canvas canvas, Paint paint, double angle, Color color) {
    canvas.save();
    canvas.rotate(angle);
    paint
      ..color = color
      ..strokeWidth = .068;
    canvas.drawLine(const Offset(-.09, 0), const Offset(.24, 0), paint);
    canvas.drawLine(const Offset(.15, -.086), const Offset(.24, 0), paint);
    canvas.drawLine(const Offset(.15, .086), const Offset(.24, 0), paint);
    canvas.restore();
  }
}
