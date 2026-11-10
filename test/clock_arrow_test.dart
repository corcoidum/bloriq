import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_pool.dart';
import 'package:flutter_test/flutter_test.dart';

const _east = Position(1, 0);
const _south = Position(0, 1);
const _west = Position(-1, 0);
const _north = Position(0, -1);
const _start = Position(0, 1);
const _goal = Level.goalBlockId;

Level _board(
  Map<Position, Position> arrows, {
  List<Block> blocks = const [],
  List<Position> rocks = const [],
  bool mirror = false,
}) => Level(
  id: 1,
  boardWidth: 5,
  boardHeight: 5,
  startPosition: _start,
  exitPosition: const Position(4, 4),
  blocks: blocks,
  obstacles: rocks,
  minimumMoves: 0,
  difficulty: 'test',
  mechanics: [
    ClockArrow(arrows),
    if (mirror)
      MirrorPair.parse({
        'type': 'mirrorPair',
        'blocks': ['b1', 'b2'],
      }),
  ],
);

void main() {
  test('cardinal arrows turn clockwise in screen coordinates and wrap', () {
    const bases = [_east, _south, _west, _north];
    for (final (index, base) in bases.indexed) {
      final level = _board({_start: base});
      final clock = level.mechanic<ClockArrow>(ClockArrow.typeId)!;
      for (var moves = 0; moves <= 4; moves++) {
        final state = PuzzleState(level: level, blocks: const [], moves: moves);
        expect(clock.stateKey(state), moves % 4);
        expect(
          cardinalDirections.where(
            (direction) => state.canLeave(_start, direction),
          ),
          [bases[(index + moves) % 4]],
        );
      }
    }
  });

  test(
    'only the old phase restricts leaving; entry is free, failed moves stay',
    () {
      const second = Position(1, 1);
      final controller = PuzzleController(
        _board({_start: _east, second: _north}),
      );
      final start = controller.state;
      expect(controller.move(_goal, const Position(0, 2)), isFalse);
      expect(controller.state, same(start));
      // (1,1)의 t=0 화살표는 위쪽이어도 왼쪽에서 들어갈 수 있다.
      expect(controller.move(_goal, second), isTrue);
      final entered = controller.state;
      expect(ClockArrow.phaseAt(entered.moves), 1);
      expect(controller.move(_goal, const Position(1, 0)), isFalse);
      expect(controller.state, same(entered));
      // t=1에서 북쪽 화살표가 동쪽을 가리킨다.
      expect(controller.move(_goal, const Position(2, 1)), isTrue);
      expect(ClockArrow.phaseAt(controller.state.moves), 2);
      expect(controller.undo(), isTrue);
      expect(controller.state, same(entered));
      expect(controller.move(_goal, const Position(2, 1)), isTrue);
      controller.restart();
      expect(controller.state.moves, 0);
      expect(controller.state.goal.position, _start);
    },
  );

  test('a leap, seal and directionless swap each spend one phase', () {
    final leap = PuzzleController(
      _board({_start: _east}, rocks: const [Position(1, 1)]),
      powers: const {PuzzlePower.moonflowerLeap},
    );
    expect(leap.usePower(PuzzlePower.moonflowerLeap, _goal, _south), isFalse);
    expect(leap.state.moves, 0);
    expect(leap.usePower(PuzzlePower.moonflowerLeap, _goal, _east), isTrue);
    expect(leap.state.goal.position, const Position(2, 1));
    expect(leap.state.moves, 1);

    const helper = Block(id: 'b1', position: Position(3, 1));
    final seal = PuzzleController(
      _board({_start: _north}, blocks: const [helper]),
      powers: const {PuzzlePower.seal},
    )..move('b1', const Position(3, 2));
    expect(seal.usePower(PuzzlePower.seal, _goal, _south), isFalse);
    expect(seal.state.moves, 1);
    expect(seal.usePower(PuzzlePower.seal, _goal, _east), isTrue);
    expect(seal.state.echo, helper.position);
    expect(seal.state.moves, 2);

    final swap = PuzzleController(
      _board({_start: _east}, blocks: const [helper]),
      powers: const {PuzzlePower.lightSwap},
    )..move('b1', const Position(3, 2));
    // 물길과 마찬가지로 빛 교대는 방향을 쓰지 않는 순간이동이다.
    expect(swap.usePower(PuzzlePower.lightSwap, _goal, _east), isTrue);
    expect(swap.state.goal.position, helper.position);
    expect(swap.state.moves, 2);
  });

  test('wind uses the old phase across every tile and ticks once', () {
    const stop = Position(2, 1);
    final controller = PuzzleController(
      _board({const Position(1, 1): _east, stop: _north}),
      powers: const {PuzzlePower.wind},
    );
    expect(controller.usePower(PuzzlePower.wind, _goal, _east), isTrue);
    expect(controller.state.goal.position, stop);
    expect(controller.state.moves, 1);
    expect(controller.state.canLeave(stop, _east), isTrue);
  });

  test('a mirror twin uses the same pre-move clock and never adds a tick', () {
    const twin = Position(4, 1);
    for (final (arrow, expected) in [
      (_west, const Position(3, 1)),
      (_south, twin),
    ]) {
      final controller = PuzzleController(
        _board(
          {twin: arrow},
          blocks: const [
            Block(id: 'b1', position: Position(1, 1)),
            Block(id: 'b2', position: twin),
          ],
          mirror: true,
        ),
      );
      expect(controller.move('b1', const Position(2, 1)), isTrue);
      expect(controller.state.positionOf('b2'), expected);
      expect(controller.state.moves, 1);
      expect(controller.undo(), isTrue);
      expect(controller.state.positionOf('b2'), twin);
      expect(controller.state.moves, 0);
    }
  });

  test('BFS keeps two identical arrangements at different phases', () {
    const start = Position(0, 0);
    const exit = Position(1, 0);
    const helper = Block(id: 'b1', position: Position(2, 1));
    const other = Position(3, 1);
    final level = Level(
      id: 1,
      boardWidth: 4,
      boardHeight: 2,
      startPosition: start,
      exitPosition: exit,
      blocks: const [helper],
      obstacles: const [
        Position(0, 1),
        Position(1, 1),
        Position(2, 0),
        Position(3, 0),
      ],
      echoErasers: {helper.position, other},
      minimumMoves: 3,
      difficulty: 'test',
      mechanics: [
        ClockArrow({start: _west}),
      ],
    );
    final path = const PuzzleSolver().solve(level)!;
    expect(path.map((move) => move.target), [other, helper.position, exit]);
    // 대칭은 회전 방향을 뒤집으므로 시곗바늘 판은 회전만 사용한다.
    expect(transformLevel(level, 4), same(level));
    expect(const PuzzleSolver().solve(transformLevel(level, 5)), hasLength(3));
  });
}
