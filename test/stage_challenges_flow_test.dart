import 'package:bloriq/game/stage_challenge_card.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progress/stage_challenges.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_STAGE_CHALLENGES');
const _beforeMirrorLake = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
final _cardButton = releaseKey('stage-challenge-card');
final _result = releaseKey('result-stage-challenges');
final _stage = releaseKey('world-stage-201');

void main() {
  setUp(rootBundle.clear);

  testWidgets('판 카드와 지도는 진행을 표시하고 새 별꽃만 피어난다', (tester) async {
    seedCampaign(_beforeMirrorLake, cleared: releaseLevels(3).take(2));
    final boundary = await openReleaseApp(
      tester,
      captureArt: _capture,
      reduceMotion: false,
    );
    await enterReleaseWorld(tester, 3);
    expect(_mapFlowers(tester).earned, {
      StageChallenge.clear,
      StageChallenge.optimal,
    });
    await _shot(tester, boundary, 'world-map');

    await _openStage(tester);
    await tapVisible(tester, _cardButton);
    expect(find.text('권능·도움 없이 깨기'), findsOneWidget);
    expect(find.text('별꽃 2 / 3'), findsOneWidget);
    await _shot(tester, boundary, 'stage-card');
    await tapVisible(tester, find.text('닫기'));
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, _result);
    expect(tester.widget<StageChallengeCard>(_result).blooming, {
      StageChallenge.technique,
    });
    expect(_blooms(), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('별꽃 3 / 3'), findsOneWidget);
    await _shot(tester, boundary, 'result');

    final saved = await ProgressRepository.load();
    expect(saved.forLevel(201)!.stageChallenges, StageChallenge.values.toSet());
    await tapVisible(tester, releaseKey('game-home'));
    await enterReleaseWorld(tester, 3);
    expect(_mapFlowers(tester).earned, StageChallenge.values.toSet());
    await closeReleaseApp(tester);
  });

  for (final (locale, close) in [
    (const Locale('ko'), '닫기'),
    (const Locale('en'), 'Close'),
  ]) {
    testWidgets('320×568 / 200% ${locale.languageCode} 지도·판 카드·결과', (
      tester,
    ) async {
      seedCampaign(_beforeMirrorLake);
      await openReleaseApp(tester, locale: locale);
      await enterReleaseWorld(tester, 3);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      expect(_mapFlowers(tester).earned, isEmpty);
      await _openStage(tester);
      await tapVisible(tester, _cardButton);
      expect(find.byType(StageChallengeCard), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.text(close));
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, _result);
      expect(
        tester.widget<StageChallengeCard>(_result).earned,
        StageChallenge.values.toSet(),
      );
      expect(_blooms(), findsNothing);
      await tester.ensureVisible(releaseKey('result-next'));
      await tester.pump();
      expect(releaseKey('result-next').hitTestable(), findsOneWidget);
      await closeReleaseApp(tester);
    });
  }

  testWidgets('무료 열쇠 힌트는 별과 최단 과제를 유지하고 도움 없는 과제를 막는다', (tester) async {
    seedCampaign(_beforeMirrorLake);
    await openReleaseApp(tester, locale: const Locale('en'));
    await enterReleaseWorld(tester, 3);
    await _openStage(tester);
    for (var i = 0; i < 3; i++) {
      await tapVisible(tester, find.text('Restart'));
    }
    await tapVisible(tester, releaseKey('stuck-help'));
    expect(releaseKey('help-key'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    await solveVisibleBoard(tester);
    final record = (await ProgressRepository.load()).forLevel(201)!;
    expect(record.bestStars, 3);
    expect(record.stageChallenges, {
      StageChallenge.clear,
      StageChallenge.optimal,
    });
    await closeReleaseApp(tester);
  });
}

StageChallengeFlowers _mapFlowers(WidgetTester tester) => tester.widget(
  find.descendant(of: _stage, matching: find.byType(StageChallengeFlowers)),
);

Finder _blooms() => find.descendant(
  of: _result,
  matching: find.byType(TweenAnimationBuilder<double>),
);

Future<void> _openStage(WidgetTester tester) async {
  await tapVisible(tester, _stage);
  await waitForReleaseWidget(tester, releaseBoard);
  final skip = releaseKey('mirror-guide-skip');
  if (skip.evaluate().isNotEmpty) await tapVisible(tester, skip);
}

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/challenges/$name.png',
    );
  }
}
