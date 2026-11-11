import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/star_art.dart';
import '../domain/mechanics/ice.dart';
import '../domain/mechanics/mirror_pair.dart';
import '../domain/puzzle.dart';

abstract final class IceArt {
  static const previewColor = Color(0xffc8f1ff);
  static const frostColor = Color(0xffdef8ff);
  static final _tile = RRect.fromRectAndRadius(
    const Rect.fromLTWH(-.5, -.5, 1, 1),
    const Radius.circular(.14),
  );
  static final _glass = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xab84dfff), Color(0x933e93c2), Color(0xb027548b)],
  ).createShader(_tile.outerRect);
  static final _cracks = Path()
    ..moveTo(-.40, -.16)
    ..lineTo(-.17, -.09)
    ..lineTo(-.08, .05)
    ..lineTo(.19, .15)
    ..lineTo(.38, .36)
    ..moveTo(-.08, .05)
    ..lineTo(.07, -.12)
    ..lineTo(.31, -.25);

  static void tile(
    Canvas canvas,
    Offset center,
    double extent, {
    ui.Image? texture,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(extent);
    canvas.drawRRect(_tile, Paint()..shader = _glass);
    if (texture != null) {
      StarArt.drawTile(canvas, texture, _tile, opacity: .76);
    }
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .025
      ..color = const Color(0xb08dd7ff);
    canvas.drawRRect(_tile.deflate(.015), edge);
    edge
      ..strokeCap = StrokeCap.round
      ..strokeWidth = .014
      ..color = const Color(0xc3d8f7ff);
    canvas.drawPath(_cracks, edge);
    canvas.drawLine(const Offset(-.31, -.36), const Offset(.15, -.36), edge);
    canvas.restore();
  }

  static void trajectory(Canvas canvas, Offset from, Offset to, double cell) {
    final delta = to - from;
    final length = delta.distance;
    if (length == 0) return;
    final direction = delta / length;
    final paint = Paint()..color = previewColor;
    for (var along = cell * .23; along < length; along += cell * .14) {
      canvas.drawCircle(from + direction * along, cell * .029, paint);
    }
  }
}

/// 한 칸에 70ms를 쓰는 등속 이동과, 도착 직후 짧게 물러나는 반동.
class IceSlide {
  const IceSlide._(this.cells, {required this.frostStart});

  static const secondsPerCell = .07;
  static const _reboundSeconds = .12;
  final int cells;
  final int frostStart;

  double get travelSeconds => cells * secondsPerCell;
  double get seconds => travelSeconds + _reboundSeconds;

  static int distance(Position from, Position to) =>
      (to.x - from.x).abs() + (to.y - from.y).abs();

  static IceSlide? forMove(MoveRecord move) {
    final end = move.teleportOf(move.blockId)?.from ?? move.to;
    if (end == move.landing ||
        move.before.level
                .mechanic<Ice>(Ice.typeId)
                ?.positions
                .contains(move.landing) !=
            true) {
      return null;
    }
    return IceSlide._(
      distance(move.from, end),
      frostStart: move.power == PuzzlePower.moonflowerLeap ? 2 : 0,
    );
  }

  static IceSlide? forTwin(MirrorShift? shift, {Position? landing}) {
    if (shift == null) return null;
    final cells = distance(shift.from, landing ?? shift.to);
    return cells > 1 ? IceSlide._(cells, frostStart: 0) : null;
  }

  Offset draw(
    Canvas canvas,
    Offset from,
    Offset to,
    double cell,
    double fraction,
  ) {
    final elapsed = fraction * seconds;
    final step = (to - from) / cells.toDouble();
    final traveled = elapsed / secondsPerCell;
    final side = Offset(-step.dy, step.dx);
    final paint = Paint();
    for (var i = 0; i < 11; i++) {
      final along = traveled - (i + 1) * .17;
      if (along < frostStart || along > cells) continue;
      final spread = (.17 + (i % 4) * .055) * (i.isEven ? 1 : -1);
      paint.color = IceArt.frostColor.withValues(alpha: .82 - i * .055);
      canvas.drawCircle(
        from + step * along + side * spread,
        cell * (.022 + (i % 3) * .008),
        paint,
      );
    }
    if (elapsed <= travelSeconds) return from + step * traveled;
    final recoil = (elapsed - travelSeconds) / _reboundSeconds;
    return to - step * (.16 * math.sin(math.pi * recoil) * (1 - recoil));
  }
}
