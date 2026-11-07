import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

const _all = {
  PuzzlePower.moonflowerLeap,
  PuzzlePower.lightSwap,
  PuzzlePower.seal,
  PuzzlePower.wind,
};

Level _level({
  int width = 5,
  int height = 1,
  Position start = const Position(0, 0),
  Position exit = const Position(4, 0),
  List<Block> blocks = const [],
  List<Position> obstacles = const [],
  Position? echoSwitch,
  Position? echoGate,
  Set<Position> holds = const {},
  Map<Position, Position> oneWays = const {},
  Set<Position> goalOnly = const {},
}) => Level(
  id: 900,
  boardWidth: width,
  boardHeight: height,
  startPosition: start,
  exitPosition: exit,
  blocks: blocks,
  obstacles: obstacles,
  minimumMoves: 1,
  difficulty: 'test',
  echoSwitch: echoSwitch,
  echoGate: echoGate,
  echoHolds: holds,
  oneWays: oneWays,
  goalOnlyTiles: goalOnly,
);

void main() {
  group('moonflower leap', () {
    test('jumps one rock, counts one move and is used up', () {
      final level = _level(obstacles: const [Position(1, 0)]);
      final controller = PuzzleController(level, powers: _all);
      expect(controller.move('goal', const Position(1, 0)), false);
      expect(
        controller.usePower(
          PuzzlePower.moonflowerLeap,
          'goal',
          const Position(1, 0),
        ),
        true,
      );
      final state = controller.state;
      expect(state.goal.position, const Position(2, 0));
      expect(state.moves, 1);
      expect(state.echo, const Position(0, 0));
      expect(state.powers.contains(PuzzlePower.moonflowerLeap), false);
      expect(controller.usedPower, true);
    });

    test('needs a rock to jump and a free landing', () {
      final open = _level();
      expect(
        PowerRules.landing(
          PuzzleState.initial(open, powers: _all),
          PuzzlePower.moonflowerLeap,
          'goal',
          const Position(1, 0),
        ),
        isNull,
      );
      final blockedLanding = _level(
        obstacles: const [Position(1, 0)],
        blocks: const [Block(id: 'b1', position: Position(2, 0))],
      );
      expect(
        PowerRules.landing(
          PuzzleState.initial(blockedLanding, powers: _all),
          PuzzlePower.moonflowerLeap,
          'goal',
          const Position(1, 0),
        ),
        isNull,
      );
      // 일반 블록은 출구에 내릴 수 없다.
      final ontoExit = _level(
        start: const Position(4, 0),
        exit: const Position(2, 0),
        blocks: const [Block(id: 'b1', position: Position(0, 0))],
        obstacles: const [Position(1, 0)],
      );
      expect(
        PowerRules.landing(
          PuzzleState.initial(ontoExit, powers: _all),
          PuzzlePower.moonflowerLeap,
          'b1',
          const Position(1, 0),
        ),
        isNull,
      );
    });

    test('respects the one-way arrow under the jumper', () {
      final level = _level(
        start: const Position(2, 0),
        exit: const Position(4, 0),
        obstacles: const [Position(1, 0), Position(3, 0)],
        oneWays: {Position(2, 0): Position(1, 0)},
      );
      final state = PuzzleState.initial(level, powers: _all);
      expect(
        PowerRules.landing(
          state,
          PuzzlePower.moonflowerLeap,
          'goal',
          const Position(-1, 0),
        ),
        isNull,
      );
      expect(
        PowerRules.landing(
          state,
          PuzzlePower.moonflowerLeap,
          'goal',
          const Position(1, 0),
        ),
        const Position(4, 0),
      );
    });
  });

  group('light swap', () {
    test('moves a block onto the echo and leaves a new echo', () {
      final level = _level(
        width: 4,
        height: 2,
        exit: const Position(3, 1),
        blocks: const [Block(id: 'b1', position: Position(3, 0))],
      );
      final controller = PuzzleController(level, powers: _all);
      expect(
        controller.usePower(PuzzlePower.lightSwap, 'b1', const Position(0, 0)),
        false,
        reason: 'no echo yet',
      );
      controller.move('goal', const Position(1, 0));
      expect(controller.state.echo, const Position(0, 0));
      expect(
        controller.usePower(PuzzlePower.lightSwap, 'b1', const Position(0, 0)),
        true,
      );
      expect(controller.state.positionOf('b1'), const Position(0, 0));
      expect(controller.state.echo, const Position(3, 0));
      expect(controller.state.moves, 2);
    });

    test('cannot swap a rune stone into a goal-only tile', () {
      final level = _level(
        width: 4,
        height: 2,
        start: const Position(1, 0),
        exit: const Position(3, 1),
        blocks: const [Block(id: 'b1', position: Position(3, 0))],
        goalOnly: {Position(0, 0)},
      );
      final controller = PuzzleController(level, powers: _all)
        ..move('goal', const Position(0, 0))
        ..move('goal', const Position(0, 1));
      expect(controller.state.echo, const Position(0, 0));
      expect(
        controller.usePower(PuzzlePower.lightSwap, 'b1', const Position(0, 0)),
        false,
      );
      expect(
        controller.usePower(
          PuzzlePower.lightSwap,
          'goal',
          const Position(0, 0),
        ),
        true,
      );
    });
  });

  group('seal', () {
    test('keeps the old echo for one more turn', () {
      final level = _level(width: 5, height: 2, exit: const Position(4, 1));
      final controller = PuzzleController(level, powers: _all)
        ..move('goal', const Position(1, 0));
      expect(controller.state.echo, const Position(0, 0));
      expect(
        controller.usePower(PuzzlePower.seal, 'goal', const Position(1, 0)),
        true,
      );
      expect(controller.state.goal.position, const Position(2, 0));
      expect(controller.state.echo, const Position(0, 0));
      controller.move('goal', const Position(3, 0));
      expect(controller.state.echo, const Position(2, 0));
    });

    test('needs an echo and keeps a gate open across two moves', () {
      final level = _level(
        width: 4,
        height: 3,
        start: const Position(1, 0),
        exit: const Position(3, 2),
        blocks: const [Block(id: 'b1', position: Position(0, 0))],
        echoSwitch: const Position(0, 0),
        echoGate: const Position(2, 1),
      );
      final fresh = PuzzleState.initial(level, powers: _all);
      expect(
        PowerRules.landing(
          fresh,
          PuzzlePower.seal,
          'goal',
          const Position(0, 1),
        ),
        isNull,
      );
      final controller = PuzzleController(level, powers: _all)
        ..move('b1', const Position(0, 1));
      expect(controller.state.isGateOpen, true);
      controller.usePower(PuzzlePower.seal, 'goal', const Position(0, 1));
      expect(controller.state.isGateOpen, true, reason: 'echo still on switch');
      expect(controller.move('goal', const Position(2, 1)), true);
    });
  });

  group('wind', () {
    test('slides until blocked and leaves the echo at the start', () {
      final level = _level(
        width: 5,
        height: 2,
        exit: const Position(4, 1),
        obstacles: const [Position(4, 0)],
      );
      final controller = PuzzleController(level, powers: _all);
      expect(
        controller.usePower(PuzzlePower.wind, 'goal', const Position(1, 0)),
        true,
      );
      expect(controller.state.goal.position, const Position(3, 0));
      expect(controller.state.echo, const Position(0, 0));
      expect(controller.state.moves, 1);
    });

    test('RIQ stops on the exit; stones stop before it', () {
      final level = _level(
        width: 6,
        exit: const Position(3, 0),
        blocks: const [Block(id: 'b1', position: Position(5, 0))],
      );
      final state = PuzzleState.initial(level, powers: _all);
      expect(
        PowerRules.landing(
          state,
          PuzzlePower.wind,
          'goal',
          const Position(1, 0),
        ),
        const Position(3, 0),
      );
      expect(
        PowerRules.landing(
          state,
          PuzzlePower.wind,
          'b1',
          const Position(-1, 0),
        ),
        const Position(4, 0),
      );
    });

    test('stops on an arrow tile that points elsewhere', () {
      final level = _level(
        width: 5,
        height: 2,
        exit: const Position(4, 1),
        oneWays: {Position(2, 0): Position(0, 1)},
      );
      final state = PuzzleState.initial(level, powers: _all);
      expect(
        PowerRules.landing(
          state,
          PuzzlePower.wind,
          'goal',
          const Position(1, 0),
        ),
        const Position(2, 0),
      );
    });
  });

  group('controller and solver', () {
    test('undo restores a spent power and restart restores all', () {
      final level = _level(obstacles: const [Position(1, 0)]);
      final controller = PuzzleController(level, powers: _all)
        ..usePower(PuzzlePower.moonflowerLeap, 'goal', const Position(1, 0));
      controller.undo();
      expect(controller.state.powers, _all);
      expect(controller.usedPower, false);
      controller
        ..usePower(PuzzlePower.moonflowerLeap, 'goal', const Position(1, 0))
        ..restart();
      expect(controller.state.powers, _all);
    });

    test('powers are inert in world 1 states', () {
      final level = _level(obstacles: const [Position(1, 0)]);
      final controller = PuzzleController(level);
      expect(
        controller.usePower(
          PuzzlePower.moonflowerLeap,
          'goal',
          const Position(1, 0),
        ),
        false,
      );
      expect(const PuzzleSolver().solve(level), isNull);
    });

    test('solver uses a power only when it helps and replays exactly', () {
      final level = _level(
        width: 5,
        height: 3,
        exit: const Position(4, 0),
        obstacles: const [Position(2, 0)],
      );
      final bare = const PuzzleSolver().solve(level)!;
      final powered = const PuzzleSolver().solve(level, powers: _all)!;
      expect(bare.length, 6);
      // 도약(→(3,0)) 또는 아래로 내려가 바람을 타는 3수.
      expect(powered.length, 3);
      expect(powered.any((move) => move.power != null), true);
      final controller = PuzzleController(level, powers: _all);
      for (final move in powered) {
        expect(controller.apply(move), true);
      }
      expect(controller.state.isComplete, true);
    });
  });
}
