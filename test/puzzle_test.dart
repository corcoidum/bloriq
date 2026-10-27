import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

Level corridor() => Level(
  id: 1,
  boardWidth: 3,
  boardHeight: 3,
  startPosition: const Position(0, 1),
  exitPosition: const Position(2, 1),
  blocks: const [Block(id: 'a', position: Position(1, 1))],
  obstacles: const [
    Position(0, 0),
    Position(2, 0),
    Position(0, 2),
    Position(2, 2),
  ],
  minimumMoves: 1,
  difficulty: 'beginner',
);

void main() {
  group('블록 이동', () {
    test('한 칸 이동은 횟수를 늘리고 잘못된 이동은 상태를 보존한다', () {
      final game = PuzzleController(corridor());
      final initial = game.state;
      expect(game.move('missing', const Position(1, 0)), isFalse);
      expect(game.move('a', const Position(1, -1)), isFalse);
      expect(game.move('a', const Position(0, 1)), isFalse);
      expect(game.move('a', const Position(0, 0)), isFalse);
      expect(game.state, same(initial));
      expect(game.move('a', const Position(1, 0)), isTrue);
      expect(game.state.moves, 1);
      expect(game.state.blocks.single.position, const Position(1, 0));
    });

    test('다른 블록과 겹칠 수 없다', () {
      final level = Level(
        id: 2,
        boardWidth: 4,
        boardHeight: 2,
        startPosition: const Position(0, 0),
        exitPosition: const Position(3, 0),
        blocks: const [
          Block(id: 'a', position: Position(1, 1)),
          Block(id: 'b', position: Position(2, 1)),
        ],
        obstacles: const [],
        minimumMoves: 0,
        difficulty: 'beginner',
      );
      expect(PuzzleController(level).move('a', const Position(2, 1)), isFalse);
    });

    test('undo와 restart는 이전 배치와 이동 횟수를 복구한다', () {
      final game = PuzzleController(corridor());
      expect(game.undo(), isFalse);
      expect(game.move('a', const Position(1, 0)), isTrue);
      expect(game.undo(), isTrue);
      expect(game.state.moves, 0);
      expect(game.state.blocks.single.position, const Position(1, 1));
      game.move('a', const Position(1, 2));
      game.restart();
      expect(game.canUndo, isFalse);
      expect(game.state.moves, 0);
      expect(game.state.path, isEmpty);
      expect(game.state.blocks.single.position, const Position(1, 1));
    });
  });

  group('탈출 경로', () {
    test('시작점, 인접성, 충돌, 중복 방문을 검증한다', () {
      final game = PuzzleController(corridor());
      expect(game.appendPath(const Position(1, 1)), isFalse);
      expect(game.appendPath(const Position(0, 1)), isTrue);
      expect(game.appendPath(const Position(1, 1)), isFalse);
      expect(game.appendPath(const Position(2, 1)), isFalse);
      expect(game.appendPath(const Position(0, 1)), isFalse);
      expect(game.state.isComplete, isFalse);
      game.clearPath();
      expect(game.state.path, isEmpty);
    });

    test('출구까지 유효하게 연결하면 클리어하고 추가 입력을 거부한다', () {
      final game = PuzzleController(corridor());
      game.move('a', const Position(1, 0));
      expect(game.appendPath(const Position(0, 1)), isTrue);
      expect(game.appendPath(const Position(1, 1)), isTrue);
      expect(game.appendPath(const Position(2, 1)), isTrue);
      expect(game.state.isComplete, isTrue);
      expect(game.appendPath(const Position(2, 2)), isFalse);
      expect(game.move('a', const Position(1, 1)), isFalse);
    });
  });

  group('BFS solver', () {
    test('최소 한 번 이동하는 해를 반환한다', () {
      final level = corridor();
      final solution = const PuzzleSolver().solve(level);
      expect(solution, isNotNull);
      expect(solution, hasLength(1));
      final game = PuzzleController(level);
      for (final move in solution!) {
        expect(game.move(move.blockId, move.target), isTrue);
      }
      expect(PathValidator.hasEscapePath(game.state), isTrue);
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
        () => const PuzzleSolver(maxStates: 1).solve(corridor()),
        throwsStateError,
      );
    });
  });

  test('중복 좌표인 레벨은 로드하지 않는다', () {
    expect(
      () => Level(
        id: 1,
        boardWidth: 3,
        boardHeight: 3,
        startPosition: const Position(0, 0),
        exitPosition: const Position(2, 2),
        blocks: const [Block(id: 'a', position: Position(1, 1))],
        obstacles: const [Position(1, 1)],
        minimumMoves: 0,
        difficulty: 'beginner',
      ),
      throwsFormatException,
    );
  });
}
