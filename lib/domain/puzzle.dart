import 'dart:collection';

import 'mechanics/board_mechanic.dart';
import 'mechanics/echo_eraser.dart';
import 'mechanics/echo_gate.dart';
import 'mechanics/echo_hold.dart';
import 'mechanics/goal_only.dart';
import 'mechanics/mechanic_registry.dart';
import 'mechanics/one_way.dart';
import 'mechanics/shelf_door.dart';

/// 격자 좌표. 왼쪽 위가 (0, 0)이다.
class Position {
  const Position(this.x, this.y);

  final int x;
  final int y;

  factory Position.fromJson(Map<String, dynamic> json) =>
      Position(json['x'] as int, json['y'] as int);

  bool isAdjacentTo(Position other) =>
      (x - other.x).abs() + (y - other.y).abs() == 1;

  Iterable<Position> get neighbors => [
    Position(x + 1, y),
    Position(x - 1, y),
    Position(x, y + 1),
    Position(x, y - 1),
  ];

  @override
  bool operator ==(Object other) =>
      other is Position && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// 구름바다 등대(월드 2)에서 쓰는 별자리 권능. id는 성장 시스템의
/// `PowerIds`와 같다. 각 권능은 한 스테이지에 한 번, 한 수로 센다.
enum PuzzlePower {
  /// 달꽃 도약: 블록이 바로 옆 바위 하나를 뛰어넘어 그 너머 칸에 내린다.
  moonflowerLeap('moonflower_leap'),

  /// 빛 교대: 블록 하나가 잔상 자리로 옮겨 가고, 떠난 자리가 새 잔상이 된다.
  lightSwap('light_swap'),

  /// 봉인: 이번 한 수 동안 잔상을 그대로 붙잡아 둔다(떠난 칸은 잔상이 되지 않는다).
  seal('seal'),

  /// 바람: 블록이 막힐 때까지 한 방향으로 미끄러진다.
  wind('wind');

  const PuzzlePower(this.id);
  final String id;

  static PuzzlePower? byId(String? id) {
    for (final power in values) {
      if (power.id == id) return power;
    }
    return null;
  }
}

/// 네 방향 단위 벡터.
const cardinalDirections = [
  Position(1, 0),
  Position(-1, 0),
  Position(0, 1),
  Position(0, -1),
];

class Block {
  const Block({required this.id, required this.position});

  final String id;
  final Position position;

  factory Block.fromJson(Map<String, dynamic> json) =>
      Block(id: json['id'] as String, position: Position.fromJson(json));

  Block at(Position position) => Block(id: id, position: position);
}

/// startPosition은 목표 블록의 초기 위치, blocks는 일반 블록이다.
class Level {
  Level({
    required this.id,
    required this.boardWidth,
    required this.boardHeight,
    required this.startPosition,
    required this.exitPosition,
    required List<Block> blocks,
    required List<Position> obstacles,
    required this.minimumMoves,
    required this.difficulty,
    this.revision = 1,
    Position? echoSwitch,
    Position? echoGate,
    Set<Position> echoErasers = const {},
    Set<Position> echoHolds = const {},
    Map<Position, Position> oneWays = const {},
    Set<Position> goalOnlyTiles = const {},
    Iterable<BoardMechanic> mechanics = const [],
    List<PuzzleMove> solution = const [],
    this.world = 1,
    this.bareHandedMoves,
    Set<PuzzlePower> requiredPowers = const {},
    this.featuredPower,
    Set<PuzzlePower>? availablePowers,
  }) : blocks = List.unmodifiable(blocks),
       requiredPowers = Set.unmodifiable(requiredPowers),
       availablePowers = Set.unmodifiable(
         availablePowers ?? PuzzlePower.values.toSet(),
       ),
       obstacles = List.unmodifiable(obstacles),
       solution = List.unmodifiable(solution),
       mechanics = MechanicRegistry.index([
         ...mechanics,
         if (echoErasers.isNotEmpty) EchoEraser(echoErasers),
         if (echoHolds.isNotEmpty) EchoHold(echoHolds),
         if (oneWays.isNotEmpty) OneWay(oneWays),
         if (goalOnlyTiles.isNotEmpty) GoalOnly(goalOnlyTiles),
         if (echoSwitch != null && echoGate != null)
           EchoGate(echoSwitch, echoGate),
       ]) {
    if (revision < 1 ||
        id < 1 ||
        boardWidth < 1 ||
        boardHeight < 1 ||
        minimumMoves < 0) {
      throw const FormatException('Invalid level dimensions or metadata');
    }
    if (!contains(startPosition) ||
        !contains(exitPosition) ||
        startPosition == exitPosition) {
      throw const FormatException('Invalid start or exit');
    }
    final occupied = <Position>{startPosition, exitPosition};
    final ids = <String>{goalBlockId};
    for (final obstacle in this.obstacles) {
      if (!contains(obstacle) || !occupied.add(obstacle)) {
        throw const FormatException('Invalid or overlapping obstacle');
      }
    }
    for (final block in this.blocks) {
      if (block.id.isEmpty ||
          !ids.add(block.id) ||
          !contains(block.position) ||
          !occupied.add(block.position)) {
        throw const FormatException('Invalid or overlapping block');
      }
    }
    if ((echoSwitch == null) != (echoGate == null)) {
      throw const FormatException(
        'A switch and gate must be provided together',
      );
    }
    // 독점 기믹은 서로 겹치지 않게 하여 판정과 표시를 명확히 한다.
    final mechanismPositions = this.obstacles.toSet();
    for (final mechanic in this.mechanics.values) {
      for (final tile in mechanic.cells) {
        if (!contains(tile) ||
            (mechanic.hasExclusiveCells && !mechanismPositions.add(tile))) {
          throw const FormatException('Invalid or overlapping mechanism tile');
        }
      }
      mechanic.validate(this);
    }
    if (world < 1 ||
        (bareHandedMoves != null && bareHandedMoves! < minimumMoves)) {
      throw const FormatException('Invalid world or bare-handed metadata');
    }
  }

