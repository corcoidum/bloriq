import 'support/legacy_levels.dart';

import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/postcard/echo_postcard.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('completion, replay, postcard and retry preserve progress', (
    tester,
  ) async {
    await tester.pumpWidget(BloriqApp(loadLevels: loadLegacyLevels));
    final boardFinder = find.byType(GameWidget<BloriqGame>);
    for (var i = 0; i < 100 && boardFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(boardFinder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));

    Future<void> move(int x, int y, int dx, int dy) async {
      final board = tester.getRect(boardFinder);
      final cell = board.width / 3;
      await tester.dragFrom(
        board.topLeft + Offset(cell * (x + .5), cell * (y + .5)),
        Offset(cell * dx, cell * dy),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> tapVisible(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await tester.pump();
    }

    await move(0, 1, 1, 0);
    await move(1, 1, 1, 0);
    expect(find.text('You escaped!'), findsOneWidget);
    expect(find.text('Personal best: 2 moves'), findsOneWidget);
    expect(find.text('New personal best!'), findsOneWidget);
    expect(find.text('★★★'), findsOneWidget);
    final game = tester.widget<GameWidget<BloriqGame>>(boardFinder).game!;
    final completed = game.controller.state;
    expect(completed.moves, 2);
    expect(completed.isComplete, isTrue);

    await tapVisible('Watch Echo Replay');
    expect(game.isReplaying, isTrue);
    expect(find.text('Skip replay'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Undo'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Restart'),
          )
          .onPressed,
      isNull,
    );
    await tapVisible('Skip replay');
    expect(game.isReplaying, isFalse);
    expect(game.controller.state, same(completed));

    await tapVisible('Watch Echo Replay');
    for (var i = 0; i < 200 && game.isReplaying; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(game.isReplaying, isFalse);
    expect(game.controller.state, same(completed));
    expect(find.text('Moves: 2'), findsOneWidget);
    expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);

    await tapVisible('Echo Postcard');
    await tester.pump(const Duration(milliseconds: 300));
    final dialog = tester.widget<EchoPostcardDialog>(
      find.byType(EchoPostcardDialog),
    );
    expect(dialog.data.levelId, 1);
    expect(dialog.data.moves, 2);
    expect(dialog.data.bestMoves, 2);
    expect(dialog.data.stars, 3);
    expect(find.text('Share image'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));

    await tapVisible('Try again');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await move(0, 1, 0, -1);
    await move(0, 0, 1, 0);
    await move(1, 0, 0, 1);
    await move(1, 1, 1, 0);
    expect(find.text('Personal best: 2 moves'), findsOneWidget);
    expect(find.text('New personal best!'), findsNothing);
    expect(find.text('★★☆'), findsOneWidget);
    final progress = (await ProgressRepository.load()).forLevel(1)!;
    expect(progress.bestMoves, 2);
    expect(progress.bestStars, 3);
    expect(progress.completionCount, 2);

    await tapVisible('Levels');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('★★★'), findsWidgets);
  });
}
