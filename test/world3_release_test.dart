import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD3_RELEASE');
const _chaptersThroughWorld2 = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'Mirror Lake shows its three cards, help replay, and first clear',
    (tester) async {
      seedCampaign(_chaptersThroughWorld2);
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      final world3 = await openLightroad(tester, 3);
      expect(
        find.descendant(of: world3, matching: find.text('둘째 등대 · 물에 비친 잔상')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: world3, matching: find.text('0 / 25 스테이지')),
        findsOneWidget,
      );
      expect(releaseKey('saga-enter-3'), findsOneWidget);
      await _shot(tester, boundary, 'lightroad');
      await tapVisible(tester, releaseKey('saga-close'));

      await enterReleaseWorld(tester, 3);
      expect(releaseMapText(3, '거울 호수 등대'), findsOneWidget);
      expect(releaseKey('world-guardian-205'), findsNothing);
      await _shot(tester, boundary, 'mirror-lake-map');
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('mirror-guide-1'));
      expect(releaseGame(tester).controller.state.level.id, 201);
      expect(find.text('하나를 밀어 봐요'), findsOneWidget);
      await tapVisible(tester, releaseKey('mirror-guide-next'));
      expect(find.text('짝은 반대로'), findsOneWidget);
      await _shot(tester, boundary, 'mirror-tutorial');
      await tapVisible(tester, releaseKey('mirror-guide-next'));
      expect(find.text('막히면 제자리'), findsOneWidget);
      await tapVisible(tester, releaseKey('mirror-guide-next'));
      expect(releaseKey('mirror-guide-3'), findsNothing);

      final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
      expect(frame.skin?.palette?.board, const Color(0xff263d59));
      expect(
        releaseGame(tester).controller.state.level.mechanics.keys,
        contains('mirrorPair'),
      );
      await _shot(tester, boundary, 'mirror-lake-game');
      await tapVisible(tester, find.byTooltip('게임 방법'));
      await tapVisible(tester, releaseKey('replay-mirror-guide'));
      expect(releaseKey('mirror-guide-1'), findsOneWidget);
      await tapVisible(tester, releaseKey('mirror-guide-skip'));

      await tapVisible(tester, releaseKey('game-home'));
      await waitForHome(tester);
      await enterReleaseWorld(tester, 3);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseKey('mirror-guide-1'), findsNothing);
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, releaseKey('result-next'));
      await _shot(tester, boundary, 'mirror-lake-result');
      expect((await ProgressRepository.load()).forLevel(201)?.bestStars, 3);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('the last Cloud-Sea clear opens the second lighthouse', (
    tester,
  ) async {
    seedCampaign(
      _chaptersThroughWorld2.difference({10}),
      cleared: releaseLevels(2).take(24),
    );
    await openReleaseApp(tester);
    await openLightroad(tester, 3);
    expect(releaseKey('saga-enter-3'), findsNothing);
    await tapVisible(tester, releaseKey('saga-close'));

    await enterReleaseWorld(tester, 2);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 125);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('world-clear'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(10),
    );
    await tapVisible(tester, releaseKey('result-next'));
    await waitForReleaseWidget(tester, releaseWorldMap(3));
    expect(releaseMapText(3, '거울 호수 등대'), findsOneWidget);
    await tapVisible(tester, releaseKey('world-close'));
    await waitForHome(tester);
    expect(
      find.descendant(
        of: releaseKey('world-entry'),
        matching: find.text('거울 호수 등대'),
      ),
      findsOneWidget,
    );
    final world3 = await openLightroad(tester, 3);
    expect(releaseKey('saga-enter-3'), findsOneWidget);
    expect(
      find.descendant(of: world3, matching: find.text('0 / 25 스테이지')),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets(
    'clearing the guardian exposes its memory in the constellation atlas',
    (tester) async {
      seedCampaign({
        ..._chaptersThroughWorld2,
        11,
      }, cleared: releaseLevels(3).take(5));
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      await enterReleaseWorld(tester, 3);
      final pages = find.descendant(
        of: releaseWorldMap(3),
        matching: find.byType(PageView),
      );
      await tester.drag(pages, const Offset(300, 0));
      await tester.pump(const Duration(milliseconds: 450));
      await waitForReleaseWidget(tester, releaseKey('world-guardian-205'));
      await tapVisible(tester, releaseKey('world-guardian-205'));
      final atlas = releaseKey('guardian-atlas-205');
      expect(atlas, findsOneWidget);
      expect(
        find.descendant(of: atlas, matching: find.text('별자리 도감')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: atlas, matching: find.text('고요')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: atlas,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is KeepAllText && widget.data.contains('발소리는 이어졌어'),
          ),
        ),
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
      await tapVisible(tester, releaseKey('world-stage-201'));
      expect(releaseGame(tester).controller.state.level.id, 201);
      expect(releaseKey('mirror-guide-1'), findsNothing);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('Mirror Lake play and victory fit 320×568 with 200% text', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld2);
    await openReleaseApp(tester);
    await enterReleaseWorld(tester, 3);
    await tapVisible(tester, releaseKey('world-continue'));
    await tapVisible(tester, releaseKey('mirror-guide-skip'));
    tester.view.physicalSize = const Size(320, 568);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(MediaQuery.textScalerOf(tester.element(releaseBoard)).scale(10), 20);
    expect(tester.takeException(), isNull);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('result-next'));
    expect(releaseVictory, findsOneWidget);
    await tester.ensureVisible(releaseKey('result-next'));
    await tester.pump();
    expect(
      tester.getRect(releaseKey('result-next')).bottom,
      lessThanOrEqualTo(568 - 32),
    );
    expect(tester.takeException(), isNull);
    await closeReleaseApp(tester);
  });
}

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/world3/$name.png',
    );
  }
}
