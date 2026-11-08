import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../design/game_theme.dart';
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
  GameColors _colors = GameColors.light;
  bool _reduceMotion = false;
  double _celebrationProgress = 1;
  bool _isNewBest = false;
  List<MoveRecord>? _replay;
  double _replayTime = 0;
  VoidCallback? _onReplayFinished;

  bool get isReplaying => _replay != null;
  GameColors get gameColors => _colors;
  bool get reduceMotion => _reduceMotion;
  double get celebrationProgress => _celebrationProgress;

  /// 테마와 접근성만 바꾸며 게임 상태와 진행 중인 드래그는 유지한다.
  void configureAppearance({
    required GameColors colors,
    required bool reduceMotion,
  }) {
    _colors = colors;
    _reduceMotion = reduceMotion;
    if (reduceMotion) _motion = 1;
  }

  /// Flutter의 단일 타임라인을 사용한다. 기록 저장이나 규칙을 실행하지 않는다.
  void setCelebrationProgress(double progress, {bool isNewBest = false}) {
    _celebrationProgress = progress.isFinite ? progress.clamp(0.0, 1.0) : 1;
    _isNewBest = isNewBest;
  }

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
    _motion = _reduceMotion ? 1 : 0;
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
    _celebrationProgress = 1;
    _isNewBest = false;
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
      _motion = _reduceMotion
          ? 1
          : math.min(
              1.0,
              _motion + dt * 1000 / GameEffects.moveDuration.inMilliseconds,
            );
    }
    _blockedTime = math.max(0.0, _blockedTime - dt);
    if (!_reduceMotion) _hintTime += dt;
  }

  @override
  Color backgroundColor() => _colors.background;

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
      _motion = _reduceMotion ? 1 : (progress - index).clamp(0.0, 1.0);
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
    canvas.drawRRect(board, paint..color = _colors.boardSurface);

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
            ..color = _colors.highlight
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_colors.tileTop, _colors.tileBottom],
            ).createShader(rect),
        );
        paint.shader = null;
        canvas.drawRRect(
          tile.deflate(1),
          paint
            ..color = _colors.outline.withValues(alpha: .30)
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
      for (final p in state.level.echoErasers) (p, '×', _colors.echo),
      for (final p in state.level.echoHolds) (p, 'Ⅱ', _colors.echo),
      for (final entry in state.level.oneWays.entries)
        (entry.key, directionSymbol(entry.value), _colors.primary),
      for (final p in state.level.goalOnlyTiles) (p, '▶', _colors.goal),
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
      _label(
        canvas,
        symbol,
        center(position),
        cell * .28,
        color == _colors.echo
            ? _colors.echoInk
            : Color.lerp(color, _colors.text, .26)!,
      );
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
          ..color = _colors.cyan.withValues(alpha: .18)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRRect(
        plate.deflate(cell * .015),
        paint
          ..color = _colors.cyan
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
      canvas.drawPath(diamond, paint..color = _colors.cyan);
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
      final gateColor = _colors.cyan;
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
          ..color = previewState.isGateOpen ? _colors.cyan : _colors.error
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .045),
      );
      paint.style = PaintingStyle.fill;
      _label(
        canvas,
        previewState.isGateOpen ? '↗' : '×',
        center(gatePosition) + Offset(cell * .34, -cell * .34),
        cell * .25,
        previewState.isGateOpen ? _colors.cyan : _colors.error,
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
        paint..color = _colors.slate.withValues(alpha: .25),
      );
      canvas.drawRRect(
        wall,
        paint
          ..color = _colors.highlight
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(_colors.slate, _colors.highlight, .12)!,
              _colors.slate,
            ],
          ).createShader(rect),
      );
      paint.shader = null;
      canvas.drawRRect(
        wall.deflate(cell * .035),
        paint
          ..color = _colors.highlight.withValues(alpha: .23)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .012),
      );
      paint.style = PaintingStyle.fill;
    }

    final exit = center(state.level.exitPosition);
    final glow = _reduceMotion ? .5 : .5 + .5 * math.sin(_hintTime * 1.8);
    canvas.drawCircle(
      exit,
      cell * (.39 + glow * .015),
      paint..color = _colors.reward.withValues(alpha: .12 + glow * .05),
    );
    canvas.drawCircle(exit, cell * .33, paint..color = _colors.reward);
    canvas.drawCircle(
      exit,
      cell * .27,
      paint..color = Color.lerp(_colors.reward, _colors.surface, .65)!,
    );
    canvas.drawCircle(
      exit,
      cell * .27,
      paint
        ..color = _colors.highlight.withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .015),
    );
    paint.style = PaintingStyle.fill;
    _label(canvas, '★', exit, cell * .33, _colors.rewardInk);

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
        paint..color = _colors.echo.withValues(alpha: .18 * alpha),
      );
      canvas.drawRRect(
        rounded,
        paint
          ..color = _colors.echoInk.withValues(alpha: .95 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, cell * .025),
      );
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        center(p),
        cell * (.19 + (_reduceMotion ? 0 : .008 * math.sin(_hintTime * 2.4))),
        paint
          ..color = _colors.echoInk.withValues(alpha: .16 * alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, cell * .015),
      );
      paint.style = PaintingStyle.fill;
      _label(
        canvas,
        '◌',
        center(p),
        cell * .30,
        _colors.echoInk.withValues(alpha: alpha),
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
          ..color = previewState != null ? _colors.goal : _colors.error
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
      final escaping = state.isComplete && isGoal;
      final celebrating = escaping && !isReplaying && !_reduceMotion;
      if (escaping &&
          ((!celebrating && _motion >= 1) ||
              (celebrating && _celebrationProgress >= .34))) {
        continue;
      }
      final escapeTime = ((_celebrationProgress - .12) / .22).clamp(0.0, 1.0);
      final scale = celebrating
          ? 1 + .14 * math.sin(escapeTime * math.pi)
          : 1.0;
      final opacity = celebrating
          ? 1 - ((_celebrationProgress - .24) / .10).clamp(0.0, 1.0)
          : 1.0;
      if (celebrating && escapeTime > 0) {
        // 겹친 반투명 원으로 부드러운 빛을 표현하며 실시간 blur는 사용하지 않는다.
        for (var layer = 0; layer < 3; layer++) {
          canvas.drawCircle(
            at,
            cell * (.44 + layer * .08) * scale,
            paint
              ..color = _colors.goal.withValues(
                alpha: (.09 - layer * .02) * math.sin(escapeTime * math.pi),
              ),
          );
        }
      }
      final rect = Rect.fromCenter(
        center: at,
        width: cell * .76 * scale,
        height: cell * .76 * scale,
      );
      final color = isGoal ? _colors.goal : _colors.primary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.shift(Offset(0, cell * .05)),
          Radius.circular(cell * .18),
        ),
        paint..color = color.withValues(alpha: .25 * opacity),
      );
      final rounded = RRect.fromRectAndRadius(
        rect,
        Radius.circular(cell * .18),
      );
      canvas.drawRRect(
        rounded,
        paint
          ..color = _colors.highlight
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(
                color,
                _colors.highlight,
                .20,
              )!.withValues(alpha: opacity),
              color.withValues(alpha: opacity),
            ],
          ).createShader(rect),
      );
      paint.shader = null;
      canvas.drawRRect(
        rounded.deflate(cell * .022),
        paint
          ..color = _colors.highlight.withValues(alpha: .45 * opacity)
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
        paint..color = _colors.highlight.withValues(alpha: .36 * opacity),
      );
      _label(
        canvas,
        isGoal ? '▶' : '•',
        at,
        cell * (isGoal ? .31 : .4) * scale,
        _colors.blockSymbol.withValues(alpha: opacity),
      );
    }
    for (final (position, symbol, color) in mechanicTiles) {
      final marker = center(position) + Offset(cell * .34, -cell * .34);
      canvas.drawCircle(marker, cell * .12, paint..color = color);
      _label(canvas, symbol, marker, cell * .17, _colors.blockSymbol);
    }
    if (switchPosition != null) {
      // The corner marker remains visible when a block covers the plate.
      final marker = center(switchPosition) + Offset(-cell * .34, -cell * .34);
      canvas.drawCircle(marker, cell * .095, paint..color = _colors.cyan);
      final mark = Path()
        ..moveTo(marker.dx, marker.dy - cell * .05)
        ..lineTo(marker.dx + cell * .05, marker.dy)
        ..lineTo(marker.dx, marker.dy + cell * .05)
        ..lineTo(marker.dx - cell * .05, marker.dy)
        ..close();
      canvas.drawPath(mark, paint..color = _colors.surface);
    }
    if (state.isComplete && !isReplaying && !_reduceMotion) {
      _drawCelebration(canvas, exit, cell);
    }
    if (state.level.id == 1 && state.moves == 0 && _dragId == null) {
      final goal = center(state.level.startPosition);
      final shift = _reduceMotion ? 0.0 : math.sin(_hintTime * 3) * cell * .05;
      final start = goal + Offset(cell * .10 + shift, -cell * .48);
      final end = goal + Offset(cell * .63 + shift, -cell * .48);
      paint
        ..color = _colors.primaryInk
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
          ..color = _colors.error.withValues(alpha: _blockedTime / .42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .04),
      );
      paint.style = PaintingStyle.fill;
    }
  }

  void _drawCelebration(Canvas canvas, Offset exit, double cell) {
    final paint = Paint();
    final progress = _celebrationProgress;
    if (progress >= .23 && progress < .72) {
      final t = ((progress - .23) / .49).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      final fade = 1 - t;
      // 결정적인 위치, 최대 12개 입자와 원형 파동 하나만 그린다.
      final count = math.min(GameEffects.particleCount, 12);
      for (var i = 0; i < count; i++) {
        final angle = i * math.pi * 2 / count + .15;
        final distance = cell * (.20 + (i.isEven ? .60 : .48) * eased);
        final at = exit + Offset(math.cos(angle), math.sin(angle)) * distance;
        canvas.drawCircle(
          at,
          cell * (i.isEven ? .040 : .026) * (1 - t * .45),
          paint
            ..color = (i.isEven ? _colors.echo : _colors.goal).withValues(
              alpha: .85 * fade,
            ),
        );
      }
      canvas.drawCircle(
        exit,
        cell * (.35 + .48 * eased),
        paint
          ..color = _colors.echo.withValues(alpha: .38 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, cell * .025 * fade),
      );
      paint.style = PaintingStyle.fill;
    }
    if (_isNewBest && progress >= .65 && progress < 1) {
      final t = ((progress - .65) / .35).clamp(0.0, 1.0);
      final strength = math.sin(t * math.pi);
      paint
        ..color = _colors.reward.withValues(alpha: .80 * strength)
        ..strokeWidth = math.max(1.2, cell * .018)
        ..strokeCap = StrokeCap.round;
      // 최고 기록만 금색 반짝임 4개를 추가해 기본 축하와 구별한다.
      for (var i = 0; i < 4; i++) {
        final angle = i * math.pi / 2 + math.pi / 4;
        final at = exit + Offset(math.cos(angle), math.sin(angle)) * cell * .59;
        final radius = cell * .065 * strength;
        canvas.drawLine(at - Offset(radius, 0), at + Offset(radius, 0), paint);
        canvas.drawLine(at - Offset(0, radius), at + Offset(0, radius), paint);
      }
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
          // Flutter UI와 같은 서체를 명시해 Canvas 기호도 일관되게 표시한다.
          fontFamily: GameTypography.canvasFontFamily,
          fontSize: fontSize,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
    text.dispose();
  }
}
