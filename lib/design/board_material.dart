import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/puzzle.dart';
import '../game/board_geometry.dart';
import 'game_theme.dart';

/// 판·룬석·받침에 같은 광원과 돌의 두께를 적용한다. 그림과 입력은 분리된다.
class BoardMaterial {
  const BoardMaterial(this.colors);
  final GameColors colors;
  bool get dark => colors == GameColors.dark;
  Color get stone => dark ? const Color(0xff4b6180) : const Color(0xffb3bfce);
  Color get edge => dark ? const Color(0xff202e49) : const Color(0xff6c7f98);
  Color get well => dark ? const Color(0xff15263d) : const Color(0xffd0d6df);

  void frame(Canvas canvas, BoardGeometry geometry) {
    final shape = geometry.frameShape;
    final depth = geometry.stoneDepth;
    canvas.drawRRect(
      shape.shift(Offset(0, depth + 1)),
      Paint()..color = Colors.black.withValues(alpha: dark ? .35 : .16),
    );
    canvas.drawRRect(shape.shift(Offset(0, depth)), Paint()..color = edge);
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(stone, colors.highlight, .24)!,
            stone,
            Color.lerp(stone, edge, .32)!,
          ],
        ).createShader(shape.outerRect),
    );
    canvas.drawRRect(
      shape.deflate(1),
      Paint()
        ..color = colors.highlight.withValues(alpha: .24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final inner = RRect.fromRectAndRadius(
      geometry.framedBoardRect.inflate(3),
      Radius.circular(geometry.boardRadius + 3),
    );
    canvas.drawRRect(inner, Paint()..color = edge);
    canvas.drawRRect(
      inner.inflate(4),
      Paint()
        ..color = colors.rewardInk.withValues(alpha: dark ? .27 : .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // 각 모서리의 작은 각인은 보드 안쪽과 겹치지 않는다.
    final band = geometry.frameInset / 2;
    for (final p in [
      Offset(shape.left + band + 2, shape.top + band),
      Offset(shape.right - band - 2, shape.top + band),
      Offset(shape.left + band + 2, shape.bottom - band),
      Offset(shape.right - band - 2, shape.bottom - band),
    ]) {
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final angle = -math.pi / 2 + i * math.pi / 4;
        final r = i.isEven ? 3.8 : 1.3;
        final at = p + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      canvas.drawPath(
        path..close(),
        Paint()..color = colors.reward.withValues(alpha: .68),
      );
    }
  }

  void floor(Canvas canvas, BoardGeometry geometry) {
    canvas.drawRRect(geometry.boardShape, Paint()..color = well);
    for (var y = 0; y < geometry.rows; y++) {
      for (var x = 0; x < geometry.columns; x++) {
        final rect = geometry.tileRect(Position(x, y));
        final radius = geometry.cellSize * .14;
        final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        canvas.drawRRect(
          shape,
          Paint()..color = edge.withValues(alpha: dark ? .78 : .45),
        );
        final face = shape.deflate(1.3).shift(const Offset(0, 1));
        canvas.drawRRect(
          face,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(well, Colors.black, dark ? .12 : .02)!,
                Color.lerp(well, colors.tileTop, .45)!,
              ],
            ).createShader(rect),
        );
        canvas.drawRRect(
          shape.deflate(.5),
          Paint()
            ..color = colors.highlight.withValues(alpha: dark ? .09 : .38)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
      }
    }
  }

  void raised(
    Canvas canvas,
    Rect rect,
    double cell,
    Color color, {
    double opacity = 1,
  }) {
    final depth = (cell * .05).clamp(3.0, 6.0);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(cell * .15));
    canvas.drawRRect(
      shape.shift(Offset(0, depth + 1)),
      Paint()..color = Colors.black.withValues(alpha: .2 * opacity),
    );
    canvas.drawRRect(
      shape.shift(Offset(0, depth)),
      Paint()..color = Color.lerp(color, edge, .55)!.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, colors.highlight, .3)!.withValues(alpha: opacity),
            color.withValues(alpha: opacity),
            Color.lerp(color, edge, .18)!.withValues(alpha: opacity),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape.deflate(cell * .025),
      Paint()
        ..color = colors.highlight.withValues(alpha: .4 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .014),
    );
    final highlight = Path()
      ..moveTo(rect.left + cell * .15, rect.top + cell * .065)
      ..lineTo(rect.right - cell * .18, rect.top + cell * .065);
    canvas.drawPath(
      highlight,
      Paint()
        ..color = colors.highlight.withValues(alpha: .5 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3,
    );
  }
}

class MoonstoneFramePainter extends CustomPainter {
  const MoonstoneFramePainter(this.geometry, this.colors);
  final BoardGeometry geometry;
  final GameColors colors;
  @override
  void paint(Canvas canvas, Size size) =>
      BoardMaterial(colors).frame(canvas, geometry);
  @override
  bool shouldRepaint(MoonstoneFramePainter oldDelegate) =>
      !geometry.sameLayout(oldDelegate.geometry) ||
      colors != oldDelegate.colors;
}