  static const goalBlockId = 'goal';
  final int id;
  final int revision;
  final int boardWidth;
  final int boardHeight;
  final Position startPosition;
  final Position exitPosition;
  final List<Block> blocks;
  final List<Position> obstacles;
  final int minimumMoves;
  final String difficulty;
  final Map<String, BoardMechanic> mechanics;
  final List<PuzzleMove> solution;

  T? mechanic<T extends BoardMechanic>(String type) => mechanics[type] as T?;

  // 기존 호출부도 같은 기믹 설정을 읽는다.
  Position? get echoSwitch =>
      mechanic<EchoGate>(EchoGate.typeId)?.switchPosition;
  Position? get echoGate => mechanic<EchoGate>(EchoGate.typeId)?.gatePosition;
  Set<Position> get echoErasers =>
      mechanic<EchoEraser>(EchoEraser.typeId)?.cells ?? const {};
  Set<Position> get echoHolds =>
      mechanic<EchoHold>(EchoHold.typeId)?.cells ?? const {};
  Map<Position, Position> get oneWays =>
      mechanic<OneWay>(OneWay.typeId)?.arrows ?? const {};
  Set<Position> get goalOnlyTiles =>
      mechanic<GoalOnly>(GoalOnly.typeId)?.cells ?? const {};

  /// 1 = 달빛 숲(기본), 2 = 구름바다 등대.
  final int world;

  /// 권능 없이 풀 때의 최소 이동 수. 권능 없이는 풀 수 없으면 null.
  /// 월드 1 레벨은 권능이 없으므로 [minimumMoves]와 같게 본다.
  final int? bareHandedMoves;

  /// 이 권능이 없으면(다른 권능은 모두 있어도) 풀 수 없다.
  final Set<PuzzlePower> requiredPowers;

  /// 이 스테이지가 소개하거나 강조하는 권능.
  final PuzzlePower? featuredPower;

  /// 이 스테이지에서 쓸 수 있는 권능. 장마다 한두 권능만 열어 퍼즐을 깊게 만든다.
  /// JSON 에 없으면 네 권능 모두다.
  final Set<PuzzlePower> availablePowers;

  bool get solvableBareHanded => world == 1 || bareHandedMoves != null;

