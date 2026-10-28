import 'package:bloriq/design/game_theme.dart';
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

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

Future<void> _ready(WidgetTester tester) async {
  for (var i = 0; i < 100 && _board.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(_board, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _step(WidgetTester tester, PuzzleMove move) async {
  await tester.ensureVisible(_board);
  await tester.pump();
  final state = _game(tester).controller.state;
  final block = state.blocks.firstWhere((block) => block.id == move.blockId);
  final rect = tester.getRect(_board);
  final cell = rect.width / state.level.boardWidth;
  await tester.dragFrom(
    rect.topLeft +
        Offset((block.position.x + .5) * cell, (block.position.y + .5) * cell),
    Offset(
      (move.target.x - block.position.x) * cell,
      (move.target.y - block.position.y) * cell,
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'live theme settings preserve puzzle, follow system, and restore after restart',
    (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(const BloriqApp());
      await _ready(tester);
      final original = _game(tester);
      final solution = const PuzzleSolver().solve(
        original.controller.state.level,
      )!;
      await _step(tester, solution.first);
      final state = original.controller.state;
      expect(state.moves, 1);
      await _tap(tester, find.byTooltip('Settings'));
      await _tap(tester, find.text('Dark'));
      expect(_game(tester), same(original));
      expect(original.controller.state, same(state));
      expect(original.gameColors, same(GameColors.dark));
      expect((await GameSettings.load()).themeMode, ThemeMode.dark);

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pump();
      expect(original.gameColors, same(GameColors.dark));
      await _tap(tester, find.text('System'));
      expect(original.gameColors, same(GameColors.light));
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      expect(original.gameColors, same(GameColors.dark));
      expect(original.controller.state, same(state));
      await _tap(tester, find.text('Light'));
      await _tap(tester, find.text('Close'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const BloriqApp());
      await _ready(tester);
      expect(_game(tester).gameColors, same(GameColors.light));
      expect((await GameSettings.load()).themeMode, ThemeMode.light);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name}: victory saves before animation, skips, and cannot double-complete',
      (tester) async {
        final settings = await GameSettings.load();
        await settings.setThemeMode(mode);
        await tester.pumpWidget(BloriqApp(settings: settings));
        await _ready(tester);
        final game = _game(tester);
        for (final move in const PuzzleSolver().solve(
          game.controller.state.level,
        )!) {
          await _step(tester, move);
        }
        expect(game.controller.state.isComplete, isTrue);
        expect(find.text('Skip celebration'), findsOneWidget);
        final saved = (await ProgressRepository.load()).forLevel(1)!;
        expect(saved.completionCount, 1);
        expect(saved.bestMoves, game.controller.state.moves);
        final completed = game.controller.state;
        // 완료 후 빠른 연속 드래그는 이동/저장 횟수를 늘리지 않는다.
        final rect = tester.getRect(_board);
        for (var i = 0; i < 3; i++) {
          await tester.dragFrom(rect.center, const Offset(60, 0));
        }
        expect(game.controller.state, same(completed));
        await _tap(tester, find.text('Skip celebration'));
        expect(find.text('Skip celebration'), findsNothing);
        expect(find.text('New personal best!'), findsOneWidget);
        expect(find.text('★★★'), findsOneWidget);
        expect(
          (await ProgressRepository.load()).forLevel(1)!.completionCount,
          1,
        );
        await _tap(tester, find.text('Next level'));
        expect(_game(tester).controller.state.level.id, 2);
        expect(_game(tester).controller.state.moves, 0);
        await tester.pump(const Duration(seconds: 2));
        expect(_game(tester).controller.state.moves, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );

    testWidgets(
      '${mode.name}: small display, large text, settings and help fit',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final settings = await GameSettings.load();
        await settings.setThemeMode(mode);
        await tester.pumpWidget(BloriqApp(settings: settings));
        await _ready(tester);
        expect(tester.takeException(), isNull);
        await _tap(tester, find.byTooltip('Settings'));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Reduce motion'));
        expect(settings.reduceMotion, isTrue);
        await _tap(tester, find.text('Close'));
        expect(_game(tester).reduceMotion, isTrue);
        await _tap(tester, find.byTooltip('How to play'));
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Close'));
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }

  testWidgets(
    'system reduced motion finishes an active celebration without changing records',
    (tester) async {
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(const BloriqApp());
      await _ready(tester);
      for (final move in const PuzzleSolver().solve(
        _game(tester).controller.state.level,
      )!) {
        await _step(tester, move);
      }
      expect(find.text('Skip celebration'), findsOneWidget);
      final state = _game(tester).controller.state;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump();
      await tester.pump();
      expect(_game(tester).reduceMotion, isTrue);
      expect(_game(tester).controller.state, same(state));
      expect(find.text('Skip celebration'), findsNothing);
      expect(find.text('Next level'), findsOneWidget);
      expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'independent watchdog reveals results when animation tickers are stopped',
    (tester) async {
      final ticking = ValueNotifier(true);
      await tester.pumpWidget(
        ValueListenableBuilder<bool>(
          valueListenable: ticking,
          child: const BloriqApp(),
          builder: (context, enabled, child) =>
              TickerMode(enabled: enabled, child: child!),
        ),
      );
      await _ready(tester);
      for (final move in const PuzzleSolver().solve(
        _game(tester).controller.state.level,
      )!) {
        await _step(tester, move);
      }
      expect(find.text('Skip celebration'), findsOneWidget);
      ticking.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1800));
      await tester.pump();
      expect(find.text('Skip celebration'), findsNothing);
      expect(find.text('Next level'), findsOneWidget);
      expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
      await _tap(tester, find.text('Next level'));
      expect(_game(tester).controller.state.level.id, 2);
      await tester.pumpWidget(const SizedBox());
      ticking.dispose();
    },
  );

  testWidgets(
    'stage change during victory cancels old callbacks and reduced motion skips timeline',
    (tester) async {
      final settings = await GameSettings.load();
      await tester.pumpWidget(BloriqApp(settings: settings));
      await _ready(tester);
      for (final move in const PuzzleSolver().solve(
        _game(tester).controller.state.level,
      )!) {
        await _step(tester, move);
      }
      expect(find.text('Skip celebration'), findsOneWidget);
      await _tap(tester, find.text('Levels'));
      await _tap(tester, find.text('Level 2').last);
      await tester.pump(const Duration(seconds: 2));
      expect(_game(tester).controller.state.level.id, 2);
      expect(_game(tester).controller.state.moves, 0);
      expect(find.text('You escaped!'), findsNothing);
      await settings.setReduceMotion(true);
      await tester.pump();
      expect(_game(tester).reduceMotion, isTrue);
      for (final move in const PuzzleSolver().solve(
        _game(tester).controller.state.level,
      )!) {
        await _step(tester, move);
      }
      expect(find.text('Skip celebration'), findsNothing);
      expect(find.text('Next level'), findsOneWidget);
      expect((await ProgressRepository.load()).forLevel(2)!.completionCount, 1);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );
}
