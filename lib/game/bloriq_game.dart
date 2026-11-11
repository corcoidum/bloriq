import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/board_material.dart';
import '../design/star_art.dart';
import 'block_art.dart';
import 'board_geometry.dart';
import 'board_badge.dart';
import 'clock_arrow_art.dart';
import 'ice_art.dart';
import '../domain/mechanics/board_mechanic.dart';
import '../domain/mechanics/clock_arrow.dart';
import '../domain/mechanics/echo_eraser.dart';
import '../domain/mechanics/echo_gate.dart';
import '../domain/mechanics/echo_hold.dart';
import '../domain/mechanics/goal_only.dart';
import '../domain/mechanics/ice.dart';
import '../domain/mechanics/mirror_pair.dart';
import '../domain/mechanics/one_way.dart';
import '../domain/mechanics/shelf_door.dart';
import '../domain/puzzle.dart';
import '../world/world_theme.dart';
import 'mirror_pair_art.dart';
import 'shelf_door_art.dart';

typedef _ShelfFrame = ({MoveTeleport hop, bool arriving, double half});

typedef _MechanicCanvas = ({
  Canvas canvas,
  Paint paint,
  PuzzleState state,
  PuzzleState? preview,
  Offset Function(Position) center,
  double cell,
  double pulse,
  double clockTurn,
  _ShelfFrame? shelfFrame,
  _ShelfFrame? twinShelfFrame,
});
typedef _MechanicPainter = void Function(
  BloriqGame game,
  _MechanicCanvas board,
  BoardMechanic mechanic,
  bool badges,
);

/// 드래그 중 표시할 가상 이동. 실제 게임 상태에는 적용하지 않는다.
class DragPreview {
  const DragPreview({
    required this.from,
    required this.target,
    this.nextState,
    this.twin,
    this.teleport,
    this.twinTeleport,
    this.slides = false,
  });

  final Position from;
  final Position target;
  final PuzzleState? nextState;
  final MirrorShift? twin;
  final MoveTeleport? teleport;
  final MoveTeleport? twinTeleport;
  final bool slides;
  bool get isValid => nextState != null;
}

/// 얼음과 순간 이동에만 별도 시간을 주고 기존 보간을 재사용한다.
class _BlockTravel {
  const _BlockTravel({this.slide, this.teleport});

  factory _BlockTravel.primary(MoveRecord move) => _BlockTravel(
    slide: IceSlide.forMove(move),
    teleport: move.teleportOf(move.blockId),
  );

  factory _BlockTravel.twin(MoveRecord move, MirrorShift? shift) {
    final hop = shift == null ? null : move.teleportOf(shift.blockId);
    return _BlockTravel(
      slide: IceSlide.forTwin(shift, landing: hop?.from),
      teleport: hop,
    );
  }

  static final _normalSeconds = GameEffects.moveDuration.inMilliseconds / 1000;
  final IceSlide? slide;
  final MoveTeleport? teleport;

  double get approachSeconds => slide?.travelSeconds ?? _normalSeconds;
  double get seconds => teleport == null
      ? slide?.seconds ?? _normalSeconds
      : approachSeconds + ShelfDoorArt.transitSeconds;
  bool get hasEffect => slide != null || teleport != null;

  _ShelfFrame? shelfFrame(double fraction) {
    final hop = teleport;
    if (hop == null || fraction >= 1) return null;
    final phase =
        (fraction * seconds - approachSeconds) / ShelfDoorArt.transitSeconds;
    if (phase < 0) return null;
    final arriving = phase >= .5;
    return (
      hop: hop,
      arriving: arriving,
      half: (phase * 2 - (arriving ? 1 : 0)).clamp(0.0, 1.0),
    );
  }

  Offset approach(
    Canvas canvas,
    Offset from,
    Offset to,
    double cell,
    double fraction,
  ) {
    final ice = slide;
    if (teleport == null) {
      return ice?.draw(canvas, from, to, cell, fraction) ??
          Offset.lerp(from, to, Curves.easeOutCubic.transform(fraction))!;
    }
    final elapsed = math.min(fraction * seconds, approachSeconds);
    return ice?.draw(canvas, from, to, cell, elapsed / ice.seconds) ??
        Offset.lerp(
          from,
          to,
          Curves.easeOutCubic.transform(elapsed / approachSeconds),
        )!;
  }
}

/// The domain owns the rules; this renderer only animates their results.
class BloriqGame extends FlameGame {
  BloriqGame(this.controller)
    : _clockPhase =
          controller.state.level.mechanics.containsKey(ClockArrow.typeId)
          ? ValueNotifier(ClockArrow.phaseAt(controller.state.moves))
          : null;
  final PuzzleController controller;
  final ValueNotifier<int>? _clockPhase;
  ValueListenable<int>? get clockPhase => _clockPhase;
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
  _BlockTravel _travel = const _BlockTravel();
  static const _twinDelay = .1;
  static const _clockTurnSeconds = .2;
  double _clockTurn = 1;
  MirrorShift? _twin;
  _BlockTravel _twinTravel = const _BlockTravel();
  double _twinTime = 0;
  Position? _blocked;
  double _blockedTime = 0;

  /// 착지 충격(먼지·파동·보드 흔들림)과 막힌 이동 흔들림. 표시 전용이다.
  static const _impactDuration = .42;
  static const _shakeDuration = .36;
  double _impactTime = 0;
  Position? _impactAt;
  Offset _impactDirection = Offset.zero;
  bool _impactGoal = false;
  String? _shakeId;
  Offset _shakeDirection = Offset.zero;
  double _shakeTime = 0;