  factory Level.fromJson(Map<String, dynamic> json) {
    final solution = json['solution'];
    if (solution != null && solution is! List) {
      throw const FormatException('Solution must be a list');
    }
    final rawPowers = json['availablePowers'];
    Set<PuzzlePower>? availablePowers;
    if (rawPowers != null) {
      if (rawPowers is! List) {
        throw const FormatException('Available powers must be a list');
      }
      availablePowers = <PuzzlePower>{};
      for (final id in rawPowers) {
        final power = id is String ? PuzzlePower.byId(id) : null;
        if (power == null || !availablePowers.add(power)) {
          throw const FormatException('Unknown or repeated available power');
        }
      }
    }
    return Level(
      id: json['id'] as int,
      revision: json['revision'] as int? ?? 1,
      boardWidth: json['boardWidth'] as int,
      boardHeight: json['boardHeight'] as int,
      startPosition: Position.fromJson(
        json['startPosition'] as Map<String, dynamic>,
      ),
      exitPosition: Position.fromJson(
        json['exitPosition'] as Map<String, dynamic>,
      ),
      blocks: (json['blocks'] as List<dynamic>)
          .map((item) => Block.fromJson(item as Map<String, dynamic>))
          .toList(),
      obstacles: (json['obstacles'] as List<dynamic>)
          .map((item) => Position.fromJson(item as Map<String, dynamic>))
          .toList(),
      minimumMoves: json['minimumMoves'] as int,
      difficulty: json['difficulty'] as String,
      mechanics: MechanicRegistry.parse(json['specialRules']),
      solution: solution is List
          ? solution.map(PuzzleMove.fromJson).toList()
          : const [],
      world: json['world'] as int? ?? 1,
      bareHandedMoves: json['bareHandedMoves'] as int?,
      requiredPowers: {
        for (final id in (json['requiredPowers'] as List<dynamic>? ?? []))
          PuzzlePower.byId(id as String) ??
              (throw const FormatException('Unknown power')),
      },
      featuredPower: json['featuredPower'] == null
          ? null
          : PuzzlePower.byId(json['featuredPower'] as String) ??
                (throw const FormatException('Unknown power')),
      availablePowers: availablePowers,
    );
  }

  bool contains(Position position) =>
      position.x >= 0 &&
      position.x < boardWidth &&
      position.y >= 0 &&
      position.y < boardHeight;
}

/// 잔상은 다음 유효한 이동의 판정이 끝날 때까지 남는다.
class PuzzleState {
  PuzzleState({
    required this.level,
    required List<Block> blocks,
    this.moves = 0,
    this.echo,
    Set<PuzzlePower> powers = const {},
  }) : blocks = List.unmodifiable(blocks),
       powers = Set.unmodifiable(powers);

  /// [powers]는 이번 스테이지에서 아직 쓰지 않은 권능이다.
  factory PuzzleState.initial(
    Level level, {
    Set<PuzzlePower> powers = const {},
  }) => PuzzleState(
    level: level,
    blocks: [
      Block(id: Level.goalBlockId, position: level.startPosition),
      ...level.blocks,
    ],
    powers: powers,
  );

  final Level level;
  final List<Block> blocks;
  final int moves;
  final Position? echo;

  /// 남은 권능. 하나를 쓰면 이 스테이지에서는 다시 쓸 수 없다.
  final Set<PuzzlePower> powers;

  Block get goal => blocks.firstWhere((block) => block.id == Level.goalBlockId);
  bool get isComplete => goal.position == level.exitPosition;
  bool get isGateOpen =>
      level.mechanic<EchoGate>(EchoGate.typeId)?.isOpen(echo) ?? false;

  bool _occupied(Position position, [List<Block>? occupiedBlocks]) =>
      level.obstacles.contains(position) ||
      echo == position ||
      (occupiedBlocks ?? blocks).any((block) => block.position == position);

  bool _canEnter(String? blockId, Position target) {
    for (final mechanic in level.mechanics.values) {
      if (!mechanic.canEnter(this, blockId, target)) return false;
    }
    return true;
  }

  bool isBlocked(Position position) =>
      _occupied(position) || !_canEnter(null, position);

  /// 칸 하나에 블록이 들어설 수 있는지(출발 칸·방향과 무관한 조건).
  /// 배치 변환 중에는 갱신된 블록 위치와 이동 전 잔상을 함께 검사한다.
  bool canOccupy(
    String blockId,
    Position target, {
    List<Block>? occupiedBlocks,
    bool allowNonGoalExit = false,
  }) =>
      level.contains(target) &&
      (allowNonGoalExit ||
          target != level.exitPosition ||
          blockId == Level.goalBlockId) &&
      !_occupied(target, occupiedBlocks) &&
      _canEnter(blockId, target);

