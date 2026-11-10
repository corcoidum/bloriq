import 'package:bloriq/domain/mechanics/board_mechanic.dart';
import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/echo_eraser.dart';
import 'package:bloriq/domain/mechanics/echo_gate.dart';
import 'package:bloriq/domain/mechanics/echo_hold.dart';
import 'package:bloriq/domain/mechanics/goal_only.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/mechanics/one_way.dart';
import 'package:bloriq/domain/mechanics/shelf_door.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

const _goal = Level.goalBlockId;
const _start = Position(0, 1);
const _a = Position(1, 1);
const _b = Position(4, 3);
const _exit = Position(5, 0);
const _east = Position(1, 0);

Level _level({
  Position start = _start,
  List<Block> blocks = const [],
  List<Position> walls = const [],
  List<(Position, Position)> pairs = const [(_a, _b)],
  List<BoardMechanic> extras = const [],
}) => Level(
  id: 501,
  boardWidth: 6,
  boardHeight: 5,
  startPosition: start,
  exitPosition: _exit,
  blocks: blocks,
  obstacles: walls,
  minimumMoves: 0,
  difficulty: 'test',
  mechanics: [...extras, ShelfDoor(pairs)],
);

MirrorPair _mirror() => MirrorPair.parse({
  'blocks': [_goal, 'rune'],
});

PuzzleState _withEcho(Level level, {Set<PuzzlePower> powers = const {}}) =>
    PuzzleState(
      level: level,
      blocks: PuzzleState.initial(level).blocks,
      echo: _b,
      powers: powers,
    );

