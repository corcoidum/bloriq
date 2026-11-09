import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = Position(1, 2);
const _landing = Position(2, 2);
const _twinStart = Position(4, 2);
const _twinLanding = Position(3, 2);

Map<String, int> _point(Position p) => {'x': p.x, 'y': p.y};

Level _level({
  Position goal = const Position(0, 0),
  Position exit = const Position(4, 0),
  Position twin = _twinStart,
  Map<String, Position> extra = const {},
  List<Position> walls = const [],
  List<List<Object?>> pairs = const [
    ['b1', 'b2'],
  ],
  List<Map<String, Object>> rules = const [],
}) => Level.fromJson({
  'id': 201,
  'boardWidth': 5,
  'boardHeight': 5,
  'startPosition': _point(goal),
  'exitPosition': _point(exit),
  'blocks': [
    for (final entry in {'b1': _source, 'b2': twin, ...extra}.entries)
      {'id': entry.key, ..._point(entry.value)},
  ],
  'obstacles': walls.map(_point).toList(),
  'minimumMoves': 0,
  'difficulty': 'test',
  'specialRules': [
    for (final pair in pairs) {'type': MirrorPair.typeId, 'blocks': pair},
    ...rules,
  ],
});

Map<String, Object> _gate(Position plate) => {
  'type': 'echoGate',
  'switch': _point(plate),
  'gate': _point(_twinLanding),
};

