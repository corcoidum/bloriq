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

/// Phase 1에서 지원하지 않는 규칙은 명시적으로 거부한다.
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
    final ids = <String>{};
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
  }

  final int id;
  final int boardWidth;
  final int boardHeight;
  final Position startPosition;
  final Position exitPosition;
  final List<Block> blocks;
  final List<Position> obstacles;
  final int minimumMoves;
  final String difficulty;

  factory Level.fromJson(Map<String, dynamic> json) {
    final rules = json['specialRules'] as List<dynamic>;
    if (rules.isNotEmpty) {
      throw const FormatException('Special rules are not supported yet');
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
    );
  }

  bool contains(Position position) =>
      position.x >= 0 &&
      position.x < boardWidth &&
      position.y >= 0 &&
      position.y < boardHeight;
}

class PuzzleState {
  PuzzleState({
    required this.level,
    required List<Block> blocks,
    this.moves = 0,
    List<Position> path = const [],
  }) : blocks = List.unmodifiable(blocks),
       path = List.unmodifiable(path);

  factory PuzzleState.initial(Level level) =>
      PuzzleState(level: level, blocks: level.blocks);

  final Level level;
  final List<Block> blocks;
  final int moves;
  final List<Position> path;

  bool get isComplete => path.isNotEmpty && path.last == level.exitPosition;

  bool isBlocked(Position position) =>
      level.obstacles.contains(position) ||
      blocks.any((block) => block.position == position);
}

class MoveValidator {
  static bool canMove(PuzzleState state, String blockId, Position target) {
    if (state.isComplete ||
        !state.level.contains(target) ||
        target == state.level.startPosition ||
        target == state.level.exitPosition ||
        state.isBlocked(target)) {
      return false;
    }
    for (final block in state.blocks) {
      if (block.id == blockId) return block.position.isAdjacentTo(target);
    }
    return false;
  }
}

class PathValidator {
  static bool canAppend(PuzzleState state, Position position) {
    if (state.isComplete ||
        !state.level.contains(position) ||
        state.isBlocked(position) ||
        state.path.contains(position)) {
      return false;
    }
    if (state.path.isEmpty) return position == state.level.startPosition;
    return state.path.last.isAdjacentTo(position);
  }

  /// 현재 블록 배치에서 실제로 연결 가능한 경로가 있는지 확인한다.
  static bool hasEscapePath(PuzzleState state) {
    final queue = Queue<Position>()..add(state.level.startPosition);
    final visited = <Position>{state.level.startPosition};
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (current == state.level.exitPosition) return true;
      for (final next in current.neighbors) {
        if (state.level.contains(next) &&
            !state.isBlocked(next) &&
            visited.add(next)) {
          queue.add(next);
        }
      }
    }
    return false;
  }
}

/// UI와 독립적인 게임 상태 전이. 잘못된 입력은 상태를 바꾸지 않는다.
class PuzzleController {
  PuzzleController(Level level) : _state = PuzzleState.initial(level);

  PuzzleState _state;
  final List<PuzzleState> _history = [];
  PuzzleState get state => _state;
  bool get canUndo => _history.isNotEmpty;

  bool move(String blockId, Position target) {
    if (!MoveValidator.canMove(_state, blockId, target)) return false;
    _history.add(_state);
    _state = PuzzleState(
      level: _state.level,
      blocks: _state.blocks
          .map((block) => block.id == blockId ? block.at(target) : block)
          .toList(),
      moves: _state.moves + 1,
    );
    return true;
  }

  bool appendPath(Position position) {
    if (!PathValidator.canAppend(_state, position)) return false;
    _state = PuzzleState(
      level: _state.level,
      blocks: _state.blocks,
      moves: _state.moves,
      path: [..._state.path, position],
    );
    return true;
  }

  /// 새 선을 그릴 때 기존 선을 지운다. 블록 이동 횟수는 유지한다.
  void clearPath() {
    if (_state.isComplete || _state.path.isEmpty) return;
    _state = PuzzleState(
      level: _state.level,
      blocks: _state.blocks,
      moves: _state.moves,
    );
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

/// 블록 이동 횟수를 기준으로 최단 해를 찾는다. null은 해결 불가능을 뜻한다.
class PuzzleSolver {
  const PuzzleSolver({this.maxStates = 200000});
  final int maxStates;

  List<PuzzleMove>? solve(Level level) {
    final initial = PuzzleState.initial(level);
    final queue = Queue<_SearchNode>()..add(_SearchNode(initial, const []));
    final visited = <String>{_key(initial.blocks)};
    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (PathValidator.hasEscapePath(node.state)) return node.moves;
      for (final block in node.state.blocks) {
        for (final target in block.position.neighbors) {
          if (!MoveValidator.canMove(node.state, block.id, target)) continue;
          final blocks = node.state.blocks
              .map((item) => item.id == block.id ? item.at(target) : item)
              .toList();
          if (!visited.add(_key(blocks))) continue;
          if (visited.length > maxStates) {
            throw StateError('Solver state limit exceeded: $maxStates');
          }
          queue.add(
            _SearchNode(PuzzleState(level: level, blocks: blocks), [
              ...node.moves,
              PuzzleMove(block.id, target),
            ]),
          );
        }
      }
    }
    return null;
  }

  String _key(List<Block> blocks) => blocks
      .map((block) => '${block.position.x},${block.position.y}')
      .join(';');
}