void main() {
  test('a single teleport preserves the input, turn, and departure echo', () {
    final controller = PuzzleController(_level());
    final before = controller.state;
    final previewHops = <MoveTeleport>[];
    final preview = previewMove(before, _goal, _a, teleports: previewHops)!;
    expect(preview.goal.position, _b);
    expect(controller.state, same(before));
    expect(controller.move(_goal, _a), isTrue);
    final move = controller.lastMove!;
    expect(move.landing, _a);
    expect(move.to, _b);
    expect(move.teleports, [(blockId: _goal, from: _a, to: _b)]);
    expect(previewHops, move.teleports);
    expect(controller.state.echo, _start);
    expect(controller.state.moves, 1);
    expect(controller.undo(), isTrue);
    expect(controller.state, same(before));
    expect(controller.lastMove, isNull);
  });

  test(
    'leaving the arrival shelf walks normally, reentering teleports back',
    () {
      final controller = PuzzleController(
        _level(
          blocks: [const Block(id: 'rune', position: Position(0, 4))],
        ),
      );
      const floor = Position(5, 3);
      expect(controller.move(_goal, _a), isTrue);
      expect(controller.move(_goal, floor), isTrue);
      expect(controller.lastMove!.teleports, isEmpty);
      expect(controller.state.echo, _b);
      expect(controller.move(_goal, _b), isFalse);
      expect(controller.move('rune', const Position(1, 4)), isTrue);
      expect(controller.move(_goal, _b), isTrue);
      expect(controller.lastMove!.to, _a);
      expect(controller.lastMove!.teleports.single.from, _b);
      expect(controller.state.echo, floor);
    },
  );

  test('a shelf endpoint changes the echo only when the main block leaves', () {
    for (final (mechanic, echo) in [
      (EchoHold({_b}), _start),
      (EchoEraser({_b}), null),
    ]) {
      final controller = PuzzleController(_level(extras: [mechanic]));
      expect(controller.move(_goal, _a), isTrue);
      expect(controller.state.goal.position, _b);
      expect(controller.state.echo, _start);
      expect(controller.move(_goal, const Position(5, 3)), isTrue);
      expect(controller.state.echo, echo);
    }
  });

  test(
    'a rock, occupied block, or previous echo at B leaves the move at A',
    () {
      final cases = [
        PuzzleState.initial(_level(walls: [_b])),
        PuzzleState.initial(
          _level(
            blocks: [const Block(id: 'rune', position: _b)],
          ),
        ),
        _withEcho(_level()),
      ];
      for (final before in cases) {
        final hops = <MoveTeleport>[];
        final after = previewMove(before, _goal, _a, teleports: hops)!;
        expect(after.goal.position, _a);
        expect(after.echo, _start);
        expect(after.moves, 1);
        expect(hops, isEmpty);
      }
    },
  );

  test('the reserved primary source blocks a jump to an adjacent shelf', () {
    final controller = PuzzleController(_level(pairs: [(_a, _start)]));
    expect(controller.move(_goal, _a), isTrue);
    expect(controller.state.goal.position, _a);
    expect(controller.state.echo, _start);
    expect(controller.lastMove!.teleports, isEmpty);
  });

  test('clover at B accepts RIQ and blocks a rune', () {
    final clover = GoalOnly({_b});
    final riq = PuzzleController(_level(extras: [clover]));
    expect(riq.move(_goal, _a), isTrue);
    expect(riq.state.goal.position, _b);

    final rune = PuzzleController(
      _level(
        start: const Position(0, 0),
        blocks: [const Block(id: 'rune', position: _start)],
        extras: [clover],
      ),
    );
    expect(rune.move('rune', _a), isTrue);
    expect(rune.state.positionOf('rune'), _a);
    expect(rune.lastMove!.teleports, isEmpty);
  });

  test('teleport uses the same closed-gate entry check', () {
    // 데이터는 이 겹침을 거부한다. 변환 훅은 닫힌 문도 진입 장애물로 본다.
    final shelf = ShelfDoor([(_a, _b)]);
    const crystal = Position(3, 3);
    final level = Level(
      id: 501,
      boardWidth: 6,
      boardHeight: 5,
      startPosition: _start,
      exitPosition: _exit,
      blocks: [],
      obstacles: [],
      minimumMoves: 0,
      difficulty: 'test',
      mechanics: [EchoGate(crystal, _b)],
    );
    final block = const Block(id: _goal, position: _a);
    expect(
      shelf.finishTeleport(
        PuzzleState.initial(level),
        [block],
        block,
        vacated: _start,
      ),
      _a,
    );
    final open = PuzzleState(
      level: level,
      blocks: PuzzleState.initial(level).blocks,
      echo: crystal,
    );
    expect(shelf.finishTeleport(open, [block], block, vacated: _start), _b);
  });

  test(
    'ice stops at the entrance before a teleport and clock advances once',
    () {
      const entrance = Position(3, 1);
      final clock = ClockArrow({const Position(5, 4): _east});
      final controller = PuzzleController(
        _level(
          pairs: [(entrance, _b)],
          extras: [
            clock,
            Ice({_a, const Position(2, 1), const Position(5, 3)}),
          ],
        ),
      );
      expect(controller.move(_goal, _a), isTrue);
      final move = controller.lastMove!;
      expect(move.landing, _a);
      expect(move.teleports.single.from, entrance);
      expect(move.to, _b);
      expect(move.nextEcho, _start);
      expect(ClockArrow.phaseAt(move.after.moves), 1);
      expect(controller.undo(), isTrue);
      expect(ClockArrow.phaseAt(controller.state.moves), 0);
    },
  );

  test(
    'mirror reads the primary destination when the twin enters its old shelf',
    () {
      final controller = PuzzleController(
        _level(
          blocks: [const Block(id: 'rune', position: Position(2, 1))],
          extras: [_mirror()],
        ),
      );
      expect(controller.move(_goal, _a), isTrue);
      expect(controller.state.goal.position, _b);
      expect(controller.state.positionOf('rune'), _a);
      expect(controller.lastMove!.teleports.single.blockId, _goal);
      expect(controller.state.echo, _start);
    },
  );

  test('a twin can slide to another pair and teleport in the same turn', () {
    const twinEntrance = Position(2, 2);
    const twinExit = Position(2, 3);
    final controller = PuzzleController(
      _level(
        blocks: [const Block(id: 'rune', position: Position(5, 2))],
        pairs: [(_a, _b), (twinEntrance, twinExit)],
        extras: [
          _mirror(),
          Ice({const Position(4, 2), const Position(3, 2)}),
        ],
      ),
    );
    expect(controller.move(_goal, _a), isTrue);
    expect(controller.state.goal.position, _b);
    expect(controller.state.positionOf('rune'), twinExit);
    expect(controller.lastMove!.teleports, [
      (blockId: _goal, from: _a, to: _b),
      (blockId: 'rune', from: twinEntrance, to: twinExit),
    ]);
    expect(controller.state.moves, 1);
    expect(controller.state.echo, _start);
  });

  test(
    'a twin can return to its own vacated shelf because it leaves no echo',
    () {
      const entrance = Position(3, 3);
      final controller = PuzzleController(
        _level(
          blocks: [const Block(id: 'rune', position: _b)],
          pairs: [(entrance, _b)],
          extras: [_mirror()],
        ),
      );
      expect(controller.move(_goal, _a), isTrue);
      final move = controller.lastMove!;
      expect(move.after.positionOf('rune'), _b);
      expect(move.teleports, [(blockId: 'rune', from: entrance, to: _b)]);
      expect(move.nextEcho, _start);
    },
  );

  test(
    'leap landing and wind stop teleport, light swap placement does not',
    () {
      const leap = PuzzlePower.moonflowerLeap;
      const wind = PuzzlePower.wind;
      const swap = PuzzlePower.lightSwap;
      const leapLanding = Position(2, 1);
      const windStop = Position(3, 1);
      final leapController = PuzzleController(
        _level(walls: [_a], pairs: [(leapLanding, _b)]),
        powers: {leap},
      );
      final windController = PuzzleController(
        _level(
          walls: [const Position(4, 1)],
          pairs: [(windStop, _b), (_a, const Position(1, 4))],
        ),
        powers: {wind},
      );
      for (final (controller, power, landing) in [
        (leapController, leap, leapLanding),
        (windController, wind, windStop),
      ]) {
        expect(controller.usePower(power, _goal, _east), isTrue);
        expect(controller.state.goal.position, _b);
        expect(controller.lastMove!.landing, landing);
        expect(controller.state.moves, 1);
        expect(controller.state.echo, _start);
        expect(controller.state.powers, isEmpty);
      }
      final before = _withEcho(_level(), powers: {swap});
      final hops = <MoveTeleport>[];
      final swapped = previewPower(
        before,
        swap,
        _goal,
        _east,
        teleports: hops,
      )!;
      expect(swapped.goal.position, _b);
      expect(swapped.echo, _start);
      expect(hops, isEmpty);
    },
  );

  test(
    'wind passes a clock arrow, teleports once and leaves its twin still',
    () {
      const twin = Position(4, 2);
      const windStop = Position(3, 1);
      final controller = PuzzleController(
        _level(
          blocks: [const Block(id: 'rune', position: twin)],
          walls: [const Position(4, 1)],
          pairs: [(windStop, _b)],
          extras: [
            _mirror(),
            ClockArrow({_a: _east}),
          ],
        ),
        powers: {PuzzlePower.wind},
      );
      expect(controller.usePower(PuzzlePower.wind, _goal, _east), isTrue);
      expect(controller.lastMove!.landing, windStop);
      expect(controller.lastMove!.teleports, [
        (blockId: _goal, from: windStop, to: _b),
      ]);
      expect(controller.state.goal.position, _b);
      expect(controller.state.positionOf('rune'), twin);
      expect(controller.state.echo, _start);
      expect(controller.state.moves, 1);
      expect(controller.state.canLeave(_a, const Position(0, 1)), isTrue);
    },
  );

  test('shelves reject forbidden overlaps and invalid endpoints', () {
    for (final rule in [
      Ice({_b}),
      OneWay({_b: _east}),
      ClockArrow({_b: _east}),
      EchoGate(_b, const Position(3, 4)),
      EchoGate(const Position(3, 4), _b),
    ]) {
      expect(
        () => _level(extras: [rule]),
        throwsFormatException,
        reason: rule.type,
      );
    }
    for (final pairs in <List<(Position, Position)>>[
      [],
      [(_a, _exit)],
      [(_a, _a)],
      [(_a, _b), (_a, const Position(2, 2))],
      [(_a, const Position(6, 4))],
      [
        (_a, _b),
        (const Position(2, 2), const Position(2, 3)),
        (const Position(3, 2), const Position(3, 3)),
      ],
    ]) {
      expect(() => _level(pairs: pairs), throwsFormatException);
    }
    expect(
      () => ShelfDoor.parse({
        'pairs': [
          {
            'a': {'x': 0, 'y': 0},
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('reorientation keeps each shelf linked to its own partner', () {
    final shelf = ShelfDoor([
      (_a, _b),
      (const Position(2, 2), const Position(3, 3)),
    ]);
    Position point(Position p) => Position(5 - p.x, p.y);
    expect(shelf.reorient(point, (p) => p).pairs, [
      for (final (a, b) in shelf.pairs) (point(a), point(b)),
    ]);
  });
}
