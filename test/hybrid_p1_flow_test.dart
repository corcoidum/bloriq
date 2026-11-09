import 'dart:convert';
import 'dart:io';

import 'package:bloriq/analytics/local_analytics.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/tutorial/echo_tutorial.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

final board = find.byType(GameWidget<BloriqGame>);
BloriqGame game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(board).game!;
Future<void> waitKey(WidgetTester tester, String key) async {
  for (
    var i = 0;
    i < 200 && find.byKey(ValueKey(key)).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byKey(ValueKey(key)), findsOneWidget);
}

Future<void> solve(WidgetTester tester) async {
  final level = game(tester).controller.state.level;
  for (final move in const PuzzleSolver().solveFromState(
    game(tester).controller.state,
  )!) {
    await tester.ensureVisible(board);
    await tester.pump();
    final block = game(tester).controller.state.blocks
        .firstWhere((b) => b.id == move.blockId);
    final rect = tester.getRect(board);
    final cell = rect.width / level.boardWidth;
    await tester.dragFrom(
      rect.topLeft +
          Offset(
            (block.position.x + .5) * cell,
            (block.position.y + .5) * cell,
          ),
      Offset(
        (move.target.x - block.position.x) * cell,
        (move.target.y - block.position.y) * cell,
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 1800));
  await tester.pump();
  expect(game(tester).controller.state.isComplete, true);
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
    });
  });
  for (final consent in [false, true]) {
    testWidgets(
      'test build choice $consent precedes tutorial and never forces tracking',
      (tester) async {
        await tester.pumpWidget(const BloriqApp(playtestMode: true));
        await waitKey(tester, 'consent-accept');
        expect(board, findsNothing);
        expect(
          (await SharedPreferences.getInstance()).containsKey(
            LocalAnalytics.storageKey,
          ),
          false,
        );
        await tapVisible(
          tester,
          find.byKey(ValueKey(consent ? 'consent-accept' : 'consent-decline')),
        );
        await waitKey(tester, 'skip-tutorial');
        final session = tester
            .widget<GameScreen>(find.byType(GameScreen))
            .session;
        expect(session.analytics.enabled, consent);
        expect(
          session.analytics.snapshot()['participantId'],
          consent ? isNotNull : isNull,
        );
        if (consent) {
          expect(
            (session.analytics.snapshot()['events'] as List).any(
              (event) => event['name'] == 'tutorial_start',
            ),
            true,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'Daily actual gestures save only Daily, home refreshes across midnight',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(Onboarding.storageKey, 'skipped');
      var now = DateTime(2026, 10, 29, 23, 59);
      await tester.pumpWidget(BloriqApp(clock: () => now));
      await waitForHome(tester);
      await tapVisible(tester, find.byKey(const ValueKey('daily-play')));
      await tester.pump(const Duration(milliseconds: 350));
      final screen = tester.widget<GameScreen>(find.byType(GameScreen));
      final challenge = screen.play.challenge!;
      await solve(tester);
      expect(
        screen.session.daily.bestMoves(challenge.date),
        challenge.level.minimumMoves,
      );
      expect((await ProgressRepository.load()).hasAnyProgress, false);
      await tapVisible(tester, find.byKey(const ValueKey('game-home')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Replay today’s Echo'), findsOneWidget);
      now = DateTime(2026, 10, 30);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Play Daily Echo'), findsOneWidget);
      expect(screen.session.daily.completed(challenge.date), true);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('consent from settings mid-run does not backfill earlier moves', (
    tester,
  ) async {
    await pumpGame(tester, const BloriqApp());
    final rect = tester.getRect(board), cell = tester.getRect(board).width / 3;
    await tester.dragFrom(
      rect.topLeft + Offset(cell * .5, cell * 1.5),
      Offset(cell, 0),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final screen = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(screen.session.analytics.eventCount, 0);
    await tapVisible(tester, find.byTooltip('Settings'));
    await tapVisible(tester, find.byKey(const ValueKey('analytics-consent')));
    await tapVisible(tester, find.text('Close'));
    await solve(tester);
    final events = screen.session.analytics.snapshot()['events'] as List;
    final completion = events
        .where((event) => event['name'] == 'level_complete')
        .single;
    expect(completion['validMoves'], 1);
    expect(completion['moves'], 2);
    expect(
      events.where((event) => event['name'] == 'first_move'),
      hasLength(1),
    );
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('landscape keeps each board cell at least 48 logical pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(568, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGame(tester, const BloriqApp(), levelId: 5);
    expect(
      tester.getRect(board).width /
          game(tester).controller.state.level.boardWidth,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  final drafts = (jsonDecode(
    File('assets/levels/draft_levels_26_40.json').readAsStringSync(),
  ) as List).map((raw) => Level.fromJson(raw)).toList();
  for (final level in drafts) {
    testWidgets(
      'unpublished candidate ${level.id}: Dart optimum, actual drag, Undo and Restart',
      (tester) async {
        await pumpGame(
          tester,
          BloriqApp(loadLevels: () async => [level]),
          levelId: level.id,
        );
        final solution = const PuzzleSolver().solve(level)!;
        expect(solution.length, level.minimumMoves);
        final controller = game(tester).controller;
        final initial = controller.state;
        controller.move(solution.first.blockId, solution.first.target);
        expect(controller.undo(), true);
        expect(controller.state, same(initial));
        controller.restart();
        expect(controller.state.moves, 0);
        expect(controller.state.echo, isNull);
        await solve(tester);
        expect(controller.state.moves, level.minimumMoves);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
