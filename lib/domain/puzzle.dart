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
    this.echoSwitch,
    this.echoGate,
  }) : blocks = List.unmodifiable(blocks),
       obstacles = List.unmodifiable(obstacles) {
    if (id < 1 || boardWidth < 1 || boardHeight < 1 || minimumMoves < 0) {
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
  }

  static const goalBlockId = 'goal';
  final int id;
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

  factory Level.fromJson(Map<String, dynamic> json) {
    final rules = json['specialRules'] as List<dynamic>;
    Position? echoSwitch;
    Position? echoGate;
    if (rules.length > 1) {
      throw const FormatException('Only one echo gate is supported');
    }
    if (rules.isNotEmpty) {
      final rule = rules.single;
      if (rule is! Map<String, dynamic> || rule['type'] != 'echoGate') {
        throw const FormatException('Unsupported special rule');
      }
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
    }
    return Level(
      id: json['id'] as int,
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
        state.isBlocked(target)) {
      return false;
    }
    for (final block in state.blocks) {
      if (block.id == blockId) return block.position.isAdjacentTo(target);
    }
    return false;
  }
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
    echo: moving.position,
  );
}

/// 잘못된 입력은 턴을 소비하지 않고 Undo는 잔상을 함께 되돌린다.
class PuzzleController {
  PuzzleController(Level level) : _state = PuzzleState.initial(level);

  PuzzleState _state;
  final List<PuzzleState> _history = [];
  PuzzleState get state => _state;
  bool get canUndo => _history.isNotEmpty;

  bool move(String blockId, Position target) {
    if (!MoveValidator.canMove(_state, blockId, target)) return false;
    _history.add(_state);
    _state = _move(_state, blockId, target);
    return true;
  }

  bool undo() {
    if (_history.isEmpty) return false;
    _state = _history.removeLast();
    return true;
  }

  void restart() {
    _history.clear();
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
    final initial = PuzzleState.initial(level);
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