  /// 별빛 길이 비추는 다음 한 수. 블록을 움직이면 사라진다.
  ({Position from, Position to})? hintMove;

  /// 장착한 이동 잔영 id(`TrailIds`). `gold_`로 시작하면 금빛 반짝임이 더해진다.
  String trailStyle = 'moonlight';

  /// 테마와 상관없이 색이 정해진 잔영. 보상 화면의 색 견본도 이 표를 쓴다.
  static const trailPalette = <String, Color>{
    'petal': Color(0xfff4a9c4),
    'firefly': Color(0xffffd86b),
    'aurora': Color(0xff7ef0d0),
    'starfall': Color(0xfffff0b3),
    'first_starlight': Color(0xffe8eeff),
    'tide': Color(0xff6fd3ff),
    'rose': Color(0xffff8fa3),
    'ember': Color(0xffff9a5c),
    'lilac': Color(0xffc9a7ff),
    'jade': Color(0xff6fe0a4),
    'silver': Color(0xffdde6f5),
    'gold_forest': Color(0xffffcf4a),
    'gold_cloud': Color(0xffffe08a),
    'gold_mirror': Color(0xfff0b84a),
  };

  static const firstStarlightColors = [
    Color(0xffb7f2fa),
    Color(0xff71e6d6),
    Color(0xffffd083),
    Color(0xff92deff),
    Color(0xfff4a9cb),
  ];

  Color _trailColor(bool isGoal) => switch (trailStyle) {
    'meteor' => _colors.reward,
    'mist' => _colors.echo,
    final id when trailPalette.containsKey(id) => trailPalette[id]!,
    _ => isGoal ? _colors.goal : _colors.primary,
  };

