import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';

/// 판 위의 정령 장치. 기호 대신 밤숲의 물건으로 그리며 칸을 가득 채운다.
enum DeviceKind {
  gate('gate_closed'),
  moonbloom('switch_bud'),
  eraser('eraser'),
  hold('hold'),
  oneWay('oneway'),
  goalOnly('goal_only'),
  wall('wall');

  const DeviceKind(this.asset);

  /// `assets/art/devices/<asset>.png`가 있으면 코드 그림 대신 쓴다.
  final String asset;
}

abstract final class DeviceArt {
  static const _vine = Color(0xff4fa98a);
  static const _vineLight = Color(0xff8fe0bb);
  static const _stoneLight = Color(0xff6f86a8);
  static const _stoneDark = Color(0xff324364);
  static const _hollow = Color(0xff0b1428);

  /// [phase]는 초 단위 시간이며 모션 줄이기에서는 0이다. [amount]는 달문과
  /// 꽃판의 열림 정도(0..1)이고, [direction]은 바람 잎길이 가리키는 방향이다.
  static void draw(
    Canvas canvas,
    DeviceKind kind,
    Rect rect,
    GameColors colors, {
    double phase = 0,
    double amount = 0,
    Offset direction = const Offset(1, 0),
    int variant = 0,
  }) {
    if (_drawImage(canvas, kind, rect, amount, direction)) return;
    switch (kind) {
      case DeviceKind.gate:
        _gate(canvas, rect, colors, amount);
      case DeviceKind.moonbloom:
        _moonbloom(canvas, rect, colors, amount);
      case DeviceKind.eraser:
        _eraser(canvas, rect, colors, phase);
      case DeviceKind.hold:
        _hold(canvas, rect, colors, phase);
      case DeviceKind.oneWay:
        _oneWay(canvas, rect, colors, phase, direction);
      case DeviceKind.goalOnly:
        _goalOnly(canvas, rect, colors);
      case DeviceKind.wall:
        _wall(canvas, rect, variant);
    }
  }

  /// 블록이 올라가 칸이 가려질 때 모서리에 남기는 작은 표식.
  static void badge(
    Canvas canvas,
    DeviceKind kind,
    Offset at,
    double radius,
    GameColors colors, {
    double amount = 0,
    Offset direction = const Offset(1, 0),
  }) {
    canvas.drawCircle(
      at,
      radius,
      Paint()..color = colors.background.withValues(alpha: .92),
    );
    canvas.drawCircle(
      at,
      radius,
      Paint()
        ..color = colors.highlight.withValues(alpha: .55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, radius * .1),
    );
    draw(
      canvas,
      kind,
      Rect.fromCircle(center: at, radius: radius * .86),
      colors,
      amount: amount,
      direction: direction,
    );
  }

