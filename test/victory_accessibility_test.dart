import 'support/start_game.dart';

import 'dart:convert';

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
  for (var frame = 0; frame < 100 && _board.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(_board, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _solve(WidgetTester tester) async {
  final game = _game(tester);
  final solution = const PuzzleSolver().solve(game.controller.state.level)!;
  for (final move in solution) {
    await tester.ensureVisible(_board);
    await tester.pump();
    final before = game.controller.state;
    final block = before.blocks.firstWhere((b) => b.id == move.blockId);
    final board = tester.getRect(_board);
    final cell = board.width / before.level.boardWidth;
    await tester.dragFrom(
      board.topLeft +
          Offset(
            (block.position.x + .5) * cell,
            (block.position.y + .5) * cell,
          ),
      Offset(
        (move.target.x - block.position.x) * cell,
        (move.target.y - block.position.y) * cell,
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      game.controller.state.moves,
      before.moves + 1,
      reason: 'Every horizontal and vertical gesture must move one cell',
    );
  }
  expect(game.controller.state.isComplete, isTrue);
}

Future<void> _tapNext(WidgetTester tester) async {
  final next = find.text('Next level');
  await tester.ensureVisible(next);
  await tester.pump();
  await tester.tap(next);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  for (final feature in [
    (
      'Android disabled animations',
      const FakeAccessibilityFeatures(disableAnimations: true),
    ),
    ('iOS reduce motion', const FakeAccessibilityFeatures(reduceMotion: true)),
  ]) {
    testWidgets('${feature.$1} skips celebration and preserves saved results', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = feature.$2;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpGame(tester, const BloriqApp());
      await _ready(tester);
      final game = _game(tester);
      expect(game.reduceMotion, isTrue);
      await _solve(tester);
      expect(game.celebrationProgress, 1);
      expect(find.text('Skip celebration'), findsNothing);
      expect(find.text('Next level'), findsOneWidget);
      expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
      await _tapNext(tester);
      expect(_game(tester).controller.state.level.id, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('enabling system reduced motion during victory ends it safely', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpGame(tester, const BloriqApp());
    await _ready(tester);
    final game = _game(tester);
    await _solve(tester);
    final completed = game.controller.state;
    expect(game.celebrationProgress, lessThan(1));
    expect(find.text('Skip celebration'), findsOneWidget);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    await tester.pump();
    await tester.pump();
    expect(game.reduceMotion, isTrue);
    expect(game.celebrationProgress, 1);
    expect(game.controller.state, same(completed));
    expect(find.text('Skip celebration'), findsNothing);
    expect(find.text('Next level'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('watchdog reveals result when animation ticker is suspended', (
    tester,
  ) async {
    final ticking = ValueNotifier(true);
    await pumpGame(
      tester,
      ValueListenableBuilder<bool>(
        valueListenable: ticking,
        builder: (context, enabled, child) =>
            TickerMode(enabled: enabled, child: child!),
        child: const BloriqApp(),
      ),
    );
    await _ready(tester);
    final game = _game(tester);
    await _solve(tester);
    final completed = game.controller.state;
    expect(game.celebrationProgress, lessThan(1));
    ticking.value = false;
    await tester.pump();
    final pausedProgress = game.celebrationProgress;
    await tester.pump(const Duration(milliseconds: 500));
    expect(game.celebrationProgress, pausedProgress);
    expect(
      find.text('Next level'),
      findsOneWidget,
      reason: 'Discovery results allow continuing from the first frame',
    );
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump();
    expect(game.celebrationProgress, 1);
    expect(game.controller.state, same(completed));
    expect(find.text('Skip celebration'), findsNothing);
    expect(find.text('Next level'), findsOneWidget);
    expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
    ticking.value = true;
    await tester.pump();
    await _tapNext(tester);
    expect(_game(tester).controller.state.level.id, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    ticking.dispose();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      '${mode.name}: stage 14 and 20 complete through real gestures',
      (tester) async {
        final raw = jsonDecode(
          await rootBundle.loadString('assets/levels/levels.json'),
        ) as List<dynamic>;
        final levels = raw
            .map((json) => Level.fromJson(json as Map<String, dynamic>))
            .where((level) => {14, 20, 21}.contains(level.id))
            .toList();
        final settings = await GameSettings.load();
        await settings.setThemeMode(mode);
        await settings.setReduceMotion(true);
        await pumpGame(
          tester,
          BloriqApp(settings: settings, loadLevels: () async => levels),
          levelId: 14,
        );
        await _ready(tester);
        for (final id in [14, 20]) {
          final game = _game(tester);
          expect(game.controller.state.level.id, id);
          await _solve(tester);
          expect(find.text('Next level'), findsOneWidget);
          final progress = (await ProgressRepository.load()).forLevel(id)!;
          expect(progress.bestMoves, game.controller.state.level.minimumMoves);
          expect(progress.bestStars, 3);
          expect(progress.completionCount, 1);
          await _tapNext(tester);
        }
        expect(_game(tester).controller.state.level.id, 21);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      },
    );
  }
}
