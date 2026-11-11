import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/star_art.dart';

abstract final class ShelfDoorArt {
  static const transitSeconds = .25;
  static const _inside = Color(0xff191629);
  static const _gilt = Color(0xffffe8b0);
  static Color pairColor(int pair) =>
      pair == 0 ? const Color(0xffd88be4) : const Color(0xff85d6a2);

  static final _moon = Path.combine(
    PathOperation.difference,
    Path()..addOval(Rect.fromCircle(center: Offset.zero, radius: .5)),
    Path()
      ..addOval(Rect.fromCircle(center: const Offset(.24, -.20), radius: .44)),
  );
  static final _star = Path()
    ..moveTo(0, -.52)
    ..lineTo(.13, -.16)
    ..lineTo(.51, -.16)
    ..lineTo(.21, .07)
    ..lineTo(.32, .45)
    ..lineTo(0, .22)
    ..lineTo(-.32, .45)
    ..lineTo(-.21, .07)
    ..lineTo(-.51, -.16)
    ..lineTo(-.13, -.16)
    ..close();

  static void link(
    Canvas canvas,
    Offset from,
    Offset to,
    double cell,
    int pair,
  ) {
    final distance = (to - from).distance;
    final paint = Paint()..color = pairColor(pair).withValues(alpha: .32);
    for (
      var along = cell * .48;
      along < distance - cell * .47;
      along += cell * .11
    ) {
      canvas.drawCircle(
        Offset.lerp(from, to, along / distance)!,
        cell * .018,
        paint,
      );
    }
  }

  static void tile(
    Canvas canvas,
    Offset center,
    double extent,
    int pair, {
    double openness = 0,
    ui.Image? texture,
  }) {
    final accent = pairColor(pair);
    final outer = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-.5, -.5, 1, 1),
      const Radius.circular(.14),
    );
    final inner = outer.deflate(.055);
    final paint = Paint();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(extent);
    canvas.drawRRect(outer, paint..color = Color.lerp(_inside, accent, .37)!);
    canvas.drawRRect(inner, paint..color = _inside);
    canvas.save();
    canvas.clipRRect(inner);
    for (final side in [-1, 1]) {
      final left = side < 0 ? -.44 : .01;
      final panel = Rect.fromLTWH(left, -.44, .43, .88);
      canvas.save();
      canvas.translate(side * openness * .37, 0);
      canvas.drawRect(panel, paint..color = Color.lerp(_inside, accent, .18)!);
      if (texture != null) {
        canvas.save();
        canvas.clipRect(panel);
        StarArt.draw(canvas, texture, inner.outerRect, opacity: .65);
        canvas.restore();
      }
      for (var spine = 0; spine < 3; spine++) {
        final x = left + .035 + spine * .127;
        final height = .31 + ((spine + (side < 0 ? 0 : 1)) % 3) * .045;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, .27 - height, .10, height),
            const Radius.circular(.02),
          ),
          paint..color = Color.lerp(accent, _inside, .12 + spine * .19)!,
        );
        canvas.drawRect(
          Rect.fromLTWH(x + .012, .17, .076, .023),
          paint..color = _gilt,
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(left, .27, .43, .045),
        paint..color = accent,
      );
      canvas.restore();
    }
    canvas.restore();
    canvas.drawRRect(
      outer.deflate(.017),
      paint
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = .035,
    );
    marker(canvas, const Offset(0, -.255), .29, pair);
    canvas.restore();
  }

  static void marker(Canvas canvas, Offset center, double size, int pair) {
    final paint = Paint();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(size);
    canvas.drawCircle(Offset.zero, .65, paint..color = _inside);
    canvas.drawPath(pair == 0 ? _moon : _star, paint..color = _gilt);
    canvas.restore();
  }

  static double opening(double half) => math.sin(math.pi * half);
}
