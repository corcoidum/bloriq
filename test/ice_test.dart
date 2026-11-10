import 'package:bloriq/domain/mechanics/board_mechanic.dart';
import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_pool.dart';
import 'package:flutter_test/flutter_test.dart';

const _goal = Level.goalBlockId;
const _start = Position(0, 1);
const _first = Position(1, 1);
const _second = Position(2, 1);
const _stop = Position(3, 1);
const _east = Position(1, 0);
const _south = Position(0, 1);
const _pair = {
  'type': 'mirrorPair',
  'blocks': ['b1', 'b2'],
};

Level _level({
  Position start = _start,
  Position exit = const Position(4, 4),
  Set<Position>? ice,
  List<Block> blocks = const [],
  List<Position> rocks = const [],
  Set<Position> erasers = const {},
  Set<Position> holds = const {},
  Set<Position> clovers = const {},
  Map<Position, Position> streams = const {},
  Position? echoSwitch,
  Position? echoGate,
  List<BoardMechanic> extra = const [],
}) => Level(
  id: 401,
  world: 5,
  boardWidth: 5,
  boardHeight: 5,
  startPosition: start,
  exitPosition: exit,
  blocks: blocks,
  obstacles: rocks,
  minimumMoves: 0,
  difficulty: 'test',
  mechanics: [
    Ice(ice ?? {_first, _second}),
    ...extra,
  ],
  echoErasers: erasers,
  echoHolds: holds,
  goalOnlyTiles: clovers,
  oneWays: streams,
  echoSwitch: echoSwitch,
  echoGate: echoGate,
);

PuzzleState _withEcho(
  Level level,
  Position echo, {
  Set<PuzzlePower> powers = const {},
}) => PuzzleState(
  level: level,
  blocks: PuzzleState.initial(level).blocks,
  powers: powers,
  echo: echo,
);

