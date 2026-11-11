import 'dart:convert';
import 'dart:io';

import 'package:bloriq/app/journey_panel.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_JOURNEY');

final _status = find.byKey(const PageStorageKey('journey-status-list'));
final _pages = releaseKey('journey-constellation-pages');
final _pageCount = releaseKey('journey-constellation-page-count');
final _companions = find.byKey(const PageStorageKey('journey-companion-grid'));
final _rewards = find.byKey(const PageStorageKey('journey-rewards-list'));
final _lastReward = releaseKey('journey-title-${titles.last.id}');

List<Level> _campaign() =>
    (jsonDecode(File('assets/levels/levels.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map(Level.fromJson)
        .toList();

Finder _tab(String label) => find.widgetWithText(Tab, label);

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

Future<void> _openJourney(WidgetTester tester) async {
  final backfill = releaseKey('dismiss-backfill');
  if (backfill.evaluate().isNotEmpty) await tapVisible(tester, backfill);
  await tapVisible(tester, releaseKey('home-journey'));
  await tester.pumpAndSettle();
}

void _expectStageRow(WidgetTester tester, int firstId) {
  final first = tester.getRect(
    releaseKey('journey-play-$firstId').hitTestable(),
  );
  expect(first.width, greaterThanOrEqualTo(47.9));
  expect(first.height, greaterThanOrEqualTo(48));
  var last = first;
  for (var id = firstId + 1; id < firstId + 5; id++) {
    final next = tester.getRect(releaseKey('journey-play-$id').hitTestable());
    expect(next.top, closeTo(first.top, .01));
    expect(next.height, closeTo(first.height, .01));
    expect(next.width, closeTo(first.width, .01));
    expect(next.left, greaterThan(last.right));
    last = next;
  }
}

Future<void> _captureJourney(
  WidgetTester tester,
  GlobalKey key,
  String name,
) async {
  if (!_capture) return;
  await tester.pumpAndSettle();
  await captureReleaseScreen(
    tester,
    key,
    'docs/screenshots/journey-ui/$name.png',
  );
}

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'journey separates tab swipes from vertical content and keeps positions',
    (tester) async {
      final cleared = [..._campaign(), releaseLevels(2).first];
      seedCampaign({1, 2, 3, 4, 5}, cleared: cleared);
      final prefs = await SharedPreferences.getInstance();
      final progression = jsonDecode(
        prefs.getString(ProgressionRepository.storageKey)!,
      ) as Map<String, dynamic>;
      progression['stardust'] = 650;
      progression['rewardedStars'] = {
        for (final level in cleared) '${level.id}:${level.revision}': 3,
      };
      await prefs.setString(
        ProgressionRepository.storageKey,
        jsonEncode(progression),
      );
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      if (_capture) {
        await tester.runAsync(() async {
          await StarArt.loadPortrait(StarArt.lunabel);
          final story = await StoryCatalog.load();
          final context = tester.element(find.byType(MaterialApp));
          for (final spirit in story.released.take(6)) {
            await precacheImage(
              ResizeImage(AssetImage(spirit.asset!), width: 384),
              context,
            );
          }
        });
      }
      await _openJourney(tester);

      final world1 = releaseKey('journey-world-1');
      final world2 = releaseKey('journey-world-2');
      final world7 = releaseKey('journey-world-7');
      expect(find.text('26 / 175 스테이지'), findsOneWidget);
      expect(find.text('별 78 / 525'), findsOneWidget);
      expect(
        find.descendant(of: world1, matching: find.text('완료')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: world2, matching: find.text('진행 중')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: world2, matching: find.text('별 3 / 75')),
        findsOneWidget,
      );
      await _captureJourney(tester, boundary, 'journey-status');
      await _reveal(tester, _status, world7);
      expect(
        find.descendant(of: world7, matching: find.text('잠김')),
        findsOneWidget,
      );
      await _captureJourney(tester, boundary, 'journey-status-later-worlds');

      await tester.fling(_status, const Offset(-250, 0), 800);
      await tester.pumpAndSettle();
      for (var chapter = 1; chapter <= 5; chapter++) {
        expect(
          tester.widget<Text>(_pageCount).data,
          startsWith('$chapter / 5'),
        );
        _expectStageRow(tester, 1 + (chapter - 1) * 5);
        if (chapter == 1) {
          await _captureJourney(tester, boundary, 'journey-constellations');
        }
        if (chapter < 5) {
          final swipe = tester.getSize(_pages).height * .6;
          await tester.fling(_pages, Offset(0, -swipe), 800);
          await tester.pumpAndSettle();
        }
      }

      await tapVisible(tester, _tab('동료'));
      expect(find.text('수집 25 / 25'), findsOneWidget);
      final first = releaseKey('journey-companion-s1-01');
      final second = releaseKey('journey-companion-s1-02');
      final last = releaseKey('journey-companion-s1-25');
      expect(tester.getTopLeft(first).dy, tester.getTopLeft(second).dy);
      expect(last, findsNothing);
      await _captureJourney(tester, boundary, 'journey-companions');
      await _reveal(tester, _companions, last);
      await tapVisible(tester, releaseKey('journey-equip-s1-25'));
      expect(
        find.descendant(of: last, matching: find.text('함께 여행 중')),
        findsOneWidget,
      );

      await tapVisible(tester, _tab('보상'));
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
      expect(
        tester.getRect(longReward).bottom,
        lessThan(tester.getRect(b).top),
      );
      await _captureJourney(tester, boundary, 'journey-rewards');

      final item = trailShop.first;
      final buy = releaseKey('shop-buy-${item.trailId}');
      await _reveal(tester, _rewards, buy);
      await tapVisible(tester, buy);
      expect(buy, findsNothing);
      await _reveal(tester, _rewards, _lastReward);

      await tapVisible(tester, _tab('현황'));
      expect(world7.hitTestable(), findsOneWidget);
      await tapVisible(tester, _tab('동료'));
      expect(last.hitTestable(), findsOneWidget);
      await tapVisible(tester, _tab('보상'));
      expect(_lastReward.hitTestable(), findsOneWidget);
      await tapVisible(tester, _tab('별자리'));
      _expectStageRow(tester, 21);
      await tapVisible(tester, releaseKey('journey-play-25'));
      await waitForReleaseWidget(tester, releaseBoard);
      expect(releaseGame(tester).controller.state.level.id, 25);
      await closeReleaseApp(tester);
    },
  );

  for (final language in ['ko', 'en']) {
    testWidgets(
      '320px with 200% text keeps $language journey content reachable',
      (tester) async {
        seedCampaign({1}, cleared: _campaign().take(5));
        final session = await loadStorySession(tester);
        final settings = GameSettings(reduceMotion: true);
        addTearDown(settings.dispose);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          MaterialApp(
            theme: GameTheme.dark,
            locale: Locale(language),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showJourneyPanel(context, session, settings),
                  child: const Text('OPEN'),
                ),
              ),
            ),
          ),
        );
        await tapVisible(tester, find.text('OPEN'));
        await _reveal(tester, _status, releaseKey('journey-world-7'));

        await tapVisible(tester, _tab(language == 'ko' ? '별자리' : 'Stars'));
        expect(tester.widget<Text>(_pageCount).data, startsWith('2 / 5'));
        _expectStageRow(tester, 6);
        await tapVisible(tester, _tab(language == 'ko' ? '동료' : 'Friends'));
        await _reveal(
          tester,
          _companions,
          releaseKey('journey-companion-s1-25'),
        );
        await tapVisible(tester, _tab(language == 'ko' ? '보상' : 'Rewards'));
        await _reveal(tester, _rewards, releaseKey('achievement-w1-stars-75'));
        await _reveal(tester, _rewards, _lastReward);
        await closeReleaseApp(tester);
        await disposeStorySession(tester, session);
      },
    );
  }
}
