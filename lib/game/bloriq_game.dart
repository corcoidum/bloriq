import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/board_material.dart';
import 'block_art.dart';
import 'device_art.dart';
import 'board_geometry.dart';
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
  BoardGeometry? _geometry;
  BoardGeometry get geometry =>
      _geometry ??
      BoardGeometry.canvas(
        size: Size(size.x, size.y),
        columns: controller.state.level.boardWidth,
        rows: controller.state.level.boardHeight,
      );

  void configureGeometry(BoardGeometry next) {
    if (_geometry != null && !_geometry!.sameLayout(next)) setDrag(null);
    _geometry = next;
  }

  Position? tutorialTarget;
  String? _movingId;
  Position? _from;
  Position? _oldEcho;
  double _motion = 1;
  Position? _blocked;
  double _blockedTime = 0;
  String? _dragId;
  Offset _dragOffset = Offset.zero;
  double _hintTime = 0;
  double _gateAmount = 0;
  GameColors _colors = GameColors.dark;
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
    final cell = geometry.cellSize;
    if (cell <= 0 ||
        math.max(_dragOffset.dx.abs(), _dragOffset.dy.abs()) <
            geometry.dragThreshold) {
      return null;
    }
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
    // 달문과 꽃판은 상태가 바뀌면 0.2초에 걸쳐 열리고 닫힌다.
    final gateTarget = controller.state.isGateOpen ? 1.0 : 0.0;
    final gateStep = dt / .2;
    _gateAmount = _gateAmount < gateTarget
        ? math.min(gateTarget, _gateAmount + gateStep)
        : math.max(gateTarget, _gateAmount - gateStep);
  }

  @override
  Color backgroundColor() => Colors.transparent;

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
    final layout = geometry;
    final cell = layout.cellSize;
    Offset center(Position p) => layout.center(p);
    final paint = Paint();
    final preview = currentPreview;
    final previewTarget = preview?.target;
    final previewState = preview?.nextState;

    final material = BoardMaterial(_colors);
    material.floor(canvas, layout);

    // 장치는 칸을 가득 채워 그린다. 블록이 덮으면 모서리 표식이 대신 알려 준다.
    final phase = _reduceMotion ? 0.0 : _hintTime;
    Rect deviceRect(Position p) => Rect.fromCenter(
      center: center(p),
      width: cell * .94,
      height: cell * .94,
    );
    final gateAmount = isReplaying || _reduceMotion
        ? (state.isGateOpen ? 1.0 : 0.0)
        : _gateAmount;
    final devices = deviceTiles(state.level);
    double amountOf(DeviceKind kind) =>
        kind == DeviceKind.gate || kind == DeviceKind.moonbloom
        ? gateAmount
        : 0;
    final switchPosition = state.level.echoSwitch;
    final gatePosition = state.level.echoGate;
    if (switchPosition != null && gatePosition != null) {
      // 꽃판과 달문이 이어져 있음을 작은 빛방울 줄로 보여 준다.
      final from = center(switchPosition), to = center(gatePosition);
      final steps = math.max(2, ((to - from).distance / (cell * .22)).round());
      for (var i = 1; i < steps; i++) {
        canvas.drawCircle(
          Offset.lerp(from, to, i / steps)!,
          math.max(1.2, cell * .018),
          paint
            ..style = PaintingStyle.fill
            ..color = _colors.cyan.withValues(alpha: .22 + .4 * gateAmount),
        );
      }
    }
    for (final (position, kind, direction) in devices) {
      DeviceArt.draw(
        canvas,
        kind,
        deviceRect(position),
        _colors,
        phase: phase,
        amount: amountOf(kind),
        direction: direction,
      );
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
      DeviceArt.draw(
        canvas,
        DeviceKind.wall,
        deviceRect(p),
        _colors,
        variant: p.x * 7 + p.y * 13,
      );
    }

    final exit = center(state.level.exitPosition);
    BlockArt.exit(canvas, exit, cell, _colors);

    void drawEcho(Position p, double alpha) =>
        BlockArt.echo(canvas, center(p), cell, _colors, opacity: alpha);

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
      final tilt =
          !_reduceMotion &&
              block.id == _movingId &&
              _from != null &&
              _motion < 1
          ? (block.position.x - _from!.x) * .07 * math.sin(_motion * math.pi)
          : 0.0;
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(tilt);
      BlockArt.block(
        canvas,
        Offset.zero,
        cell,
        _colors,
        goal: isGoal,
        scale: scale,
        opacity: opacity,
      );
      canvas.restore();
    }
    // 블록이 장치를 덮었을 때만 모서리에 작은 표식을 남긴다.
    for (final (position, kind, direction) in devices) {
      if (!state.blocks.any((block) => block.position == position)) continue;
      DeviceArt.badge(
        canvas,
        kind,
        center(position) + Offset(cell * .33, -cell * .33),
        cell * .135,
        _colors,
        amount: amountOf(kind),
        direction: direction,
      );
    }
    if (state.isComplete && !isReplaying && !_reduceMotion) {
      _drawCelebration(canvas, exit, cell);
    }
    if (tutorialTarget case final target?) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center(target),
            width: cell * .9,
            height: cell * .9,
          ),
          Radius.circular(cell * .16),
        ),
        Paint()
          ..color = (state.echo == target ? _colors.echoInk : _colors.goalInk)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
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
    final radius = fontSize * .36;
    final paint = Paint()
      ..color = color
      ..strokeWidth = math.max(1.3, fontSize * .12)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    if (value == '×') {
      canvas.drawLine(
        center + Offset(-radius, -radius),
        center + Offset(radius, radius),
        paint,
      );
      canvas.drawLine(
        center + Offset(radius, -radius),
        center + Offset(-radius, radius),
        paint,
      );
    } else if (value == 'Ⅱ') {
      for (final x in [-radius * .55, radius * .55]) {
        canvas.drawLine(
          center + Offset(x, -radius),
          center + Offset(x, radius),
          paint,
        );
      }
    } else if (value == '▶') {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - radius * .65, center.dy - radius)
          ..lineTo(center.dx + radius, center.dy)
          ..lineTo(center.dx - radius * .65, center.dy + radius)
          ..close(),
        paint..style = PaintingStyle.fill,
      );
    } else {
      final direction = switch (value) {
        '←' => const Offset(-1, 0),
        '↑' => const Offset(0, -1),
        '↓' => const Offset(0, 1),
        '↗' => const Offset(.707, -.707),
        _ => const Offset(1, 0),
      };
      final normal = Offset(-direction.dy, direction.dx);
      final tip = center + direction * radius;
      canvas.drawLine(center - direction * radius, tip, paint);
      canvas.drawLine(
        tip,
        tip - direction * radius * .65 + normal * radius * .6,
        paint,
      );
      canvas.drawLine(
        tip,
        tip - direction * radius * .65 - normal * radius * .6,
        paint,
      );
    }
  }
}

/// 판 위의 모든 장치. 순서는 그리는 순서와 안내 칩 순서에 함께 쓴다.
List<(Position, DeviceKind, Offset)> deviceTiles(Level level) => [
  if (level.echoSwitch case final p?)
    (p, DeviceKind.moonbloom, const Offset(1, 0)),
  if (level.echoGate case final p?) (p, DeviceKind.gate, const Offset(1, 0)),
  for (final p in level.echoErasers) (p, DeviceKind.eraser, const Offset(1, 0)),
  for (final p in level.echoHolds) (p, DeviceKind.hold, const Offset(1, 0)),
  for (final entry in level.oneWays.entries)
    (
      entry.key,
      DeviceKind.oneWay,
      Offset(entry.value.x.toDouble(), entry.value.y.toDouble()),
    ),
  for (final p in level.goalOnlyTiles)
    (p, DeviceKind.goalOnly, const Offset(1, 0)),
];
