import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/story/collection_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
    });
  });
  testWidgets(
    'all 25 original puzzles award one friend, five correct endings, and restore a late companion',
    (tester) async {
      final settings = GameSettings(reduceMotion: true);
      await pumpGame(tester, BloriqApp(settings: settings));
      final board = find.byType(GameWidget<BloriqGame>);
      BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;
      final session = tester
          .widget<GameScreen>(find.byType(GameScreen))
          .session;
      for (var id = 1; id <= 25; id++) {
        final level = game().controller.state.level;
        expect(level.id, id);
        final solution = const PuzzleSolver().solve(level)!;
        expect(solution.length, level.minimumMoves);
        for (final move in solution) {
          await tester.ensureVisible(board);
          await tester.pump();
          final block = game().controller.state.blocks.firstWhere(
            (b) => b.id == move.blockId,
          );
          final geometry = game().geometry;
          await tester.dragFrom(
            tester.getTopLeft(board) + geometry.center(block.position),
            Offset(
                  (move.target.x - block.position.x).toDouble(),
                  (move.target.y - block.position.y).toDouble(),
                ) *
                geometry.cellSize *
                .7,
          );
          await tester.pump(const Duration(milliseconds: 60));
        }
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(game().controller.state.isComplete, true);
        expect(session.collection.owned.length, id);
        expect(session.collection.memoryIds.length, id);
        expect(
          session.progress
              .forLevel(id, revision: level.revision)!
              .completionCount,
          1,
        );
        final chapter = session.story.chapterForLevel(id);
        if (id % 5 == 0) {
          expect(find.text(chapter.endingTitle.en), findsOneWidget);
          expect(find.text(chapter.ending.en), findsOneWidget);
          expect(session.collection.chapterComplete(chapter.number), true);
        }
        await tapVisible(tester, find.byKey(const ValueKey('skip-story')));
        if (id < 25) await tapVisible(tester, find.text('Next level'));
      }
      expect(find.text('Every light in Season 1 is home.'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('result-album')));
      await tapVisible(tester, find.byKey(const ValueKey('album-chapter-5')));
      await tapVisible(tester, find.byKey(const ValueKey('spirit-s1-25')));
      await tapVisible(tester, find.byKey(const ValueKey('equip-companion')));
      expect(session.collection.companion?.id, 's1-25');
      await tapVisible(tester, find.text('Close').last);
      await tapVisible(tester, find.byTooltip('Close'));
      await tapVisible(tester, find.text('Try again'));
      final level = game().controller.state.level;
      for (final move in const PuzzleSolver().solve(level)!) {
        await tester.ensureVisible(board);
        await tester.pump();
        final block = game().controller.state.blocks.firstWhere(
          (b) => b.id == move.blockId,
        );
        final geometry = game().geometry;
        await tester.dragFrom(
          tester.getTopLeft(board) + geometry.center(block.position),
          Offset(
                (move.target.x - block.position.x).toDouble(),
                (move.target.y - block.position.y).toDouble(),
              ) *
              geometry.cellSize *
              .7,
        );
        await tester.pump(const Duration(milliseconds: 60));
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(session.collection.owned.length, 25);
      expect(find.byKey(const ValueKey('skip-story')), findsNothing);
      expect(
        session.progress
            .forLevel(25, revision: level.revision)!
            .completionCount,
        2,
      );
      await tester.pumpWidget(const SizedBox());
      final restored = await CollectionRepository.load(session.story);
      expect(restored.owned.length, 25);
      expect(restored.companion?.id, 's1-25');
      settings.dispose();
    },
  );
}
