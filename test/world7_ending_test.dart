import 'dart:io';

import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:bloriq/world/credits_screen.dart';
import 'package:bloriq/world/ending_art.dart';
import 'package:bloriq/world/saga_map.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_ENDING');
const _scenes = ['lightroad', 'ascent', 'firstStar', 'guardians', 'farewell'];
final _next = releaseKey('ending-next');
final _skip = releaseKey('ending-skip');

class _FinalClearStore extends InMemorySharedPreferencesStore {
  _FinalClearStore(super.data) : super.withData();

  bool failNextClear = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (failNextClear && key == 'flutter.${ProgressRepository.storageKey}') {
      failNextClear = false;
      return false;
    }
    return super.setValue(valueType, key, value);
  }
}

Set<int> get _completedSaga => {
  for (var world = 1; world <= Worlds.finalWorld; world++)
    ...Worlds.chaptersOf(world),
};

Future<void> _settingsAction(WidgetTester tester, String key) async {
  final t = _strings(tester, releaseKey('home-screen'));
  await tapVisible(tester, find.byTooltip(t.settings));
  await tapVisible(tester, releaseKey(key));
}

AppLocalizations _strings(WidgetTester tester, Finder finder) =>
    AppLocalizations.of(tester.element(finder))!;

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'seven successive worlds open, and the last clear leads to the ending',
    (tester) async {
      final garden = Worlds.parseLevels(
        File('assets/levels/levels.json').readAsStringSync(),
        1,
      );
      // 세계마다 마지막 판만 남기고, 결과 화면으로 다음 세계를 실제로 연다.
      seedCampaign(
        {
          for (var world = 1; world <= Worlds.finalWorld; world++)
            for (var chapter = 1; chapter < Worlds.chapterCount; chapter++)
              Worlds.globalChapter(world, chapter),
        },
        cleared: [
          ...garden.take(Worlds.stageCount - 1),
          for (var world = 2; world <= Worlds.finalWorld; world++)
            ...releaseLevels(world).take(Worlds.stageCount - 1),
        ],
      );
      final previousStore = SharedPreferencesStorePlatform.instance;
      final store = _FinalClearStore(await previousStore.getAll());
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(
        () => SharedPreferencesStorePlatform.instance = previousStore,
      );
      await openReleaseApp(tester, captureArt: _capture);
      await tapVisible(tester, releaseKey('home-play'));
      await waitForReleaseWidget(tester, releaseBoard);
      final session = tester
          .widget<GameScreen>(find.byType(GameScreen))
          .session;
      final progression = session.progression;
      final resultNext = releaseKey('result-next');

      for (var world = 1; world <= Worlds.finalWorld; world++) {
        expect(session.worldUnlocked(world), isTrue, reason: 'World $world');
        if (world < Worlds.finalWorld) {
          expect(session.worldUnlocked(world + 1), isFalse);
        }
        expect(
          releaseGame(tester).controller.state.level.id,
          Worlds.firstLevelId(world) + Worlds.stageCount - 1,
        );
        if (world == Worlds.finalWorld) store.failNextClear = true;
        await solveVisibleBoard(tester);
        if (world == Worlds.finalWorld) {
          final retry = releaseKey('retry-progress');
          await waitForReleaseWidget(tester, retry);
          expect(session.sagaComplete, isFalse);
          await tapVisible(tester, retry);
        }
        await waitForReleaseWidget(tester, releaseKey('world-clear'));
        expect(Worlds.isComplete(world, progression.completedChapters), isTrue);
        if (world == Worlds.finalWorld) {
          expect(
            find.descendant(of: resultNext, matching: find.text('빛길의 끝으로')),
            findsOneWidget,
          );
          break;
        }
        await tapVisible(tester, resultNext);
        await waitForReleaseWidget(tester, releaseWorldMap(world + 1));
        await tapVisible(tester, releaseKey('world-continue'));
        await waitForReleaseWidget(tester, releaseBoard);
      }

      expect(progression.completedChapters, _completedSaga);
      expect(progression.worldStars(7), lessThan(75));
      expect(progression.ownedTitles, contains(sagaCompletionTitleId));
      expect(progression.ownedTrails, contains(TrailIds.firstStarlight));
      expect(progression.endingSeen, isFalse);
      await tapVisible(tester, resultNext);
      await waitForReleaseWidget(tester, _skip);
      for (final scene in _scenes) {
        final frame = releaseKey('ending-$scene');
        expect(frame, findsOneWidget);
        expect(_skip.hitTestable(), findsOneWidget);
        await tester.tapAt(tester.getTopLeft(frame) + const Offset(12, 50));
        await tester.pump(const Duration(milliseconds: 550));
      }

      await waitForReleaseWidget(tester, find.byType(CreditsScreen));
      expect((await ProgressionRepository.load()).endingSeen, isTrue);
      await tester.scrollUntilVisible(
        releaseKey('credits-continue'),
        180,
        scrollable: find.descendant(
          of: releaseKey('credits-scroll'),
          matching: find.byType(Scrollable),
        ),
      );
      await tapVisible(tester, releaseKey('credits-continue'));
      expect(find.text('첫 별의 잔상'), findsOneWidget);
      expect(find.text('첫 별빛'), findsOneWidget);
      await tapVisible(tester, releaseKey('ending-voyage'));
      await waitForReleaseWidget(tester, releaseKey('endless-harbor'));
      await tapVisible(tester, releaseKey('endless-home'));

      await openLightroad(tester, 1);
      expect(find.text('켜진 등대 5 / 5'), findsOneWidget);
      await tapVisible(tester, releaseKey('saga-close'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(SagaMap), findsNothing);
      await closeReleaseApp(tester);
    },
  );

  for (final (size, scale, lang) in [
    (const Size(320, 568), 2.0, 'ko'),
    (const Size(320, 568), 2.0, 'en'),
    (const Size(360, 740), 1.0, 'ko'),
    (const Size(393, 852), 1.0, 'en'),
  ]) {
    testWidgets(
      'ending and credits fit ${size.width} × ${size.height}, $scale ($lang)',
      (tester) async {
        seedCampaign(_completedSaga);
        await openReleaseApp(tester, locale: Locale(lang));
        tester.view.physicalSize = size;
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 30);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        await _settingsAction(tester, 'replay-ending');
        final t = _strings(tester, _skip);
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: releaseKey('ending-lightroad'),
                        matching: find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint && w.painter is EndingLightroad,
                        ),
                      ),
                    )
                    .painter!
                as EndingLightroad;
        expect(
          painter.progress,
          1,
          reason: 'Reduced motion shows the completed map',
        );
        for (final scene in _scenes) {
          expect(releaseKey('ending-$scene'), findsOneWidget);
          expect(_skip.hitTestable(), findsOneWidget);
          expect(_next.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull, reason: scene);
          if (scene == 'farewell') {
            expect(find.text(t.endingFarewell), findsOneWidget);
          }
          await tapVisible(tester, _next);
        }

        final credits = releaseKey('credits-scroll');
        final scrollable = find.descendant(
          of: credits,
          matching: find.byType(Scrollable),
        );
        final thanks = find.text(t.endingThankYou);
        await tester.scrollUntilVisible(thanks, 150, scrollable: scrollable);
        await Scrollable.ensureVisible(tester.element(thanks), alignment: .5);
        await tester.pump();
        expect(
          tester.getRect(credits).contains(tester.getCenter(thanks)),
          isTrue,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          releaseKey('credits-continue'),
          150,
          scrollable: scrollable,
        );
        await tapVisible(tester, releaseKey('credits-continue'));
        await tester.scrollUntilVisible(
          releaseKey('ending-home'),
          180,
          scrollable: find.descendant(
            of: releaseKey('ending-rewards'),
            matching: find.byType(Scrollable),
          ),
        );
        await tapVisible(tester, releaseKey('ending-home'));
        await _settingsAction(tester, 'settings-credits');
        expect(find.byType(CreditsScreen), findsOneWidget);
        await closeReleaseApp(tester);
      },
    );
  }

  testWidgets(
    'normal ending advances on its own and replay can skip immediately',
    (tester) async {
      seedCampaign(_completedSaga);
      final boundary = await openReleaseApp(
        tester,
        captureArt: _capture,
        reduceMotion: false,
      );
      if (_capture) {
        final context = tester.element(find.byType(Scaffold).first);
        await tester.runAsync(
          () => Future.wait([
            precacheImage(
              const AssetImage('assets/art/season1/aster.png'),
              context,
            ),
            for (var world = 2; world < Worlds.finalWorld; world++)
              precacheImage(
                AssetImage('assets/art/world$world/spirits/s$world-25.png'),
                context,
              ),
          ]),
        );
      }
      await _settingsAction(tester, 'replay-ending');
      expect(tester.widget<FilledButton>(_skip).onPressed, isNull);
      const seconds = [9, 10, 5, 9, 7];
      const captureAt = [8300, 6400, 1800, 8650, 900];
      const settle = 240;
      const names = [
        'a-lightroad',
        'b-ascent',
        'c-first-star',
        'd-guardians',
        'e-farewell',
      ];
      for (final (index, scene) in _scenes.indexed) {
        expect(releaseKey('ending-$scene'), findsOneWidget);
        await tester.pump(Duration(milliseconds: captureAt[index]));
        await tester.pump(const Duration(milliseconds: settle));
        expect(releaseKey('ending-$scene'), findsOneWidget);
        expect(tester.widget<FilledButton>(_skip).onPressed, isNotNull);
        if (_capture) {
          await captureReleaseScreen(
            tester,
            boundary,
            'docs/screenshots/ending/${names[index]}.png',
          );
        }
        await tester.pump(
          Duration(
            milliseconds:
                seconds[index] * 1000 - captureAt[index] - settle + 20,
          ),
        );
        await tester.pump();
      }
      expect(find.byType(CreditsScreen), findsOneWidget);
      expect(find.text('corcoidum'), findsOneWidget);
      if (_capture) {
        await captureReleaseScreen(
          tester,
          boundary,
          'docs/screenshots/ending/credits.png',
        );
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await _settingsAction(tester, 'replay-ending');
      expect(tester.widget<FilledButton>(_skip).onPressed, isNotNull);
      await tapVisible(tester, _skip);
      expect(releaseKey('ending-rewards'), findsOneWidget);
      await closeReleaseApp(tester);
    },
  );
}
