import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/progression/progression_rules.dart';
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
    'all 25 original puzzles bring the five ability spirits and open the next world',
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
        expect(
          session.progress
              .forLevel(id, revision: level.revision)!
              .completionCount,
          1,
        );
        // 판마다 뜨던 정령 발견 카드는 없다. 장을 마칠 때만 능력 정령이 합류한다.
        expect(find.byKey(const ValueKey('skip-story')), findsNothing);
        final joined = find.byKey(const ValueKey('result-spirit-joined'));
        if (id % 5 == 0) {
          for (var i = 0; i < 10 && joined.evaluate().isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(joined, findsOneWidget, reason: 'stage $id');
          expect(
            session.progression.hasPower(powerCatalog[id ~/ 5 - 1].id),
            isTrue,
          );
        } else {
          expect(joined, findsNothing, reason: 'stage $id');
        }
        if (id < 25) await tapVisible(tester, find.text('Next level'));
      }
      // 세계 1을 다 마치면 "첫 스테이지로" 대신 다음 세계 안내가 나온다.
      expect(find.byKey(const ValueKey('world-clear')), findsOneWidget);
      expect(find.text('Moonlit Forest Garden complete!'), findsOneWidget);
      expect(
        find.text('The star gate to the Cloud-Sea Lighthouse is open'),
        findsOneWidget,
      );
      expect(find.text('To the Cloud-Sea Lighthouse'), findsOneWidget);
      expect(find.text('First level'), findsNothing);
      expect(
        powerCatalog.every((power) => session.progression.hasPower(power.id)),
        isTrue,
      );
      expect(session.collection.companion, isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
