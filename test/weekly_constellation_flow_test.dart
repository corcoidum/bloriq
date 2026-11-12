import 'dart:convert';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/weekly/weekly_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WEEKLY');
DateTime _clock() => DateTime(2026, 11, 12, 10);

Future<void> _solveWeeklyStage(WidgetTester tester) async {
  await waitForReleaseWidget(tester, releaseBoard);
  await tester.pump(const Duration(milliseconds: 350));
  final game = releaseGame(tester);
  final controller = game.controller;
  final level = controller.state.level;
  final solution = const PuzzleSolver().solve(level)!;
  expect(solution, hasLength(level.minimumMoves));
  await tester.ensureVisible(releaseBoard);
  await tester.pump();
  for (final move in solution) {
    final source = controller.state.positionOf(move.blockId)!;
    await tester.dragFrom(
      tester.getTopLeft(releaseBoard) + game.geometry.center(source),
      Offset(
            (move.target.x - source.x).sign.toDouble(),
            (move.target.y - source.y).sign.toDouble(),
          ) *
          game.geometry.cellSize *
          .74,
    );
    await tester.pump();
  }
  expect(controller.state.isComplete, isTrue);
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('home weekly card opens five playable stages and a reward', (
    tester,
  ) async {
    seedCampaign({});
    final boundary = await openReleaseApp(
      tester,
      captureArt: _capture,
      clock: _clock,
    );
    final weekly = releaseKey('home-weekly');
    final daily = releaseKey('daily-play');
    expect(weekly, findsNothing);
    await openPlayModes(tester);
    expect(weekly.hitTestable(), findsOneWidget);
    expect(daily.hitTestable(), findsOneWidget);
    expect(
      tester.getCenter(weekly).dy,
      greaterThan(tester.getCenter(daily).dy),
    );
    if (_capture) {
      await tester.pump(const Duration(milliseconds: 350));
      await captureReleaseScreen(
        tester,
        boundary,
        'docs/screenshots/weekly/home.png',
      );
    }
    await tapVisible(tester, weekly);
    final stages = releaseKey('weekly-stages');
    await waitForReleaseWidget(tester, stages);
    expect(find.text('2026-11-09 시작'), findsOneWidget);
    expect(
      tester.widget<Text>(releaseKey('weekly-progress')).data,
      '5판 중 0판 완료',
    );

    final scrollable = find.descendant(
      of: stages,
      matching: find.byType(Scrollable),
    );
    for (var number = 1; number <= 5; number++) {
      final stage = releaseKey('weekly-stage-$number');
      await tester.scrollUntilVisible(stage, 120, scrollable: scrollable);
      await tapVisible(tester, stage);
      await _solveWeeklyStage(tester);
      await waitForReleaseWidget(tester, releaseKey('weekly-result-progress'));
      expect(
        releaseKey('weekly-result-reward'),
        number == 5 ? findsOneWidget : findsNothing,
      );
      await tapVisible(tester, releaseKey('result-next'));
      await waitForReleaseWidget(tester, stages);
    }
    final progress = releaseKey('weekly-progress');
    await tester.scrollUntilVisible(progress, -120, scrollable: scrollable);
    expect(tester.widget<Text>(progress).data, '이번 주 별자리를 완성했어요!');
    if (_capture) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      await captureReleaseScreen(
        tester,
        boundary,
        'docs/screenshots/weekly/constellation.png',
      );
    }
    final prefs = await SharedPreferences.getInstance();
    final data = jsonDecode(prefs.getString(WeeklyRepository.storageKey)!);
    expect(
      (data['weeks']['2026-11-09']['bestMoves'] as List).whereType<int>(),
      hasLength(5),
    );
    await tapVisible(tester, find.byType(BackButton));
    await openPlayModes(tester);
    expect(
      find.descendant(of: weekly, matching: find.text('5판 중 5판 완료')),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets('weekly stages are reachable at 320x568 with 200% text', (
    tester,
  ) async {
    seedCampaign({});
    await openReleaseApp(tester, clock: _clock, locale: const Locale('en'));
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    await openPlayModes(tester);
    final weekly = releaseKey('home-weekly');
    await tapVisible(tester, weekly);
    final stages = releaseKey('weekly-stages');
    await waitForReleaseWidget(tester, stages);
    final fifth = releaseKey('weekly-stage-5');
    await tester.scrollUntilVisible(
      fifth,
      150,
      scrollable: find.descendant(
        of: stages,
        matching: find.byType(Scrollable),
      ),
    );
    await tapVisible(tester, fifth);
    await waitForReleaseWidget(tester, releaseBoard);
    expect(tester.takeException(), isNull);
    await closeReleaseApp(tester);
  });
}
