import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
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
  }) {
    final image = goal ? StarArt.riqImage : StarArt.runeImage;
    if (image != null) {
      if (goal) {
        final mark = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: at + Offset(0, cell * .045),
            width: cell * .77 * scale,
            height: cell * .73 * scale,
          ),
          Radius.circular(cell * .18),
        );
        canvas.drawRRect(
          mark,
          Paint()..color = colors.goal.withValues(alpha: .18 * opacity),
        );
        canvas.drawRRect(
          mark,
          Paint()
            ..color = colors.goalInk.withValues(alpha: opacity)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(2, cell * .023),
        );
      }
      final extent = cell * BoardGeometry.spriteFraction * scale;
      // Source silhouette anchor (.486,.539) places RIQ's visual center on the cell center.
      final anchor = goal ? const Offset(.486, .539) : const Offset(.5, .5);
      final rect = Rect.fromCenter(
        center:
            at + Offset((.5 - anchor.dx) * extent, (.5 - anchor.dy) * extent),
        width: extent,
        height: extent,
      );
      StarArt.draw(canvas, image, rect, opacity: opacity);
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

  static void echo(
    Canvas canvas,
    Offset at,
    double cell,
    GameColors colors, {
    double opacity = 1,
  }) {
    if (StarArt.echoImage case final image?) {
      StarArt.draw(
        canvas,
        image,
        Rect.fromCenter(
          center: at,
          width: cell * BoardGeometry.spriteFraction,
          height: cell * BoardGeometry.spriteFraction,
        ),
        opacity: opacity,
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