void main() {
  test('one turn records both shifts and only the pushed block echo', () {
    final controller = PuzzleController(_level());
    final initial = controller.state;
    final preview = previewMove(initial, 'b1', _landing)!;
    expect(preview.positionOf('b1'), _landing);
    expect(preview.positionOf('b2'), _twinLanding);
    expect(preview.echo, _source);
    expect(controller.state, same(initial));

    expect(controller.move('b1', _landing), isTrue);
    expect(controller.state.positionOf('b2'), _twinLanding);
    expect(controller.state.moves, 1);
    final move = controller.moveHistory.single;
    expect(move.before, same(initial));
    expect(move.after, same(controller.state));
    expect(MirrorPair.recordedShift(move), (
      blockId: 'b2',
      pair: 0,
      from: _twinStart,
      to: _twinLanding,
    ));
    expect(controller.undo(), isTrue);
    expect(controller.state, same(initial));
    expect(controller.moveHistory, isEmpty);
    expect(controller.move('b1', _landing), isTrue);
    controller.restart();
    expect(controller.state.positionOf('b1'), _source);
    expect(controller.state.positionOf('b2'), _twinStart);
    expect(controller.state.echo, isNull);
    expect(controller.state.moves, 0);
    expect(controller.moveHistory, isEmpty);
  });

  test('two disjoint pairs follow independently', () {
    final controller = PuzzleController(
      _level(
        extra: {'b3': const Position(1, 4), 'b4': const Position(4, 4)},
        pairs: const [
          ['b1', 'b2'],
          ['b3', 'b4'],
        ],
      ),
    );
    expect(controller.move('b1', _landing), isTrue);
    expect(controller.state.positionOf('b3'), const Position(1, 4));
    expect(controller.state.positionOf('b4'), const Position(4, 4));
    expect(controller.move('b4', const Position(3, 4)), isTrue);
    expect(controller.state.positionOf('b3'), const Position(2, 4));
    expect(controller.state.positionOf('b1'), _landing);
    expect(controller.state.positionOf('b2'), _twinLanding);
    expect(MirrorPair.recordedShift(controller.lastMove!)?.pair, 1);
  });

  test('invalid pair data is rejected', () {
    for (final pairs in <List<List<Object?>>>[
      [[]],
      [
        ['b1'],
      ],
      [
        ['b1', 'b2', 'goal'],
      ],
      [
        ['b1', 2],
      ],
      [
        ['b1', 'missing'],
      ],
      [
        ['b1', 'b1'],
      ],
      [
        ['b1', 'b2'],
        ['goal', 'b1'],
      ],
      [
        ['b1', 'b2'],
        ['b3', 'b4'],
        ['b5', 'goal'],
      ],
    ]) {
      expect(
        () => _level(
          pairs: pairs,
          extra: const {
            'b3': Position(1, 4),
            'b4': Position(2, 4),
            'b5': Position(3, 4),
          },
        ),
        throwsFormatException,
        reason: '$pairs',
      );
    }
  });

  test('a blocked primary push changes neither piece nor turn', () {
    final controller = PuzzleController(_level(walls: [_landing]));
    final before = controller.state;
    expect(controller.move('b1', _landing), isFalse);
    expect(controller.state, same(before));
    expect(controller.moveHistory, isEmpty);
  });

  final blocked = {
    'board edge': _level(twin: const Position(0, 2)),
    'rock': _level(walls: [_twinLanding]),
    'another block': _level(extra: {'b3': _twinLanding}),
    'primary block landing': _level(twin: _twinLanding),
    'stream direction': _level(
      rules: [
        {
          'type': 'oneWay',
          'tiles': [
            {..._point(_twinStart), 'dx': 1, 'dy': 0},
          ],
        },
      ],
    ),
    'clover': _level(
      rules: [
        {
          'type': 'goalOnly',
          'positions': [_point(_twinLanding)],
        },
      ],
    ),
    'closed gate': _level(rules: [_gate(const Position(0, 4))]),
  };
  for (final entry in blocked.entries) {
    test('the twin stays at a blocked ${entry.key}', () {
      final controller = PuzzleController(entry.value);
      final start = controller.state.positionOf('b2');
      expect(controller.move('b1', _landing), isTrue);
      expect(controller.state.positionOf('b1'), _landing);
      expect(controller.state.positionOf('b2'), start);
      expect(controller.state.echo, _source);
      expect(controller.state.moves, 1);
      expect(MirrorPair.recordedShift(controller.lastMove!), isNull);
    });
  }

  test('the previous echo blocks the twin until the turn finishes', () {
    final controller = PuzzleController(_level(extra: {'b3': _twinLanding}));
    expect(controller.move('b3', const Position(3, 3)), isTrue);
    expect(controller.state.echo, _twinLanding);
    expect(controller.move('b1', _landing), isTrue);
    expect(controller.state.positionOf('b2'), _twinStart);
    expect(controller.state.echo, _source);
  });

  test('a twin cannot enter the newly vacated echo cell', () {
    final level = _level();
    final before = PuzzleState.initial(level);
    final pair = level.mechanic<MirrorPair>(MirrorPair.typeId)!;
    // 선행 배치 변환으로 짝이 출발 칸 바로 옆에 옮겨진 경우도 막는다.
    final landed = [
      before.goal,
      level.blocks[0].at(_twinLanding),
      level.blocks[1].at(_landing),
    ];
    expect(
      pair.transformMove(before, const PuzzleMove('b1', _landing), landed),
      same(landed),
    );
  });

  test(
    'the gate uses the old echo for entry and the new echo after moving',
    () {
      final opening = PuzzleController(_level(rules: [_gate(_source)]));
      expect(opening.move('b1', _landing), isTrue);
      expect(opening.state.positionOf('b2'), _twinStart);
      expect(opening.state.isGateOpen, isTrue);

      const plate = Position(0, 4);
      final closing = PuzzleController(
        _level(extra: {'b3': plate}, rules: [_gate(plate)]),
      );
      expect(closing.move('b3', const Position(1, 4)), isTrue);
      expect(closing.state.isGateOpen, isTrue);
      expect(closing.move('b1', _landing), isTrue);
      expect(closing.state.positionOf('b2'), _twinLanding);
      expect(closing.state.isGateOpen, isFalse);
    },
  );

  for (final kind in ['echoEraser', 'echoHold']) {
    test('$kind only applies to the pushed block', () {
      PuzzleController setup() => PuzzleController(
        _level(
          rules: [
            {
              'type': kind,
              'positions': [_point(_twinStart)],
            },
          ],
        ),
      )..move(Level.goalBlockId, const Position(1, 0));

      final following = setup();
      expect(following.move('b1', _landing), isTrue);
      expect(following.state.positionOf('b2'), _twinLanding);
      expect(following.state.echo, _source);

      final pushed = setup();
      expect(pushed.move('b2', _twinLanding), isTrue);
      expect(
        pushed.state.echo,
        kind == 'echoHold' ? const Position(0, 0) : null,
      );
    });
  }

  test('a rune on the star does not clear the level', () {
    final controller = PuzzleController(_level(exit: _twinLanding));
    expect(previewMove(controller.state, 'b2', _twinLanding), isNull);
    expect(controller.move('b1', _landing), isTrue);
    expect(controller.state.positionOf('b2'), _twinLanding);
    expect(controller.state.isComplete, isFalse);
  });

  test('RIQ following onto the star clears the level', () {
    final controller = PuzzleController(
      _level(
        goal: _twinStart,
        exit: _twinLanding,
        twin: const Position(0, 1),
        pairs: const [
          ['b1', 'goal'],
        ],
        rules: [
          {
            'type': 'goalOnly',
            'positions': [_point(_twinLanding)],
          },
        ],
      ),
    );
    final (_, next) = PuzzleSolver.successors(controller.state).firstWhere(
      (edge) => edge.$1.blockId == 'b1' && edge.$1.target == _landing,
    );
    expect(next.isComplete, isTrue);
    expect(controller.move('b1', _landing), isTrue);
    expect(controller.state.isComplete, isTrue);
    expect(controller.state.goal.position, _twinLanding);
    expect(MirrorPair.recordedShift(controller.lastMove!)?.blockId, 'goal');
  });

  for (final power in PuzzlePower.values) {
    test('${power.id} moves the pushed piece only', () {
      final twin = power == PuzzlePower.lightSwap
          ? const Position(2, 1)
          : const Position(4, 3);
      final controller = PuzzleController(
        _level(
          twin: twin,
          walls: power == PuzzlePower.moonflowerLeap ? [_landing] : [],
        ),
        powers: {power},
      );
      expect(controller.move(Level.goalBlockId, const Position(1, 0)), isTrue);
      expect(controller.usePower(power, 'b1', const Position(1, 0)), isTrue);
      expect(controller.state.positionOf('b1'), isNot(_source));
      expect(controller.state.positionOf('b2'), twin);
      expect(MirrorPair.recordedShift(controller.lastMove!), isNull);
    });
  }
}
