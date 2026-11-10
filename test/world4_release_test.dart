import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/world/saga_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD4_RELEASE');
final _chaptersThroughWorld3 = {
  for (var chapter = 1; chapter <= 15; chapter++) chapter,
};

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'Clocktower shows all three guide cards and saves the first clear',
    (tester) async {
      seedCampaign(_chaptersThroughWorld3);
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      final world = await openLightroad(tester, 4);
      expect(
        find.descendant(of: world, matching: find.text('셋째 등대 · 멈춘 밤의 시각')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: world, matching: find.text('0 / 25 스테이지')),
        findsOneWidget,
      );
      expect(releaseKey('saga-enter-4'), findsOneWidget);
      await _shot(tester, boundary, 'lightroad');
      await tapVisible(tester, releaseKey('saga-close'));

      await tapVisible(tester, find.byTooltip('게임 방법'));
      await tapVisible(tester, releaseKey('replay-clock-guide'));
      expect(releaseKey('clock-guide-1'), findsOneWidget);
      await tapVisible(tester, releaseKey('clock-guide-skip'));

      await enterReleaseWorld(tester, 4);
      expect(find.text('시계탑 등대'), findsOneWidget);
      expect(releaseKey('world-guardian-305'), findsNothing);
      await _shot(tester, boundary, 'clocktower-map');
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('clock-guide-1'));
      expect(releaseGame(tester).controller.state.level.id, 301);
      expect(find.text('바늘 쪽으로만 나가요'), findsOneWidget);
      await tapVisible(tester, releaseKey('clock-guide-next'));
      expect(find.text('한 수마다 모든 바늘이 돌아요'), findsOneWidget);
      await _shot(tester, boundary, 'clock-tutorial');
      await tapVisible(tester, releaseKey('clock-guide-next'));
      expect(find.text('다른 블록으로 기다려요'), findsOneWidget);
      await tapVisible(tester, releaseKey('clock-guide-next'));
      expect(releaseKey('clock-guide-3'), findsNothing);

      final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
      expect(frame.skin?.woodFloor, isTrue);
      expect(frame.skin?.palette?.border, const Color(0xffc59551));
      if (_capture) expect(StarArt.plankImage, isNotNull);
      expect(
        releaseGame(tester).controller.state.level.mechanics.keys,
        contains(ClockArrow.typeId),
      );
      expect(releaseKey('clock-phase'), findsOneWidget);
      await _shot(tester, boundary, 'clocktower-game');
      await tapVisible(tester, find.byTooltip('게임 방법'));
      await tapVisible(tester, releaseKey('replay-clock-guide'));
      expect(releaseKey('clock-guide-1'), findsOneWidget);
      await tapVisible(tester, releaseKey('clock-guide-skip'));

      await tapVisible(tester, releaseKey('game-home'));
      await waitForHome(tester);
      await enterReleaseWorld(tester, 4);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseKey('clock-guide-1'), findsNothing);
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, releaseKey('result-next'));
      await _shot(tester, boundary, 'clocktower-result');
      expect((await ProgressRepository.load()).forLevel(301)?.bestStars, 3);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('the last Mirror Lake clear opens the third lighthouse', (
    tester,
  ) async {
    seedCampaign(
      _chaptersThroughWorld3.difference({15}),
      cleared: releaseLevels(3).take(24),
    );
    await openReleaseApp(tester);
    await openLightroad(tester, 4);
    expect(releaseKey('saga-enter-4'), findsNothing);
    await tapVisible(tester, releaseKey('saga-close'));

    await enterReleaseWorld(tester, 3);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 225);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('world-clear'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(15),
    );
    await tapVisible(tester, releaseKey('result-next'));
    await waitForReleaseWidget(tester, releaseWorldMap(4));
    expect(find.text('시계탑 등대'), findsOneWidget);
    await tapVisible(tester, releaseKey('world-close'));
    await waitForHome(tester);
    expect(
      find.descendant(
        of: releaseKey('world-entry'),
        matching: find.text('시계탑 등대로'),
      ),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets('clearing 305 reveals the Winding guardian memory and atlas', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld3, cleared: releaseLevels(4).take(4));
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await enterReleaseWorld(tester, 4);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 305);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('result-next'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(16),
    );
    await tapVisible(tester, releaseKey('game-home'));
    await waitForHome(tester);

    await enterReleaseWorld(tester, 4);
    final pages = find.descendant(
      of: releaseWorldMap(4),
      matching: find.byType(PageView),
    );
    await tester.drag(pages, const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 450));
    final guardian = releaseKey('world-guardian-305');
    await waitForReleaseWidget(tester, guardian);
    await tapVisible(tester, guardian);
    final atlas = releaseKey('guardian-atlas-305');
    expect(
      find.descendant(of: atlas, matching: find.text('별자리 도감')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: find.text('모루')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: _storyText('시계를 멈추려는 손길이었어')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: find.byIcon(Icons.star_rounded)),
      findsOneWidget,
    );
    await _shot(tester, boundary, 'guardian-atlas');
    await tapVisible(
      tester,
      find.descendant(of: atlas, matching: find.text('닫기')),
    );
    await closeReleaseApp(tester);
  });

  testWidgets('clearing 325 completes Clocktower and previews the Ice Cave', (
    tester,
  ) async {
    seedCampaign({
      ..._chaptersThroughWorld3,
      16,
      17,
      18,
      19,
    }, cleared: releaseLevels(4).take(24));
    await openReleaseApp(tester);
    await enterReleaseWorld(tester, 4);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 325);
    await solveVisibleBoard(tester);
    final cleared = releaseKey('world-clear');
    await waitForReleaseWidget(tester, cleared);
    expect(
      find.descendant(of: cleared, matching: _storyText('얼음 동굴 등대')),
      findsOneWidget,
    );
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(20),
    );
    await tapVisible(tester, releaseKey('result-next'));
    final saga = find.byType(SagaMap);
    await waitForReleaseWidget(tester, saga);
    final cave = releaseKey('saga-world-5');
    await tester.scrollUntilVisible(
      cave,
      170,
      scrollable: find
          .descendant(of: saga, matching: find.byType(Scrollable))
          .first,
    );
    expect(
      find.descendant(of: cave, matching: _storyText('기억 보존 장치')),
      findsOneWidget,
    );
    expect(releaseKey('saga-enter-5'), findsNothing);
    await closeReleaseApp(tester);
  });

  for (final (lang, firstCard, help) in [
    ('ko', '바늘 쪽으로만 나가요', '게임 방법'),
    ('en', 'Leave the way the hand points', 'How to play'),
  ]) {
    testWidgets(
      'Clocktower guide, play and result fit 320×568 at 200% ($lang)',
      (tester) async {
        seedCampaign(_chaptersThroughWorld3);
        await openReleaseApp(tester, locale: Locale(lang));
        await enterReleaseWorld(tester, 4);
        await tapVisible(tester, releaseKey('world-continue'));
        await waitForReleaseWidget(tester, releaseKey('clock-guide-1'));
        tester.view.physicalSize = const Size(320, 568);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();

        expect(find.text(firstCard), findsOneWidget);
        for (var i = 0; i < 3; i++) {
          await tapVisible(tester, releaseKey('clock-guide-next'));
          expect(tester.takeException(), isNull);
        }
        expect(
          MediaQuery.textScalerOf(tester.element(releaseBoard)).scale(10),
          20,
        );
        expect(releaseKey('clock-phase'), findsOneWidget);
        await tapVisible(tester, find.byTooltip(help));
        expect(tester.takeException(), isNull, reason: 'help dialog ($lang)');
        await tapVisible(tester, releaseKey('replay-clock-guide'));
        await tapVisible(tester, releaseKey('clock-guide-skip'));
        expect(tester.takeException(), isNull);
        await solveVisibleBoard(tester);
        final next = releaseKey('result-next');
        await waitForReleaseWidget(tester, next);
        expect(releaseVictory, findsOneWidget);
        await tester.ensureVisible(next);
        await tester.pump();
        expect(tester.getRect(next).bottom, lessThanOrEqualTo(568 - 32));
        await closeReleaseApp(tester);
      },
    );
  }
}

Finder _storyText(String part) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data.contains(part),
);

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/world4/$name.png',
    );
  }
}
