import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../domain/puzzle.dart';

/// The domain owns the rules; this renderer only animates their results.
class BloriqGame extends FlameGame {
  BloriqGame(this.controller);
  final PuzzleController controller;

  String? _movingId;
  Position? _from;
  Position? _oldEcho;
  double _motion = 1;
  Position? _blocked;
  double _blockedTime = 0;
  String? _dragId;
  Offset _dragOffset = Offset.zero;
  double _hintTime = 0;
  double _celebrationTime = 0;

  void setDrag(String? id, [Offset offset = Offset.zero]) {
    _dragId = id;
    _dragOffset = offset;
  }

  void animateMove(String id, Position from, Position? oldEcho) {
    _dragId = null;
    _movingId = id;
    _from = from;
    _oldEcho = oldEcho;
    _motion = 0;
  }

  void flashBlocked(Position position) {
    _dragId = null;
    _blocked = position;
    _blockedTime = .42;
  }

  void clearEffects() {
    _movingId = null;
    _dragId = null;
    _motion = 1;
    _blockedTime = 0;
    _celebrationTime = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    _motion = math.min(1.0, _motion + dt / .22);
    _blockedTime = math.max(0.0, _blockedTime - dt);
    _hintTime += dt;
    if (controller.state.isComplete) {
      _celebrationTime += dt;
    }
  }

  @override
  Color backgroundColor() => const Color(0xFFF6F8FF);

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    final state = controller.state;
    final cell = math.min(
      size.x / state.level.boardWidth,
      size.y / state.level.boardHeight,
    );
    final boardSize = Size(
      cell * state.level.boardWidth,
      cell * state.level.boardHeight,
    );
    final origin = Offset(
      (size.x - boardSize.width) / 2,
      (size.y - boardSize.height) / 2,
    );
    Offset center(Position p) =>
        origin + Offset((p.x + .5) * cell, (p.y + .5) * cell);
    final paint = Paint();

    // A quiet border makes the grid read as one tactile game board.
    final board = RRect.fromRectAndRadius(
      (origin & boardSize).deflate(cell * .015),
      Radius.circular(cell * .22),
    );
    canvas.drawRRect(board, paint..color = const Color(0xFFD7E2F7));

