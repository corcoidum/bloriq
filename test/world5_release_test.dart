import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD5_RELEASE');
final _chaptersThroughWorld4 = {
  for (var chapter = 1; chapter <= 20; chapter++) chapter,
};

void main() {
  setUp(rootBundle.clear);

  testWidgets('Ice Cave shows three guide cards and saves the first clear', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld4);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    final world = await openLightroad(tester, 5);
    expect(
      find.descendant(of: world, matching: find.text('넷째 등대 · 얼어붙은 기억')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: world, matching: find.text('0 / 25 스테이지')),
      findsOneWidget,
    );
    expect(releaseKey('saga-enter-5'), findsOneWidget);
    await _shot(tester, boundary, 'lightroad');
    await tapVisible(tester, releaseKey('saga-close'));

    await enterReleaseWorld(tester, 5);
    expect(releaseMapText(5, '얼음 동굴 등대'), findsOneWidget);
    expect(_storyText('동굴에서 찬바람이 불어왔어'), findsOneWidget);
    expect(releaseKey('world-guardian-405'), findsNothing);
    await _shot(tester, boundary, 'ice-cave-map');
    await tapVisible(tester, releaseKey('world-continue'));
    await waitForReleaseWidget(tester, releaseKey('ice-guide-1'));
    expect(releaseGame(tester).controller.state.level.id, 401);
    expect(find.text('얼음에 들어가면 미끄러져요'), findsOneWidget);
    await tapVisible(tester, releaseKey('ice-guide-next'));
    expect(find.text('막히는 곳에서 멈춰요'), findsOneWidget);
    await _shot(tester, boundary, 'ice-tutorial');
    await tapVisible(tester, releaseKey('ice-guide-next'));
    expect(find.text('블록과 잔상으로 멈출 자리를 만들어요'), findsOneWidget);
    await tapVisible(tester, releaseKey('ice-guide-next'));
    expect(releaseKey('ice-guide-3'), findsNothing);

    final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
    expect(frame.skin?.palette?.board, const Color(0xffb2daed));
    expect(frame.skin?.palette?.border, const Color(0xffe6f8ff));
    expect(
      releaseGame(tester).controller.state.level.mechanics.keys,
      contains(Ice.typeId),
    );
    await _shot(tester, boundary, 'ice-cave-game');
    await tapVisible(tester, find.byTooltip('게임 방법'));
    await tapVisible(tester, releaseKey('replay-ice-guide'));
    expect(releaseKey('ice-guide-1'), findsOneWidget);
    await tapVisible(tester, releaseKey('ice-guide-skip'));

    await tapVisible(tester, releaseKey('game-home'));
    await waitForHome(tester);
    await enterReleaseWorld(tester, 5);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseKey('ice-guide-1'), findsNothing);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('result-next'));
    await _shot(tester, boundary, 'ice-cave-result');
    expect((await ProgressRepository.load()).forLevel(401)?.bestStars, 3);
    await closeReleaseApp(tester);
  });

  testWidgets('the last Clocktower clear opens the fourth lighthouse', (
    tester,
  ) async {
    seedCampaign(
      _chaptersThroughWorld4.difference({20}),
      cleared: releaseLevels(4).take(24),
    );
    await openReleaseApp(tester);
    await openLightroad(tester, 5);
    expect(releaseKey('saga-enter-5'), findsNothing);
    await tapVisible(tester, releaseKey('saga-close'));

    await tapVisible(tester, find.byTooltip('게임 방법'));
    expect(releaseKey('replay-ice-guide'), findsNothing);
    await tapVisible(tester, find.text('닫기'));

    await enterReleaseWorld(tester, 4);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 325);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('world-clear'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(20),
    );
    await tapVisible(tester, releaseKey('result-next'));
    await waitForReleaseWidget(tester, releaseWorldMap(5));
    expect(releaseMapText(5, '얼음 동굴 등대'), findsOneWidget);
    await tapVisible(tester, releaseKey('world-close'));
    await waitForHome(tester);
    expect(
      find.descendant(
        of: releaseKey('world-entry'),
        matching: find.text('얼음 동굴 등대'),
      ),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets('clearing 405 reveals the Frost guardian memory and atlas', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld4, cleared: releaseLevels(5).take(4));
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await enterReleaseWorld(tester, 5);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 405);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('result-next'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(21),
    );
    await tapVisible(tester, releaseKey('game-home'));
    await waitForHome(tester);

    await enterReleaseWorld(tester, 5);
    final pages = find.descendant(
      of: releaseWorldMap(5),
      matching: find.byType(PageView),
    );
    await tester.drag(pages, const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 450));
    final guardian = releaseKey('world-guardian-405');
    await waitForReleaseWidget(tester, guardian);
    await tapVisible(tester, guardian);
    final atlas = releaseKey('guardian-atlas-405');
    expect(
      find.descendant(of: atlas, matching: find.text('별자리 도감')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: find.text('서온')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: _storyText('작은 장면들이 갇혀 있었어')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: find.byType(Image)),
      findsOneWidget,
    );
    await _shot(tester, boundary, 'guardian-atlas');
    await tapVisible(
      tester,
      find.descendant(of: atlas, matching: find.text('닫기')),
    );
    await closeReleaseApp(tester);
  });

  testWidgets('all three unlocked guides fit home help at 200% text', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld4);
    await openReleaseApp(tester, locale: const Locale('en'));
    await _smallScreen(tester);
    await tapVisible(tester, find.byTooltip('How to play'));
    for (final name in ['mirror', 'clock', 'ice']) {
      expect(releaseKey('replay-$name-guide'), findsOneWidget);
    }
    await tapVisible(tester, releaseKey('replay-ice-guide'));
    expect(releaseKey('ice-guide-1'), findsOneWidget);
    await tapVisible(tester, releaseKey('ice-guide-skip'));
    await closeReleaseApp(tester);
  });

  for (final (lang, firstCard, help) in [
    ('ko', '얼음에 들어가면 미끄러져요', '게임 방법'),
    ('en', 'Slide when you enter ice', 'How to play'),
  ]) {
    testWidgets('Ice Cave guide, play and result fit 320×568 at 200% ($lang)', (
      tester,
    ) async {
      seedCampaign(_chaptersThroughWorld4);
      await openReleaseApp(tester, locale: Locale(lang));
      await enterReleaseWorld(tester, 5);
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('ice-guide-1'));
      await _smallScreen(tester);

      expect(find.text(firstCard), findsOneWidget);
      for (var page = 0; page < 3; page++) {
        await tapVisible(tester, releaseKey('ice-guide-next'));
        expect(tester.takeException(), isNull);
      }
      expect(
        MediaQuery.textScalerOf(tester.element(releaseBoard)).scale(10),
        20,
      );
      await tapVisible(tester, find.byTooltip(help));
      await tapVisible(tester, releaseKey('replay-ice-guide'));
      await tapVisible(tester, releaseKey('ice-guide-skip'));
      expect(tester.takeException(), isNull);
      await solveVisibleBoard(tester);
      final next = releaseKey('result-next');
      await waitForReleaseWidget(tester, next);
      expect(releaseVictory, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.pump();
      expect(tester.getRect(next).bottom, lessThanOrEqualTo(536));
      await closeReleaseApp(tester);
    });
  }
}

Future<void> _smallScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pump();
}

Finder _storyText(String part) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data.contains(part),
);

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/world5/$name.png',
    );
  }
}
