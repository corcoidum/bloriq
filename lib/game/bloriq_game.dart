import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../domain/puzzle.dart';

/// 드래그 중 표시할 가상 이동. 실제 게임 상태에는 적용하지 않는다.
class DragPreview {
  const DragPreview({required this.from, required this.target, this.nextState});

  final Position from;
  final Position target;
  final PuzzleState? nextState;
  bool get isValid => nextState != null;
}

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
  List<MoveRecord>? _replay;
  double _replayTime = 0;
  VoidCallback? _onReplayFinished;

  bool get isReplaying => _replay != null;

  DragPreview? get currentPreview {
    if (isReplaying || _dragId == null) return null;
    final state = controller.state;
    final cell = math.min(
      size.x / state.level.boardWidth,
      size.y / state.level.boardHeight,
    );
    if (cell <= 0 || _dragOffset.distance < cell * .24) return null;
    final block = state.blocks
        .where((block) => block.id == _dragId)
        .firstOrNull;
    if (block == null) return null;
    final dx = _dragOffset.dx.abs() >= _dragOffset.dy.abs()
        ? _dragOffset.dx.sign.toInt()
        : 0;
    final dy = dx == 0 ? _dragOffset.dy.sign.toInt() : 0;
    final target = Position(block.position.x + dx, block.position.y + dy);
    return DragPreview(
      from: block.position,
      target: target,
      nextState: previewMove(state, block.id, target),
    );
  }

  /// 완료한 실제 상태를 그대로 두고 기록된 스냅샷만 렌더링한다.
  bool startReplay({required VoidCallback onFinished}) {
    if (isReplaying || !controller.state.isComplete) return false;
    final moves = controller.moveHistory;
    if (moves.isEmpty) return false;
    clearEffects();
    _replay = moves;
    _replayTime = 0;
    _onReplayFinished = onFinished;
    return true;
  }

  void skipReplay() {
    if (!isReplaying) return;
    _replay = null;
    _motion = 1;
    _movingId = null;
    _from = null;
    _oldEcho = null;
    final callback = _onReplayFinished;
    _onReplayFinished = null;
    callback?.call();
  }

  @override
  void onRemove() {
    // 위젯이 해제된 뒤 이전 화면의 콜백이 실행되지 않도록 정리한다.
    _replay = null;
    _onReplayFinished = null;
    super.onRemove();
  }

  void setDrag(String? id, [Offset offset = Offset.zero]) {
    if (isReplaying) return;
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
    if (isReplaying) {
      _replayTime += dt;
      if (_replayTime >= 2.5) {
        skipReplay();
      }
    } else {
      _motion = math.min(1.0, _motion + dt / .22);
    }
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
    final replay = _replay;
    PuzzleState state;
    if (replay != null) {
      final progress = (_replayTime / 2.5 * replay.length).clamp(
        0.0,
        replay.length.toDouble(),
      );
      final index = math.min(progress.floor(), replay.length - 1);
      final move = replay[index];
      state = move.after;
      _movingId = move.blockId;
      _from = move.from;
      _oldEcho = move.previousEcho;
      _motion = (progress - index).clamp(0.0, 1.0);
    } else {
      state = controller.state;
    }
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
    final preview = currentPreview;
    final previewTarget = preview?.target;
    final previewState = preview?.nextState;

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

    // 기믹은 색과 모양을 함께 사용하고, 블록이 덮어도 아래 모서리 표시를 남긴다.
    String directionSymbol(Position direction) {
      if (direction.x == 1) return '→';
      if (direction.x == -1) return '←';
      if (direction.y == 1) return '↓';
      return '↑';
    }

    final mechanicTiles = <(Position, String, Color)>[
      for (final p in state.level.echoErasers)
        (p, '×', const Color(0xFFD17B75)),
      for (final p in state.level.echoHolds) (p, 'Ⅱ', const Color(0xFF9077BE)),
      for (final entry in state.level.oneWays.entries)
        (entry.key, directionSymbol(entry.value), const Color(0xFF5277B9)),
      for (final p in state.level.goalOnlyTiles)
        (p, '▶', const Color(0xFF298F76)),
    ];
    for (final (position, symbol, color) in mechanicTiles) {
      final rect = Rect.fromCenter(
        center: center(position),
        width: cell * .88,
        height: cell * .88,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .15)),
        paint..color = color.withValues(alpha: .15),
      );
      _label(canvas, symbol, center(position), cell * .28, color);
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
    // 실제 문의 상태는 유지하고, 이동 후 바뀔 상태만 바깥 테두리에 표시한다.
    if (gatePosition != null &&
        previewState != null &&
        previewState.isGateOpen != state.isGateOpen) {
      final rect = Rect.fromCenter(
        center: center(gatePosition),
        width: cell * .98,
        height: cell * .98,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .18)),
        paint
          ..color = previewState.isGateOpen
              ? const Color(0xFF39BA91)
              : const Color(0xFFE58383)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .045),
      );
      paint.style = PaintingStyle.fill;
      _label(
        canvas,
        previewState.isGateOpen ? '↗' : '×',
        center(gatePosition) + Offset(cell * .34, -cell * .34),
        cell * .25,
        previewState.isGateOpen
            ? const Color(0xFF16866C)
            : const Color(0xFFC45050),
      );
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
    if (previewState?.echo != null && previewState!.echo != state.echo) {
      drawEcho(previewState.echo!, .5);
    }
    if (previewTarget != null && state.level.contains(previewTarget)) {
      final rect = Rect.fromCenter(
        center: center(previewTarget),
        width: cell * .91,
        height: cell * .91,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .18)),
        paint
          ..color = previewState != null
              ? const Color(0xFF58BC97)
              : const Color(0xFFE78383)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .045),
      );
      paint.style = PaintingStyle.fill;
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
    for (final (position, symbol, color) in mechanicTiles) {
      final marker = center(position) + Offset(cell * .34, -cell * .34);
      canvas.drawCircle(marker, cell * .12, paint..color = color);
      _label(canvas, symbol, marker, cell * .17, Colors.white);
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
