import 'dart:convert';
import 'dart:io';

import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_JOURNEY');

final _status = find.byKey(const PageStorageKey('journey-status-list'));
final _stars = find.byKey(const PageStorageKey('journey-constellation-list'));
final _companions = releaseKey('journey-companion-list');
final _rewards = find.byKey(const PageStorageKey('journey-rewards-list'));
final _lastReward = releaseKey('journey-title-${titles.last.id}');

Finder _tab(String name) => releaseKey('journey-tab-$name');

Future<void> _reveal(WidgetTester tester, Finder list, Finder item) async {
  await tester.scrollUntilVisible(
    item,
    210,
    maxScrolls: 120,
    scrollable: find.descendant(of: list, matching: find.byType(Scrollable)),
  );
  await tester.pumpAndSettle();
  expect(item.hitTestable(), findsOneWidget);
}

Future<void> _captureJourney(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!_capture) return;
  await tester.pumpAndSettle();
  await captureReleaseScreen(
    tester,
    boundary,
    'docs/screenshots/journey-redesign/$name.png',
  );
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('home and play use all worlds and preserve the active board', (
    tester,
  ) async {
    seedSaga(throughWorld: 7, stars: {623: 2, 624: 2, 625: 2});
    if (_capture) {
      final prefs = await SharedPreferences.getInstance();
      final growth = jsonDecode(
        prefs.getString(ProgressionRepository.storageKey)!,
      ) as Map<String, dynamic>;
      growth['xp'] = [
        for (var level = 1; level < 33; level++) xpToNextLevel(level),
      ].fold(0, (sum, xp) => sum + xp);
      growth['stardust'] = 12742;
      await prefs.setString(
        ProgressionRepository.storageKey,
        jsonEncode(growth),
      );
    }
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    final backfill = releaseKey('dismiss-backfill');
    if (backfill.evaluate().isNotEmpty) await tapVisible(tester, backfill);
    if (_capture) {
      final context = tester.element(find.byKey(const ValueKey('home-screen')));
      await tester.runAsync(() async {
        for (var stage = 1; stage <= 5; stage++) {
          await precacheImage(
            ResizeImage(
              AssetImage('assets/art/world7/spirits/s7-0$stage.png'),
              width: 512,
            ),
            context,
          );
        }
      });
    }
    expect(find.text('첫 별 · 스테이지 23'), findsOneWidget);
    await _captureJourney(tester, boundary, 'home');

    await openHomeJourney(tester);
    expect(find.text('빛길 지도'), findsOneWidget);
    expect(find.text('175 / 175 스테이지'), findsOneWidget);
    expect(find.text('별 522 / 525'), findsOneWidget);
    expect(find.text('정령 175 / 175'), findsOneWidget);
    expect(find.text('이어서 할 곳'), findsOneWidget);
    await _captureJourney(tester, boundary, 'status');

    await tester.fling(_status, const Offset(-250, 0), 800);
    await tester.pumpAndSettle();
    expect(find.text('별자리 복원 35 / 35'), findsOneWidget);
    expect(find.text('첫별자리'), findsOneWidget);
    expect(find.text('복원 완료 · 별 12 / 15'), findsOneWidget);
    for (var stage = 621; stage <= 625; stage++) {
      final size = tester.getSize(
        releaseKey('journey-stage-$stage').hitTestable(),
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    }
    await _captureJourney(tester, boundary, 'constellations');

    await tapVisible(tester, _tab('companions'));
    expect(find.text('전체 수집 175 / 175'), findsOneWidget);
    expect(find.text('이 세계 25 / 25'), findsOneWidget);
    expect(releaseKey('spirit-s7-01').hitTestable(), findsOneWidget);
    await _captureJourney(tester, boundary, 'companions');
    await tapVisible(tester, releaseKey('spirit-s7-01'));
    expect(releaseKey('spirit-detail-s7-01'), findsOneWidget);
    await tapVisible(tester, find.text('닫기').last);
    await tapVisible(tester, releaseKey('journey-close'));

    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseBoard);
    final controller = releaseGame(tester).controller;
    expect(controller.state.level.id, 623);
    expect(controller.apply(controller.state.level.solution.first), isTrue);
    expect(controller.canUndo, isTrue);

    await tapVisible(tester, releaseKey('game-journey'));
    expect(find.text('플레이 중'), findsOneWidget);
    await tapVisible(tester, _tab('constellations'));
    expect(find.text('별자리 복원 35 / 35'), findsOneWidget);
    expect(find.text('첫별자리'), findsOneWidget);
    expect(find.text('23 다시 도전'), findsOneWidget);
    await tapVisible(tester, _tab('companions'));
    expect(find.text('전체 수집 175 / 175'), findsOneWidget);
    await tapVisible(tester, releaseKey('journey-close'));
    expect(releaseGame(tester).controller, same(controller));
    expect(controller.state.moves, 1);

    await tapVisible(tester, releaseKey('game-journey'));
    await tapVisible(tester, _tab('constellations'));
    await chooseJourneyWorld(
      tester,
      releaseKey('journey-constellation-world'),
      2,
    );
    await tapVisible(tester, releaseKey('journey-play-stage'));
    expect(find.text('다른 스테이지로 이동할까요?'), findsOneWidget);
    await tapVisible(tester, find.text('계속 플레이'));
    expect(releaseGame(tester).controller, same(controller));
    expect(controller.state.moves, 1);
    expect(controller.canUndo, isTrue);

    await tapVisible(tester, releaseKey('game-journey'));
    await tapVisible(tester, releaseKey('journey-world-2'));
    await tapVisible(tester, releaseKey('world-continue'));
    expect(find.textContaining('구름바다 등대 · 스테이지 1'), findsOneWidget);
    await tapVisible(tester, releaseKey('journey-switch-confirm'));
    await tester.pump(const Duration(milliseconds: 500));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 101);
    expect(releaseGame(tester).controller.state.moves, 0);
    await tapVisible(tester, releaseKey('game-home'));
    await waitForHome(tester);
    await closeReleaseApp(tester);
  });

  testWidgets('journey preserves equipment and reward flows across its tabs', (
    tester,
  ) async {
    seedSaga(throughWorld: 1, extra: 1);
    final prefs = await SharedPreferences.getInstance();
    final progression = jsonDecode(
      prefs.getString(ProgressionRepository.storageKey)!,
    ) as Map<String, dynamic>;
    final levels = (jsonDecode(
      File('assets/levels/levels.json').readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    progression['stardust'] = 650;
    progression['rewardedStars'] = {
      for (final level in levels) '${level['id']}:${level['revision']}': 3,
      '101:${releaseLevels(2).first.revision}': 3,
    };
    await prefs.setString(
      ProgressionRepository.storageKey,
      jsonEncode(progression),
    );
    await openReleaseApp(tester);
    await openHomeJourney(tester);
    expect(find.text('26 / 175 스테이지'), findsOneWidget);
    expect(find.text('별 78 / 525'), findsOneWidget);
    expect(find.text('정령 26 / 175'), findsOneWidget);
    final world7 = releaseKey('journey-world-7');
    await _reveal(tester, _status, world7);
    expect(tester.widget<InkWell>(world7).onTap, isNull);

    await tapVisible(tester, _tab('companions'));
    await chooseJourneyWorld(tester, releaseKey('journey-companion-world'), 1);
    await _reveal(tester, _companions, releaseKey('album-chapter-5'));
    await tapVisible(tester, releaseKey('album-chapter-5'));
    final last = releaseKey('spirit-s1-25');
    await _reveal(tester, _companions, last);
    await tapVisible(tester, last);
    await tapVisible(tester, releaseKey('equip-companion'));
    expect(
      tester.widget<FilledButton>(releaseKey('equip-companion')).onPressed,
      isNull,
    );
    await tapVisible(tester, find.text('닫기').last);

    await tapVisible(tester, _tab('rewards'));
    await _reveal(tester, _rewards, releaseKey('journey-rewards-stars'));
    final a = releaseKey('achievement-w1-stars-75');
    final b = releaseKey('achievement-w2-stars-25');
    final aCount = find.descendant(of: a, matching: find.text('75 / 75'));
    final bCount = find.descendant(of: b, matching: find.text('3 / 25'));
    expect(
      tester.getRect(aCount).right,
      closeTo(tester.getRect(bCount).right, .01),
    );
    final longReward = find.descendant(
      of: a,
      matching: find.byType(KeepAllText),
    );
    expect(tester.getRect(longReward).bottom, lessThan(tester.getRect(b).top));
    final buy = releaseKey('shop-buy-${trailShop.first.trailId}');
    await _reveal(tester, _rewards, buy);
    await tapVisible(tester, buy);
    expect(buy, findsNothing);
    await _reveal(tester, _rewards, _lastReward);

    await tapVisible(tester, _tab('companions'));
    expect(last.hitTestable(), findsOneWidget);
    await tapVisible(tester, _tab('rewards'));
    expect(_lastReward.hitTestable(), findsOneWidget);
    await closeReleaseApp(tester);
  });

  for (final language in ['ko', 'en']) {
    testWidgets('320px with 200% text keeps $language journey reachable', (
      tester,
    ) async {
      seedSaga(throughWorld: 0);
      await openReleaseApp(tester, locale: Locale(language));
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      await openHomeJourney(tester);
      await _reveal(tester, _status, releaseKey('journey-world-7'));
      await tapVisible(tester, _tab('constellations'));
      await _reveal(tester, _stars, releaseKey('journey-stage-5'));
      expect(
        tester.getSize(releaseKey('journey-stage-5')).width,
        greaterThanOrEqualTo(44),
      );
      await _reveal(tester, _stars, releaseKey('journey-play-stage'));
      await tapVisible(tester, _tab('companions'));
      await _reveal(tester, _companions, releaseKey('album-chapter-5'));
      await tapVisible(tester, releaseKey('album-chapter-5'));
      await _reveal(tester, _companions, releaseKey('spirit-s1-25'));
      await tapVisible(tester, _tab('rewards'));
      await _reveal(tester, _rewards, releaseKey('achievement-w1-stars-75'));
      await _reveal(tester, _rewards, _lastReward);
      await closeReleaseApp(tester);
    });
  }
}
