import 'dart:convert';
import 'dart:io';

import 'package:bloriq/app/play_context.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/tutorial/echo_tutorial.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

final board = find.byType(GameWidget<BloriqGame>);
BloriqGame game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(board).game!;
Future<void> ready(WidgetTester tester) async {
  for (var i = 0; i < 150 && board.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 350));
  expect(board, findsOneWidget);
}

Future<void> swipe(WidgetTester tester, int x, int direction) async {
  await tester.ensureVisible(board);
  await tester.pump();
  final rect = tester.getRect(board);
  final cell = rect.width / 3;
  await tester.dragFrom(
    rect.topLeft + Offset((x + .5) * cell, 1.5 * cell),
    Offset(direction * cell, 0),
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  test('failed migration and completion writes retain source and report unsaved memory state', () async {
    final raw = jsonEncode({
      'version': 1,
      'levels': [
        {'levelId': 6, 'bestMoves': 6, 'bestStars': 3, 'completionCount': 1},
      ],
    });
    SharedPreferences.setMockInitialValues({
      ProgressRepository.course2StorageKey: raw,
    });
    final repo = await ProgressRepository.load(writer: (_, _) async => false);
    expect(repo.saveFailed, true);
    expect(repo.forLevel(6)!.bestMoves, 6);
    final result = await repo.recordCompletion(
      levelId: 2,
      revision: 2,
      moves: 4,
      minimumMoves: 4,
    );
    expect(result.saved, false);
    expect(repo.forLevel(2, revision: 2), isNotNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString(ProgressRepository.course2StorageKey), raw);
    expect(preferences.getString(ProgressRepository.storageKey), isNull);
    expect((await ProgressRepository.load()).forLevel(6)!.bestMoves, 6);
  });
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
    });
  });
  test('migration archives changed revisions, preserves unchanged and older course', () async {
    final old = jsonEncode({
      'version': 1,
      'levels': [
        for (final id in [1, 2, 6, 25])
          {'levelId': id, 'bestMoves': 4, 'bestStars': 3, 'completionCount': 2},
      ],
    });
    SharedPreferences.setMockInitialValues({
      ProgressRepository.course2StorageKey: old,
      ProgressRepository.legacyStorageKey: 'older course',
    });
    final repo = await ProgressRepository.load();
    expect(repo.forLevel(2, revision: 2), isNull);
    expect(repo.forLevel(2)!.completionCount, 2);
    expect(repo.forLevel(6)!.bestStars, 3);
    await repo.recordCompletion(
      levelId: 2,
      revision: 2,
      moves: 4,
      minimumMoves: 4,
    );
    final loaded = await ProgressRepository.load();
    expect(loaded.forLevel(2, revision: 2)!.completionCount, 1);
    expect(loaded.forLevel(2)!.completionCount, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ProgressRepository.course2StorageKey), old);
    expect(
      prefs.getString(ProgressRepository.legacyStorageKey),
      'older course',
    );
  });
  test('only 2..5 changed and both current and archived layouts remain identifiable', () {
    final baseline = jsonDecode(
      File('assets/levels/course2_baseline.json').readAsStringSync(),
    ) as List;
    final current = jsonDecode(
      File('assets/levels/levels.json').readAsStringSync(),
    ) as List;
    for (var i = 0; i < 25; i++) {
      if (i >= 1 && i <= 4) {
        expect(current[i]['revision'], 2);
      } else {
        expect(current[i], baseline[i]);
      }
    }
  });
  test(
    'solver solves current state and distinguishes limit from no solution',
    () {
      final levels = (jsonDecode(
        File('assets/levels/levels.json').readAsStringSync(),
      ) as List).map((v) => Level.fromJson(v)).toList();
      final c = PuzzleController(levels[1]);
      final moves = const PuzzleSolver().solve(levels[1])!;
      c.move(moves.first.blockId, moves.first.target);
      expect(
        const PuzzleSolver().solveFromState(c.state)!.length,
        moves.length - 1,
      );
      expect(
        () => const PuzzleSolver(maxStates: 1).solve(levels[1]),
        throwsStateError,
      );
    },
  );
  testWidgets(
    'unfinished tutorial starts fresh after process restart; home exit is a skip',
    (tester) async {
      await tester.pumpWidget(const BloriqApp());
      await ready(tester);
      await swipe(tester, 0, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const BloriqApp());
      await ready(tester);
      expect(game(tester).controller.state.moves, 0);
      expect(find.byKey(const ValueKey('skip-tutorial')), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('game-home')));
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        (await SharedPreferences.getInstance()).getString(
          Onboarding.storageKey,
        ),
        'skipped',
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'fresh launch teaches real Echo in three gestures and saves campaign once',
    (tester) async {
      await tester.pumpWidget(const BloriqApp());
      await ready(tester);
      expect(find.byKey(const ValueKey('intro-screen')), findsNothing);
      expect(
        tester.widget<InkWell>(find.byKey(const ValueKey('game-levels'))).onTap,
        isNull,
      );
      await swipe(tester, 0, 1);
      expect(find.textContaining('Try sliding back left'), findsOneWidget);
      expect(game(tester).controller.state.moves, 1);
      expect(game(tester).controller.state.echo, const Position(0, 1));
      await swipe(tester, 1, -1);
      expect(game(tester).controller.state.moves, 1);
      await swipe(tester, 1, 1);
      expect(game(tester).controller.state.isComplete, true);
      expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
      expect(
        (await SharedPreferences.getInstance()).getString(
          Onboarding.storageKey,
        ),
        'complete',
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(const BloriqApp());
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.byKey(const ValueKey('intro-screen')), findsNothing);
      await waitForHome(tester);
      expect(find.byKey(const ValueKey('home-screen')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'skip preserves moved board and persists; practice never saves campaign',
    (tester) async {
      await tester.pumpWidget(const BloriqApp());
      await ready(tester);
      await swipe(tester, 0, 1);
      final state = game(tester).controller.state;
      await tapVisible(tester, find.byKey(const ValueKey('skip-tutorial')));
      expect(game(tester).controller.state, same(state));
      expect(
        tester.widget<InkWell>(find.byKey(const ValueKey('game-levels'))).onTap,
        isNotNull,
      );
      await tapVisible(tester, find.byTooltip('How to play'));
      await tapVisible(tester, find.byKey(const ValueKey('replay-tutorial')));
      await ready(tester);
      await swipe(tester, 0, 1);
      await swipe(tester, 1, -1);
      await swipe(tester, 1, 1);
      expect((await ProgressRepository.load()).forLevel(1), isNull);
      expect(
        tester.widget<GameScreen>(find.byType(GameScreen).last).play.mode,
        PlayMode.tutorialReplay,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
