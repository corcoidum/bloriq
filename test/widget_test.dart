import 'support/start_game.dart';
import 'support/legacy_levels.dart';

import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('optional help explains the rules without changing the board', (
    tester,
  ) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Moves: 0'), findsOneWidget);
    await tester.tap(find.byTooltip('How to play'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('How to play'), findsOneWidget);
    expect(
      find.textContaining('The square a block leaves behind'),
      findsOneWidget,
    );
    expect(
      find.textContaining('an echo on the diamond opens the gate'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('How to play'), findsNothing);
    expect(find.text('Moves: 0'), findsOneWidget);
  });
  testWidgets('drag, undo, restart, escape and echo blocking', (tester) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(GameWidget<BloriqGame>), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));

    Future<void> move(int x, int y, int dx, int dy) async {
      final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
      final cellWidth = board.width / 3;
      final cellHeight = board.height / 3;
      final start =
          board.topLeft + Offset(cellWidth * (x + .5), cellHeight * (y + .5));
      await tester.dragFrom(start, Offset(cellWidth * dx, cellHeight * dy));
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text('Moves: 0'), findsOneWidget);
    await move(0, 1, 1, 0);
    expect(find.text('Moves: 1'), findsOneWidget);
    expect(
      find.text('An echo disappears after your next move.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Undo'));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Moves: 0'), findsOneWidget);
    await move(0, 1, 1, 0);
    await tester.ensureVisible(find.text('Restart'));
    await tester.pump();
    await tester.tap(find.text('Restart'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Moves: 0'), findsOneWidget);
    await move(0, 1, 1, 0);
    await move(1, 1, 1, 0);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Our star, at last!'), findsOneWidget);
    expect(find.text('Solved in the fewest moves!'), findsOneWidget);
    await tester.ensureVisible(find.text('Next level'));
    await tester.pump();
    await tester.tap(find.text('Next level'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Level 2'), findsOneWidget);
    await move(1, 1, 0, -1);
    expect(find.text('Moves: 1'), findsOneWidget);
    await move(0, 1, 1, 0);
    expect(find.text('Moves: 1'), findsOneWidget);
    await move(1, 0, 1, 0);
    await move(0, 1, 1, 0);
    await move(1, 1, 1, 0);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Our star, at last!'), findsOneWidget);
  });

  testWidgets('nonoptimal completion suggests a retry', (tester) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Could not load the levels.'), findsNothing);
    expect(find.byType(GameWidget<BloriqGame>), findsOneWidget);
    Future<void> move(int x, int y, int dx, int dy) async {
      final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
      final start =
          board.topLeft +
          Offset(board.width * (x + .5) / 3, board.height * (y + .5) / 3);
      await tester.dragFrom(
        start,
        Offset(board.width * dx / 3, board.height * dy / 3),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    await move(0, 1, 0, -1);
    await move(0, 0, 1, 0);
    await move(1, 0, 0, 1);
    await move(1, 1, 1, 0);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Can you escape in 2 moves?'), findsOneWidget);
    await tester.ensureVisible(find.text('Restart'));
    await tester.pump();
    await tester.tap(find.text('Restart'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Moves: 0'), findsOneWidget);
  });

  testWidgets('last stage offers a return to the first stage', (tester) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final json = jsonDecode(
      File('assets/levels/legacy_levels.json').readAsStringSync(),
    ) as List<dynamic>;
    final level = Level.fromJson(json.last as Map<String, dynamic>);
    final solution = const PuzzleSolver().solve(level)!;
    final controller = PuzzleController(level);
    await tapVisible(tester, find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await selectOpenLevel(tester, level.id);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    for (final move in solution) {
      final block = controller.state.blocks.firstWhere(
        (item) => item.id == move.blockId,
      );
      final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
      final cellWidth = board.width / level.boardWidth;
      final cellHeight = board.height / level.boardHeight;
      final start =
          board.topLeft +
          Offset(
            cellWidth * (block.position.x + .5),
            cellHeight * (block.position.y + .5),
          );
      await tester.dragFrom(
        start,
        Offset(
          cellWidth * (move.target.x - block.position.x),
          cellHeight * (move.target.y - block.position.y),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.move(move.blockId, move.target), isTrue);
    }
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('First level'), findsOneWidget);
    await tester.ensureVisible(find.text('First level'));
    await tester.pump();
    await tester.tap(find.text('First level'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Level 1'), findsOneWidget);
  });

  testWidgets('drag uses both dimensions on a rectangular board', (
    tester,
  ) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final json = jsonDecode(
      File('assets/levels/legacy_levels.json').readAsStringSync(),
    ) as List<dynamic>;
    final levels = json.map(
      (item) => Level.fromJson(item as Map<String, dynamic>),
    );
    final level = levels.firstWhere(
      (item) => item.boardWidth != item.boardHeight,
    );
    final firstMove = const PuzzleSolver().solve(level)!.first;
    final controller = PuzzleController(level);
    final block = controller.state.blocks.firstWhere(
      (item) => item.id == firstMove.blockId,
    );
    await tapVisible(tester, find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await selectOpenLevel(tester, level.id);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
    final cellWidth = board.width / level.boardWidth;
    final cellHeight = board.height / level.boardHeight;
    final start =
        board.topLeft +
        Offset(
          cellWidth * (block.position.x + .5),
          cellHeight * (block.position.y + .5),
        );
    await tester.dragFrom(
      start,
      Offset(
        cellWidth * (firstMove.target.x - block.position.x),
        cellHeight * (firstMove.target.y - block.position.y),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Moves: 1'), findsOneWidget);
    expect(
      find.text('An echo disappears after your next move.'),
      findsOneWidget,
    );
  });

  testWidgets('echo switch opens gate for one move and undo restores it', (
    tester,
  ) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final json = jsonDecode(
      File('assets/levels/legacy_levels.json').readAsStringSync(),
    ) as List<dynamic>;
    final level = json
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .firstWhere((item) => item.echoGate != null);
    final controller = PuzzleController(level);
    final solution = const PuzzleSolver().solve(level)!;

    await tapVisible(tester, find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await selectOpenLevel(tester, level.id);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Leave an echo on the diamond to open the gate.'),
      findsOneWidget,
    );

    Future<void> move(Position from, Position target) async {
      final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
      final cellWidth = board.width / level.boardWidth;
      final cellHeight = board.height / level.boardHeight;
      final start =
          board.topLeft +
          Offset(cellWidth * (from.x + .5), cellHeight * (from.y + .5));
      await tester.dragFrom(
        start,
        Offset(
          cellWidth * (target.x - from.x),
          cellHeight * (target.y - from.y),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(level.startPosition.isAdjacentTo(level.echoGate!), isTrue);
    await move(level.startPosition, level.echoGate!);
    expect(find.text('Moves: 0'), findsOneWidget);
    expect(
      find.text('The gate is closed. Leave an echo on the diamond.'),
      findsOneWidget,
    );

    var observedOpen = false;
    var observedOccupied = false;
    for (final step in solution) {
      final block = controller.state.blocks.firstWhere(
        (item) => item.id == step.blockId,
      );
      await move(block.position, step.target);
      expect(controller.move(step.blockId, step.target), isTrue);
      if (controller.state.isGateOpen) {
        observedOpen = true;
        expect(
          find.text('Gate open! Move through on this turn.'),
          findsOneWidget,
        );
      }
      if (!controller.state.isComplete &&
          !controller.state.isGateOpen &&
          controller.state.blocks.any(
            (item) => item.position == level.echoGate,
          )) {
        observedOccupied = true;
        expect(
          find.text('A block on a closed gate can still leave.'),
          findsOneWidget,
        );
      }
    }
    expect(observedOpen, isTrue);
    expect(observedOccupied, isTrue);
    await tester.pump(const Duration(milliseconds: 1600));
    await tester.pump();
    expect(find.text('Our star, at last!'), findsOneWidget);
    await tester.ensureVisible(find.text('Undo'));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('A block on a closed gate can still leave.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Undo'));
    await tester.pump();
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Gate open! Move through on this turn.'), findsOneWidget);
  });

  testWidgets('a position with no legal move suggests undo', (tester) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tapVisible(tester, find.text('Levels'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await selectOpenLevel(tester, 11);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
    final block =
        board.topLeft + Offset(board.width * 1.5 / 4, board.height * 1.5 / 4);
    await tester.dragFrom(block, Offset(0, -board.height / 4));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('No moves left. Undo and try another way.'),
      findsOneWidget,
    );
    expect(find.text('Undo last move'), findsOneWidget);
    await tapVisible(tester, find.text('Undo last move'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('No moves left. Undo and try another way.'), findsNothing);
    expect(find.text('Moves: 0'), findsOneWidget);
  });
}