  static bool _drawImage(
    Canvas canvas,
    DeviceKind kind,
    Rect rect,
    double amount,
    Offset direction,
  ) {
    final open = switch (kind) {
      DeviceKind.gate => 'gate_open',
      DeviceKind.moonbloom => 'switch_bloom',
      _ => null,
    };
    final image = amount >= .5 && open != null
        ? StarArt.devices[open]
        : StarArt.devices[kind.asset];
    if (image == null) return false;
    canvas.save();
    if (kind == DeviceKind.oneWay) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(math.atan2(direction.dy, direction.dx));
      canvas.translate(-rect.center.dx, -rect.center.dy);
    }
    StarArt.draw(canvas, image, rect);
    canvas.restore();
    return true;
  }

  static Offset _at(Rect r, double x, double y) =>
      r.topLeft + Offset(x * r.width, y * r.height);

  static Path _leaf(Offset base, double angle, double length, double width) {
    final tip = base + Offset(math.cos(angle), math.sin(angle)) * length;
    final middle = base + (tip - base) * .5;
    final normal = Offset(-math.sin(angle), math.cos(angle)) * width;
    final left = middle + normal, right = middle - normal;
    return Path()
      ..moveTo(base.dx, base.dy)
      ..quadraticBezierTo(left.dx, left.dy, tip.dx, tip.dy)
      ..quadraticBezierTo(right.dx, right.dy, base.dx, base.dy)
      ..close();
  }

  /// 덩굴 달문: 초승달 이맛돌이 있는 돌 아치. 닫히면 덩굴이 입구를 엮어 막는다.
  static void _gate(Canvas canvas, Rect r, GameColors colors, double open) {
    final w = r.width;
    Path arch(double left, double right, double top) => Path()
      ..moveTo(_at(r, left, .96).dx, _at(r, left, .96).dy)
      ..lineTo(_at(r, left, top).dx, _at(r, left, top).dy)
      ..arcToPoint(
        _at(r, right, top),
        radius: Radius.circular((right - left) / 2 * w),
      )
      ..lineTo(_at(r, right, .96).dx, _at(r, right, .96).dy)
      ..close();

    final outer = arch(.07, .93, .47);
    canvas.drawPath(
      outer.shift(Offset(0, w * .03)),
      Paint()..color = Colors.black.withValues(alpha: .28),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_stoneLight, _stoneDark],
        ).createShader(r),
    );
    canvas.drawPath(
      outer,
      Paint()
        ..color = colors.highlight.withValues(alpha: .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * .012),
    );

    final inner = arch(.23, .77, .50);
    canvas.drawPath(inner, Paint()..color = _hollow);
    if (open > 0) {
      canvas.drawPath(
        inner,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, .1),
            radius: .75,
            colors: [
              colors.cyan.withValues(alpha: .85 * open),
              colors.goal.withValues(alpha: .25 * open),
              Colors.transparent,
            ],
          ).createShader(r),
      );
    }

    // 닫힌 덩굴은 입구를 X자로 엮고, 열리면 양쪽 기둥으로 물러난다.
    canvas.save();
    canvas.clipPath(outer);
    final vine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final leafPaint = Paint();
    for (final (startX, endX, sideX) in const [
      (.30, .70, .17),
      (.70, .30, .83),
      (.50, .50, .50),
    ]) {
      final isMiddle = startX == endX;
      final fromX = ui.lerpDouble(startX, sideX, open)!;
      final toX = ui.lerpDouble(endX, sideX, open)!;
      if (isMiddle && open > .98) continue;
      final from = _at(r, fromX, .26 + (isMiddle ? .02 : 0));
      final to = _at(r, toX, .94);
      final bend = _at(
        r,
        (fromX + toX) / 2 + (startX < endX ? .14 : -.14) * (1 - open),
        .58,
      );
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
      canvas.drawPath(
        path,
        vine
          ..color = _vine.withValues(alpha: isMiddle ? 1 - open : 1)
          ..strokeWidth = w * .062,
      );
      canvas.drawPath(
        path,
        vine
          ..color = _vineLight.withValues(
            alpha: isMiddle ? .5 * (1 - open) : .5,
          )
          ..strokeWidth = w * .018,
      );
      for (final (t, side) in const [(.35, 1), (.62, -1), (.85, 1)]) {
        final at = Offset(
          (1 - t) * (1 - t) * from.dx +
              2 * (1 - t) * t * bend.dx +
              t * t * to.dx,
          (1 - t) * (1 - t) * from.dy +
              2 * (1 - t) * t * bend.dy +
              t * t * to.dy,
        );
        canvas.drawPath(
          _leaf(at, side > 0 ? -.5 : math.pi + .5, w * .13, w * .05),
          leafPaint
            ..color = Color.lerp(
              _vine,
              _vineLight,
              .4,
            )!.withValues(alpha: isMiddle ? 1 - open : 1),
        );
      }
    }
    canvas.restore();

    // 이맛돌의 초승달은 꽃판과 같은 색으로 연결을 알린다.
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: _at(r, .5, .16), radius: w * .1)),
      Path()..addOval(
        Rect.fromCircle(center: _at(r, .545, .135), radius: w * .085),
      ),
    );
    canvas.drawCircle(_at(r, .5, .16), w * .135, Paint()..color = _stoneDark);
    canvas.drawPath(moon, Paint()..color = colors.cyan);
  }

  /// 달빛 꽃판: 잔상이 올라오면 봉오리가 활짝 피고 문이 열린다.
  static void _moonbloom(
    Canvas canvas,
    Rect r,
    GameColors colors,
    double open,
  ) {
    final w = r.width;
    final center = r.center;
    canvas.drawCircle(
      center + Offset(0, w * .03),
      w * .44,
      Paint()..color = Colors.black.withValues(alpha: .28),
    );
    canvas.drawCircle(
      center,
      w * .44,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_stoneLight, _stoneDark],
        ).createShader(r),
    );
    canvas.drawCircle(
      center,
      w * .36,
      Paint()
        ..color = colors.cyan.withValues(alpha: .55 + .45 * open)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, w * .022),
    );
    if (open > 0) {
      canvas.drawCircle(
        center,
        w * .36,
        Paint()..color = colors.cyan.withValues(alpha: .26 * open),
      );
    }
    final petals = 6;
    final spread = ui.lerpDouble(.32, 1, open)!;
    final length = w * ui.lerpDouble(.25, .31, open)!;
    final petal = Paint();
    for (var i = 0; i < petals; i++) {
      final angle =
          -math.pi / 2 +
          (i - (petals - 1) / 2) * (math.pi * 2 / petals) * spread;
      petal.shader = LinearGradient(
        colors: [
          colors.echo,
          Color.lerp(colors.cyan, colors.highlight, .35 + .3 * open)!,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: length));
      canvas.drawPath(_leaf(center, angle, length, w * .085), petal);
    }
    petal.shader = null;
    canvas.drawCircle(
      center,
      w * ui.lerpDouble(.05, .075, open)!,
      Paint()..color = colors.reward,
    );
  }

  /// 별먼지 샘: 돌 테두리 안에서 라벤더 물살이 돌며 잔상을 씻어 낸다.
  static void _eraser(Canvas canvas, Rect r, GameColors colors, double phase) {
    final w = r.width;
    final center = r.center;
    canvas.drawCircle(
      center + Offset(0, w * .03),
      w * .44,
      Paint()..color = Colors.black.withValues(alpha: .28),
    );
    canvas.drawCircle(center, w * .44, Paint()..color = _stoneDark);
    canvas.drawCircle(
      center,
      w * .44,
      Paint()
        ..color = _stoneLight
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, w * .035),
    );
    canvas.drawCircle(
      center,
      w * .36,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(colors.echo, colors.highlight, .35)!,
            colors.echoInk,
            const Color(0xff2b2360),
          ],
          stops: const [0, .45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: w * .36)),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(phase * .9);
    final swirl = Paint()
      ..color = colors.highlight.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.4, w * .03);
    for (var arm = 0; arm < 3; arm++) {
      final path = Path();
      for (var i = 0; i <= 14; i++) {
        final t = i / 14;
        final angle = arm * math.pi * 2 / 3 + t * 2.6;
        final radius = w * (.05 + .25 * t);
        final point = Offset(math.cos(angle), math.sin(angle)) * radius;
        i == 0
            ? path.moveTo(point.dx, point.dy)
            : path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, swirl);
    }
    for (var i = 0; i < 5; i++) {
      final angle = i * 1.26;
      canvas.drawCircle(
        Offset(math.cos(angle), math.sin(angle)) * (w * (.14 + i * .035)),
        w * .016,
        Paint()..color = colors.reward,
      );
    }
    canvas.restore();
  }

  /// 호박 이슬: 모래시계가 굳은 호박 방울. 떠나도 이전 잔상을 붙잡아 둔다.
  static void _hold(Canvas canvas, Rect r, GameColors colors, double phase) {
    final w = r.width;
    final pulse = 1 + .03 * math.sin(phase * 2.2);
    final center = _at(r, .5, .55);
    canvas.drawOval(
      Rect.fromCenter(center: _at(r, .5, .88), width: w * .72, height: w * .2),
      Paint()..color = _vine.withValues(alpha: .75),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(pulse);
    final top = Offset(0, -w * .44);
    final drop = Path()
      ..moveTo(top.dx, top.dy)
      ..cubicTo(w * .13, -w * .22, w * .34, -w * .08, w * .34, w * .1)
      ..arcToPoint(Offset(-w * .34, w * .1), radius: Radius.circular(w * .34))
      ..cubicTo(-w * .34, -w * .08, -w * .13, -w * .22, top.dx, top.dy)
      ..close();
    canvas.drawPath(
      drop,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colors.reward, colors.highlight, .4)!,
            colors.reward,
            const Color(0xffb86f24),
          ],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: w * .45)),
    );
    canvas.drawPath(
      drop,
      Paint()
        ..color = const Color(0xff7a4514)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * .014),
    );
    // 안쪽 모래시계
    final ink = Paint()..color = const Color(0xff5a300c);
    final glass = Path()
      ..moveTo(-w * .13, -w * .08)
      ..lineTo(w * .13, -w * .08)
      ..lineTo(w * .025, w * .08)
      ..lineTo(w * .13, w * .24)
      ..lineTo(-w * .13, w * .24)
      ..lineTo(-w * .025, w * .08)
      ..close();
    canvas.drawPath(glass, ink);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-w * .13, -w * .06),
        width: w * .1,
        height: w * .17,
      ),
      Paint()..color = colors.highlight.withValues(alpha: .6),
    );
    canvas.restore();
  }

  /// 바람 잎길: 잎 화살촉들이 나갈 수 있는 한 방향으로 흐른다.
  static void _oneWay(
    Canvas canvas,
    Rect r,
    GameColors colors,
    double phase,
    Offset direction,
  ) {
    final w = r.width;
    canvas.save();
    canvas.translate(r.center.dx, r.center.dy);
    canvas.rotate(math.atan2(direction.dy, direction.dx));
    final lane = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * .92, height: w * .62),
      Radius.circular(w * .2),
    );
    canvas.drawRRect(
      lane.shift(Offset(0, w * .025)),
      Paint()..color = Colors.black.withValues(alpha: .22),
    );
    canvas.drawRRect(
      lane,
      Paint()
        ..shader = LinearGradient(
          colors: [
            colors.primaryInk.withValues(alpha: .18),
            colors.primary.withValues(alpha: .55),
          ],
        ).createShader(lane.outerRect),
    );
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      final x = w * (-.27 + i * .27);
      // 뒤에서 앞으로 빛이 지나가며 방향을 알린다.
      final wave = (math.sin(phase * 3.2 - i * 1.25) + 1) / 2;
      paint.color = Color.lerp(
        colors.goal,
        colors.highlight,
        wave * .6,
      )!.withValues(alpha: .62 + .38 * (i + 1) / 3 * (.6 + .4 * wave));
      final tip = Offset(x + w * .13, 0);
      canvas.drawPath(_leaf(tip, math.pi - .72, w * .28, w * .055), paint);
      canvas.drawPath(_leaf(tip, math.pi + .72, w * .28, w * .055), paint);
    }
    canvas.restore();
  }

  /// 리크 이끼: 발자국과 별 표식이 있는 이끼 쿠션. 리크만 올라설 수 있다.
  static void _goalOnly(Canvas canvas, Rect r, GameColors colors) {
    final w = r.width;
    final center = r.center;
    final moss = Path();
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      moss.addOval(
        Rect.fromCircle(
          center: center + Offset(math.cos(angle), math.sin(angle)) * (w * .31),
          radius: w * .13,
        ),
      );
    }
    moss.addOval(Rect.fromCircle(center: center, radius: w * .34));
    canvas.drawPath(
      moss.shift(Offset(0, w * .03)),
      Paint()..color = Colors.black.withValues(alpha: .26),
    );
    canvas.drawPath(
      moss,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.goal, Color.lerp(colors.goal, _vine, .75)!],
        ).createShader(r),
    );
    final paw = Paint()..color = const Color(0xfffdf4e0);
    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, w * .07),
        width: w * .27,
        height: w * .22,
      ),
      paw,
    );
    for (final (dx, dy) in const [
      (-.15, -.07),
      (-.05, -.15),
      (.05, -.15),
      (.15, -.07),
    ]) {
      canvas.drawCircle(center + Offset(dx * w, dy * w), w * .05, paw);
    }
    IntroStar.paint(canvas, _at(r, .8, .2), w * .09, colors.reward);
  }

  /// 이끼 돌: 위치마다 고정된 세 모양. 움직이는 룬석과 달리 울퉁불퉁하고 이끼가 덮여 있다.
  static void _wall(Canvas canvas, Rect r, int variant) {
    final w = r.width;
    const shapes = [
      [.42, .46, .40, .47, .43, .45, .41, .46],
      [.46, .41, .45, .43, .47, .40, .44, .42],
      [.40, .45, .47, .42, .41, .47, .45, .40],
    ];
    final radii = shapes[variant % 3];
    final center = r.center;
    Path blob(double scale) {
      final points = [
        for (var i = 0; i < radii.length; i++)
          center +
              Offset(
                    math.cos(i * math.pi / 4 + .39),
                    math.sin(i * math.pi / 4 + .39),
                  ) *
                  (radii[i] * w * scale),
      ];
      final path = Path();
      for (var i = 0; i < points.length; i++) {
        final a = points[i], b = points[(i + 1) % points.length];
        final middle = (a + b) / 2;
        i == 0
            ? path.moveTo(middle.dx, middle.dy)
            : path.quadraticBezierTo(a.dx, a.dy, middle.dx, middle.dy);
      }
      final a = points[0], b = points[1];
      final middle = (a + b) / 2;
      path.quadraticBezierTo(a.dx, a.dy, middle.dx, middle.dy);
      return path..close();
    }

    final stone = blob(1);
    final depth = Offset(0, (w * .05).clamp(3.0, 6.0));
    canvas.drawPath(
      stone.shift(depth + const Offset(0, 1)),
      Paint()..color = Colors.black.withValues(alpha: .3),
    );
    canvas.drawPath(
      stone.shift(depth),
      Paint()..color = const Color(0xff222f4a),
    );
    canvas.drawPath(
      stone,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff7c8fa8), Color(0xff55677f), Color(0xff3e4e68)],
        ).createShader(r),
    );
    canvas.save();
    canvas.clipPath(stone);
    final mossCenter = _at(
      r,
      variant % 3 == 1 ? .68 : .34,
      variant % 3 == 2 ? .78 : .2,
    );
    final moss = Paint()..color = const Color(0xff5e9d78);
    for (final (dx, dy, radius) in const [
      (-.14, -.02, .13),
      (0.0, -.05, .17),
      (.15, 0.0, .13),
      (.05, .07, .11),
    ]) {
      canvas.drawCircle(mossCenter + Offset(dx * w, dy * w), radius * w, moss);
    }
    final crack = Paint()
      ..color = const Color(0xff2a3852)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1, w * .014);
    final start = _at(r, variant % 3 == 1 ? .3 : .62, .46);
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..relativeLineTo(w * .07, w * .1)
        ..relativeLineTo(-w * .05, w * .08)
        ..relativeLineTo(w * .05, w * .08),
      crack,
    );
    canvas.restore();
    canvas.drawPath(
      stone,
      Paint()
        ..color = const Color(0xffc4d0e0).withValues(alpha: .28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, w * .012),
    );
  }
}

/// 장치와 안내가 함께 쓰는 작은 다섯 꼭지 별.
abstract final class IntroStar {
  static void paint(Canvas canvas, Offset at, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? radius : radius * .45;
      final point = at + Offset(math.cos(angle), math.sin(angle)) * r;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }
}

/// 게임 아래 안내 칩과 도움말에 쓰는 장치 아이콘.
class DeviceIcon extends StatelessWidget {
  const DeviceIcon({
    super.key,
    required this.kind,
    this.size = 28,
    this.amount = 0,
  });
  final DeviceKind kind;
  final double size, amount;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _DeviceIconPainter(kind, GameTheme.colorsOf(context), amount),
  );
}

class _DeviceIconPainter extends CustomPainter {
  const _DeviceIconPainter(this.kind, this.colors, this.amount);
  final DeviceKind kind;
  final GameColors colors;
  final double amount;

  @override
  void paint(Canvas canvas, Size size) =>
      DeviceArt.draw(canvas, kind, Offset.zero & size, colors, amount: amount);

  @override
  bool shouldRepaint(_DeviceIconPainter old) =>
      old.kind != kind || old.amount != amount;
}
