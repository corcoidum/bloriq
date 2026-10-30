import 'dart:async';

import 'package:bloriq/app/intro_screen.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/legacy_levels.dart';
import 'support/start_game.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

Future<void> _waitIntro(WidgetTester tester) async {
  await waitForHome(tester);
  await tapVisible(tester, find.byTooltip('Settings'));
  await tapVisible(tester, find.byKey(const ValueKey('replay-intro')));
  for (var i = 0; i < 100 && find.byType(IntroScreen).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(find.byType(IntroScreen), findsOneWidget);
}

Future<void> _play(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const ValueKey('home-play')));
  for (var i = 0; i < 100 && _board.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
  expect(_board, findsOneWidget);
}

Future<void> _move(WidgetTester tester, int x, int y, int dx, int dy) async {
  await tester.ensureVisible(_board);
  await tester.pump();
  final rect = tester.getRect(_board);
  final cell = rect.width / _game(tester).controller.state.level.boardWidth;
  await tester.dragFrom(
    rect.topLeft + Offset((x + .5) * cell, (y + .5) * cell),
    Offset(dx * cell, dy * cell),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'bloriq.onboarding.v1': 'skipped',
      GameAudio.musicKey: false,
      GameAudio.effectsKey: false,
    });
  });

  testWidgets(
    'returning cold starts enter journey home directly without demo progress',
    (tester) async {
      for (var i = 0; i < 2; i++) {
        await tester.pumpWidget(BloriqApp(loadLevels: loadLegacyLevels));
        await waitForHome(tester);
        expect(find.byType(IntroScreen), findsNothing);
        expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
        expect(
          (await SharedPreferences.getInstance()).getString(
            ProgressRepository.storageKey,
          ),
          isNull,
        );
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('manual four-second intro finishes once after repeated skip', (
    tester,
  ) async {
    await tester.pumpWidget(BloriqApp(loadLevels: loadLegacyLevels));
    await _waitIntro(tester);
    await tester.pump(const Duration(milliseconds: 1000));
    final skip = tester
        .widget<TextButton>(find.byKey(const ValueKey('skip-intro')))
        .onPressed!;
    skip();
    skip();
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump(const Duration(seconds: 5));
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home remains responsive while levels are loading', (
    tester,
  ) async {
    final pending = Completer<List<Level>>();
    await tester.pumpWidget(BloriqApp(loadLevels: () => pending.future));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(IntroScreen), findsNothing);
    final play = find.byKey(const ValueKey('home-play'));
    expect(tester.widget<FilledButton>(play).onPressed, isNull);
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
    pending.complete(await loadLegacyLevels());
    await waitForHome(tester);
    await _play(tester);
    expect(_game(tester).controller.state.level.id, 1);
    await _move(tester, 0, 1, 1, 0);
    expect(_game(tester).controller.state.moves, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('level-load failure offers a working retry after intro', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      BloriqApp(
        loadLevels: () async {
          if (++attempts == 1) throw const FormatException('bad fixture');
          return loadLegacyLevels();
        },
      ),
    );
    for (
      var i = 0;
      i < 100 && find.byKey(const ValueKey('retry-load')).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('Could not load the levels.'), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('retry-load')));
    await waitForHome(tester);
    expect(attempts, 2);
    await _play(tester);
    await tester.pumpWidget(const SizedBox());
  });

  for (final completed in <List<int>>[
    [],
    [1],
    [2],
    [1, 2],
  ]) {
    testWidgets(
      'play picks first unfinished stage for $completed; all done returns to first',
      (tester) async {
        final levels = (await loadLegacyLevels()).take(2).toList();
        final progress = await ProgressRepository.load();
        for (final id in completed) {
          final level = levels.firstWhere((level) => level.id == id);
          await progress.recordCompletion(
            levelId: id,
            moves: level.minimumMoves,
            minimumMoves: level.minimumMoves,
          );
        }
        await tester.pumpWidget(BloriqApp(loadLevels: () async => levels));
        await waitForHome(tester);
        expect(find.text('${completed.length} / 2 completed'), findsOneWidget);
        expect(find.text('${completed.length * 3} stars'), findsOneWidget);
        await _play(tester);
        final expectedId = completed.contains(1) && !completed.contains(2)
            ? 2
            : 1;
        expect(_game(tester).controller.state.level.id, expectedId);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('completion refreshes home progress and next-stage target', (
    tester,
  ) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    await _move(tester, 0, 1, 1, 0);
    await _move(tester, 1, 1, 1, 0);
    await tapVisible(tester, find.byKey(const ValueKey('game-home')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('1 / 25 completed'), findsOneWidget);
    expect(find.text('3 stars'), findsOneWidget);
    expect(find.text('Continue · Gate 2'), findsOneWidget);
    await _play(tester);
    expect(_game(tester).controller.state.level.id, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'unfinished home exit confirms; cancel and background preserve board; leave resets it',
    (tester) async {
      await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
      await _move(tester, 0, 1, 1, 0);
      final game = _game(tester);
      final state = game.controller.state;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.byType(IntroScreen), findsNothing);
      expect(game.controller.state, same(state));
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Return home?'), findsOneWidget);
      await tapVisible(tester, find.text('Keep playing'));
      expect(_game(tester), same(game));
      expect(game.controller.state, same(state));
      await tapVisible(tester, find.byKey(const ValueKey('game-home')));
      await tapVisible(tester, find.text('Return home'));
      await tester.pump(const Duration(milliseconds: 400));
      await waitForHome(tester);
      await _play(tester);
      expect(_game(tester).controller.state.moves, 0);
      expect(_game(tester).controller.canUndo, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('intro replay from settings preserves board and Undo history', (
    tester,
  ) async {
    await pumpGame(tester, BloriqApp(loadLevels: loadLegacyLevels));
    await _move(tester, 0, 1, 1, 0);
    final game = _game(tester);
    final state = game.controller.state;
    await tapVisible(tester, find.byTooltip('Settings'));
    await tapVisible(tester, find.byKey(const ValueKey('replay-intro')));
    expect(find.byType(IntroScreen), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('skip-intro')));
    expect(_game(tester), same(game));
    expect(game.controller.state, same(state));
    await tapVisible(tester, find.text('Undo'));
    expect(game.controller.state.moves, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('background ends intro; resume stays home', (tester) async {
    await tester.pumpWidget(BloriqApp(loadLevels: loadLegacyLevels));
    await _waitIntro(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await waitForHome(tester);
    expect(find.byType(IntroScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final (index, feature) in [
    const FakeAccessibilityFeatures(disableAnimations: true),
    const FakeAccessibilityFeatures(reduceMotion: true),
  ].indexed) {
    testWidgets('system reduced motion skips intro: $index', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = feature;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(const BloriqApp());
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.byType(IntroScreen), findsNothing);
      expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'app reduced motion changing during intro completes immediately',
    (tester) async {
      final settings = GameSettings();
      await tester.pumpWidget(BloriqApp(settings: settings));
      await _waitIntro(tester);
      await settings.setReduceMotion(true);
      await tester.pump();
      await tester.pump();
      expect(find.byType(IntroScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets('watchdog ends intro with tickers disabled', (tester) async {
    final settings = GameSettings();
    await tester.pumpWidget(
      TickerMode(enabled: false, child: BloriqApp(settings: settings)),
    );
    await _waitIntro(tester);
    await tester.pump(const Duration(milliseconds: 4300));
    await tester.pump();
    expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
    expect(find.byType(IntroScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets('all 25 stages remain available in the scrollable grid', (
    tester,
  ) async {
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
    await selectOpenLevel(tester, 25);
    expect(_game(tester).controller.state.level.id, 25);
    await tester.pumpWidget(const SizedBox());
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final locale in ['en', 'ko']) {
      for (final size in [
        const Size(320, 568),
        const Size(390, 844),
        const Size(768, 1024),
      ]) {
        testWidgets(
          '${mode.name} $locale $size: home, level grid, settings, help fit at 200% text',
          (tester) async {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = 2;
            tester.platformDispatcher.localesTestValue = [Locale(locale)];
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            addTearDown(tester.platformDispatcher.clearLocalesTestValue);
            final settings = GameSettings(themeMode: mode);
            await tester.pumpWidget(BloriqApp(settings: settings));
            await waitForHome(tester);
            expect(tester.takeException(), isNull);
            await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
            expect(tester.takeException(), isNull);
            await selectOpenLevel(tester, 25);
            expect(tester.takeException(), isNull);
            final isKo = locale == 'ko';
            await tapVisible(tester, find.byTooltip(isKo ? '설정' : 'Settings'));
            expect(tester.takeException(), isNull);
            await tapVisible(tester, find.text(isKo ? '닫기' : 'Close'));
            await tapVisible(
              tester,
              find.byTooltip(isKo ? '게임 방법' : 'How to play'),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            settings.dispose();
          },
        );
      }
    }
  }
}