  bool canLeave(Position from, Position direction) {
    for (final mechanic in level.mechanics.values) {
      if (!mechanic.canLeave(this, from, direction)) return false;
    }
    return true;
  }

  Position? positionOf(String blockId) {
    for (final block in blocks) {
      if (block.id == blockId) return block.position;
    }
    return null;
  }
}

class MoveValidator {
  static bool canMove(PuzzleState state, String blockId, Position target) {
    if (state.isComplete || !state.canOccupy(blockId, target)) return false;
    final from = state.positionOf(blockId);
    if (from == null) return false;
    return from.isAdjacentTo(target) &&
        state.canLeave(from, Position(target.x - from.x, target.y - from.y));
  }
}

/// 권능 한 번의 판정. 모두 순수 함수이며 controller와 solver가 함께 쓴다.
abstract final class PowerRules {
  /// [power]를 [blockId]에 [direction] 방향으로 쓸 때 블록이 내릴 칸.
  /// 쓸 수 없으면 null. 빛 교대는 방향을 보지 않는다.
  static Position? landing(
    PuzzleState state,
    PuzzlePower power,
    String blockId,
    Position direction,
  ) {
    if (state.isComplete || !state.powers.contains(power)) return null;
    final from = state.positionOf(blockId);
    if (from == null) return null;
    final level = state.level;
    final cardinal = direction.x.abs() + direction.y.abs() == 1;
    Position step(Position p) => Position(p.x + direction.x, p.y + direction.y);
    switch (power) {
      case PuzzlePower.moonflowerLeap:
        if (!cardinal || !state.canLeave(from, direction)) return null;
        final over = step(from);
        final land = step(over);
        if (!level.obstacles.contains(over)) return null;
        return state.canOccupy(blockId, land) ? land : null;
      case PuzzlePower.lightSwap:
        final echo = state.echo;
        if (echo == null) return null;
        // 잔상 칸은 비어 있으므로, 출구·전용 칸·닫힌 문 조건만 본다.
        final probe = PuzzleState(
          level: level,
          blocks: state.blocks,
          echo: null,
          moves: state.moves,
          powers: state.powers,
        );
        return probe.canOccupy(blockId, echo) ? echo : null;
      case PuzzlePower.seal:
        if (!cardinal || state.echo == null) return null;
        final target = step(from);
        return MoveValidator.canMove(state, blockId, target) ? target : null;
      case PuzzlePower.wind:
        if (!cardinal) return null;
        var current = from;
        while (true) {
          if (!state.canLeave(current, direction)) break;
          final next = step(current);
          if (!state.canOccupy(blockId, next)) break;
          current = next;
          if (blockId == Level.goalBlockId && current == level.exitPosition) {
            break;
          }
        }
        return current == from ? null : current;
    }
  }
}

/// 미리보기와 재생 모두 실제 controller 상태를 변경하지 않는다.
PuzzleState? previewMove(
  PuzzleState state,
  String blockId,
  Position target, {
  List<MoveTeleport>? teleports,
}) {
  if (!MoveValidator.canMove(state, blockId, target)) return null;
  return _move(state, PuzzleMove(blockId, target), teleports: teleports);
}

/// 권능 한 번을 적용한 다음 상태. 쓸 수 없으면 null.
PuzzleState? previewPower(
  PuzzleState state,
  PuzzlePower power,
  String blockId,
  Position direction, {
  List<MoveTeleport>? teleports,
}) {
  final land = PowerRules.landing(state, power, blockId, direction);
  if (land == null) return null;
  return _move(
    state,
    PuzzleMove(blockId, land, power: power),
    teleports: teleports,
  );
}

typedef MoveTeleport = ({String blockId, Position from, Position to});

/// 유효한 한 이동의 전후 스냅샷. Undo한 이동은 목록에서 제거한다.
class MoveRecord {
  const MoveRecord({
    required this.blockId,
    required this.from,
    required this.to,
    required this.before,
    required this.after,
    this.power,
    Position? landing,
    this.teleports = const [],
  }) : landing = landing ?? to;

  final String blockId;
  final Position from;
  final Position to;