  /// 덩굴 문이 열린 정도(0~1). 도메인의 문 상태를 따라 부드럽게 움직인다.
  double _gateOpen = 0;
  bool _gateTarget = false;
  String? _dragId;
  Offset _dragOffset = Offset.zero;
  PuzzlePower? _dragPower;
  double _hintTime = 0;
  GameColors _colors = GameColors.light;
  WorldBoardSkin? _skin;
  bool _reduceMotion = false;
  double _celebrationProgress = 1;
  bool _isNewBest = false;
  List<MoveRecord>? _replay;
  double _replayDuration = 2.5;
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
    WorldBoardSkin? skin,
  }) {
    _colors = colors;
    _skin = skin;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _motion = 1;
      _clockTurn = 1;
      _twin = null;
      _impactTime = 0;
    }
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
    final power = _dragPower;
    final hops = state.level.mechanics.containsKey(ShelfDoor.typeId)
        ? <MoveTeleport>[]
        : null;
    final next = power == null
        ? previewMove(state, block.id, target, teleports: hops)
        : previewPower(
            state,
            power,
            block.id,
            Position(dx, dy),
            teleports: hops,
          );
    final end = next?.positionOf(block.id);
    final hop = hops?.where((hop) => hop.blockId == block.id).firstOrNull;
    final ground = hop?.from ?? end;
    final slides =
        ground != null &&
        state.level.mechanics.containsKey(Ice.typeId) &&
        switch (power) {
          PuzzlePower.wind || PuzzlePower.lightSwap => false,
          PuzzlePower.moonflowerLeap =>
            IceSlide.distance(block.position, ground) > 2,
          _ => ground != target,
        };
    return DragPreview(
      from: block.position,
      target: end ?? target,
      nextState: next,
      slides: slides,
      teleport: hop,
      twinTeleport: hops?.where((hop) => hop.blockId != block.id).firstOrNull,
      twin: power == null && next != null
          ? state.level
                .mechanic<MirrorPair>(MirrorPair.typeId)
                ?.shiftBetween(state, next, block.id)
          : null,
    );
  }

  static double _twinLag(_BlockTravel primary) =>
      primary.teleport == null ? _twinDelay : primary.seconds;

  /// 완료한 실제 상태를 그대로 두고 기록된 스냅샷만 렌더링한다.
  bool startReplay({required VoidCallback onFinished}) {
    if (isReplaying || !controller.state.isComplete) return false;
    final moves = controller.moveHistory;
    if (moves.isEmpty) return false;
    clearEffects();
    _replay = moves;
    _replayTime = 0;
    // 빠른 리플레이에서도 시곗바늘 한 바퀴의 1/4이 잘리지 않게 한다.
    _replayDuration = _clockPhase == null
        ? 2.5
        : math.max(2.5, moves.length * _clockTurnSeconds);
    final mechanics = controller.state.level.mechanics;
    if (!_reduceMotion &&
        (mechanics.containsKey(Ice.typeId) ||
            mechanics.containsKey(ShelfDoor.typeId))) {
      for (final move in moves) {
        final primary = _BlockTravel.primary(move);
        final shift = MirrorPair.recordedShift(
          move,
          includeTeleportReturn: true,
        );
        final twin = _BlockTravel.twin(move, shift);
        final seconds = math.max(
          primary.hasEffect ? primary.seconds : 0.0,
          shift != null && (twin.hasEffect || primary.teleport != null)
              ? _twinLag(primary) + twin.seconds
              : 0.0,
        );
        _replayDuration = math.max(_replayDuration, seconds * moves.length);
      }
    }
    _onReplayFinished = onFinished;
    _syncReplayClock();
    return true;
  }

  void skipReplay() {
    if (!isReplaying) return;
    _replay = null;
    _motion = 1;
    _movingId = null;
    _from = null;
    _oldEcho = null;
    _syncClockPhase();
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

  void setDrag(String? id, [Offset offset = Offset.zero, PuzzlePower? power]) {
    if (isReplaying) return;
    _dragId = id;
    _dragOffset = offset;
    _dragPower = power;
  }

  void animateMove(MoveRecord move) {
    _dragId = null;
    hintMove = null;
    _movingId = move.blockId;
    _from = move.from;
    _oldEcho = move.previousEcho;
    _motion = _reduceMotion ? 1 : 0;
    _travel = _BlockTravel.primary(move);
    if (_clockPhase != null) {
      _clockTurn = _reduceMotion ? 1 : 0;
      _syncClockPhase();
    }
    _twin = _reduceMotion
        ? null
        : MirrorPair.recordedShift(move, includeTeleportReturn: true);
    _twinTravel = _BlockTravel.twin(move, _twin);
    _twinTime = 0;
    if (_travel.hasEffect || _twinTravel.hasEffect) _impactTime = 0;
  }

  void flashBlocked(Position position, {String? blockId}) {
    _dragId = null;
    _blocked = position;
    _blockedTime = .42;
    final block = controller.state.blocks
        .where((block) => block.id == blockId)
        .firstOrNull;
    if (block == null || _reduceMotion) return;
    _shakeId = block.id;
    _shakeDirection = Offset(
      (position.x - block.position.x).sign.toDouble(),
      (position.y - block.position.y).sign.toDouble(),
    );
    _shakeTime = _shakeDuration;
  }

  void _land() {
    final id = _movingId;
    final from = _from;
    if (id == null || from == null || _reduceMotion || _travel.hasEffect) {
      return;
    }
    final block = controller.state.blocks
        .where((block) => block.id == id)
        .firstOrNull;
    if (block == null) return;
    _impactAt = block.position;
    _impactDirection = Offset(
      (block.position.x - from.x).toDouble(),
      (block.position.y - from.y).toDouble(),
    );
    _impactGoal = id == Level.goalBlockId;
    _impactTime = _impactDuration;
  }

  void clearEffects() {
    _movingId = null;
    _dragId = null;
    _motion = 1;
    _travel = const _BlockTravel();
    _clockTurn = 1;
    _syncClockPhase();
    _twin = null;
    _twinTravel = const _BlockTravel();
    _blockedTime = 0;
    _impactTime = 0;
    _shakeTime = 0;
    _celebrationProgress = 1;
    _isNewBest = false;
  }

  void _syncClockPhase([int? moves]) {
    _clockPhase?.value = ClockArrow.phaseAt(moves ?? controller.state.moves);
  }

  ({MoveRecord move, double fraction})? get _replayFrame {
    final replay = _replay;
    if (replay == null) return null;
    final progress = _replayTime / _replayDuration * replay.length;
    final index = math.min(progress.floor(), replay.length - 1);
    return (move: replay[index], fraction: (progress - index).clamp(0.0, 1.0));
  }

  double _replayClockTurn(double fraction) => _reduceMotion
      ? 1
      : math.min(
          1.0,
          fraction * _replayDuration / _replay!.length / _clockTurnSeconds,
        );

  void _syncReplayClock() {
    if (_clockPhase == null) return;
    final (:move, :fraction) = _replayFrame!;
    _syncClockPhase(
      _replayClockTurn(fraction) < 1 ? move.before.moves : move.after.moves,
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (isReplaying) {
      _replayTime += dt;
      if (_replayTime >= _replayDuration) {
        skipReplay();
      } else {
        _syncReplayClock();
      }
    } else {
      final wasMoving = _motion < 1;
      final seconds = _travel.seconds;
      _motion = _reduceMotion ? 1 : math.min(1.0, _motion + dt / seconds);
      if (_clockTurn < 1) {
        _clockTurn = math.min(1.0, _clockTurn + dt / _clockTurnSeconds);
      }
      if (_twin != null &&
          _twinTime < _twinLag(_travel) + _twinTravel.seconds) {
        _twinTime += dt;
      }
      if (wasMoving && _motion >= 1) _land();
    }
    _blockedTime = math.max(0.0, _blockedTime - dt);
    _impactTime = math.max(0.0, _impactTime - dt);
    _shakeTime = math.max(0.0, _shakeTime - dt);
    final gateGoal = _gateTarget ? 1.0 : 0.0;
    _gateOpen = _reduceMotion
        ? gateGoal
        : _gateOpen + (gateGoal - _gateOpen).clamp(-dt / .35, dt / .35);
    if (!_reduceMotion) _hintTime += dt;
  }

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    var travel = _travel;
    var twin = _twin;
    var twinTravel = _twinTravel;
    var twinMotion = ((_twinTime - _twinLag(travel)) / twinTravel.seconds)
        .clamp(0.0, 1.0);
    var clockTurn = _clockTurn;
    PuzzleState state;
    if (_replayFrame case (:final move, :final fraction)) {
      state = move.after;
      _movingId = move.blockId;
      _from = move.from;
      _oldEcho = move.previousEcho;
      travel = _BlockTravel.primary(move);
      final secondsPerMove = _replayDuration / _replay!.length;
      final elapsed = fraction * secondsPerMove;
      _motion = _reduceMotion
          ? 1
          : travel.hasEffect
          ? math.min(1.0, elapsed / travel.seconds)
          : fraction;
      if (_clockPhase != null) clockTurn = _replayClockTurn(fraction);
      twin = MirrorPair.recordedShift(move, includeTeleportReturn: true);
      twinTravel = _BlockTravel.twin(move, twin);
      // 짧은 재생 구간에서도 짝의 이동이 다음 수에 잘리지 않게 지연을 줄인다.
      final lag = math.min(.45, _twinDelay / secondsPerMove);
      twinMotion = _reduceMotion
          ? 1
          : twinTravel.hasEffect || travel.teleport != null
          ? ((elapsed - _twinLag(travel)) / twinTravel.seconds).clamp(0.0, 1.0)
          : ((fraction - lag) / (1 - lag)).clamp(0.0, 1.0);
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
    final shelfFrame = travel.shelfFrame(_motion);
    final twinShelfFrame = twin == null
        ? null
        : twinTravel.shelfFrame(twinMotion);
    final shelf = state.level.mechanic<ShelfDoor>(ShelfDoor.typeId);
    final mirror = state.level.mechanic<MirrorPair>(MirrorPair.typeId);

    // 착지 순간 보드 전체가 이동 방향으로 살짝 밀렸다가 돌아온다.
    canvas.save();
    if (_impactTime > 0) {
      final p = 1 - _impactTime / _impactDuration;
      if (p < .4) {
        canvas.translate(
          _impactDirection.dx * cell * .03 * math.sin(p / .4 * math.pi),
          _impactDirection.dy * cell * .03 * math.sin(p / .4 * math.pi),
        );
      }
    }

    final material = BoardMaterial(_colors, skin: _skin);
    final palette = _skin?.palette;
    material.floor(canvas, layout);

    final mechanicCanvas = (
      canvas: canvas,
      paint: paint,
      state: state,
      preview: previewState,
      center: center,
      cell: cell,
      pulse: _reduceMotion ? 0.0 : .5 + .5 * math.sin(_hintTime * 2.2),
      clockTurn: clockTurn,
      shelfFrame: shelfFrame,
      twinShelfFrame: twinShelfFrame,
    );
    _gateTarget = state.isGateOpen;
    _drawMechanics(mechanicCanvas, badges: false);
    for (final p in state.level.obstacles) {
      if (BlockArt.obstacle(
        canvas,
        center(p),
        cell,
        p.x * 7 + p.y * 3,
        customRock: _skin?.rock,
        useGarden: palette == null,
      )) {
        continue;
      }
      material.raised(
        canvas,
        Rect.fromCenter(
          center: center(p),
          width: cell * .8,
          height: cell * .76,
        ),
        cell,
        palette == null
            ? _colors.slate
            : Color.lerp(palette.background, palette.board, .28)!,
      );
    }

    final exit = center(state.level.exitPosition);
    if (!_reduceMotion && StarArt.garden.isNotEmpty) {
      _drawExitRays(canvas, exit, cell);
    }
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
    if (preview case DragPreview(:final from, :final target, slides: true)) {
      IceArt.trajectory(
        canvas,
        center(from),
        center(preview.teleport?.from ?? target),
        cell,
      );
    }
    if (preview?.twin case final shift?) {
      final ground = preview!.twinTeleport?.from ?? shift.to;
      if (IceSlide.distance(shift.from, ground) > 1) {
        IceArt.trajectory(canvas, center(shift.from), center(ground), cell);
      }
    }
    if (previewTarget != null && state.level.contains(previewTarget)) {
      final shelfStop =
          previewState != null &&
          (shelf?.cells.contains(previewTarget) ?? false);
      final at = center(previewTarget);
      if (shelfStop) {
        BlockArt.block(
          canvas,
          at,
          cell,
          _colors,
          goal: _dragId == Level.goalBlockId,
          opacity: .40,
        );
      }
      final rect = Rect.fromCenter(
        center: at,
        width: cell * .91,
        height: cell * .91,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .18)),
        paint
          ..color = shelfStop
              ? _colors.goal.withValues(alpha: .66)
              : previewState != null
              ? _colors.goal
              : _colors.error
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .045),
      );
      paint.style = PaintingStyle.fill;
    }

    for (final block in state.blocks) {
      final isGoal = block.id == Level.goalBlockId;
      var at = center(block.position);
      final following = twin != null && twin.blockId == block.id;
      if (following && twinMotion < 1) {
        final start = center(twin.from);
        final ground = center(twinTravel.teleport?.from ?? block.position);
        at = twinShelfFrame == null
            ? twinTravel.approach(canvas, start, ground, cell, twinMotion)
            : ground;
        if (twinMotion > 0 && twinShelfFrame == null) {
          MirrorPairArt.ripple(canvas, at, cell, twin.pair, twinMotion);
        }
      }
      final moving = block.id == _movingId && _from != null && _motion < 1;
      var along = 1.0, across = 1.0;
      var axis = Offset.zero;
      if (moving) {
        final eased = Curves.easeOutCubic.transform(_motion);
        final start = center(_from!);
        final end = center(travel.teleport?.from ?? block.position);
        at = shelfFrame == null
            ? travel.approach(canvas, start, end, cell, _motion)
            : end;
        axis = Offset(
          (block.position.x - _from!.x).toDouble(),
          (block.position.y - _from!.y).toDouble(),
        );
        if (!_reduceMotion && !travel.hasEffect) {
          _drawTrail(canvas, start, end, at, eased, cell, isGoal);
          // 빠르게 미끄러지는 동안 진행 방향으로 늘어난다.
          final stretch = .14 * math.sin(_motion * math.pi);
          along = 1 + stretch;
          across = 1 - stretch * .5;
        }
      } else if (_impactTime > 0 && block.position == _impactAt) {
        // 착지하면 진행 방향으로 눌렸다가 탄성 있게 돌아온다.
        final p = 1 - _impactTime / _impactDuration;
        final squash = p < .55
            ? math.sin(p / .55 * math.pi)
            : -.35 * math.sin((p - .55) / .45 * math.pi);
        axis = _impactDirection;
        along = 1 - .13 * squash;
        across = 1 + .09 * squash;
      }
      var shelfScale = 1.0;
      final frame = moving ? shelfFrame : (following ? twinShelfFrame : null);
      if (frame case (:final hop, :final arriving, :final half)) {
        at = center(arriving ? hop.to : hop.from);
        shelfScale = arriving
            ? Curves.easeOutCubic.transform(half)
            : 1 - Curves.easeInCubic.transform(half);
        if (shelfScale == 0) continue;
      }
      if (block.id == _shakeId && _shakeTime > 0) {
        // 막힌 방향으로 부딪힌 뒤 튕겨 나오며 잦아든다.
        final p = 1 - _shakeTime / _shakeDuration;
        at +=
            _shakeDirection * cell * .09 * math.sin(p * math.pi * 4) * (1 - p);
      }
      if (block.id == _dragId) {
        final maxDrag = cell * .8;
        at += Offset(
          _dragOffset.dx.clamp(-maxDrag, maxDrag).toDouble(),
          _dragOffset.dy.clamp(-maxDrag, maxDrag).toDouble(),
        );
      }
      final escaping =
          state.isComplete &&
          isGoal &&
          (!following || twinMotion >= 1) &&
          (!travel.hasEffect || !moving);
      final celebrating = escaping && !isReplaying && !_reduceMotion;
      if (escaping &&
          ((!celebrating && _motion >= 1) ||
              (celebrating && _celebrationProgress >= .34))) {
        continue;
      }
      final escapeTime = ((_celebrationProgress - .12) / .22).clamp(0.0, 1.0);
      final scale =
          shelfScale *
          (celebrating ? 1 + .14 * math.sin(escapeTime * math.pi) : 1.0);
      final opacity =
          shelfScale *
          (celebrating
              ? 1 - ((_celebrationProgress - .24) / .10).clamp(0.0, 1.0)
              : 1.0);
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
              !travel.hasEffect &&
              block.id == _movingId &&
              _from != null &&
              _motion < 1
          ? (block.position.x - _from!.x) * .07 * math.sin(_motion * math.pi)
          : 0.0;
      if (mirror?.partnerOf(block.id) case final link?) {
        MirrorPairArt.marker(
          canvas,
          at,
          cell * shelfScale,
          link.pair,
          opacity: opacity,
        );
      }
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(tilt);
      if (along != 1 || across != 1) {
        final horizontal = axis.dx != 0;
        canvas.scale(horizontal ? along : across, horizontal ? across : along);
      }
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
    if (preview?.twin case final shift?) {
      final hop = preview!.twinTeleport;
      final ground = hop?.from ?? shift.to;
      if (hop != null) {
        BlockArt.block(
          canvas,
          center(hop.to),
          cell,
          _colors,
          goal: shift.blockId == Level.goalBlockId,
          opacity: .33,
        );
      }
      if (shift.from == ground) {
        MirrorPairArt.blocked(canvas, center(shift.from), cell, shift.pair);
      } else {
        MirrorPairArt.arrow(
          canvas,
          center(ground),
          center(ground) - center(shift.from),
          cell * .53,
          shift.pair,
          opacity: .68,
        );
      }
    }
    if (!_reduceMotion) _drawImpact(canvas, layout);
    _drawMechanics(mechanicCanvas, badges: true);
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
    if (hintMove case final hint? when !isReplaying && !state.isComplete) {
      _drawHint(canvas, center(hint.from), center(hint.to), cell);
    }
    if (!_reduceMotion && StarArt.garden.isNotEmpty) {
      _drawFireflies(canvas, layout);
    }
    canvas.restore();
  }

  /// 별빛 길 화살표: 블록에서 다음 칸까지 금빛 길과 도착 고리.
  static final _mechanicPainters = <String, _MechanicPainter>{
    EchoEraser.typeId: (game, board, mechanic, badges) =>
        game._drawTileMechanic(board, mechanic, badges, 'tile_dandelion'),
    EchoHold.typeId: (game, board, mechanic, badges) =>
        game._drawTileMechanic(board, mechanic, badges, 'tile_amber'),
    OneWay.typeId: (game, board, mechanic, badges) => game._drawTileMechanic(
      board,
      mechanic,
      badges,
      'tile_stream',
      arrows: (mechanic as OneWay).arrows,
    ),
    GoalOnly.typeId: (game, board, mechanic, badges) =>
        game._drawTileMechanic(board, mechanic, badges, 'tile_clover'),
    EchoGate.typeId: (game, board, mechanic, badges) =>
        game._drawGateMechanic(board, mechanic as EchoGate, badges),
    Ice.typeId: (_, board, mechanic, badges) =>
        _drawIceMechanic(board, mechanic as Ice, badges),
    ShelfDoor.typeId: (_, board, mechanic, badges) =>
        _drawShelfMechanic(board, mechanic as ShelfDoor, badges),
    ClockArrow.typeId: (game, board, mechanic, badges) =>
        game._drawClockMechanic(board, mechanic as ClockArrow, badges),
  };

  /// 먼저 판석을 그리고, 블록 위에 남는 작은 배지는 나중에 그린다.
  void _drawMechanics(_MechanicCanvas board, {required bool badges}) {
    for (final mechanic in board.state.level.mechanics.values) {
      _mechanicPainters[mechanic.type]?.call(this, board, mechanic, badges);
    }
  }

  static void _drawIceMechanic(_MechanicCanvas board, Ice ice, bool badges) {
    for (final position in ice.positions) {
      final center = board.center(position);
      if (!badges) {
        IceArt.tile(board.canvas, center, board.cell * .94);
      } else if (board.state.blocks.any(
        (block) => block.position == position,
      )) {
        final at = center + Offset(board.cell * .32, -board.cell * .32);
        IceArt.tile(board.canvas, at, board.cell * .30);
      }
    }
  }

  static void _drawShelfMechanic(
    _MechanicCanvas board,
    ShelfDoor shelf,
    bool badges,
  ) {
    double openness(Position at) {
      for (final frame in [board.shelfFrame, board.twinShelfFrame]) {
        if (frame case (:final hop, :final arriving, :final half)
            when at == (arriving ? hop.to : hop.from)) {
          return ShelfDoorArt.opening(half);
        }
      }
      return 0;
    }

    for (final (pair, (a, b)) in shelf.pairs.indexed) {
      if (!badges) {
        ShelfDoorArt.link(
          board.canvas,
          board.center(a),
          board.center(b),
          board.cell,
          pair,
        );
      }
      for (final at in [a, b]) {
        final center = board.center(at);
        if (!badges) {
          ShelfDoorArt.tile(
            board.canvas,
            center,
            board.cell * .94,
            pair,
            openness: openness(at),
          );
        } else if (board.state.level.obstacles.contains(at) ||
            board.state.echo == at ||
            board.state.blocks.any((block) => block.position == at)) {
          final badge = center + Offset(-board.cell * .31, -board.cell * .30);
          ShelfDoorArt.marker(board.canvas, badge, board.cell * .25, pair);
        }
      }
    }
  }

  void _drawClockMechanic(
    _MechanicCanvas board,
    ClockArrow mechanic,
    bool badges,
  ) {
    const quarter = math.pi / 2;
    final phase = ClockArrow.phaseAt(board.state.moves);
    // 3 → 0도 앞으로 90°만 돌도록 현재 시각에서 이전 각도를 구한다.
    final turn = (phase - 1 + board.clockTurn) * quarter;
    final nextTurn = board.preview == null
        ? null
        : ClockArrow.phaseAt(board.preview!.moves) * quarter;
    for (final MapEntry(key: position, value: arrow)
        in mechanic.arrows.entries) {
      final occupied = board.state.blocks.any(
        (block) => block.position == position,
      );
      if (badges != occupied) continue;
      final center = board.center(position);
      final base = math.atan2(arrow.y, arrow.x);
      ClockArrowArt.draw(
        board.canvas,
        occupied
            ? center + Offset(board.cell * .32, -board.cell * .32)
            : center,
        board.cell * (occupied ? .32 : .61),
        angle: base + turn,
        previewAngle: nextTurn == null ? null : base + nextTurn,
      );
    }
  }

  void _drawTileMechanic(
    _MechanicCanvas board,
    BoardMechanic mechanic,
    bool badges,
    String art, {
    Map<Position, Position>? arrows,
  }) {
    final canvas = board.canvas;
    final cell = board.cell;
    for (final position in mechanic.cells) {
      final arrow = arrows?[position];
      final direction = arrow == null
          ? Offset.zero
          : Offset(arrow.x.toDouble(), arrow.y.toDouble());
      final at = board.center(position);
      if (badges) {
        BoardBadge.draw(
          canvas,
          at + Offset(cell * .34, -cell * .34),
          cell * .27,
          mechanic.type,
          direction: direction,
        );
      } else if (BlockArt.mechanic(
        canvas,
        art,
        at,
        cell,
        direction: direction,
        pulse: board.pulse,
      )) {
        if (arrows != null && !_reduceMotion) {
          _drawCurrent(canvas, at, direction, cell);
        }
      } else {
        BoardBadge.draw(
          canvas,
          at,
          cell * .38,
          mechanic.type,
          direction: direction,
        );
      }
    }
  }

  void _drawGateMechanic(
    _MechanicCanvas board,
    EchoGate mechanic,
    bool badges,
  ) {
    final (
      :canvas,
      :paint,
      :state,
      :preview,
      :center,
      :cell,
      pulse: _,
      clockTurn: _,
      shelfFrame: _,
      twinShelfFrame: _,
    ) = board;
    final switchPosition = mechanic.switchPosition;
    final gatePosition = mechanic.gatePosition;
    final previewGateOpen = preview?.isGateOpen;
    final showGatePreview =
        previewGateOpen != null && previewGateOpen != state.isGateOpen;
    if (badges) {
      BoardBadge.draw(
        canvas,
        center(switchPosition) + Offset(-cell * .34, -cell * .34),
        cell * .27,
        mechanic.type,
      );
      if (showGatePreview) {
        BoardBadge.draw(
          canvas,
          center(gatePosition) + Offset(cell * .34, -cell * .34),
          cell * .27,
          mechanic.type,
          gate: previewGateOpen ? GateBadge.open : GateBadge.closed,
        );
      }
      return;
    }

    _drawVineLink(canvas, center(switchPosition), center(gatePosition), cell);
    if (!BlockArt.switchPlate(
      canvas,
      center(switchPosition),
      cell,
      _colors,
      glow: _gateOpen,
    )) {
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
      BoardBadge.draw(canvas, switchCenter, cell * .38, mechanic.type);
    }

    if (!BlockArt.gate(
      canvas,
      center(gatePosition),
      cell,
      _colors,
      open: _gateOpen,
    )) {
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
    if (showGatePreview) {
      final rect = Rect.fromCenter(
        center: center(gatePosition),
        width: cell * .98,
        height: cell * .98,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cell * .18)),
        paint
          ..color = previewGateOpen ? _colors.cyan : _colors.error
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(3.0, cell * .045),
      );
      paint.style = PaintingStyle.fill;
    }
  }

  void _drawHint(Canvas canvas, Offset from, Offset to, double cell) {
    final pulse = _reduceMotion ? 1.0 : .6 + .4 * math.sin(_hintTime * 4);
    final direction = (to - from) / (to - from).distance;
    final normal = Offset(-direction.dy, direction.dx);
    final start = from + direction * cell * .3;
    final tip = to - direction * cell * .12;
    final paint = Paint()
      ..color = _colors.reward.withValues(alpha: .9 * pulse)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(3.0, cell * .07)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(start, tip, paint);
    canvas.drawPath(
      Path()
        ..moveTo(
          tip.dx + direction.dx * cell * .08,
          tip.dy + direction.dy * cell * .08,
        )
        ..lineTo(
          tip.dx - direction.dx * cell * .12 + normal.dx * cell * .12,
          tip.dy - direction.dy * cell * .12 + normal.dy * cell * .12,
        )
        ..lineTo(
          tip.dx - direction.dx * cell * .12 - normal.dx * cell * .12,
          tip.dy - direction.dy * cell * .12 - normal.dy * cell * .12,
        )
        ..close(),
      Paint()..color = _colors.reward.withValues(alpha: .95 * pulse),
    );
    canvas.drawCircle(
      to,
      cell * (.36 + .06 * pulse),
      Paint()
        ..color = _colors.reward.withValues(alpha: .55 * pulse)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, cell * .035),
    );
  }

  /// 스위치와 문을 잇는 희미한 덩굴 빛줄기. 열리면 빛이 문 쪽으로 흐른다.
  void _drawVineLink(Canvas canvas, Offset from, Offset to, double cell) {
    final bend = Offset(-(to - from).dy, (to - from).dx) * .18;
    final control = Offset.lerp(from, to, .5)! + bend;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);
    canvas.drawPath(
      path,
      Paint()
        ..color = BoardMaterial.moss.withValues(alpha: .35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, cell * .05)
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = _colors.cyan.withValues(alpha: .18 + .42 * _gateOpen)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, cell * .018)
        ..strokeCap = StrokeCap.round,
    );
    if (_gateOpen > 0 && !_reduceMotion) {
      final metric = path.computeMetrics().first;
      for (var i = 0; i < 3; i++) {
        final t = (_hintTime * .6 + i / 3) % 1;
        final spot = metric.getTangentForOffset(metric.length * t)!.position;
        canvas.drawCircle(
          spot,
          cell * .045,
          Paint()
            ..color = _colors.cyan.withValues(
              alpha: .8 * _gateOpen * math.sin(t * math.pi),
            ),
        );
      }
    }
  }

  /// 물길 칸 위로 흐름 방향을 따라 흘러가는 물결 점.
  void _drawCurrent(Canvas canvas, Offset at, Offset direction, double cell) {
    final normal = Offset(-direction.dy, direction.dx);
    for (var i = 0; i < 3; i++) {
      final t = (_hintTime * .7 + i / 3) % 1;
      final spot =
          at + direction * cell * (t - .5) * .8 + normal * cell * (i - 1) * .1;
      canvas.drawLine(
        spot - direction * cell * .05,
        spot + direction * cell * .05,
        Paint()
          ..color = _colors.highlight.withValues(
            alpha: .55 * math.sin(t * math.pi),
          )
          ..strokeWidth = math.max(1.2, cell * .018)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// 별문 뒤에서 천천히 도는 빛살.
  void _drawExitRays(Canvas canvas, Offset exit, double cell) {
    final paint = Paint()
      ..strokeWidth = math.max(1.2, cell * .022)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 12; i++) {
      final angle = _hintTime * .35 + i * math.pi / 6;
      final direction = Offset(math.cos(angle), math.sin(angle));
      final flicker = .5 + .5 * math.sin(_hintTime * 2 + i * 1.3);
      canvas.drawLine(
        exit + direction * cell * .4,
        exit + direction * cell * (.45 + .04 * flicker),
        paint..color = _colors.reward.withValues(alpha: .28 * flicker),
      );
    }
  }

  /// 판 위를 천천히 떠다니는 반딧불. 위치는 시간만으로 정해진다.
  void _drawFireflies(Canvas canvas, BoardGeometry layout) {
    final rect = layout.boardRect;
    for (var i = 0; i < 5; i++) {
      final t = _hintTime * (.11 + i * .023) + i * 1.7;
      final at = Offset(
        rect.left + rect.width * (.5 + .44 * math.sin(t + i)),
        rect.top + rect.height * (.5 + .42 * math.cos(t * 1.3 + i * 2)),
      );
      final twinkle = .5 + .5 * math.sin(_hintTime * 3 + i * 1.9);
      final radius = layout.cellSize * .12;
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              const Color(0xfffff1b0).withValues(alpha: .55 * twinkle),
              const Color(0xffffd36b).withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: radius)),
      );
      canvas.drawCircle(
        at,
        math.max(1.0, layout.cellSize * .016),
        Paint()
          ..color = const Color(0xfffff6d6).withValues(alpha: .9 * twinkle),
      );
    }
  }

  /// 출발 칸의 파동, 빛 꼬리, 잔영 블록으로 속도감을 준다.
  void _drawTrail(
    Canvas canvas,
    Offset start,
    Offset end,
    Offset at,
    double eased,
    double cell,
    bool isGoal,
  ) {
    final fade = 1 - _motion;
    final color = _trailColor(isGoal);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, cell * .04 * fade)
      ..color = color.withValues(alpha: .5 * fade);
    canvas.drawCircle(start, cell * (.3 + .22 * _motion), paint);
    if ((at - start).distance > 1) {
      canvas.drawLine(
        start,
        at,
        Paint()
          ..shader = ui.Gradient.linear(
            start,
            at,
            trailStyle == 'first_starlight'
                ? [
                    for (final light in firstStarlightColors)
                      light.withValues(alpha: .38 * fade),
                  ]
                : [
                    color.withValues(alpha: 0),
                    color.withValues(alpha: .38 * fade),
                  ],
          )
          ..strokeWidth = cell * .46
          ..strokeCap = StrokeCap.round,
      );
    }
    if (trailStyle.startsWith('gold_') && !_reduceMotion) {
      // 황금 잔영: 지나간 길에 작은 금빛 별이 흩어진다.
      final sparkle = Paint()..color = color.withValues(alpha: .85 * fade);
      for (var i = 1; i <= 5; i++) {
        final along = Offset.lerp(start, at, i / 6)!;
        final side = (i.isEven ? 1 : -1) * cell * .18 * math.sin(i * 1.7);
        final dir = at - start;
        final normal = dir.distance < 1
            ? Offset.zero
            : Offset(-dir.dy, dir.dx) / dir.distance;
        canvas.drawCircle(
          along + normal * side,
          cell * (.035 + .015 * (i % 2)) * fade,
          sparkle,
        );
      }
    }
    for (var k = 3; k >= 1; k--) {
      final t = eased - k * .17;
      if (t <= 0) continue;
      BlockArt.block(
        canvas,
        Offset.lerp(start, end, t)!,
        cell,
        _colors,
        goal: isGoal,
        scale: 1 - k * .05,
        opacity: (.34 - k * .08) * fade,
      );
    }
  }

  /// 착지 칸에서 충격 파동과 먼지·별가루가 퍼진다.
  void _drawImpact(Canvas canvas, BoardGeometry layout) {
    final at = _impactAt;
    if (at == null || _impactTime <= 0) return;
    final cell = layout.cellSize;
    final p = 1 - _impactTime / _impactDuration;
    final eased = Curves.easeOutCubic.transform(p);
    final fade = 1 - p;
    final c = layout.center(at);
    final color = trailStyle != 'moonlight'
        ? _trailColor(_impactGoal)
        : _impactGoal
        ? _colors.goal
        : StarArt.garden.isEmpty
        ? _colors.primary
        : BoardMaterial.moss;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, cell * .05 * fade)
      ..color = color.withValues(alpha: .6 * fade);
    canvas.drawCircle(c, cell * (.34 + .36 * eased), paint);
    paint.style = PaintingStyle.fill;
    final direction = _impactDirection;
    final normal = Offset(-direction.dy, direction.dx);
    final edge = c + direction * cell * .34;
    for (var i = 0; i < 12; i++) {
      final side = i.isEven ? 1.0 : -1.0;
      final spread = (i ~/ 2) / 5;
      final velocity =
          normal * side * (.25 + .5 * spread) - direction * (.1 + .3 * spread);
      canvas.drawCircle(
        edge + velocity * cell * .9 * eased,
        cell * (.05 - .025 * spread) * (1 - .5 * p),
        paint
          ..color = (i % 3 == 0 ? _colors.reward : color).withValues(
            alpha: .85 * fade,
          ),
      );
    }
    if (_impactGoal) {
      paint
        ..color = _colors.reward.withValues(alpha: .9 * math.sin(p * math.pi))
        ..strokeWidth = math.max(1.2, cell * .022)
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 4; i++) {
        final angle = i * math.pi / 2 + math.pi / 4;
        final spot =
            c +
            Offset(math.cos(angle), math.sin(angle)) * cell * (.4 + .2 * eased);
        final radius = cell * .07 * math.sin(p * math.pi);
        canvas.drawLine(
          spot - Offset(radius, 0),
          spot + Offset(radius, 0),
          paint,
        );
        canvas.drawLine(
          spot - Offset(0, radius),
          spot + Offset(0, radius),
          paint,
        );
      }
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
}
