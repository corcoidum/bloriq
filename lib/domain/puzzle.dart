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
  }) : blocks = List.unmodifiable(blocks),
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
  }) : blocks = List.unmodifiable(blocks);

  factory PuzzleState.initial(Level level) => PuzzleState(
    level: level,
    blocks: [
      Block(id: Level.goalBlockId, position: level.startPosition),
      ...level.blocks,
    ],
  );

  final Level level;
  final List<Block> blocks;
  final int moves;
  final Position? echo;

  Block get goal => blocks.firstWhere((block) => block.id == Level.goalBlockId);
  bool get isComplete => goal.position == level.exitPosition;
  bool get isGateOpen => level.echoSwitch != null && echo == level.echoSwitch;

  bool isBlocked(Position position) =>
      level.obstacles.contains(position) ||
      (level.echoGate == position && !isGateOpen) ||
      echo == position ||
      blocks.any((block) => block.position == position);
}

class MoveValidator {
  static bool canMove(PuzzleState state, String blockId, Position target) {
    if (state.isComplete ||
        !state.level.contains(target) ||
        (target == state.level.exitPosition && blockId != Level.goalBlockId) ||
        (state.level.goalOnlyTiles.contains(target) &&
            blockId != Level.goalBlockId) ||
        state.isBlocked(target)) {
      return false;
    }
    for (final block in state.blocks) {
      if (block.id == blockId) {
        final direction = state.level.oneWays[block.position];
        return block.position.isAdjacentTo(target) &&
            (direction == null ||
                target ==
                    Position(
                      block.position.x + direction.x,
                      block.position.y + direction.y,
                    ));
      }
    }
    return false;
  }
}

/// 미리보기와 재생 모두 실제 controller 상태를 변경하지 않는다.
PuzzleState? previewMove(PuzzleState state, String blockId, Position target) {
  if (!MoveValidator.canMove(state, blockId, target)) return null;
  return _move(state, blockId, target);
}

/// 유효한 한 이동의 전후 스냅샷. Undo한 이동은 목록에서 제거한다.
class MoveRecord {
  const MoveRecord({
    required this.blockId,
    required this.from,
    required this.to,
    required this.before,
    required this.after,
  });

  final String blockId;
  final Position from;
  final Position to;
  final PuzzleState before;
  final PuzzleState after;
  Position? get previousEcho => before.echo;
  Position? get nextEcho => after.echo;
}

/// Controller와 solver가 같은 상태 전이를 사용한다.
PuzzleState _move(PuzzleState state, String blockId, Position target) {
  final moving = state.blocks.firstWhere((block) => block.id == blockId);
  return PuzzleState(
    level: state.level,
    blocks: state.blocks
        .map((block) => block.id == blockId ? block.at(target) : block)
        .toList(),
    moves: state.moves + 1,
    // 보존 칸은 이전 Echo를 유지하며, 지우개 칸은 이전 Echo를 제거한다.
    echo: state.level.echoHolds.contains(moving.position)
        ? state.echo
        : state.level.echoErasers.contains(moving.position)
        ? null
        : moving.position,
  );
}

/// 잘못된 입력은 턴을 소비하지 않고 Undo는 잔상을 함께 되돌린다.
class PuzzleController {
  PuzzleController(Level level) : _state = PuzzleState.initial(level);

  PuzzleState _state;
  final List<PuzzleState> _history = [];
  final List<MoveRecord> _moves = [];
  PuzzleState get state => _state;
  bool get canUndo => _history.isNotEmpty;
  List<MoveRecord> get moveHistory => List.unmodifiable(_moves);

  bool move(String blockId, Position target) {
    if (!MoveValidator.canMove(_state, blockId, target)) return false;
    final before = _state;
    final from = before.blocks
        .firstWhere((block) => block.id == blockId)
        .position;
    _history.add(_state);
    _state = _move(_state, blockId, target);
    _moves.add(
      MoveRecord(
        blockId: blockId,
        from: from,
        to: target,
        before: before,
        after: _state,
      ),
    );
    return true;
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
    _state = PuzzleState.initial(_state.level);
  }
}

class PuzzleMove {
  const PuzzleMove(this.blockId, this.target);
  final String blockId;
  final Position target;
}

class _SearchNode {
  const _SearchNode(this.state, this.moves);
  final PuzzleState state;
  final List<PuzzleMove> moves;
}

/// 블록 위치와 잔상을 함께 탐색하여 최소 이동 해를 찾는다.
class PuzzleSolver {
  const PuzzleSolver({this.maxStates = 200000});
  final int maxStates;

  List<PuzzleMove>? solve(Level level) {
    return solveFromState(PuzzleState.initial(level));
  }

  List<PuzzleMove>? solveFromState(PuzzleState initial) {
    final queue = Queue<_SearchNode>()..add(_SearchNode(initial, const []));
    final visited = <String>{_key(initial)};
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (node.state.isComplete) return node.moves;
      for (final block in node.state.blocks) {
        for (final target in block.position.neighbors) {
          if (!MoveValidator.canMove(node.state, block.id, target)) continue;
          final next = _move(node.state, block.id, target);
          if (!visited.add(_key(next))) continue;
          if (visited.length > maxStates) {
            throw StateError('Solver state limit exceeded: $maxStates');
          }
          queue.add(
            _SearchNode(next, [...node.moves, PuzzleMove(block.id, target)]),
          );
        }
      }
    }
    return null;
  }

  String _key(PuzzleState state) =>
      '${state.blocks.map((block) => '${block.position.x},${block.position.y}').join(';')}'
      '|${state.echo?.x},${state.echo?.y}';
}
