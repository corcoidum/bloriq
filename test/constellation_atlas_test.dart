import 'dart:convert';
import 'dart:io';

import 'package:bloriq/constellation/constellation_atlas.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';

/// 1장은 모두 별 3개(황금), 7번은 별 2개.
Map<String, Object> _progress() {
  final levels = (jsonDecode(
    File('assets/levels/levels.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();
  Map<String, Object> entry(int id, int stars) {
    final level = levels.firstWhere((l) => l['id'] == id);
    return {
      'levelId': id,
      'revision': level['revision'] ?? 1,
      'bestMoves': level['minimumMoves'] as int,
      'bestStars': stars,
      'completionCount': 1,
    };
  }

  return {
    'bloriq.audio.music': false,
    'bloriq.audio.effects': false,
    'bloriq.onboarding.v1': 'complete',
    ProgressRepository.storageKey: jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': [for (var id = 1; id <= 5; id++) entry(id, 3), entry(7, 2)],
    }),
  };
}

Future<int?> _open(
  WidgetTester tester, {
  required bool dark,
  required String language,
}) async {
  final session = await loadStorySession(tester);
  final settings = GameSettings(reduceMotion: true);
  int? picked;
  var closed = false;
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? GameTheme.dark : GameTheme.light,
      locale: Locale(language),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              picked = await showConstellationAtlas(context, session, settings);
              closed = true;
            },
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );
  await tapVisible(tester, find.text('OPEN'));
  expect(find.byKey(const ValueKey('constellation-atlas')), findsOneWidget);
  for (var chapter = 1; chapter <= 5; chapter++) {
    await tester.scrollUntilVisible(
      find.byKey(ValueKey('atlas-chapter-$chapter')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('atlas-list')),
        matching: find.byType(Scrollable),
      ),
    );
  }
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('atlas-chapter-1')),
    -120,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('atlas-list')),
      matching: find.byType(Scrollable),
    ),
  );
  expect(tester.takeException(), isNull);
  await tapVisible(tester, find.byKey(const ValueKey('atlas-chapter-1')));
  expect(find.byKey(const ValueKey('atlas-detail-1')), findsOneWidget);
  await tapVisible(tester, find.byKey(const ValueKey('atlas-back')));
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('atlas-chapter-2')),
    120,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('atlas-list')),
      matching: find.byType(Scrollable),
    ),
  );
  await tapVisible(tester, find.byKey(const ValueKey('atlas-chapter-2')));
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('atlas-play-7')),
    120,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('atlas-detail-2')),
      matching: find.byType(Scrollable),
    ),
  );
  await tapVisible(tester, find.byKey(const ValueKey('atlas-play-7')));
  expect(closed, isTrue);
  expect(tester.takeException(), isNull);
  return picked;
}

void main() {
  for (final dark in [true, false]) {
    for (final language in ['ko', 'en']) {
      testWidgets(
        'atlas ${dark ? 'dark' : 'light'} $language: states, detail and replay pick',
        (tester) async {
          SharedPreferences.setMockInitialValues(_progress());
          final picked = await _open(tester, dark: dark, language: language);
          expect(picked, 7);
        },
      );
    }
  }

  testWidgets('atlas cards describe state in words, not color alone', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(_progress());
    final session = await loadStorySession(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: GameTheme.dark,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: ConstellationAtlasDialog(session: session)),
      ),
    );
    await tester.pump();
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        RegExp(r'Moonflower constellation\. 5 of 5 stars lit\. .*Golden'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        RegExp(
          r'Five Lights constellation\. 1 of 5 stars lit\. .*Still asleep',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('320px and 200% text keep the atlas usable', (tester) async {
    SharedPreferences.setMockInitialValues(_progress());
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final picked = await _open(tester, dark: true, language: 'ko');
    expect(picked, 7);
  });
}
