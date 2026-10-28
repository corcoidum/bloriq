import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

Level tutorial() => Level(
  id: 1,
  boardWidth: 3,
  boardHeight: 3,
  startPosition: const Position(0, 1),
  exitPosition: const Position(2, 1),
  blocks: const [
    Block(id: 'a', position: Position(1, 1)),
    Block(id: 'b', position: Position(2, 2)),
  ],
  obstacles: const [],
  minimumMoves: 4,
  difficulty: 'beginner',
);

void main() {
  group('잔상 스위치와 문', () {
    Level gateLevel() => Level(
      id: 11,
      boardWidth: 4,
      boardHeight: 2,
      startPosition: const Position(0, 1),
      exitPosition: const Position(3, 1),
      blocks: const [Block(id: 'a', position: Position(0, 0))],
      obstacles: const [Position(2, 0), Position(3, 0)],
      minimumMoves: 4,
      difficulty: 'beginner',
      echoSwitch: const Position(0, 0),
      echoGate: const Position(1, 1),
    );

    test('잔상이 스위치에 있을 때만 문으로 들어가고 닫힌 문에서 나갈 수 있다', () {
      final game = PuzzleController(gateLevel());
      expect(game.state.isGateOpen, isFalse);
      expect(game.move('goal', const Position(1, 1)), isFalse);
      expect(game.move('a', const Position(1, 0)), isTrue);
      expect(game.state.isGateOpen, isTrue);
      // A rejected move does not use up the open turn.
      expect(game.move('a', const Position(2, 0)), isFalse);
      expect(game.state.isGateOpen, isTrue);
      expect(game.move('goal', const Position(1, 1)), isTrue);
      expect(game.state.isGateOpen, isFalse);
      expect(game.state.goal.position, const Position(1, 1));
      expect(game.move('goal', const Position(2, 1)), isTrue);
      expect(game.move('goal', const Position(1, 1)), isFalse);
      expect(game.move('goal', const Position(3, 1)), isTrue);
      expect(game.state.isComplete, isTrue);
    });

    test('undo와 restart는 문 상태도 잔상과 함께 복원한다', () {
      final game = PuzzleController(gateLevel());
      game.move('a', const Position(1, 0));
      game.move('goal', const Position(1, 1));
      expect(game.state.isGateOpen, isFalse);
      expect(game.undo(), isTrue);
      expect(game.state.isGateOpen, isTrue);
      expect(game.state.echo, const Position(0, 0));
      expect(game.state.goal.position, const Position(0, 1));
      game.restart();
      expect(game.state.isGateOpen, isFalse);
      expect(game.state.echo, isNull);
    });

    test('solver가 문이 열리는 한 턴을 사용해 탈출한다', () {
      final level = gateLevel();
      final solution = const PuzzleSolver().solve(level);
      expect(solution, hasLength(4));
      final game = PuzzleController(level);
      for (final move in solution!) {
        expect(game.move(move.blockId, move.target), isTrue);
      }
      expect(game.state.isComplete, isTrue);
    });

    test('규칙 JSON을 읽고 중복 또는 알 수 없는 규칙은 거부한다', () {
      Map<String, dynamic> data(List<dynamic> rules) => {
        'id': 11,
        'boardWidth': 4,
        'boardHeight': 2,
        'startPosition': {'x': 0, 'y': 1},
        'exitPosition': {'x': 3, 'y': 1},
        'blocks': [
          {'id': 'a', 'x': 0, 'y': 0},
        ],
        'obstacles': [
          {'x': 2, 'y': 0},
          {'x': 3, 'y': 0},
        ],
        'minimumMoves': 4,
        'difficulty': 'beginner',
        'specialRules': rules,
      };
      final rule = {
        'type': 'echoGate',
        'switch': {'x': 0, 'y': 0},
        'gate': {'x': 1, 'y': 1},
      };
      final level = Level.fromJson(data([rule]));
      expect(level.echoSwitch, const Position(0, 0));
      expect(level.echoGate, const Position(1, 1));
      expect(() => Level.fromJson(data([rule, rule])), throwsFormatException);
      expect(
        () => Level.fromJson(
          data([
            {'type': 'unknown'},
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => Level.fromJson(
          data([
            {
              'type': 'echoGate',
              'switch': {'x': 0, 'y': 0},
              'gate': {'x': 0, 'y': 0},
            },
          ]),
        ),
        throwsFormatException,
      );
    });
  });

  group('ECHO BLOCK 이동', () {
    test('한 칸 이동의 출발점에 잔상이 남고 그 칸은 막힌다', () {
      final game = PuzzleController(tutorial());
      expect(game.move('a', const Position(1, 0)), isTrue);
      expect(game.state.echo, const Position(1, 1));
      expect(game.state.moves, 1);
      final afterMove = game.state;
      expect(game.move('goal', const Position(1, 1)), isFalse);
      expect(game.move('a', const Position(1, 1)), isFalse);
      expect(game.state, same(afterMove));
    });

    test('다음 유효한 이동이 끝나면 이전 잔상은 새 잔상으로 바뀐다', () {
      final game = PuzzleController(tutorial());
      expect(game.move('a', const Position(1, 0)), isTrue);
      expect(game.move('b', const Position(1, 2)), isTrue);
      expect(game.state.echo, const Position(2, 2));
      expect(game.move('goal', const Position(1, 1)), isTrue);
      expect(game.state.echo, const Position(0, 1));
      expect(game.move('goal', const Position(2, 1)), isTrue);
      expect(game.state.isComplete, isTrue);
      expect(game.move('b', const Position(0, 2)), isFalse);
    });

    test('잘못된 이동은 잔상과 상태를 보존한다', () {
      final game = PuzzleController(tutorial());
      game.move('a', const Position(1, 0));
      final before = game.state;
      expect(game.move('missing', const Position(0, 0)), isFalse);
      expect(game.move('a', const Position(1, -1)), isFalse);
      expect(game.move('a', const Position(2, 1)), isFalse);
      expect(game.move('b', const Position(2, 1)), isFalse);
      expect(game.state, same(before));
      expect(game.state.echo, const Position(1, 1));
    });

    test('undo와 restart는 블록, 잔상, 이동 수를 모두 복원한다', () {
      final game = PuzzleController(tutorial());
      expect(game.undo(), isFalse);
      game.move('a', const Position(1, 0));
      game.move('b', const Position(1, 2));
      expect(game.undo(), isTrue);
      expect(game.state.moves, 1);
      expect(game.state.echo, const Position(1, 1));
      expect(
        game.state.blocks.firstWhere((b) => b.id == 'b').position,
        const Position(2, 2),
      );
      expect(game.undo(), isTrue);
      expect(game.state.echo, isNull);
      expect(game.state.moves, 0);
      game.move('a', const Position(1, 2));
      game.restart();
      expect(game.canUndo, isFalse);
      expect(game.state.echo, isNull);
      expect(game.state.moves, 0);
      expect(
        game.state.blocks.firstWhere((b) => b.id == 'a').position,
        const Position(1, 1),
      );
    });
  });

  group('BFS solver', () {
    test('같은 블록 배치라도 잔상이 다르면 별도로 탐색한다', () {
      final level = Level(
        id: 4,
        boardWidth: 4,
        boardHeight: 3,
        startPosition: const Position(2, 2),
        exitPosition: const Position(0, 0),
        blocks: const [
          Block(id: 'a', position: Position(0, 1)),
          Block(id: 'b', position: Position(2, 0)),
        ],
        obstacles: const [Position(1, 1), Position(1, 2)],
        minimumMoves: 5,
        difficulty: 'beginner',
      );
      final solution = const PuzzleSolver().solve(level);
      expect(solution, hasLength(5));
      final game = PuzzleController(level);
      for (final move in solution!) {
        expect(game.move(move.blockId, move.target), isTrue);
      }
      expect(game.state.isComplete, isTrue);
    });

    test('잔상을 고려한 최소 해는 실제 게임에서도 완료된다', () {
      final level = tutorial();
      final solution = const PuzzleSolver().solve(level);
      expect(solution, isNotNull);
      expect(solution, hasLength(4));
      final game = PuzzleController(level);
      for (final move in solution!) {
        expect(game.move(move.blockId, move.target), isTrue);
      }
      expect(game.state.isComplete, isTrue);
    });

    test('해결할 수 없는 보드는 null을 반환한다', () {
      final level = Level(
        id: 3,
        boardWidth: 3,
        boardHeight: 1,
        startPosition: const Position(0, 0),
        exitPosition: const Position(2, 0),
        blocks: const [Block(id: 'a', position: Position(1, 0))],
        obstacles: const [],
        minimumMoves: 0,
        difficulty: 'beginner',
      );
      expect(const PuzzleSolver().solve(level), isNull);
    });

    test('탐색 제한은 해결 불가능으로 오인하지 않는다', () {
      expect(
        () => const PuzzleSolver(maxStates: 1).solve(tutorial()),
        throwsStateError,
      );
    });
  });

  test('겹치는 좌표 또는 예약된 목표 블록 ID를 가진 레벨은 거부한다', () {
    Level make(List<Block> blocks, List<Position> obstacles) => Level(
      id: 1,
      boardWidth: 3,
      boardHeight: 3,
      startPosition: const Position(0, 0),
      exitPosition: const Position(2, 2),
      blocks: blocks,
      obstacles: obstacles,
      minimumMoves: 0,
      difficulty: 'beginner',
    );
    expect(
      () => make(
        const [Block(id: 'a', position: Position(1, 1))],
        const [Position(1, 1)],
      ),
      throwsFormatException,
    );
    expect(
      () => make(const [Block(id: 'goal', position: Position(1, 1))], const []),
      throwsFormatException,
    );
  });
}
