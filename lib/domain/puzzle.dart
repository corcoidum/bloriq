import 'dart:collection';

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
    this.echoSwitch,
    this.echoGate,
    Set<Position> echoErasers = const {},
    Set<Position> echoHolds = const {},
    Map<Position, Position> oneWays = const {},
    Set<Position> goalOnlyTiles = const {},
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
       echoErasers = Set.unmodifiable(echoErasers),
       echoHolds = Set.unmodifiable(echoHolds),
       oneWays = Map.unmodifiable(oneWays),
       goalOnlyTiles = Set.unmodifiable(goalOnlyTiles) {
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
    // A switch can start under a block; a gate starts empty and closed.
    if ((echoSwitch == null) != (echoGate == null)) {
      throw const FormatException(
        'A switch and gate must be provided together',
      );
    }
    if (echoSwitch != null && echoGate != null) {
      if (!contains(echoSwitch!) ||
          !contains(echoGate!) ||
          echoSwitch == echoGate ||
          echoSwitch == exitPosition ||
          echoGate == exitPosition ||
          this.obstacles.contains(echoSwitch) ||
          this.obstacles.contains(echoGate) ||
          echoGate == startPosition ||
          this.blocks.any((block) => block.position == echoGate)) {
        throw const FormatException('Invalid switch or gate position');
      }
    }
    // 서로 다른 기믹은 서로 겹치지 않게 하여 판정과 표시를 명확히 한다.
    final mechanismPositions = <Position>{};
    for (final tile in [
      ...this.echoErasers,
      ...this.echoHolds,
      ...this.oneWays.keys,
      ...this.goalOnlyTiles,
    ]) {
      if (!contains(tile) ||
          this.obstacles.contains(tile) ||
          tile == echoSwitch ||
          tile == echoGate ||
          !mechanismPositions.add(tile)) {
        throw const FormatException('Invalid or overlapping mechanism tile');
      }
    }
    for (final direction in this.oneWays.values) {
      if (direction.x.abs() + direction.y.abs() != 1) {
        throw const FormatException('One-way direction must be cardinal');
      }
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
  final Position? echoSwitch;
  final Position? echoGate;
  final Set<Position> echoErasers;
  final Set<Position> echoHolds;

  /// 칸과 해당 칸에서 나갈 수 있는 상대 방향 (dx, dy).
  final Map<Position, Position> oneWays;
  final Set<Position> goalOnlyTiles;

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
    final rules = json['specialRules'] as List<dynamic>;
    Position? echoSwitch;
    Position? echoGate;
    final erasers = <Position>{};
    final holds = <Position>{};
    final oneWays = <Position, Position>{};
    final goalOnly = <Position>{};
    final seenTypes = <String>{};
    for (final rule in rules) {
      if (rule is! Map<String, dynamic> || rule['type'] is! String) {
        throw const FormatException('Unsupported special rule');
      }
      final type = rule['type'] as String;
      if (!seenTypes.add(type)) {
        throw const FormatException('Duplicate special rule');
      }
      if (type == 'echoGate') {
        final switchData = rule['switch'];
        final gateData = rule['gate'];
        if (switchData is! Map<String, dynamic> ||
            gateData is! Map<String, dynamic>) {
          throw const FormatException(
            'Echo gate requires switch and gate positions',
          );
        }
        echoSwitch = Position.fromJson(switchData);
        echoGate = Position.fromJson(gateData);
      } else if (type == 'oneWay') {
        final tiles = rule['tiles'];
        if (tiles is! List || tiles.isEmpty) {
          throw const FormatException('One-way rule requires tiles');
        }
        for (final item in tiles) {
          if (item is! Map<String, dynamic> ||
              item['dx'] is! int ||
              item['dy'] is! int) {
            throw const FormatException('Invalid one-way tile');
          }
          final position = Position.fromJson(item);
          if (oneWays.containsKey(position)) {
            throw const FormatException('Duplicate one-way tile');
          }
          oneWays[position] = Position(item['dx'] as int, item['dy'] as int);
        }
      } else if (type == 'echoEraser' ||
          type == 'echoHold' ||
          type == 'goalOnly') {
        final positions = rule['positions'];
        if (positions is! List || positions.isEmpty) {
          throw const FormatException('Mechanism rule requires positions');
        }
        final output = type == 'echoEraser'
            ? erasers
            : type == 'echoHold'
            ? holds
            : goalOnly;
        for (final item in positions) {
          if (item is! Map<String, dynamic> ||
              !output.add(Position.fromJson(item))) {
            throw const FormatException('Invalid or duplicate mechanism tile');
          }
        }
      } else {
        throw const FormatException('Unsupported special rule');
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
      echoSwitch: echoSwitch,
      echoGate: echoGate,
      echoErasers: erasers,
      echoHolds: holds,
      oneWays: oneWays,
      goalOnlyTiles: goalOnly,
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
      availablePowers: json['availablePowers'] == null
          ? null
          : {
              for (final id in json['availablePowers'] as List<dynamic>)
                PuzzlePower.byId(id as String) ??
                    (throw const FormatException('Unknown power')),
            },
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
  bool get isGateOpen => level.echoSwitch != null && echo == level.echoSwitch;

  bool isBlocked(Position position) =>
      level.obstacles.contains(position) ||
      (level.echoGate == position && !isGateOpen) ||
      echo == position ||
      blocks.any((block) => block.position == position);

  /// 칸 하나에 블록이 들어설 수 있는지(출발 칸·방향과 무관한 조건).
  bool canOccupy(String blockId, Position target) =>
      level.contains(target) &&
      !(target == level.exitPosition && blockId != Level.goalBlockId) &&
      !(level.goalOnlyTiles.contains(target) && blockId != Level.goalBlockId) &&
      !isBlocked(target);

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
    final direction = state.level.oneWays[from];
    return from.isAdjacentTo(target) &&
        (direction == null ||
            target == Position(from.x + direction.x, from.y + direction.y));
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
    final arrow = level.oneWays[from];
    final cardinal = direction.x.abs() + direction.y.abs() == 1;
    Position step(Position p) => Position(p.x + direction.x, p.y + direction.y);
    switch (power) {
      case PuzzlePower.moonflowerLeap:
        if (!cardinal || (arrow != null && arrow != direction)) return null;
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
        );
        if (level.echoGate == echo) return null;
        return probe.canOccupy(blockId, echo) ? echo : null;
      case PuzzlePower.seal:
        if (!cardinal || state.echo == null) return null;
        final target = step(from);
        return MoveValidator.canMove(state, blockId, target) ? target : null;
      case PuzzlePower.wind:
        if (!cardinal) return null;
        var current = from;
        while (true) {
          final currentArrow = level.oneWays[current];
          if (currentArrow != null && currentArrow != direction) break;
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
PuzzleState? previewMove(PuzzleState state, String blockId, Position target) {
  if (!MoveValidator.canMove(state, blockId, target)) return null;
  return _move(state, blockId, target);
}

/// 권능 한 번을 적용한 다음 상태. 쓸 수 없으면 null.
PuzzleState? previewPower(
  PuzzleState state,
  PuzzlePower power,
  String blockId,
  Position direction,
) {
  final land = PowerRules.landing(state, power, blockId, direction);
  if (land == null) return null;
  return _move(state, blockId, land, power: power);
}

/// 유효한 한 이동의 전후 스냅샷. Undo한 이동은 목록에서 제거한다.
class MoveRecord {
  const MoveRecord({
    required this.blockId,
    required this.from,
    required this.to,
    required this.before,
    required this.after,
    this.power,
  });

  final String blockId;
  final Position from;
  final Position to;
  final PuzzleState before;
  final PuzzleState after;

  /// 이 수에 쓴 권능. 일반 이동이면 null.
  final PuzzlePower? power;
  Position? get previousEcho => before.echo;
  Position? get nextEcho => after.echo;
}

/// Controller와 solver가 같은 상태 전이를 사용한다.
PuzzleState _move(
  PuzzleState state,
  String blockId,
  Position target, {
  PuzzlePower? power,
}) {
  final moving = state.blocks.firstWhere((block) => block.id == blockId);
  final source = moving.position;
  final Position? echo = switch (power) {
    // 봉인은 이전 잔상을 한 턴 더 붙잡는다.
    PuzzlePower.seal => state.echo,
    // 교대는 블록이 잔상 자리를 차지하므로 떠난 칸이 새 잔상이 된다.
    PuzzlePower.lightSwap => source,
    // 보존 칸은 이전 Echo를 유지하며, 지우개 칸은 이전 Echo를 제거한다.
    _ =>
      state.level.echoHolds.contains(source)
          ? state.echo
          : state.level.echoErasers.contains(source)
          ? null
          : source,
  };
  return PuzzleState(
    level: state.level,
    blocks: state.blocks
        .map((block) => block.id == blockId ? block.at(target) : block)
        .toList(),
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
    _history.add(_state);
    _state = _move(_state, blockId, target, power: power);
    _moves.add(
      MoveRecord(
        blockId: blockId,
        from: from,
        to: target,
        before: before,
        after: _state,
        power: power,
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
  final String blockId;
  final Position target;

  /// 권능을 쓴 수이면 그 권능. [target]은 블록이 내리는 칸이다.
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
          yield (PuzzleMove(block.id, target), _move(state, block.id, target));
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
          yield (
            PuzzleMove(block.id, land, power: power),
            _move(state, block.id, land, power: power),
          );
        }
      }
    }
  }

  /// [mustUse]가 있으면 그 권능을 쓴 해만 정답으로 본다(강조 권능 확인용).
  List<PuzzleMove>? solveFromState(
    PuzzleState initial, {
    PuzzlePower? mustUse,
  }) {
    final keyOf = _StateKey(initial);
    final root = _SearchNode(initial, null, null);
    if (initial.isComplete) return const [];
    final queue = Queue<_SearchNode>()..add(root);
    final visited = <Object>{keyOf(initial)};
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      for (final (move, next) in successors(node.state)) {
        if (!visited.add(keyOf(next))) continue;
        if (visited.length > maxStates) {
          throw StateError('Solver state limit exceeded: $maxStates');
        }
        final child = _SearchNode(next, node, move);
        if (next.isComplete) {
          if (mustUse == null || !next.powers.contains(mustUse)) {
            return child.path;
          }
          continue;
        }
        queue.add(child);
      }
    }
    return null;
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
