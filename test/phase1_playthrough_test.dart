import 'support/start_game.dart';
import 'support/legacy_levels.dart';

import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first ten stages can be played consecutively by dragging', (
    tester,
  ) async {
    final data = jsonDecode(
      File('assets/levels/legacy_levels.json').readAsStringSync(),
    ) as List<dynamic>;
    final levels = data
        .map((value) => Level.fromJson(value as Map<String, dynamic>))
        .take(10)
        .toList();
    expect(levels, hasLength(10));

    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    for (
      var frame = 0;
      frame < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      frame++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(GameWidget<BloriqGame>), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));

    for (final level in levels) {
      expect(find.text('Level ${level.id}'), findsOneWidget);
      final controller = PuzzleController(level);
      final solution = const PuzzleSolver().solve(level);
      expect(solution, isNotNull, reason: 'Level ${level.id} must be solvable');

      for (final step in solution!) {
        final block = controller.state.blocks.firstWhere(
          (item) => item.id == step.blockId,
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
            cellWidth * (step.target.x - block.position.x),
            cellHeight * (step.target.y - block.position.y),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(controller.move(step.blockId, step.target), isTrue);
        expect(
          find.text('Moves: ${controller.state.moves}'),
          findsOneWidget,
          reason: 'Level ${level.id}: drag must change the visible move count',
        );
      }
      expect(controller.state.isComplete, isTrue);
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump();
      expect(
        find.text('You escaped!'),
        findsOneWidget,
        reason: 'Level ${level.id}: completion must be shown',
      );
      expect(find.text('Next level'), findsOneWidget);
      await tester.ensureVisible(find.text('Next level'));
      await tester.pump();
      await tester.tap(find.text('Next level'));
      // AnimatedSwitcher needs one frame to begin and another to finish.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text('Level 11'), findsOneWidget);
  });
}
