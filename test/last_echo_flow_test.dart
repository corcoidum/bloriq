import 'package:bloriq/app/play_context.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;
Future<void> _ready(WidgetTester tester) async {
  for (var i = 0; i < 100 && _board.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 350));
  expect(_board, findsOneWidget);
}

Future<void> _move(WidgetTester tester, PuzzleMove move) async {
  await tester.ensureVisible(_board);
  await tester.pump();
  final game = _game(tester), layout = _game(tester).geometry;
  final block = game.controller.state.blocks.firstWhere(
    (b) => b.id == move.blockId,
  );
  final start = tester.getTopLeft(_board) + layout.center(block.position);
  final delta = Offset(
    (move.target.x - block.position.x).toDouble(),
    (move.target.y - block.position.y).toDouble(),
  );
  await tester.dragFrom(start, delta * layout.cellSize * .7);
  await tester.pump(const Duration(milliseconds: 80));
}

Future<void> _solve(WidgetTester tester) async {
  final moves = const PuzzleSolver().solve(
    _game(tester).controller.state.level,
  )!;
  for (final move in moves) {
    await _move(tester, move);
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(_game(tester).controller.state.isComplete, true);
}

void main() {
  setUp(
    () => SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
    }),
  );

  testWidgets(
    'first five puzzles show no spirit cards; the first constellation brings its ability spirit',
    (tester) async {
      final settings = GameSettings(reduceMotion: true);
      await tester.pumpWidget(BloriqApp(settings: settings));
      await _ready(tester);
      final first = _game(tester).controller.state.level;
      final solution = const PuzzleSolver().solve(first)!;
      await _move(tester, solution.first);
      final state = _game(tester).controller.state;
      await _move(
        tester,
        PuzzleMove(solution.first.blockId, first.startPosition),
      );
      expect(_game(tester).controller.state, same(state));
      await _move(tester, solution.last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final session = tester
          .widget<GameScreen>(find.byType(GameScreen))
          .session;
      for (var id = 1; id <= 5; id++) {
        if (id > 1) await _solve(tester);
        expect(
          session.progress
              .forLevel(id, revision: session.levels[id - 1].revision)!
              .completionCount,
          1,
        );
        // 능력 없는 정령은 발견 카드로 나오지 않는다.
        expect(find.byKey(const ValueKey('skip-story')), findsNothing);
        if (id < 5) {
          expect(
            find.byKey(const ValueKey('result-spirit-joined')),
            findsNothing,
          );
          await tapVisible(tester, find.text('Next level'));
        }
      }
      // 첫 별자리를 완성하면 그 장의 능력 정령이 합류한다.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(session.progression.hasPower(PowerIds.moonflowerLeap), isTrue);
      expect(
        find.byKey(const ValueKey('result-spirit-joined')),
        findsOneWidget,
      );
      expect(session.collection.companion, isNull);
      await tapVisible(tester, find.text('Try again'));
      await _solve(tester);
      expect(find.byKey(const ValueKey('result-spirit-joined')), findsNothing);
      expect(
        session.progress
            .forLevel(5, revision: session.levels[4].revision)!
            .completionCount,
        2,
      );
      await tapVisible(tester, find.byKey(const ValueKey('game-home')));
      expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
      // 합류한 정령만 홈에서 리크 곁에 선다.
      expect(find.byKey(const ValueKey('home-companion-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-companion-1')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  for (final practice in [true, false]) {
    testWidgets(
      '${practice ? 'practice' : 'Daily'} completion never grants a campaign spirit',
      (tester) async {
        final session = await loadStorySession(tester);
        final settings = GameSettings(reduceMotion: true);
        final play = practice
            ? PlayContext.tutorialReplay(session.levels.first)
            : PlayContext.daily(session.daily.today);
        await tester.pumpWidget(
          MaterialApp(
            theme: GameTheme.dark,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GameScreen(
              session: session,
              settings: settings,
              initialLevelId: play.level!.id,
              play: play,
            ),
          ),
        );
        await _ready(tester);
        if (practice) {
          await tapVisible(tester, find.byKey(const ValueKey('skip-tutorial')));
        }
        await _solve(tester);
        expect(session.collection.owned, isEmpty);
        expect(session.progress.completedCampaignLevelIds, isEmpty);
        expect(find.byKey(const ValueKey('skip-story')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await disposeStorySession(tester, session);
        settings.dispose();
      },
    );
  }
}
