import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/mechanics/clock_arrow.dart';
import '../domain/mechanics/echo_eraser.dart';
import '../domain/mechanics/echo_gate.dart';
import '../domain/mechanics/echo_hold.dart';
import '../domain/mechanics/goal_only.dart';
import '../domain/mechanics/ice.dart';
import '../domain/mechanics/mirror_pair.dart';
import '../domain/mechanics/one_way.dart';
import '../domain/mechanics/shelf_door.dart';
import 'clock_arrow_art.dart';
import 'ice_art.dart';
import 'mirror_pair_art.dart';
import 'shelf_door_art.dart';

enum GateBadge { crystal, open, closed }

typedef _BadgeGlyph = void Function(Canvas, Paint, Offset, GateBadge);

/// 보드와 설명이 같은 작은 돌 배지를 그린다.
class BoardBadge extends CustomPainter {
  const BoardBadge(this.type);

  final String type;
  static const _glyphs = <String, _BadgeGlyph>{
    EchoEraser.typeId: _drawEraser,
    EchoHold.typeId: _drawHold,
    OneWay.typeId: _drawOneWay,
    GoalOnly.typeId: _drawGoalOnly,
    EchoGate.typeId: _drawGate,
    MirrorPair.typeId: _drawMirrorPair,
  };

  static const _stoneBounds = Rect.fromLTWH(-.48, -.48, .96, .96);
  static const _amberBounds = Rect.fromLTWH(-.30, -.30, .60, .60);
  static final _slate = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff415767), Color(0xff233548), Color(0xff172638)],
  ).createShader(_stoneBounds);
  static final _stoneRim = const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xff93a5af), Color(0xff5f7588), Color(0xff394b60)],
  ).createShader(_stoneBounds);
  static final _amberGlass = const RadialGradient(
    center: Alignment(-.35, -.35),
    radius: .80,
    colors: [Color(0xff8ba9a7), Color(0xff526f82), Color(0xff2a405b)],
    stops: [0, .55, 1],
  ).createShader(_amberBounds);
  static final _auroraRim = const SweepGradient(
    colors: [
      Color(0xffcab2f0),
      Color(0xffa6b7f1),
      Color(0xff8ce5cf),
      Color(0xffb5ead0),
      Color(0xffffc4a5),
      Color(0xffffe7cc),
      Color(0xffcab2f0),
    ],
    stops: [0, .12, .30, .46, .62, .78, 1],
  ).createShader(_amberBounds);

  @override
  void paint(Canvas canvas, Size size) =>
      draw(canvas, size.center(Offset.zero), size.shortestSide, type);

  @override
  bool shouldRepaint(BoardBadge oldDelegate) => oldDelegate.type != type;

  static void draw(
    Canvas canvas,
    Offset center,
    double diameter,
    String type, {
    Offset direction = const Offset(1, 0),
    GateBadge gate = GateBadge.crystal,
  }) {
    if (type == ClockArrow.typeId) {
      ClockArrowArt.draw(
        canvas,
        center,
        diameter,
        angle: math.atan2(direction.dy, direction.dx),
      );
      return;
    }
    if (type == Ice.typeId) {
      IceArt.tile(canvas, center, diameter * .88);
      return;
    }
    if (type == ShelfDoor.typeId) {
      ShelfDoorArt.tile(canvas, center, diameter * .88, 0);
      return;
    }
    final glyph = _glyphs[type];
    if (glyph == null) return;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(diameter);
    final paint = Paint();
    canvas.drawCircle(
      const Offset(0, .04),
      .49,
      paint..color = const Color(0xaa0b1222),
    );
    canvas.drawCircle(
      Offset.zero,
      .47,
      paint
        ..color = Colors.white
        ..shader = _slate,
    );
    canvas.drawCircle(
      Offset.zero,
      .44,
      paint
        ..shader = _stoneRim
        ..strokeWidth = .045
        ..style = PaintingStyle.stroke,
    );
    paint.shader = null;

    glyph(canvas, paint, direction, gate);
    canvas.restore();
  }

  static void _drawMirrorPair(Canvas canvas, Paint _, Offset _, GateBadge _) {
    for (var pair = 0; pair < 2; pair++) {
      final x = pair == 0 ? -.17 : .17;
      MirrorPairArt.ring(
        canvas,
        Rect.fromCenter(center: Offset(x, 0), width: .32, height: .48),
        pair,
        stroke: .055,
      );
      MirrorPairArt.arrow(canvas, Offset(x, 0), Offset(x.sign, 0), .19, pair);
    }
  }

  static void _drawEraser(Canvas canvas, Paint paint, Offset _, GateBadge _) {
    paint
      ..color = const Color(0xffffecc8)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = .075;
    const puff = Offset(-.085, -.09);
    for (final point in const [
      Offset(-.24, -.10),
      Offset(-.19, -.23),
      Offset(-.07, -.28),
      Offset(.06, -.23),
      Offset(.11, -.10),
      Offset(.06, .02),
      Offset(-.18, .02),
    ]) {
      canvas.drawLine(puff, point, paint);
    }
    canvas.drawPath(
      Path()
        ..moveTo(puff.dx, puff.dy)
        ..quadraticBezierTo(-.06, .08, -.18, .25),
      paint,
    );
    canvas.drawCircle(
      const Offset(.22, .02),
      .045,
      paint..style = PaintingStyle.fill,
    );
  }

  static void _drawHold(Canvas canvas, Paint paint, Offset _, GateBadge _) {
    // 오로라는 보석 둘레에 모으고, 가운데는 방울이 읽히게 둔다.
    canvas.drawCircle(
      Offset.zero,
      .30,
      paint
        ..style = PaintingStyle.fill
        ..shader = _amberGlass,
    );
    canvas.drawCircle(
      Offset.zero,
      .263,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = .078
        ..shader = _auroraRim,
    );
    final drop = Path()
      ..moveTo(0, -.15)
      ..cubicTo(.05, -.08, .13, 0, .13, .067)
      ..quadraticBezierTo(.13, .17, 0, .17)
      ..quadraticBezierTo(-.13, .17, -.13, .067)
      ..cubicTo(-.13, 0, -.05, -.08, 0, -.15)
      ..close();
    canvas.drawPath(
      drop,
      paint
        ..shader = null
        ..color = const Color(0xffc0d5d3)
        ..strokeWidth = .05,
    );
    canvas.drawPath(
      drop,
      paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xff17263e),
    );
  }

  static void _drawOneWay(
    Canvas canvas,
    Paint paint,
    Offset direction,
    GateBadge _,
  ) {
    final normal = Offset(-direction.dy, direction.dx);
    final tip = direction * .26;
    paint
      ..color = const Color(0xffc0e1fa)
      ..strokeWidth = .095
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final tail = -direction * .25;
    final bend = -direction * .10 + normal * .16;
    canvas.drawPath(
      Path()
        ..moveTo(tail.dx, tail.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, tip.dx, tip.dy),
      paint,
    );
    final head = tip - direction * .17;
    canvas.drawPath(
      Path()
        ..moveTo((head + normal * .15).dx, (head + normal * .15).dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo((head - normal * .15).dx, (head - normal * .15).dy),
      paint,
    );
  }

  static void _drawGoalOnly(Canvas canvas, Paint paint, Offset _, GateBadge _) {
    final leaf = Path()
      ..moveTo(-.22, -.16)
      ..quadraticBezierTo(-.22, -.30, -.07, -.21)
      ..lineTo(.23, -.05)
      ..quadraticBezierTo(.34, 0, .23, .05)
      ..lineTo(-.07, .21)
      ..quadraticBezierTo(-.22, .30, -.22, .16)
      ..close();
    canvas.drawPath(
      leaf,
      paint
        ..style = PaintingStyle.fill
        ..color = const Color(0xffbde39b),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-.13, .035)
        ..quadraticBezierTo(-.04, -.035, .10, 0),
      paint
        ..color = const Color(0xff395748)
        ..strokeWidth = .055
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
  }

  static void _drawGate(Canvas canvas, Paint paint, Offset _, GateBadge gate) {
    if (gate == GateBadge.crystal) {
      final gem = Path()
        ..moveTo(0, -.32)
        ..lineTo(.21, -.04)
        ..lineTo(0, .31)
        ..lineTo(-.21, -.04)
        ..close();
      canvas.drawPath(
        gem,
        paint
          ..style = PaintingStyle.fill
          ..color = const Color(0xffa9eedb),
      );
      canvas.drawPath(
        Path()
          ..moveTo(0, -.32)
          ..lineTo(.21, -.04)
          ..lineTo(0, .31)
          ..close(),
        paint..color = const Color(0xff60aaaf),
      );
      canvas.drawLine(
        const Offset(0, -.22),
        const Offset(-.105, -.06),
        paint
          ..color = const Color(0xffe0f9ef)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = .048,
      );
      return;
    }
    final open = gate == GateBadge.open;
    paint
      ..color = open ? const Color(0xffa9eedb) : const Color(0xffffbea9)
      ..strokeWidth = .075
      ..strokeCap = StrokeCap.round;
    final left = open ? -.23 : -.12;
    final shackle = Path()
      ..moveTo(left, open ? -.10 : .04)
      ..lineTo(left, -.13)
      ..quadraticBezierTo(left, -.33, .015, -.28)
      ..quadraticBezierTo(.15, -.29, .15, -.13)
      ..lineTo(.15, .04);
    canvas.drawPath(shackle, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-.20, -.005, .42, .24),
        const Radius.circular(.06),
      ),
      paint..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      const Offset(.01, .10),
      .045,
      paint..color = const Color(0xff243446),
    );
  }
}
