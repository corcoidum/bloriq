import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../design/board_material.dart';
import 'board_geometry.dart';

/// 게임판과 시작 연출이 같은 블록의 소재감과 기호를 사용한다.
abstract final class BlockArt {
  static void block(
    Canvas canvas,
    Offset at,
    double cell,
    GameColors colors, {
    bool goal = true,
    double scale = 1,
    double opacity = 1,
    ui.Image? face,
  }) {
    final material = BoardMaterial(colors);
    if (!goal && StarArt.runeImage != null) {
      // 달빛 룬이 새겨진 돌. 바닥 그림자 위에 그림 그대로 올린다.
      _contactShadow(
        canvas,
        at + Offset(0, cell * .3 * scale),
        cell * scale,
        opacity,
      );
      StarArt.draw(
        canvas,
        StarArt.runeImage!,
        Rect.fromCenter(
          center: at + Offset(0, -cell * .02 * scale),
          width: cell * .92 * scale,
          height: cell * .92 * scale,
        ),
        opacity: opacity,
      );
      return;
    }
    if (!goal) {
      final rect = Rect.fromCenter(
        center: at,
        width: cell * .72 * scale,
        height: cell * .69 * scale,
      );
      material.raised(
        canvas,
        rect,
        cell * scale,
        colors == GameColors.dark
            ? const Color(0xff416795)
            : const Color(0xff557bae),
        opacity: opacity,
      );
      canvas.drawCircle(
        at + Offset(0, -cell * .015),
        cell * .19 * scale,
        Paint()
          ..color = colors.primary.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .045 * scale,
      );
      canvas.drawCircle(
        at + Offset(0, -cell * .015),
        cell * .205 * scale,
        Paint()
          ..color = colors.highlight.withValues(alpha: .16 * opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    final image = face ?? StarArt.riqImage;
    final cushion = StarArt.garden['riq_cushion'];
    if (image != null && cushion != null) {
      // 민트 이끼 방석 위에 앉은 리크.
      StarArt.draw(
        canvas,
        cushion,
        Rect.fromCenter(
          center: at + Offset(0, cell * .14 * scale),
          width: cell * .96 * scale,
          height: cell * .96 * scale,
        ),
        opacity: opacity,
      );
      StarArt.draw(
        canvas,
        image,
        goalSpriteRect(at, cell, scale: scale),
        opacity: opacity,
      );
      return;
    }
    if (image != null) {
      material.raised(
        canvas,
        Rect.fromCenter(
          center: at + Offset(0, cell * .045),
          width: cell * .77 * scale,
          height: cell * .71 * scale,
        ),
        cell * scale,
        colors.goalInk,
        opacity: opacity,
      );
      StarArt.draw(
        canvas,
        image,
        goalSpriteRect(at, cell, scale: scale),
        opacity: opacity,
      );
      return;
    }
    final paint = Paint();
    final rect = Rect.fromCenter(
      center: at,
      width: cell * .76 * scale,
      height: cell * .76 * scale,
    );
    final color = goal ? colors.goal : colors.primary;
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(cell * .18));
    canvas.drawRRect(
      rounded.shift(Offset(0, cell * .065)),
      paint..color = colors.blockSymbol.withValues(alpha: .15 * opacity),
    );
    canvas.drawRRect(
      rounded,
      paint
        ..color = Colors.white
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(
              color,
              colors.highlight,
              .32,
            )!.withValues(alpha: opacity),
            color.withValues(alpha: opacity),
            Color.lerp(
              color,
              colors.blockSymbol,
              .10,
            )!.withValues(alpha: opacity),
          ],
        ).createShader(rect),
    );
    paint.shader = null;
    canvas.drawRRect(
      rounded.deflate(cell * .022),
      paint
        ..color = colors.highlight.withValues(alpha: .52 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .014),
    );
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left + rect.width * .16,
          rect.top + rect.height * .12,
          rect.width * .40,
          rect.height * .055,
        ),
        Radius.circular(cell * .04),
      ),
      paint..color = colors.highlight.withValues(alpha: .48 * opacity),
    );
    label(
      canvas,
      goal ? '▶' : '•',
      at,
      cell * (goal ? .31 : .4) * scale,
      colors.blockSymbol.withValues(alpha: opacity),
    );
  }

  /// 리크 스프라이트가 놓이는 영역. 표정 오버레이도 같은 영역을 쓴다.
  static Rect goalSpriteRect(Offset at, double cell, {double scale = 1}) {
    final extent = cell * BoardGeometry.spriteFraction * scale;
    return Rect.fromCenter(
      center: at + Offset(.014 * extent, -.039 * extent),
      width: extent,
      height: extent,
    );
  }

  static void echo(
    Canvas canvas,
    Offset at,
    double cell,
    GameColors colors, {
    double opacity = 1,
  }) {
    if (StarArt.riqImage case final riq? when StarArt.garden.isNotEmpty) {
      // 보랏빛 안개로 남은 리크의 실루엣과 발밑의 빛.
      final mist = Rect.fromCenter(
        center: at + Offset(0, cell * .08),
        width: cell * .92,
        height: cell * .7,
      );
      canvas.drawOval(
        mist,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors.echo.withValues(alpha: .42 * opacity),
              colors.echo.withValues(alpha: 0),
            ],
          ).createShader(mist),
      );
      final rect = goalSpriteRect(at, cell, scale: .94);
      StarArt.draw(
        canvas,
        riq,
        rect,
        opacity: .62 * opacity,
        tint: colors == GameColors.light ? colors.echoInk : colors.echo,
      );
      StarArt.draw(canvas, riq, rect, opacity: .16 * opacity);
      return;
    }
    if (StarArt.echoImage case final image?) {
      StarArt.draw(
        canvas,
        image,
        Rect.fromCenter(
          center: at,
          width: cell * BoardGeometry.spriteFraction,
          height: cell * BoardGeometry.spriteFraction,
        ),
        opacity: opacity * .72,
        tint: colors == GameColors.light
            ? colors.echoInk.withValues(alpha: .85)
            : null,
      );
      return;
    }
    final rect = Rect.fromCenter(
      center: at,
      width: cell * .78,
      height: cell * .78,
    );
    final rounded = RRect.fromRectAndRadius(rect, Radius.circular(cell * .17));
    final paint = Paint()..color = colors.echo.withValues(alpha: .20 * opacity);
    canvas.drawRRect(rounded, paint);
    canvas.drawRRect(
      rounded,
      paint
        ..color = colors.echoInk.withValues(alpha: .9 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2, cell * .025),
    );
    canvas.drawRRect(
      rounded.deflate(cell * .075),
      paint
        ..color = colors.echo.withValues(alpha: .4 * opacity)
        ..strokeWidth = math.max(1, cell * .012),
    );
    label(
      canvas,
      '◌',
      at,
      cell * .30,
      colors.echoInk.withValues(alpha: opacity),
    );
  }

  static void exit(Canvas canvas, Offset at, double cell, GameColors colors) {
    canvas.drawCircle(
      at + Offset(0, cell * .025),
      cell * .37,
      Paint()..color = Colors.black.withValues(alpha: .18),
    );
    canvas.drawCircle(
      at,
      cell * .37,
      Paint()..color = colors.rewardInk.withValues(alpha: .16),
    );
    canvas.drawCircle(
      at,
      cell * .385,
      Paint()
        ..color = colors.reward.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .015),
    );
    if (StarArt.portalImage case final image?) {
      StarArt.draw(
        canvas,
        image,
        Rect.fromCenter(center: at, width: cell, height: cell),
        tint: colors == GameColors.light
            ? colors.rewardInk.withValues(alpha: .65)
            : null,
      );
      return;
    }
    final paint = Paint()..color = colors.reward.withValues(alpha: .15);
    canvas.drawCircle(at, cell * .43, paint);
    canvas.drawCircle(
      at,
      cell * .34,
      paint..color = colors.reward.withValues(alpha: .25),
    );
    canvas.drawCircle(
      at,
      cell * .34,
      paint
        ..color = colors.reward
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * .045,
    );
    canvas.drawCircle(
      at,
      cell * .30,
      paint
        ..color = colors.highlight.withValues(alpha: .75)
        ..strokeWidth = math.max(1.2, cell * .012),
    );
    label(canvas, '★', at, cell * .38, colors.rewardInk);
  }

  static void _contactShadow(
    Canvas canvas,
    Offset at,
    double cell,
    double opacity,
  ) {
    canvas.drawOval(
      Rect.fromCenter(center: at, width: cell * .74, height: cell * .16),
      Paint()..color = Colors.black.withValues(alpha: .28 * opacity),
    );
  }

  /// 세계의 바위 또는 기본 이끼 바위와 그루터기.
  static bool obstacle(
    Canvas canvas,
    Offset at,
    double cell,
    int variant, {
    ui.Image? customRock,
    bool useGarden = true,
  }) {
    final image =
        customRock ??
        (useGarden
            ? StarArt.garden[variant % 3 == 0 ? 'stump' : 'rock'] ??
                  StarArt.garden['rock']
            : null);
    if (image == null) return false;
    _contactShadow(canvas, at + Offset(0, cell * .28), cell, 1);
    StarArt.draw(
      canvas,
      image,
      Rect.fromCenter(
        center: at + Offset(0, -cell * .02),
        width: cell * .94,
        height: cell * .94,
      ),
    );
    return true;
  }

  /// 기믹 칸 바닥 그림. 물길은 진행 방향으로 회전한다. 그림이 없으면 false.
  static bool mechanic(
    Canvas canvas,
    String kind,
    Offset at,
    double cell, {
    Offset direction = const Offset(1, 0),
    double pulse = 0,
  }) {
    final image = StarArt.garden[kind];
    if (image == null) return false;
    final extent = switch (kind) {
      'tile_amber' => cell * .74,
      'tile_stream' => cell * .98,
      _ => cell * .9,
    };
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(math.atan2(direction.dy, direction.dx));
    final height = extent * image.height / image.width;
    StarArt.draw(
      canvas,
      image,
      Rect.fromCenter(center: Offset.zero, width: extent, height: height),
      opacity: .92 + .08 * pulse,
    );
    canvas.restore();
    return true;
  }

  /// 달 수정 발판. 잔상이 올라가 문을 열면 빛이 차오른다.
  static bool switchPlate(
    Canvas canvas,
    Offset at,
    double cell,
    GameColors colors, {
    required double glow,
  }) {
    final image = StarArt.garden['switch_crystal'];
    if (image == null) return false;
    if (glow > 0) {
      final rect = Rect.fromCircle(center: at, radius: cell * .62);
      canvas.drawCircle(
        at,
        cell * .62,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colors.cyan.withValues(alpha: .55 * glow),
              colors.cyan.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }
    StarArt.draw(
      canvas,
      image,
      Rect.fromCenter(center: at, width: cell * .94, height: cell * .94),
    );
    return true;
  }

  /// 덩굴 문. [open]이 1에 가까울수록 덩굴이 양옆으로 말려 가운데가 열린다.
  static bool gate(
    Canvas canvas,
    Offset at,
    double cell,
    GameColors colors, {
    required double open,
  }) {
    final image = StarArt.garden['gate_closed'];
    if (image == null) return false;
    final rect = Rect.fromCenter(
      center: at,
      width: cell * .92,
      height: cell * .92,
    );
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawCircle(
      at,
      cell * .46,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colors.cyan.withValues(alpha: .10 + .22 * open),
            colors.cyan.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: at, radius: cell * .46)),
    );
    for (final side in [-1.0, 1.0]) {
      final half = side < 0
          ? Rect.fromLTRB(
              source.left,
              source.top,
              source.center.dx,
              source.bottom,
            )
          : Rect.fromLTRB(
              source.center.dx,
              source.top,
              source.right,
              source.bottom,
            );
      final target = side < 0
          ? Rect.fromLTRB(rect.left, rect.top, rect.center.dx, rect.bottom)
          : Rect.fromLTRB(rect.center.dx, rect.top, rect.right, rect.bottom);
      final hinge = Offset(side < 0 ? rect.left : rect.right, rect.bottom);
      canvas.save();
      canvas.translate(hinge.dx, hinge.dy);
      canvas.rotate(side * .16 * open);
      canvas.scale(1 - .45 * open, 1 - .06 * open);
      canvas.translate(-hinge.dx, -hinge.dy);
      canvas.drawImageRect(image, half, target, paint);
      canvas.restore();
    }
    if (open > 0) {
      // 열린 덩굴에 작은 꽃이 핀다.
      for (final (dx, dy) in [
        (-.36, -.22),
        (-.30, .12),
        (.34, -.12),
        (.38, .2),
      ]) {
        final bloom = at + Offset(dx * cell, dy * cell);
        for (var i = 0; i < 5; i++) {
          final angle = i * math.pi * 2 / 5;
          canvas.drawCircle(
            bloom +
                Offset(math.cos(angle), math.sin(angle)) * cell * .028 * open,
            cell * .024 * open,
            Paint()..color = const Color(0xffc9e4ff).withValues(alpha: open),
          );
        }
        canvas.drawCircle(
          bloom,
          cell * .016 * open,
          Paint()..color = colors.reward.withValues(alpha: open),
        );
      }
    }
    return true;
  }

  static void label(
    Canvas canvas,
    String value,
    Offset at,
    double size,
    Color color,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontFamily: GameTypography.canvasFontFamily,
          fontFamilyFallback: const ['NanumGothic'],
          fontSize: size,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, at - Offset(text.width / 2, text.height / 2));
    text.dispose();
  }
}