    for (var y = 0; y < state.level.boardHeight; y++) {
      for (var x = 0; x < state.level.boardWidth; x++) {
        final rect = Rect.fromLTWH(
          origin.dx + x * cell + 3,
          origin.dy + y * cell + 3,
          cell - 6,
          cell - 6,
        );
        final tile = RRect.fromRectAndRadius(rect, Radius.circular(cell * .16));
        canvas.drawRRect(
          tile,
          paint
            ..color = Colors.white
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF4F7FF), Color(0xFFE3EBFC)],
            ).createShader(rect),
        );
        paint.shader = null;
        canvas.drawRRect(
          tile.deflate(1),
          paint
            ..color = Colors.white.withValues(alpha: .72)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
        paint.style = PaintingStyle.fill;
      }
    }

    // Matching cyan outlines connect the echo plate and its gate even while
    // a block is covering the plate. The gate state comes from the domain.
    final switchPosition = state.level.echoSwitch;
    if (switchPosition != null) {
      final switchCenter = center(switchPosition);
      final plateRect = Rect.fromCenter(
        center: switchCenter,
        width: cell * .94,
        height: cell * .94,
      );
      final plate = RRect.fromRectAndRadius(
        plateRect,
        Radius.circular(cell * .18),
      );
      canvas.drawRRect(
        plate,
        paint
          ..color = const Color(0xFF4FADD3).withValues(alpha: .18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        plate.deflate(cell * .015),
        paint
          ..color = const Color(0xFF277FAD)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, cell * .025),
      );
      paint.style = PaintingStyle.fill;
      // A diamond marks the plate even in grayscale.
      final diamond = Path()
        ..moveTo(switchCenter.dx, switchCenter.dy - cell * .14)
        ..lineTo(switchCenter.dx + cell * .14, switchCenter.dy)
        ..lineTo(switchCenter.dx, switchCenter.dy + cell * .14)
        ..lineTo(switchCenter.dx - cell * .14, switchCenter.dy)
        ..close();
      canvas.drawPath(diamond, paint..color = const Color(0xFF277FAD));
    }

    final gatePosition = state.level.echoGate;
    if (gatePosition != null) {
      final gateCenter = center(gatePosition);
      final gateRect = Rect.fromCenter(
        center: gateCenter,
        width: cell * .88,
        height: cell * .88,
      );
      final gate = RRect.fromRectAndRadius(
        gateRect,
        Radius.circular(cell * .14),
      );
      final gateColor = state.isGateOpen
          ? const Color(0xFF16A891)
          : const Color(0xFF287FAF);
      canvas.drawRRect(
        gate,
        paint
          ..color = gateColor.withValues(alpha: state.isGateOpen ? .10 : .18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        gate,
        paint
          ..color = gateColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.5, cell * .035),
      );
      // Closed gates have visible bars. An open gate is an unobstructed frame.
      if (!state.isGateOpen) {
        paint
          ..strokeWidth = math.max(2.0, cell * .035)
          ..strokeCap = StrokeCap.round;
        for (final offset in [-.19, 0.0, .19]) {
          canvas.drawLine(
            gateCenter + Offset(cell * offset, -cell * .29),
            gateCenter + Offset(cell * offset, cell * .29),
            paint,
          );
        }
      }
      paint.style = PaintingStyle.fill;
    }
    for (final p in state.level.obstacles) {
      final rect = Rect.fromCenter(
        center: center(p),
        width: cell * .86,
        height: cell * .86,
      );
      final wall = RRect.fromRectAndRadius(rect, Radius.circular(cell * .15));
      canvas.drawRRect(
        wall.shift(Offset(0, cell * .025)),
        paint..color = const Color(0xFF566A89).withValues(alpha: .25),
      );
      canvas.drawRRect(
        wall,
        paint
          ..color = Colors.white
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9AAFC6), Color(0xFF7488A6)],
          ).createShader(rect),
      );
      paint.shader = null;
      canvas.drawRRect(
        wall.deflate(cell * .035),
        paint
          ..color = Colors.white.withValues(alpha: .23)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .012),
      );
      paint.style = PaintingStyle.fill;
    }

    final exit = center(state.level.exitPosition);
    final glow = .5 + .5 * math.sin(_hintTime * 1.8);
    canvas.drawCircle(
      exit,
      cell * (.39 + glow * .015),
      paint
        ..color = const Color(0xFFF9C958).withValues(alpha: .12 + glow * .05),
    );
    canvas.drawCircle(exit, cell * .33, paint..color = const Color(0xFFFFD768));
    canvas.drawCircle(exit, cell * .27, paint..color = const Color(0xFFFFF4C9));
    canvas.drawCircle(
      exit,
      cell * .27,
      paint
        ..color = Colors.white.withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .015),
    );
    paint.style = PaintingStyle.fill;
    _label(canvas, '★', exit, cell * .33, const Color(0xFFBB7C0B));

    void drawEcho(Position p, double alpha) {
      if (alpha <= 0) return;
      final rect = Rect.fromCenter(
        center: center(p),
        width: cell * .72,
        height: cell * .72,
      );
      final rounded = RRect.fromRectAndRadius(
        rect,
        Radius.circular(cell * .17),
      );
      canvas.drawRRect(
        rounded,
        paint..color = const Color(0xFF8B79C6).withValues(alpha: .18 * alpha),
      );
      canvas.drawRRect(
        rounded,
        paint
          ..color = const Color(0xFF7866AD).withValues(alpha: .76 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, cell * .025),
      );
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        center(p),
        cell * (.19 + .008 * math.sin(_hintTime * 2.4)),
        paint
          ..color = const Color(0xFF8B79C6).withValues(alpha: .16 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .015),
      );
      paint.style = PaintingStyle.fill;
      _label(
        canvas,
        '◌',
        center(p),
        cell * .30,
        const Color(0xFF7866AD).withValues(alpha: alpha),
      );
    }

    if (_oldEcho != null && _motion < 1 && _oldEcho != state.echo) {
      drawEcho(_oldEcho!, 1 - _motion);
    }
    if (state.echo != null) {
      drawEcho(state.echo!, _motion < 1 ? .5 + .5 * _motion : 1);
    }

    for (final block in state.blocks) {
      final isGoal = block.id == Level.goalBlockId;
      var at = center(block.position);
      if (block.id == _movingId && _from != null && _motion < 1) {
        final eased = Curves.easeOutCubic.transform(_motion);
        at = Offset.lerp(center(_from!), at, eased)!;
      }
      if (block.id == _dragId) {
        final maxDrag = cell * .8;
        at += Offset(
          _dragOffset.dx.clamp(-maxDrag, maxDrag).toDouble(),
          _dragOffset.dy.clamp(-maxDrag, maxDrag).toDouble(),
        );
      }
      if (state.isComplete && isGoal && _motion >= 1) continue;
      final scale = state.isComplete && isGoal ? 1 - .45 * _motion : 1.0;
      final rect = Rect.fromCenter(
        center: at,
        width: cell * .76 * scale,
        height: cell * .76 * scale,
      );
      final color = isGoal ? const Color(0xFF259A7D) : const Color(0xFF5274CB);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(Offset(0, cell * .05)),
          Radius.circular(cell * .18),
        ),
        paint..color = color.withValues(alpha: .25),
      );
      final rounded = RRect.fromRectAndRadius(
        rect,
        Radius.circular(cell * .18),
      );
      canvas.drawRRect(
        rounded,
        paint
          ..color = Colors.white
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isGoal
                ? const [Color(0xFF5BD8AF), Color(0xFF25A585)]
                : const [Color(0xFF91AEFA), Color(0xFF6281DC)],
          ).createShader(rect),
      );
      paint.shader = null;
      canvas.drawRRect(
        rounded.deflate(cell * .022),
        paint
          ..color = Colors.white.withValues(alpha: .45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .014),
      );
      paint.style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + rect.width * .18,
            rect.top + rect.height * .12,
            rect.width * .38,
            rect.height * .06,
          ),
          Radius.circular(cell * .04),
        ),
        paint..color = Colors.white.withValues(alpha: .36),
      );
      _label(
        canvas,
        isGoal ? '▶' : '•',
        at,
        cell * (isGoal ? .31 : .4) * scale,
        Colors.white,
      );
    }
    if (switchPosition != null) {
      // The corner marker remains visible when a block covers the plate.
      final marker = center(switchPosition) + Offset(-cell * .34, -cell * .34);
      canvas.drawCircle(
        marker,
        cell * .095,
        paint..color = const Color(0xFF277FAD),
      );
      final mark = Path()
        ..moveTo(marker.dx, marker.dy - cell * .05)
        ..lineTo(marker.dx + cell * .05, marker.dy)
        ..lineTo(marker.dx, marker.dy + cell * .05)
        ..lineTo(marker.dx - cell * .05, marker.dy)
        ..close();
      canvas.drawPath(mark, paint..color = Colors.white);
    }
    if (state.isComplete && _celebrationTime < 1.1) {
      // A small, deterministic burst communicates success without new assets.
      final t = (_celebrationTime / 1.1).clamp(0.0, 1.0);
      final distance = cell * (.18 + .52 * Curves.easeOut.transform(t));
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4;
        final particle =
            exit + Offset(math.cos(angle), math.sin(angle)) * distance;
        canvas.drawCircle(
          particle,
          cell * (i.isEven ? .035 : .023) * (1 - t * .45),
          paint
            ..color =
                (i.isEven ? const Color(0xFFFFC751) : const Color(0xFF5DCFB2))
                    .withValues(alpha: 1 - t),
        );
      }
    }
    if (state.level.id == 1 && state.moves == 0 && _dragId == null) {
      final goal = center(state.level.startPosition);
      final shift = math.sin(_hintTime * 3) * cell * .05;
      final start = goal + Offset(cell * .10 + shift, -cell * .48);
      final end = goal + Offset(cell * .63 + shift, -cell * .48);
      paint
        ..color = const Color(0xFF5271C7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3.0, cell * .035)
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(start, end, paint);
      canvas.drawLine(end, end + Offset(-cell * .13, -cell * .10), paint);
      canvas.drawLine(end, end + Offset(-cell * .13, cell * .10), paint);
      paint.style = PaintingStyle.fill;
    }
    if (_blocked != null &&
        _blockedTime > 0 &&
        state.level.contains(_blocked!)) {
      final rect = Rect.fromCenter(
        center: center(_blocked!),
        width: cell * .87,
        height: cell * .87,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .18)),
        paint
          ..color = const Color(0xFFE56767)
              .withValues(alpha: _blockedTime / .42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .04),
      );
      paint.style = PaintingStyle.fill;
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
