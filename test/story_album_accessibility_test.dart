import 'dart:convert';

import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/story/spirit_album.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';

void main() {
  for (final chapter in [1, 5]) {
    for (final dark in [true, false]) {
      for (final language in ['ko', 'en']) {
        testWidgets(
          'chapter $chapter: 320px 200% text ${dark ? 'dark' : 'light'} $language: album hides unknown memories and keeps actions accessible',
          (tester) async {
            SharedPreferences.setMockInitialValues({
              'bloriq.audio.music': false,
              'bloriq.audio.effects': false,
            });
            tester.view.physicalSize = const Size(320, 568);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final session = await loadStorySession(tester);
            await session.collection.reconcile(
              chapter == 1 ? {1, 2, 5} : {21, 22, 25},
            );
            final settings = GameSettings(reduceMotion: true);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? GameTheme.dark : GameTheme.light,
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () =>
                          showSpiritAlbum(context, session, settings),
                      child: const Text('OPEN'),
                    ),
                  ),
                ),
              ),
            );
            await tapVisible(tester, find.text('OPEN'));
            expect(tester.takeException(), isNull);
            expect(
              find.text(
                language == 'ko'
                    ? (chapter == 1 ? '도토' : '오르')
                    : (chapter == 1 ? 'Doto' : 'Or'),
              ),
              findsNothing,
            );
            expect(
              find.text(
                language == 'ko'
                    ? (chapter == 1 ? '루루' : '루체')
                    : (chapter == 1 ? 'Lulu' : 'Luche'),
              ),
              findsNothing,
            );
            await tapVisible(
              tester,
              find.byKey(
                ValueKey(
                  'spirit-s1-${(chapter * 5).toString().padLeft(2, '0')}',
                ),
              ),
            );
            expect(tester.takeException(), isNull);
            await tapVisible(
              tester,
              find.byKey(const ValueKey('equip-companion')),
            );
            expect(
              session.collection.companion?.id,
              's1-${(chapter * 5).toString().padLeft(2, '0')}',
            );
            expect(tester.takeException(), isNull);
            await tapVisible(
              tester,
              find.text(language == 'ko' ? '닫기' : 'Close').last,
            );
            await tapVisible(
              tester,
              find.byTooltip(language == 'ko' ? '닫기' : 'Close'),
            );
            await tester.pumpWidget(const SizedBox());
            await disposeStorySession(tester, session);
            settings.dispose();
          },
        );
      }
    }
  }

  testWidgets(
    'returning old revision owner gets one summary, current revision stars remain separate',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'bloriq.audio.music': false,
        'bloriq.audio.effects': false,
        ProgressRepository.course2StorageKey: jsonEncode({
          'version': 1,
          'levels': [
            {
              'levelId': 2,
              'bestMoves': 4,
              'bestStars': 3,
              'completionCount': 7,
            },
          ],
        }),
      });
      for (var launch = 0; launch < 2; launch++) {
        rootBundle.clear();
        final settings = GameSettings(reduceMotion: true);
        await tester.pumpWidget(BloriqApp(settings: settings));
        await waitForHome(tester);
        final summary = find.byKey(const ValueKey('dismiss-backfill'));
        expect(summary, launch == 0 ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('skip-story')), findsNothing);
        expect(find.text('0 / 25 completed'), findsOneWidget);
        if (launch == 0) await tapVisible(tester, summary);
        await tapVisible(tester, find.byKey(const ValueKey('home-album')));
        expect(
          find.descendant(
            of: find.byType(SpiritAlbum),
            matching: find.text('Pomi'),
          ),
          findsOneWidget,
        );
        expect(find.text('Mori'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      }
      expect((await ProgressRepository.load()).forLevel(2)!.completionCount, 7);
    },
  );
}