  /// 기믹으로 착지가 바뀌기 전의 입력. 힌트와 solver는 이 칸을 쓴다.
  final Position landing;
  final PuzzleState before;
  final PuzzleState after;
  final List<MoveTeleport> teleports;
  MoveTeleport? teleportOf(String blockId) =>
      teleports.where((hop) => hop.blockId == blockId).firstOrNull;

  /// 이 수에 쓴 권능. 일반 이동이면 null.
  final PuzzlePower? power;
  Position? get previousEcho => before.echo;
  Position? get nextEcho => after.echo;
}

/// Controller와 solver가 같은 상태 전이를 사용한다.
PuzzleState _move(
  PuzzleState state,
  PuzzleMove move, {
  List<MoveTeleport>? teleports,
}) {
  final PuzzleMove(:blockId, :target, :power) = move;
  final source = state.positionOf(blockId)!;
  final mechanics = state.level.mechanics.values;
  var blocks = [
    for (final block in state.blocks)
      block.id == blockId ? block.at(target) : block,
  ];
  // 일반/권능 착지 → 기믹 배치 변환 → 잔상. 봉인·교대의 잔상 규칙은 마지막에 우선한다.
  for (final mechanic in mechanics) {
    blocks = mechanic.transformMove(state, move, blocks, teleports: teleports);
  }
  Position? echo = source;
  for (final mechanic in mechanics) {
    echo = mechanic.nextEcho(state, move, blocks, echo);
  }
  echo = switch (power) {
    // 봉인은 이전 잔상을 한 턴 더 붙잡는다.
    PuzzlePower.seal => state.echo,
    // 교대는 블록이 잔상 자리를 차지하므로 떠난 칸이 새 잔상이 된다.
    PuzzlePower.lightSwap => source,
    _ => echo,
  };
  return PuzzleState(
    level: state.level,
    blocks: blocks,
    moves: state.moves + 1,
    echo: echo,
    powers: power == null ? state.powers : ({...state.powers}..remove(power)),
  );
}

/// 잘못된 입력은 턴을 소비하지 않고 Undo는 잔상을 함께 되돌린다.
class PuzzleController {
  PuzzleController(Level level, {Set<PuzzlePower> powers = const {}})
    : _state = PuzzleState.initial(level, powers: powers),
      _initialPowers = Set.unmodifiable(powers);

  PuzzleState _state;
  final Set<PuzzlePower> _initialPowers;
  final List<PuzzleState> _history = [];
  final List<MoveRecord> _moves = [];
  PuzzleState get state => _state;
  bool get canUndo => _history.isNotEmpty;
  MoveRecord? get lastMove => _moves.lastOrNull;
  List<MoveRecord> get moveHistory => List.unmodifiable(_moves);

  /// 이번 시도에서 권능을 한 번이라도 썼는지(Undo로 되돌린 수는 제외).
  bool get usedPower => _moves.any((move) => move.power != null);

  bool move(String blockId, Position target) {
    if (!MoveValidator.canMove(_state, blockId, target)) return false;
    _commit(blockId, target, null);
    return true;
  }

  /// [power]를 [blockId]에 [direction] 방향으로 쓴다. 쓸 수 없으면 false.
  bool usePower(PuzzlePower power, String blockId, Position direction) {
    final land = PowerRules.landing(_state, power, blockId, direction);
    if (land == null) return false;
    _commit(blockId, land, power);
    return true;
  }

  /// Solver가 낸 수를 그대로 적용한다.
  bool apply(PuzzleMove move) {
    final power = move.power;
    if (power == null) return this.move(move.blockId, move.target);
    final from = _state.positionOf(move.blockId);
    if (from == null) return false;
    final direction = Position(
      (move.target.x - from.x).sign,
      (move.target.y - from.y).sign,
    );
    final land = PowerRules.landing(_state, power, move.blockId, direction);
    if (land != move.target) return false;
    _commit(move.blockId, land!, power);
    return true;
  }

  void _commit(String blockId, Position target, PuzzlePower? power) {
    final before = _state;
    final from = before.positionOf(blockId)!;
    final teleports = before.level.mechanics.containsKey(ShelfDoor.typeId)
        ? <MoveTeleport>[]
        : null;
    _history.add(_state);
    _state = _move(
      before,
      PuzzleMove(blockId, target, power: power),
      teleports: teleports,
    );
    _moves.add(
      MoveRecord(
        blockId: blockId,
        from: from,
        to: _state.positionOf(blockId)!,
        landing: target,
        before: before,
        after: _state,
        power: power,
        teleports: teleports == null ? const [] : List.unmodifiable(teleports),
      ),
    );
  }

