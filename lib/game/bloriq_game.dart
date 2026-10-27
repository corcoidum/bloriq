import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../domain/puzzle.dart';

/// Flame은 표시만 담당하고 퍼즐 상태 변경은 도메인에서 처리한다.
class BloriqGame extends FlameGame {
  BloriqGame(this.controller);
  final PuzzleController controller;

  @override
  Color backgroundColor() => const Color(0xFFF6F8FF);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final state = controller.state;
    final cell = size.x / state.level.boardWidth;
    final paint = Paint();
    for (var y = 0; y < state.level.boardHeight; y++) {
      for (var x = 0; x < state.level.boardWidth; x++) {
        final rect = Rect.fromLTWH(
          x * cell + 3,
          y * cell + 3,
          cell - 6,
          cell - 6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(cell * .17)),
          paint..color = const Color(0xFFE5ECFB),
        );
      }
    }
    Offset center(Position p) => Offset((p.x + .5) * cell, (p.y + .5) * cell);
    for (final p in state.level.obstacles) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center(p),
            width: cell * .78,
            height: cell * .78,
          ),
          Radius.circular(cell * .16),
        ),
        paint..color = const Color(0xFF64748B),
      );
    }
    if (state.path.length > 1) {
      final line = Path()
        ..moveTo(center(state.path.first).dx, center(state.path.first).dy);
      for (final p in state.path.skip(1)) {
        line.lineTo(center(p).dx, center(p).dy);
      }
      canvas.drawPath(
        line,
        paint
          ..color = const Color(0xFF60A5FA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * .16
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      paint.style = PaintingStyle.fill;
    }
    canvas.drawCircle(
      center(state.level.startPosition),
      cell * .24,
      paint..color = const Color(0xFF4ADE80),
    );
    canvas.drawCircle(
      center(state.level.exitPosition),
      cell * .24,
      paint..color = const Color(0xFFFBBF24),
    );
    _label(
      canvas,
      '▶',
      center(state.level.startPosition),
      cell * .27,
      Colors.white,
    );
    _label(
      canvas,
      '★',
      center(state.level.exitPosition),
      cell * .30,
      Colors.white,
    );
    const colors = [
      Color(0xFF60A5FA),
      Color(0xFFFF6B6B),
      Color(0xFFA78BFA),
      Color(0xFFFB923C),
    ];
    for (var i = 0; i < state.blocks.length; i++) {
      final rect = Rect.fromCenter(
        center: center(state.blocks[i].position),
        width: cell * .78,
        height: cell * .78,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(Offset(0, cell * .04)),
          Radius.circular(cell * .18),
        ),
        paint..color = colors[i % colors.length].withValues(alpha: .25),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .18)),
        paint..color = colors[i % colors.length],
      );
      canvas.drawCircle(
        center(state.blocks[i].position),
        cell * .06,
        paint..color = Colors.white.withValues(alpha: .75),
      );
    }
  }

  void _label(
    Canvas canvas,
    String value,
    Offset center,
    double fontSize,
    Color color,
  ) {
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }
}
