import 'support/legacy_levels.dart';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Level gateLevel() => Level(
  id: 1,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('drag preview is removed on cancel and invalid drop', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(BloriqApp(loadLevels: loadLegacyLevels));
    final boardFinder = find.byType(GameWidget<BloriqGame>);
    for (var i = 0; i < 100 && boardFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(boardFinder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    var game = tester.widget<GameWidget<BloriqGame>>(boardFinder).game!;
    var board = tester.getRect(boardFinder);
    var cell = board.width / 3;
    var gesture = await tester.startGesture(
      board.topLeft + Offset(cell * .5, cell * 1.5),
    );
    await gesture.moveBy(Offset(cell * .5, 0));
    await tester.pump();
    expect(game.currentPreview?.isValid, isTrue);
    expect(game.currentPreview?.from, const Position(0, 1));
    expect(game.currentPreview?.target, const Position(1, 1));
    expect(game.currentPreview?.nextState?.echo, const Position(0, 1));
    expect(game.controller.state.moves, 0);
    expect(game.controller.moveHistory, isEmpty);
    await gesture.cancel();
    await tester.pump();
    expect(game.currentPreview, isNull);
    expect(game.controller.state.moves, 0);
    expect(game.controller.canUndo, isFalse);

    await tester.ensureVisible(find.text('Levels'));
    await tester.tap(find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.ensureVisible(find.text('Level 2').last);
    await tester.pump();
    await tester.tap(find.text('Level 2').last);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    game = tester.widget<GameWidget<BloriqGame>>(boardFinder).game!;
    board = tester.getRect(boardFinder);
    cell = board.width / 3;
    gesture = await tester.startGesture(
      board.topLeft + Offset(cell * .5, cell * 1.5),
    );
    await gesture.moveBy(Offset(cell * .5, 0));
    await tester.pump();
    expect(game.currentPreview?.target, const Position(1, 1));
    expect(game.currentPreview?.isValid, isFalse);
    expect(game.controller.state.moves, 0);
    await gesture.up();
    await tester.pump();
    expect(game.currentPreview, isNull);
    expect(game.controller.state.moves, 0);
    expect(game.controller.state.echo, isNull);
    expect(game.controller.canUndo, isFalse);
    expect(game.controller.moveHistory, isEmpty);
  });

  test(
    'preview predicts echo and gate without changing controller or undo',
    () {
      final controller = PuzzleController(gateLevel());
      final initial = controller.state;
      final preview = previewMove(initial, 'a', const Position(1, 0));
      expect(preview!.echo, const Position(0, 0));
      expect(preview.isGateOpen, isTrue);
      expect(controller.state, same(initial));
      expect(controller.state.moves, 0);
      expect(controller.canUndo, isFalse);
      expect(controller.moveHistory, isEmpty);
      expect(previewMove(initial, 'goal', const Position(1, 1)), isNull);
      expect(controller.state, same(initial));
    },
  );

  test(
    'history stores before and after snapshots and removes undone moves',
    () {
      final controller = PuzzleController(gateLevel());
      expect(controller.move('a', const Position(1, 0)), isTrue);
      expect(controller.move('goal', const Position(1, 1)), isTrue);
      expect(controller.move('goal', const Position(0, 1)), isFalse);
      final second = controller.moveHistory.last;
      expect(second.blockId, 'goal');
      expect(second.from, const Position(0, 1));
      expect(second.to, const Position(1, 1));
      expect(second.previousEcho, const Position(0, 0));
      expect(second.nextEcho, const Position(0, 1));
      expect(second.before.isGateOpen, isTrue);
      expect(second.after.isGateOpen, isFalse);
      final oldSnapshot = controller.moveHistory;
      expect(controller.undo(), isTrue);
      expect(controller.moveHistory, hasLength(1));
      expect(oldSnapshot, hasLength(2));
      expect(() => controller.moveHistory.clear(), throwsUnsupportedError);
      controller.restart();
      expect(controller.moveHistory, isEmpty);
    },
  );

  test('replay and skip preserve the completed state and move history', () {
    final controller = PuzzleController(gateLevel());
    controller.move('a', const Position(1, 0));
    controller.move('goal', const Position(1, 1));
    controller.move('goal', const Position(2, 1));
    controller.move('goal', const Position(3, 1));
    final completed = controller.state;
    final game = BloriqGame(controller);
    var finished = 0;
    expect(game.startReplay(onFinished: () => finished++), isTrue);
    expect(game.isReplaying, isTrue);
    expect(game.startReplay(onFinished: () {}), isFalse);
    game.update(1.0);
    expect(controller.state, same(completed));
    expect(controller.moveHistory, hasLength(4));
    game.skipReplay();
    expect(finished, 1);
    expect(game.isReplaying, isFalse);
    expect(controller.state, same(completed));
    expect(game.startReplay(onFinished: () => finished++), isTrue);
    game.update(2.6);
    expect(finished, 2);
    expect(game.isReplaying, isFalse);
    expect(controller.state, same(completed));
    expect(controller.state.moves, 4);
  });
}
