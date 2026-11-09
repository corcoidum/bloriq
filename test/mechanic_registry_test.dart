import 'package:bloriq/domain/mechanics/board_mechanic.dart';
import 'package:bloriq/domain/mechanics/mechanic_registry.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the five published mechanics are registered by JSON type', () {
    expect(
      MechanicRegistry.parsers.keys,
      containsAll(['echoEraser', 'echoHold', 'oneWay', 'goalOnly', 'echoGate']),
    );
  });

  test('invalid mechanic data throws a FormatException', () {
    for (final rule in [
      {'type': 'unknown'},
      {
        'type': 'echoEraser',
        'positions': [
          {'x': '1', 'y': 0},
        ],
      },
      {
        'type': 'echoGate',
        'switch': {'x': 1, 'y': 0},
      },
      {
        'type': 'oneWay',
        'tiles': [
          {'x': 1, 'y': 0, 'dx': 1, 'dy': 1},
        ],
      },
    ]) {
      expect(
        () => Level.fromJson({
          'id': 1,
          'boardWidth': 3,
          'boardHeight': 3,
          'startPosition': {'x': 0, 'y': 0},
          'exitPosition': {'x': 2, 'y': 0},
          'blocks': [],
          'obstacles': [],
          'minimumMoves': 2,
          'difficulty': 'test',
          'specialRules': [rule],
        }),
        throwsFormatException,
        reason: rule.toString(),
      );
    }
  });

  test(
    'controller, preview and solver transform a power landing before echo',
    () {
      final level = Level(
        id: 1,
        boardWidth: 4,
        boardHeight: 2,
        startPosition: const Position(0, 0),
        exitPosition: const Position(3, 0),
        blocks: const [],
        obstacles: const [Position(1, 0)],
        minimumMoves: 1,
        difficulty: 'test',
        mechanics: const [_LandingProbe()],
      );
      const powers = {PuzzlePower.moonflowerLeap};
      final controller = PuzzleController(level, powers: powers);
      final preview = previewPower(
        controller.state,
        PuzzlePower.moonflowerLeap,
        Level.goalBlockId,
        const Position(1, 0),
      )!;
      final path = const PuzzleSolver().solve(level, powers: powers)!;
      expect(path, hasLength(1));
      expect(path.single.target, const Position(2, 0));
      expect(preview.goal.position, level.exitPosition);
      expect(preview.echo, isNull);
      expect(controller.apply(path.single), isTrue);
      expect(controller.state.isComplete, isTrue);
      expect(controller.lastMove!.to, level.exitPosition);
      expect(controller.state.echo, preview.echo);
      expect(controller.undo(), isTrue);
      expect(controller.state.powers, powers);
    },
  );

  test('a mechanic can distinguish the same position on different turns', () {
    final level = Level(
      id: 1,
      boardWidth: 3,
      boardHeight: 1,
      startPosition: const Position(0, 0),
      exitPosition: const Position(2, 0),
      blocks: const [],
      obstacles: const [],
      echoErasers: {const Position(0, 0), const Position(1, 0)},
      minimumMoves: 4,
      difficulty: 'test',
      mechanics: const [_TimedExit()],
    );
    final path = const PuzzleSolver().solve(level)!;
    expect(path.map((move) => move.target), const [
      Position(1, 0),
      Position(0, 0),
      Position(1, 0),
      Position(2, 0),
    ]);
  });
}

// 새 게임 규칙을 도입하지 않고 훅의 순서와 공통 상태 전이만 검사한다.
class _LandingProbe extends BoardMechanic {
  const _LandingProbe();

  @override
  String get type => 'testLanding';

  @override
  List<Block> transformMove(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
  ) => move.target == const Position(2, 0)
      ? [blocks.single.at(before.level.exitPosition)]
      : blocks;

  @override
  Position? nextEcho(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
    Position? echo,
  ) => blocks.single.position == before.level.exitPosition ? null : echo;
}

class _TimedExit extends BoardMechanic {
  const _TimedExit();

  @override
  String get type => 'testTimedExit';

  @override
  bool canEnter(PuzzleState state, String? blockId, Position target) =>
      target != state.level.exitPosition || state.moves % 4 == 3;

  @override
  int stateKey(PuzzleState state) => state.moves % 4;
}
