import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/mechanics/shelf_door.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/postcard/echo_postcard.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/saga_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD6_RELEASE');
const _capturePostcard = bool.fromEnvironment('CAPTURE_WORLD6_POSTCARD');
const _teaser = '다섯 등대가 모두 켜지면, 빛길 끝에서 첫 별이 눈을 떠.';
final _chaptersThroughWorld5 = {
  for (var chapter = 1; chapter <= 25; chapter++) chapter,
};
final _chaptersBeforeFinal = {..._chaptersThroughWorld5, 26, 27, 28, 29};

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'Dream Library shows three shelf cards and saves the first clear',
    (tester) async {
      seedCampaign(_chaptersThroughWorld5);
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      final world = await openLightroad(tester, 6);
      expect(
        find.descendant(of: world, matching: find.text('다섯째 등대 · 첫 잔상의 기록')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: world, matching: find.text('0 / 25 스테이지')),
        findsOneWidget,
      );
      expect(releaseKey('saga-enter-6'), findsOneWidget);
      await _shot(tester, boundary, 'lightroad');
      await tapVisible(tester, releaseKey('saga-close'));

      await enterReleaseWorld(tester, 6);
      expect(find.text('꿈의 서고 등대'), findsOneWidget);
      expect(_storyText("'첫 잔상'이라는 빈 책"), findsOneWidget);
      expect(releaseKey('world-guardian-505'), findsNothing);
      await _shot(tester, boundary, 'dream-library-map');
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('shelf-guide-1'));
      expect(releaseGame(tester).controller.state.level.id, 501);
      expect(find.text('책장에 들어가면 같은 무늬 책장으로 건너가요'), findsOneWidget);
      await tapVisible(tester, releaseKey('shelf-guide-next'));
      expect(find.text('건너편이 막혀 있으면 그 자리에 머물러요'), findsOneWidget);
      await _shot(tester, boundary, 'shelf-tutorial');
      await tapVisible(tester, releaseKey('shelf-guide-next'));
      expect(find.text('건너간 책장에서 나올 때는 그냥 걸어 나와요'), findsOneWidget);
      await tapVisible(tester, releaseKey('shelf-guide-next'));
      expect(releaseKey('shelf-guide-3'), findsNothing);

      final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
      final palette = frame.skin?.palette;
      expect(palette?.board, const Color(0xff55304b));
      expect(palette?.border, const Color(0xffc7a568));
      expect(palette?.accent, const Color(0xfff4a9cb));
      expect(
        releaseGame(tester).controller.state.level.mechanics,
        contains(ShelfDoor.typeId),
      );
      await _shot(tester, boundary, 'dream-library-game');
      await tapVisible(tester, find.byTooltip('게임 방법'));
      await tapVisible(tester, releaseKey('replay-shelf-guide'));
      expect(releaseKey('shelf-guide-1'), findsOneWidget);
      await tapVisible(tester, releaseKey('shelf-guide-skip'));

      await tapVisible(tester, releaseKey('game-home'));
      await waitForHome(tester);
      await enterReleaseWorld(tester, 6);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseKey('shelf-guide-1'), findsNothing);
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, releaseKey('result-next'));
      await _shot(tester, boundary, 'dream-library-result');
      expect((await ProgressRepository.load()).forLevel(501)?.bestStars, 3);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('the last Ice Cave clear opens the fifth lighthouse', (
    tester,
  ) async {
    seedCampaign(
      _chaptersThroughWorld5.difference({25}),
      cleared: releaseLevels(5).take(24),
    );
    await openReleaseApp(tester);
    await openLightroad(tester, 6);
    expect(releaseKey('saga-enter-6'), findsNothing);
    await tapVisible(tester, releaseKey('saga-close'));
    final help = find.byTooltip('게임 방법').hitTestable();
    await waitForReleaseWidget(tester, help);
    await tapVisible(tester, help);
    await waitForReleaseWidget(tester, releaseKey('replay-tutorial'));
    expect(releaseKey('replay-shelf-guide'), findsNothing);
    await tapVisible(tester, find.text('닫기'));

    await enterReleaseWorld(tester, 5);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 425);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('world-clear'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(25),
    );
    await tapVisible(tester, releaseKey('result-next'));
    await waitForReleaseWidget(tester, releaseWorldMap(6));
    expect(find.text('꿈의 서고 등대'), findsOneWidget);
    await tapVisible(tester, releaseKey('world-close'));
    await waitForHome(tester);
    expect(
      find.descendant(
        of: releaseKey('world-entry'),
        matching: find.text('꿈의 서고 등대로'),
      ),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets('clearing 505 reveals the Bookworm guardian memory and atlas', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld5, cleared: releaseLevels(6).take(4));
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await enterReleaseWorld(tester, 6);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 505);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('result-next'));
    expect(
      (await ProgressionRepository.load()).completedChapters,
      contains(26),
    );
    await tapVisible(tester, releaseKey('game-home'));
    await waitForHome(tester);

    await enterReleaseWorld(tester, 6);
    final pages = find.descendant(
      of: releaseWorldMap(6),
      matching: find.byType(PageView),
    );
    await tester.drag(pages, const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 450));
    final guardian = releaseKey('world-guardian-505');
    await waitForReleaseWidget(tester, guardian);
    expect(_storyText('누군가가 꾼 꿈의 기록'), findsOneWidget);
    await tapVisible(tester, guardian);
    final atlas = releaseKey('guardian-atlas-505');
    expect(
      find.descendant(of: atlas, matching: find.text('별자리 도감')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: find.text('문온')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: atlas, matching: _storyText('서고에 새 책이 생겼어')),
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

  testWidgets(
    'clearing 525 lights the fifth lighthouse and previews the finale',
    (tester) async {
      seedCampaign(_chaptersBeforeFinal, cleared: releaseLevels(6).take(24));
      await openReleaseApp(tester);
      await enterReleaseWorld(tester, 6);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseGame(tester).controller.state.level.id, 525);
      await solveVisibleBoard(tester);
      final cleared = releaseKey('world-clear');
      await waitForReleaseWidget(tester, cleared);
      expect(
        find.descendant(of: cleared, matching: _storyText('첫 별')),
        findsOneWidget,
      );
      expect(
        (await ProgressionRepository.load()).completedChapters,
        contains(30),
      );
      await tapVisible(tester, releaseKey('result-next'));
      final saga = find.byType(SagaMap);
      await waitForReleaseWidget(tester, saga);
      expect(
        find.descendant(
          of: releaseKey('saga-lit'),
          matching: find.text('켜진 등대 5 / 5'),
        ),
        findsOneWidget,
      );

      final scrollable = find
          .descendant(of: saga, matching: find.byType(Scrollable))
          .first;
      final library = releaseKey('saga-world-6');
      await tester.scrollUntilVisible(library, 170, scrollable: scrollable);
      expect(
        find.descendant(of: library, matching: _storyText('첫 별이 첫 잔상을 만들었다')),
        findsOneWidget,
      );
      final finale = releaseKey('saga-world-7');
      await tester.scrollUntilVisible(finale, 170, scrollable: scrollable);
      expect(
        find.descendant(of: finale, matching: _storyText(_teaser)),
        findsOneWidget,
      );
      final sagaData = Saga.parse(await rootBundle.loadString(Saga.asset));
      expect(_storyText(sagaData.world(7).reveal.ko), findsNothing);
      expect(releaseKey('saga-enter-7'), findsNothing);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('511 postcard shows the twin direction before the shelf hop', (
    tester,
  ) async {
    seedCampaign({
      ..._chaptersThroughWorld5,
      26,
      27,
    }, cleared: releaseLevels(6).take(10));
    final boundary = await openReleaseApp(tester, captureArt: _capturePostcard);
    await enterReleaseWorld(tester, 6);
    await tapVisible(tester, releaseKey('world-continue'));
    expect(releaseGame(tester).controller.state.level.id, 511);
    await solveVisibleBoard(tester);
    await waitForReleaseWidget(tester, releaseKey('result-more'));
    await tapVisible(tester, releaseKey('result-more'));
    await tapVisible(tester, releaseKey('result-postcard'));
    final dialog = find.byType(EchoPostcardDialog);
    await waitForReleaseWidget(tester, dialog);
    expect(tester.widget<EchoPostcardDialog>(dialog).data.mirrorSteps, [
      (pair: 0, dx: 0, dy: 1),
      (pair: 0, dx: 1, dy: 0),
      (pair: 0, dx: -1, dy: 0),
    ]);
    if (_capturePostcard) {
      await captureReleaseScreen(
        tester,
        boundary,
        'docs/screenshots/world6/mirror-postcard.png',
      );
    }
    await closeReleaseApp(tester);
  });

  testWidgets('all four unlocked guides fit home help at 200% text', (
    tester,
  ) async {
    seedCampaign(_chaptersThroughWorld5);
    await openReleaseApp(tester, locale: const Locale('en'));
    await _smallScreen(tester);
    await tapVisible(tester, find.byTooltip('How to play'));
    for (final name in ['mirror', 'clock', 'ice', 'shelf']) {
      expect(releaseKey('replay-$name-guide'), findsOneWidget);
    }
    await tapVisible(tester, releaseKey('replay-shelf-guide'));
    expect(releaseKey('shelf-guide-1'), findsOneWidget);
    await tapVisible(tester, releaseKey('shelf-guide-skip'));
    await closeReleaseApp(tester);
  });

  for (final (lang, firstCard, help) in [
    ('ko', '책장에 들어가면 같은 무늬 책장으로 건너가요', '게임 방법'),
    ('en', 'Enter a shelf to cross to its twin', 'How to play'),
  ]) {
    testWidgets('Library guide, game and result fit 320×568 at 200% ($lang)', (
      tester,
    ) async {
      seedCampaign(_chaptersThroughWorld5);
      await openReleaseApp(tester, locale: Locale(lang));
      await enterReleaseWorld(tester, 6);
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('shelf-guide-1'));
      await _smallScreen(tester);
      expect(find.text(firstCard), findsOneWidget);
      for (var page = 0; page < 3; page++) {
        await tapVisible(tester, releaseKey('shelf-guide-next'));
        expect(tester.takeException(), isNull);
      }
      expect(
        MediaQuery.textScalerOf(tester.element(releaseBoard)).scale(10),
        20,
      );
      await tapVisible(tester, find.byTooltip(help));
      await tapVisible(tester, releaseKey('replay-shelf-guide'));
      await tapVisible(tester, releaseKey('shelf-guide-skip'));
      expect(tester.takeException(), isNull);
      await solveVisibleBoard(tester);
      await _checkSmallResult(tester);
      await closeReleaseApp(tester);
    });
  }

  testWidgets('wide Light Swap stage 523 and its result fit at 200%', (
    tester,
  ) async {
    seedCampaign(_chaptersBeforeFinal, cleared: releaseLevels(6).take(22));
    await openReleaseApp(tester);
    await enterReleaseWorld(tester, 6);
    await tapVisible(tester, releaseKey('world-continue'));
    await _smallScreen(tester);
    final game = releaseGame(tester);
    expect(game.controller.state.level.id, 523);
    expect(game.controller.state.powers, {PuzzlePower.lightSwap});
    expect(game.geometry.cellSize, greaterThanOrEqualTo(40));
    await solveVisibleBoard(tester);
    await _checkSmallResult(tester);
    await closeReleaseApp(tester);
  });
}

Future<void> _smallScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pump();
}

Future<void> _checkSmallResult(WidgetTester tester) async {
  final next = releaseKey('result-next');
  await waitForReleaseWidget(tester, next);
  expect(releaseVictory, findsOneWidget);
  await tester.ensureVisible(next);
  await tester.pump();
  expect(tester.getRect(next).bottom, lessThanOrEqualTo(536));
}

Finder _storyText(String part) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data.contains(part),
);

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/world6/$name.png',
    );
  }
}
