import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

Level testLevel({
  Set<Position> erasers = const {},
  Set<Position> holds = const {},
  Map<Position, Position> directions = const {},
  Set<Position> goals = const {},
}) => Level(
  id: 100,
  boardWidth: 4,
  boardHeight: 3,
  startPosition: const Position(0, 1),
  exitPosition: const Position(3, 1),
  blocks: const [Block(id: 'b1', position: Position(0, 0))],
  obstacles: const [],
  minimumMoves: 3,
  difficulty: 'test',
  echoErasers: erasers,
  echoHolds: holds,
  oneWays: directions,
  goalOnlyTiles: goals,
);

void main() {
  Level switchLevel() => Level(
    id: 102,
    boardWidth: 5,
    boardHeight: 3,
    startPosition: const Position(1, 1),
    exitPosition: const Position(4, 1),
    blocks: const [
      Block(id: 'switchBlock', position: Position(1, 0)),
      Block(id: 'holdBlock', position: Position(0, 0)),
    ],
    obstacles: const [],
    minimumMoves: 4,
    difficulty: 'test',
    echoSwitch: const Position(1, 0),
    echoGate: const Position(2, 1),
    echoHolds: {const Position(0, 0)},
    echoErasers: {const Position(1, 1)},
  );

  test('hold keeps a switch open and eraser closes it after gate entry', () {
    final controller = PuzzleController(switchLevel());
    expect(controller.move('switchBlock', const Position(2, 0)), isTrue);
    final open = controller.state;
    expect(open.isGateOpen, isTrue);
    expect(open.echo, const Position(1, 0));

    // 유지 칸에서 떠나도 이전 스위치 잔상이 남아 문은 열린 상태다.
    final heldPreview = previewMove(open, 'holdBlock', const Position(0, 1))!;
    expect(heldPreview.echo, open.echo);
    expect(heldPreview.isGateOpen, isTrue);
    expect(controller.state, same(open));
    expect(controller.move('holdBlock', const Position(0, 1)), isTrue);
    final held = controller.state;
    expect(held.echo, heldPreview.echo);
    expect(held.isGateOpen, heldPreview.isGateOpen);
    expect(held.moves, heldPreview.moves);
    expect(
      held.blocks.map((b) => b.position),
      heldPreview.blocks.map((b) => b.position),
    );

    // 열린 문에 들어갈 때 출발 칸의 지우개가 스위치 잔상을 제거한다.
    final erasedPreview = previewMove(held, 'goal', const Position(2, 1))!;
    expect(erasedPreview.echo, isNull);
    expect(erasedPreview.isGateOpen, isFalse);
    expect(controller.state, same(held));
    expect(controller.move('goal', const Position(2, 1)), isTrue);
    final erased = controller.state;
    expect(erased.echo, erasedPreview.echo);
    expect(erased.isGateOpen, erasedPreview.isGateOpen);
    expect(erased.goal.position, erasedPreview.goal.position);
    expect(erased.moves, erasedPreview.moves);
    expect(controller.move('goal', const Position(3, 1)), isTrue);
    expect(controller.move('goal', const Position(4, 1)), isTrue);
    expect(controller.state.isComplete, isTrue);

    // Replay는 보존·제거 전후의 불변 스냅샷을 그대로 사용한다.
    final records = controller.moveHistory;
    expect(records[1].before, same(open));
    expect(records[1].after, same(held));
    expect(records[1].previousEcho, const Position(1, 0));
    expect(records[1].nextEcho, const Position(1, 0));
    expect(records[2].before, same(held));
    expect(records[2].after, same(erased));
    expect(records[2].previousEcho, const Position(1, 0));
    expect(records[2].nextEcho, isNull);
    expect(records[2].after.isGateOpen, isFalse);

    expect(controller.undo(), isTrue);
    expect(controller.undo(), isTrue);
    expect(controller.undo(), isTrue);
    expect(controller.state, same(held));
    expect(controller.state.isGateOpen, isTrue);
    expect(controller.moveHistory, hasLength(2));
  });

  test('eraser closes an open gate in preview without altering real state', () {
    final controller = PuzzleController(switchLevel());
    expect(controller.move('switchBlock', const Position(2, 0)), isTrue);
    final before = controller.state;
    final preview = previewMove(before, 'goal', const Position(2, 1))!;
    expect(before.isGateOpen, isTrue);
    expect(preview.echo, isNull);
    expect(preview.isGateOpen, isFalse);
    expect(controller.state, same(before));
    expect(controller.move('goal', const Position(2, 1)), isTrue);
    expect(controller.state.echo, preview.echo);
    expect(controller.state.isGateOpen, preview.isGateOpen);
    expect(controller.undo(), isTrue);
    expect(controller.state, same(before));
    expect(controller.state.isGateOpen, isTrue);
  });
  test('echo eraser removes the previous echo and creates no new one', () {
    final controller = PuzzleController(
      testLevel(erasers: {const Position(0, 1)}),
    );
    expect(controller.move('b1', const Position(1, 0)), isTrue);
    final before = controller.state;
    expect(before.echo, const Position(0, 0));
    final preview = previewMove(before, 'goal', const Position(1, 1));
    expect(preview!.echo, isNull);
    expect(controller.state, same(before));
    expect(controller.move('goal', const Position(1, 1)), isTrue);
    expect(controller.state.echo, isNull);
    expect(controller.undo(), isTrue);
    expect(controller.state, same(before));
    expect(controller.moveHistory, hasLength(1));
  });

  test(
    'echo hold keeps previous echo including absence and undo restores it',
    () {
      final controller = PuzzleController(
        testLevel(holds: {const Position(0, 1)}),
      );
      expect(controller.move('b1', const Position(1, 0)), isTrue);
      final before = controller.state;
      expect(controller.move('goal', const Position(1, 1)), isTrue);
      expect(controller.state.echo, const Position(0, 0));
      expect(controller.undo(), isTrue);
      expect(controller.state, same(before));
      controller.restart();
      expect(controller.move('goal', const Position(1, 1)), isTrue);
      expect(controller.state.echo, isNull);
    },
  );

  test('one-way affects departure, goal-only affects entry', () {
    final controller = PuzzleController(
      testLevel(
        directions: {const Position(0, 1): const Position(1, 0)},
        goals: {const Position(1, 0)},
      ),
    );
    expect(controller.move('b1', const Position(1, 0)), isFalse);
    expect(controller.move('goal', const Position(0, 2)), isFalse);
    expect(controller.state.moves, 0);
    expect(controller.canUndo, isFalse);
    expect(controller.move('goal', const Position(1, 1)), isTrue);
    expect(controller.move('goal', const Position(1, 0)), isTrue);
  });

  test('special rules parse together, reject overlaps, and are immutable', () {
    final json = <String, dynamic>{
      'id': 101,
      'boardWidth': 4,
      'boardHeight': 3,
      'startPosition': {'x': 0, 'y': 1},
      'exitPosition': {'x': 3, 'y': 1},
      'blocks': <dynamic>[],
      'obstacles': <dynamic>[],
      'minimumMoves': 3,
      'difficulty': 'test',
      'specialRules': <dynamic>[
        {
          'type': 'echoEraser',
          'positions': [
            {'x': 0, 'y': 1},
          ],
        },
        {
          'type': 'echoHold',
          'positions': [
            {'x': 1, 'y': 1},
          ],
        },
        {
          'type': 'oneWay',
          'tiles': [
            {'x': 2, 'y': 1, 'dx': 1, 'dy': 0},
          ],
        },
        {
          'type': 'goalOnly',
          'positions': [
            {'x': 2, 'y': 0},
          ],
        },
      ],
    };
    final level = Level.fromJson(json);
    expect(level.echoErasers, contains(const Position(0, 1)));
    expect(level.echoHolds, contains(const Position(1, 1)));
    expect(level.oneWays[const Position(2, 1)], const Position(1, 0));
    expect(level.goalOnlyTiles, contains(const Position(2, 0)));
    expect(() => level.echoErasers.clear(), throwsUnsupportedError);
    expect(() => level.oneWays.clear(), throwsUnsupportedError);
    final controller = PuzzleController(level);
    for (final step in const PuzzleSolver().solve(level)!) {
      expect(controller.move(step.blockId, step.target), isTrue);
    }
    expect(controller.state.isComplete, isTrue);
    expect(controller.state.moves, 3);
    expect(
      () => testLevel(
        erasers: {const Position(1, 1)},
        holds: {const Position(1, 1)},
      ),
      throwsFormatException,
    );
    expect(
      () => testLevel(directions: {const Position(0, 1): const Position(1, 1)}),
      throwsFormatException,
    );
    expect(
      () => testLevel(goals: {const Position(9, 9)}),
      throwsFormatException,
    );
  });
}