  bool undo() {
    if (_history.isEmpty) return false;
    _state = _history.removeLast();
    _moves.removeLast();
    return true;
  }

  void restart() {
    _history.clear();
    _moves.clear();
    _state = PuzzleState.initial(_state.level, powers: _initialPowers);
  }
}

class PuzzleMove {
  const PuzzleMove(this.blockId, this.target, {this.power});

  factory PuzzleMove.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw['blockId'] is! String ||
        (raw['blockId'] as String).isEmpty) {
      throw const FormatException('Invalid solution move');
    }
    final target = raw['target'];
    if (target is! Map<String, dynamic> ||
        target['x'] is! int ||
        target['y'] is! int) {
      throw const FormatException('Invalid solution target');
    }
    final powerId = raw['power'];
    final power = powerId is String ? PuzzlePower.byId(powerId) : null;
    if (powerId != null && power == null) {
      throw const FormatException('Unknown solution power');
    }
    return PuzzleMove(
      raw['blockId'] as String,
      Position.fromJson(target),
      power: power,
    );
  }
  final String blockId;
  final Position target;

  /// 권능을 쓴 수이면 그 권능. [target]은 기믹으로 변환되기 전 착지 칸이다.
  final PuzzlePower? power;

  @override
  String toString() =>
      'PuzzleMove($blockId -> $target${power == null ? '' : ' ${power!.id}'})';
}

class _SearchNode {
  const _SearchNode(this.state, this.parent, this.move);
  final PuzzleState state;
  final _SearchNode? parent;
  final PuzzleMove? move;

  List<PuzzleMove> get path {
    final result = <PuzzleMove>[];
    _SearchNode? node = this;
    while (node != null && node.move != null) {
      result.add(node.move!);
      node = node.parent;
    }
    return result.reversed.toList();
  }
}

/// 블록 위치·잔상·남은 권능을 함께 탐색하여 최소 이동 해를 찾는다.
class PuzzleSolver {
  const PuzzleSolver({this.maxStates = 200000});
  final int maxStates;

  /// [powers]가 비어 있으면 월드 1과 같은 맨손 탐색이다.
  List<PuzzleMove>? solve(
    Level level, {
    Set<PuzzlePower> powers = const {},
    PuzzlePower? mustUse,
  }) {
    return solveFromState(
      PuzzleState.initial(level, powers: powers),
      mustUse: mustUse,
    );
  }

  /// 한 상태에서 갈 수 있는 모든 다음 수(일반 이동 먼저, 그다음 권능).
  static Iterable<(PuzzleMove, PuzzleState)> successors(
    PuzzleState state,
  ) sync* {
    if (state.isComplete) return;
    for (final block in state.blocks) {
      for (final direction in cardinalDirections) {
        final target = Position(
          block.position.x + direction.x,
          block.position.y + direction.y,
        );
        if (MoveValidator.canMove(state, block.id, target)) {
          final move = PuzzleMove(block.id, target);
          yield (move, _move(state, move));
        }
      }
    }
    for (final power in PuzzlePower.values) {
      if (!state.powers.contains(power)) continue;
      for (final block in state.blocks) {
        final directions = power == PuzzlePower.lightSwap
            ? const [Position(0, 0)]
            : cardinalDirections;
        for (final direction in directions) {
          final land = PowerRules.landing(state, power, block.id, direction);
          if (land == null) continue;
          final move = PuzzleMove(block.id, land, power: power);
          yield (move, _move(state, move));
        }
      }
    }
  }

  /// [mustUse]가 있으면 그 권능을 쓴 해만 정답으로 본다(강조 권능 확인용).
  List<PuzzleMove>? solveFromState(
    PuzzleState initial, {
    PuzzlePower? mustUse,
    Duration? timeLimit,
  }) {
    final search = _PuzzleSearch(initial, maxStates, mustUse);
    if (timeLimit == null) {
      search.advance();
    } else {
      final watch = Stopwatch()..start();
      while (!search.done) {
        _checkTime(watch, timeLimit);
        search.advance(32);
      }
      _checkTime(watch, timeLimit);
    }
    return search.solution;
  }

