import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/saga_map.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:bloriq/world/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD7_RELEASE');
const _guide = '지금까지 배운 규칙이 모두 나와요';
const _identity = '리크는 첫 별이 남긴 마지막 잔상';
final _beforeWorld7 = {for (var chapter = 1; chapter <= 30; chapter++) chapter};

void main() {
  setUp(rootBundle.clear);

  test(
    'the finale has 25 spirits, five returning families and a gated reveal',
    () {
      final source = jsonDecode(
        File('assets/story/world7.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final story = WorldStory.fromJson(source, world: 7);
      expect(story.chapters.map((chapter) => chapter.globalChapter), [
        31,
        32,
        33,
        34,
        35,
      ]);
      expect(story.spirits, hasLength(25));
      final early = jsonDecode(jsonEncode(source)) as Map<String, dynamic>;
      (early['chapters'] as List).last.remove('ending');
      final earlyText = jsonEncode(early);
      expect(earlyText, isNot(contains(_identity)));
      expect(earlyText, isNot(contains("RIQ was the First Star's last echo")));
      expect(story.chapters.last.ending.ko, contains(_identity));
      expect(
        story.chapters.last.ending.en,
        contains("RIQ was the First Star's last echo"),
      );
      final kin = story.spirits
          .take(20)
          .map((spirit) => spirit.appearance.ko)
          .join(' ');
      for (final family in ['등불 가문', '수련 가문', '태엽 가문', '서리 가문', '책벌레 가문']) {
        expect(kin, contains(family));
      }
      final guardian = story.forLevel(625)!;
      expect(guardian.id, 's7-25');
      expect(guardian.guardian, isTrue);
      for (final name in ['아스테르', '노아', '온빛', '오르', '서람', '책별']) {
        expect(guardian.appearance.ko, contains(name));
      }
      expect(story.chapters.first.ending.ko, contains('미안해, 리크'));
    },
  );

  test(
    'night-sky accents and the first-starlight trail share five colors',
    () async {
      final world = Saga.parse(File(Saga.asset).readAsStringSync()).world(7);
      expect(world.playable, isTrue);
      expect(world.lighthouse, isNull);
      expect(world.theme!.palette!.board, const Color(0xff202c51));
      expect(world.theme!.palette!.border, const Color(0xffdfe7ff));
      expect(world.theme!.palette!.accents, BloriqGame.firstStarlightColors);
      expect(trailById(TrailIds.firstStarlight)!.name.ko, '첫 별빛');
      expect(BloriqGame.trailPalette, contains(TrailIds.firstStarlight));
      final bytes = await rootBundle.load(world.theme!.bgm!);
      expect(
        ascii.decode(bytes.buffer.asUint8List(bytes.offsetInBytes, 4)),
        'RIFF',
      );
      expect(bytes.getUint32(24, Endian.little), 22050);
      expect(bytes.getUint32(40, Endian.little) / (22050 * 2), 24);
      expect(
        () => WorldPalette.fromJson({
          'background': '#0D142C',
          'board': '#202C51',
          'border': '#DFE7FF',
          'accent': '#FFF2C2',
          'accents': ['bad', '#71E6D6'],
        }),
        throwsFormatException,
      );
    },
  );

  testWidgets(
    'the seventh world opens after the Library and shows one recap card',
    (tester) async {
      seedCampaign(_beforeWorld7.difference({30}));
      await openReleaseApp(tester, captureArt: _capture);
      await openLightroad(tester, 7);
      expect(releaseKey('saga-enter-7'), findsNothing);
      expect(_storyText(_identity), findsNothing);
      await closeReleaseApp(tester);

      seedCampaign(_beforeWorld7);
      final ready = await openReleaseApp(tester, captureArt: _capture);
      final node = await openLightroad(tester, 7);
      expect(releaseKey('saga-enter-7'), findsOneWidget);
      expect(
        find.descendant(of: node, matching: find.text('0 / 25 스테이지')),
        findsOneWidget,
      );
      final scrollable = find
          .descendant(
            of: find.byType(SagaMap),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      expect(
        find.descendant(
          of: releaseKey('saga-lit'),
          matching: find.text('켜진 등대 5 / 5'),
        ),
        findsOneWidget,
      );
      expect(_storyText(_identity), findsNothing);
      await tester.scrollUntilVisible(node, 170, scrollable: scrollable);
      await _shot(tester, ready, 'lightroad');
      await closeLightroad(tester);
      await enterReleaseWorld(tester, 7);
      expect(releaseMapText(7, '첫 별'), findsOneWidget);
      expect(_storyText('다섯 등대가 모두 켜졌어'), findsOneWidget);
      await _shot(tester, ready, 'first-star-map');
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('mix-guide-1'));
      expect(find.text(_guide), findsOneWidget);
      expect(find.text('1 / 1'), findsOneWidget);
      await _shot(tester, ready, 'mixed-tutorial');
      await tapVisible(tester, releaseKey('mix-guide-next'));
      expect(releaseKey('mix-guide-1'), findsNothing);
      expect(releaseKey('mix-guide-2'), findsNothing);
      final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
      expect(frame.skin!.palette!.accents, hasLength(5));
      await _shot(tester, ready, 'first-star-game');
      await tapVisible(tester, find.byTooltip('게임 방법'));
      await tapVisible(tester, releaseKey('replay-mix-guide'));
      expect(releaseKey('mix-guide-1'), findsOneWidget);
      await tapVisible(tester, releaseKey('mix-guide-next'));
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, releaseKey('result-next'));
      await _shot(tester, ready, 'first-star-result');
      expect((await ProgressRepository.load()).forLevel(601)?.bestStars, 3);
      await closeReleaseApp(tester);
    },
  );

  testWidgets(
    'the first guardian reveals a farewell without the final identity',
    (tester) async {
      seedCampaign(_beforeWorld7, cleared: releaseLevels(7).take(4));
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      await enterReleaseWorld(tester, 7);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseGame(tester).controller.state.level.id, 605);
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, releaseKey('result-next'));
      expect(
        (await ProgressionRepository.load()).completedChapters,
        contains(31),
      );
      expect(_storyText(_identity), findsNothing);
      await tapVisible(tester, releaseKey('game-home'));
      await waitForHome(tester);
      await enterReleaseWorld(tester, 7);
      final pages = find.descendant(
        of: releaseWorldMap(7),
        matching: find.byType(PageView),
      );
      await tester.drag(pages, const Offset(300, 0));
      await tester.pump(const Duration(milliseconds: 450));
      await tapVisible(tester, releaseKey('world-guardian-605'));
      expect(
        find.descendant(
          of: releaseKey('guardian-atlas-605'),
          matching: find.text('등아'),
        ),
        findsOneWidget,
      );
      expect(_storyText('아스테르가 오래 입구에'), findsOneWidget);
      expect(_storyText(_identity), findsNothing);
      await _shot(tester, boundary, 'guardian-atlas');
      await tapVisible(
        tester,
        find.descendant(
          of: releaseKey('guardian-atlas-605'),
          matching: find.text('닫기'),
        ),
      );
      await closeReleaseApp(tester);
    },
  );

  testWidgets(
    '625 reveals the identity and restores the title and unique trail',
    (tester) async {
      await _seedFinal();
      await openReleaseApp(tester);
      await enterReleaseWorld(tester, 7);
      expect(_storyText(_identity), findsNothing);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseGame(tester).controller.state.level.id, 625);
      await solveVisibleBoard(tester);
      await waitForReleaseWidget(tester, releaseKey('world-clear'));
      final progress = await ProgressionRepository.load();
      expect(progress.completedChapters, contains(35));
      expect(progress.worldStars(7), 75);
      expect(progress.ownedTitles, contains('first_star_echo'));
      expect(progress.ownedTrails, contains(TrailIds.firstStarlight));
      await progress.equipTrail(TrailIds.firstStarlight);
      expect(
        (await ProgressionRepository.load()).equippedTrail,
        TrailIds.firstStarlight,
      );
      await tapVisible(tester, releaseKey('game-home'));
      await waitForHome(tester);
      await enterReleaseWorld(tester, 7);
      final pages = find.descendant(
        of: releaseWorldMap(7),
        matching: find.byType(PageView),
      );
      for (var page = 0; page < 4; page++) {
        await tester.drag(pages, const Offset(-300, 0));
        await tester.pump(const Duration(milliseconds: 450));
      }
      expect(_storyText(_identity), findsOneWidget);
      await closeReleaseApp(tester);
      await openReleaseApp(tester);
      await enterReleaseWorld(tester, 7);
      await tapVisible(tester, releaseKey('world-continue'));
      expect(releaseGame(tester).trailStyle, TrailIds.firstStarlight);
      await closeReleaseApp(tester);
    },
  );

  for (final (lang, guide) in [
    ('ko', _guide),
    ('en', 'Every rule you have learned returns'),
  ]) {
    testWidgets('the recap, game and result fit 320×568 at 200% ($lang)', (
      tester,
    ) async {
      seedCampaign(_beforeWorld7);
      await openReleaseApp(tester, locale: Locale(lang));
      await enterReleaseWorld(tester, 7);
      await tapVisible(tester, releaseKey('world-continue'));
      await waitForReleaseWidget(tester, releaseKey('mix-guide-1'));
      await _smallScreen(tester);
      expect(find.text(guide), findsOneWidget);
      await tapVisible(tester, releaseKey('mix-guide-next'));
      await Scrollable.ensureVisible(
        tester.element(releaseBoard),
        alignment: .5,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      await solveVisibleBoard(tester);
      await _smallResult(tester);
      await closeReleaseApp(tester);
    });

    testWidgets('the 6×6 final board and reveal fit 200% ($lang)', (
      tester,
    ) async {
      await _seedFinal();
      await openReleaseApp(tester, locale: Locale(lang));
      await enterReleaseWorld(tester, 7);
      await tapVisible(tester, releaseKey('world-continue'));
      await _smallScreen(tester);
      expect(releaseGame(tester).geometry.cellSize, greaterThanOrEqualTo(40));
      expect(
        find.ancestor(
          of: releaseBoard,
          matching: find.byType(SingleChildScrollView),
        ),
        findsOneWidget,
      );
      await Scrollable.ensureVisible(
        tester.element(releaseBoard),
        alignment: .5,
      );
      await tester.pump();
      await solveVisibleBoard(tester);
      await _smallResult(tester);
      expect(releaseKey('world-clear'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeReleaseApp(tester);
    });
  }
}

Future<void> _seedFinal() async {
  seedCampaign({
    for (var chapter = 1; chapter <= 34; chapter++) chapter,
  }, cleared: releaseLevels(7).take(24));
  final prefs = await SharedPreferences.getInstance();
  final data = jsonDecode(
    prefs.getString(ProgressionRepository.storageKey)!,
  ) as Map<String, dynamic>;
  data['rewardedStars'] = {for (var id = 601; id < 625; id++) '$id:1': 3};
  data['claimedAchievements'] = ['w7-stars-25', 'w7-stars-50'];
  await prefs.setString(ProgressionRepository.storageKey, jsonEncode(data));
}

Future<void> _smallScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _smallResult(WidgetTester tester) async {
  final next = releaseKey('result-next');
  await waitForReleaseWidget(tester, next);
  await tester.ensureVisible(next);
  await tester.pump();
  expect(tester.getRect(next).bottom, lessThanOrEqualTo(536));
  expect(tester.takeException(), isNull);
}

Finder _storyText(String part) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data.contains(part),
);

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/world7/$name.png',
    );
  }
}