void main() {
  test('a slide leaves one echo and stops on the first non-ice tile', () {
    final controller = PuzzleController(_level());
    final before = controller.state;
    final preview = previewMove(before, _goal, _first)!;
    expect(preview.goal.position, _stop);
    expect(controller.state, same(before));
    expect(controller.move(_goal, _first), isTrue);
    expect(controller.lastMove!.landing, _first);
    expect(controller.lastMove!.to, _stop);
    expect(controller.state.echo, _start);
    expect(controller.state.moves, 1);
    expect(controller.undo(), isTrue);
    expect(controller.state, same(before));
    controller.move(_goal, _first);
    controller.restart();
    expect(controller.state.goal.position, _start);
    expect(controller.state.moves, 0);
    expect(controller.state.echo, isNull);
  });

  test('an ordinary landing is one cell even if ice is one cell farther', () {
    final before = PuzzleState.initial(_level(ice: {_second}));
    expect(previewMove(before, _goal, _first)!.goal.position, _first);
  });

  test('a wall, block, board edge and previous echo stop a slide on ice', () {
    final blocker = Block(id: 'b1', position: _stop);
    final cases = [
      (PuzzleState.initial(_level(rocks: const [_stop])), _first, _second),
      (PuzzleState.initial(_level(blocks: [blocker])), _first, _second),
      (_withEcho(_level(), _stop), _first, _second),
      (
        PuzzleState.initial(
          _level(start: _second, ice: {_stop, const Position(4, 1)}),
        ),
        _stop,
        const Position(4, 1),
      ),
    ];
    for (final (before, landing, end) in cases) {
      final after = previewMove(before, _goal, landing)!;
      expect(after.goal.position, end);
      expect(after.moves, 1);
    }
    expect(previewMove(_withEcho(_level(), _first), _goal, _first), isNull);
  });

  test('only RIQ enters the star through a slide and stops even on ice', () {
    final controller = PuzzleController(
      _level(exit: _second, ice: {_first, _second, _stop}),
    );
    expect(controller.move(_goal, _first), isTrue);
    expect(controller.state.goal.position, _second);
    expect(controller.state.isComplete, isTrue);
    expect(controller.state.moves, 1);

    final rune = PuzzleState.initial(
      _level(
        start: const Position(0, 0),
        exit: _second,
        blocks: const [Block(id: 'b1', position: _start)],
      ),
    );
    expect(previewMove(rune, 'b1', _first)!.positionOf('b1'), _first);
  });

  test(
    'leaving eraser or hold affects only the echo at the original source',
    () {
      const old = Position(0, 4);
      final eraser = _withEcho(_level(erasers: {_start}), old);
      final hold = _withEcho(_level(holds: {_start}), old);
      for (final (before, echo) in [(eraser, null), (hold, old)]) {
        final after = previewMove(before, _goal, _first)!;
        expect(after.goal.position, _stop);
        expect(after.echo, echo);
      }
      final before = PuzzleState.initial(_level(erasers: {_stop}));
      final landing = previewMove(before, _goal, _first)!;
      expect(landing.echo, _start);
      expect(previewMove(landing, _goal, const Position(3, 2))!.echo, isNull);
    },
  );

  test('a slide uses clover and gate entry rules from before the move', () {
    final rune = PuzzleState.initial(
      _level(
        start: const Position(0, 0),
        clovers: {_stop},
        blocks: const [Block(id: 'b1', position: _start)],
      ),
    );
    expect(previewMove(rune, 'b1', _first)!.positionOf('b1'), _second);
    final riq = PuzzleState.initial(_level(clovers: {_stop}));
    expect(previewMove(riq, _goal, _first)!.goal.position, _stop);

    final controller = PuzzleController(
      _level(echoSwitch: _start, echoGate: _stop),
    );
    expect(controller.move(_goal, _first), isTrue);
    expect(controller.state.goal.position, _second);
    expect(controller.state.isGateOpen, isTrue);
    expect(controller.move(_goal, _stop), isTrue);
    expect(controller.state.goal.position, _stop);
    expect(controller.state.isGateOpen, isFalse);
  });

  test('both mirror twins slide in one turn and undo restores both', () {
    final controller = PuzzleController(
      _level(
        start: const Position(0, 0),
        ice: {_first, _second, const Position(3, 3), const Position(2, 3)},
        blocks: const [
          Block(id: 'b1', position: _start),
          Block(id: 'b2', position: Position(4, 3)),
        ],
        // JSON 순서보다 레지스트리의 얼음 → 짝 순서가 우선한다.
        extra: [
          MirrorPair.parse(_pair),
          ClockArrow({const Position(2, 0): _east}),
        ],
      ),
    );
    final before = controller.state;
    expect(controller.move('b1', _first), isTrue);
    expect(controller.state.positionOf('b1'), _stop);
    expect(controller.state.positionOf('b2'), const Position(1, 3));
    expect(controller.state.echo, _start);
    expect(ClockArrow.phaseAt(controller.state.moves), 1);
    expect(controller.undo(), isTrue);
    expect(controller.state, same(before));
  });

  test('the primary stop blocks its twin before the twin starts sliding', () {
    final controller = PuzzleController(
      _level(
        start: const Position(0, 0),
        ice: {_first, _second, _stop},
        blocks: const [
          Block(id: 'b1', position: _start),
          Block(id: 'b2', position: Position(4, 1)),
        ],
        extra: [MirrorPair.parse(_pair)],
      ),
    );
    expect(controller.move('b1', _first), isTrue);
    expect(controller.state.positionOf('b1'), _stop);
    expect(controller.state.positionOf('b2'), const Position(4, 1));
  });

  test('RIQ following as a twin can slide into the star', () {
    const exit = Position(2, 3);
    final controller = PuzzleController(
      _level(
        start: const Position(4, 3),
        exit: exit,
        ice: {
          _first,
          _second,
          const Position(3, 3),
          exit,
          const Position(1, 3),
        },
        blocks: const [Block(id: 'b1', position: _start)],
        extra: [
          MirrorPair.parse({
            'type': 'mirrorPair',
            'blocks': ['b1', _goal],
          }),
        ],
      ),
    );
    expect(controller.move('b1', _first), isTrue);
    expect(controller.state.goal.position, exit);
    expect(controller.state.isComplete, isTrue);
    expect(controller.state.moves, 1);
  });

  test(
    'the clock ticks once and an arrow only restricts the next departure',
    () {
      final controller = PuzzleController(
        _level(
          extra: [
            ClockArrow({_stop: _east}),
          ],
        ),
      );
      expect(controller.move(_goal, _first), isTrue);
      expect(controller.state.goal.position, _stop);
      expect(ClockArrow.phaseAt(controller.state.moves), 1);
      expect(controller.move(_goal, const Position(4, 1)), isFalse);
      expect(controller.state.moves, 1);
      expect(controller.move(_goal, const Position(3, 2)), isTrue);
      expect(ClockArrow.phaseAt(controller.state.moves), 2);

      final stream = PuzzleController(_level(streams: {_stop: _south}));
      expect(stream.move(_goal, _first), isTrue);
      expect(stream.state.goal.position, _stop);
      expect(stream.move(_goal, const Position(4, 1)), isFalse);
    },
  );

  test('wind crosses non-ice and does not slide again at its own stop', () {
    final beyond = PuzzleController(_level(), powers: const {PuzzlePower.wind});
    expect(beyond.usePower(PuzzlePower.wind, _goal, _east), isTrue);
    expect(beyond.state.goal.position, const Position(4, 1));
    final onIce = PuzzleController(
      _level(rocks: const [_stop]),
      powers: const {PuzzlePower.wind},
    );
    expect(onIce.usePower(PuzzlePower.wind, _goal, _east), isTrue);
    expect(onIce.lastMove!.landing, _second);
    expect(onIce.lastMove!.to, _second);
    expect(onIce.state.moves, 1);
  });

  test(
    'leap continues from its ice landing and leaves only the takeoff echo',
    () {
      final controller = PuzzleController(
        _level(rocks: const [_first], ice: {_second, _stop}),
        powers: const {PuzzlePower.moonflowerLeap},
      );
      expect(
        controller.usePower(PuzzlePower.moonflowerLeap, _goal, _east),
        isTrue,
      );
      expect(controller.lastMove!.landing, _second);
      expect(controller.lastMove!.to, const Position(4, 1));
      expect(controller.state.echo, _start);
      expect(controller.state.moves, 1);
    },
  );

  test(
    'light swap arrives on ice without sliding; seal slides and holds echo',
    () {
      final swap = _withEcho(
        _level(),
        _first,
        powers: const {PuzzlePower.lightSwap},
      );
      final swapped = previewPower(swap, PuzzlePower.lightSwap, _goal, _east)!;
      expect(swapped.goal.position, _first);
      expect(swapped.echo, _start);
      expect(swapped.moves, 1);
      const old = Position(1, 3);
      final seal = _withEcho(_level(), old, powers: const {PuzzlePower.seal});
      final sealed = previewPower(seal, PuzzlePower.seal, _goal, _east)!;
      expect(sealed.goal.position, _stop);
      expect(sealed.echo, old);
      expect(sealed.moves, 1);
    },
  );

  test(
    'rejects overlaps with fixed and clock arrows and invalid ice cells',
    () {
      expect(() => _level(streams: {_first: _east}), throwsFormatException);
      expect(
        () => _level(
          extra: [
            ClockArrow({_first: _east}),
          ],
        ),
        throwsFormatException,
      );
      expect(() => _level(ice: {const Position(5, 1)}), throwsFormatException);
      expect(() => _level(ice: const {}), throwsFormatException);
      const point = {'x': 1, 'y': 1};
      expect(
        () => Ice.parse({
          'positions': [point, point],
        }),
        throwsFormatException,
      );
    },
  );

  test('reflection transforms ice coordinates with the board', () {
    final reflected = transformLevel(_level(), 4);
    expect(reflected.mechanic<Ice>(Ice.typeId)!.positions, {
      const Position(3, 1),
      const Position(2, 1),
    });
    final controller = PuzzleController(reflected);
    expect(controller.move(_goal, const Position(3, 1)), isTrue);
    expect(controller.state.goal.position, const Position(1, 1));
  });
}