  /// 웹의 compute는 같은 이벤트 루프를 쓴다. 짧게 탐색하고 프레임을 양보한다.
  Future<List<PuzzleMove>?> solveCooperatively(
    PuzzleState initial, {
    required Duration timeLimit,
  }) async {
    final search = _PuzzleSearch(initial, maxStates, null);
    final watch = Stopwatch()..start();
    final slice = Stopwatch()..start();
    while (!search.done) {
      _checkTime(watch, timeLimit);
      search.advance(32);
      if (!search.done && slice.elapsedMicroseconds >= 4000) {
        await Future<void>.delayed(Duration.zero);
        slice.reset();
      }
    }
    _checkTime(watch, timeLimit);
    return search.solution;
  }

  static void _checkTime(Stopwatch watch, Duration limit) {
    if (watch.elapsed >= limit) {
      throw PuzzleSearchLimit('Solver time limit exceeded');
    }
  }
}

class PuzzleSearchLimit extends StateError {
  PuzzleSearchLimit(super.message);
}

/// 같은 BFS를 동기 검증, isolate 힌트, 웹의 분할 탐색에 사용한다.
class _PuzzleSearch {
  _PuzzleSearch(PuzzleState initial, this.maxStates, this.mustUse)
    : _keyOf = _StateKey(initial) {
    if (initial.isComplete) {
      solution = const [];
    } else {
      _queue.add(_SearchNode(initial, null, null));
      _visited.add(_keyOf(initial));
    }
  }

  final int maxStates;
  final PuzzlePower? mustUse;
  final _StateKey _keyOf;
  final _queue = Queue<_SearchNode>();
  final _visited = <Object>{};
  List<PuzzleMove>? solution;
  bool get done => solution != null || _queue.isEmpty;

  void advance([int? maxNodes]) {
    for (
      var count = 0;
      _queue.isNotEmpty && (maxNodes == null || count < maxNodes);
      count++
    ) {
      final node = _queue.removeFirst();
      for (final (move, next) in PuzzleSolver.successors(node.state)) {
        if (!_visited.add(_keyOf(next))) continue;
        if (_visited.length > maxStates) {
          throw PuzzleSearchLimit('Solver state limit exceeded: $maxStates');
        }
        final child = _SearchNode(next, node, move);
        if (next.isComplete) {
          if (mustUse == null || !next.powers.contains(mustUse)) {
            solution = child.path;
            return;
          }
          continue;
        }
        _queue.add(child);
      }
    }
  }
}

/// 상태를 정수 하나로 묶는다(웹의 53비트 안). 너무 크면 문자열을 쓴다.
class _StateKey {
  _StateKey(PuzzleState sample)
    : _width = sample.level.boardWidth,
      _bits = _bitsFor(sample.level.boardWidth * sample.level.boardHeight + 1),
      _packable =
          _bitsFor(sample.level.boardWidth * sample.level.boardHeight + 1) *
                  (sample.blocks.length + 1) +
              PuzzlePower.values.length <=
          52;

  final int _width;
  final int _bits;
  final bool _packable;

  static int _bitsFor(int count) {
    var bits = 1;
    while ((1 << bits) < count) {
      bits++;
    }
    return bits;
  }

  Object call(PuzzleState state) {
    final positions = _positionKey(state);
    StringBuffer? extra;
    for (final mechanic in state.level.mechanics.values) {
      if (mechanic.stateKey(state) case final value?) {
        (extra ??= StringBuffer(positions)).write('|${mechanic.type}:$value');
      }
    }
    return extra?.toString() ?? positions;
  }

  Object _positionKey(PuzzleState state) {
    if (!_packable) {
      return '${state.blocks.map((block) => '${block.position.x},${block.position.y}').join(';')}'
          '|${state.echo?.x},${state.echo?.y}'
          '|${state.powers.map((p) => p.index).toList()..sort()}';
    }
    var key = 0;
    for (final power in PuzzlePower.values) {
      key = key * 2 + (state.powers.contains(power) ? 1 : 0);
    }
    final scale = 1 << _bits;
    for (final block in state.blocks) {
      key = key * scale + block.position.y * _width + block.position.x;
    }
    final echo = state.echo;
    key = key * scale + (echo == null ? scale - 1 : echo.y * _width + echo.x);
    return key;
  }
}
