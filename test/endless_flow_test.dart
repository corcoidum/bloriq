import 'dart:convert';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_repository.dart';
import 'package:bloriq/endless/puzzle_generator.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/player_repository.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/story/collection_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

Future<void> _openEndless(WidgetTester tester) async {
  await tester.pumpWidget(const BloriqApp(showIntro: false));
  await waitForHome(tester);
  await tapVisible(tester, find.byKey(const ValueKey('home-endless')));
  for (var i = 0; i < 100 && _board.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pump(const Duration(milliseconds: 300));
  expect(_board, findsOneWidget);
}

Future<void> _solve(WidgetTester tester) async {
  final game = _game(tester);
  for (final move in const PuzzleSolver().solve(game.controller.state.level)!) {
    await tester.ensureVisible(_board);
    await tester.pump();
    final state = game.controller.state;
    final block = state.blocks.firstWhere((b) => b.id == move.blockId);
    final rect = tester.getRect(_board);
    final cell = rect.width / state.level.boardWidth;
    await tester.dragFrom(
      rect.topLeft +
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
  }
  expect(game.controller.state.isComplete, isTrue);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    rootBundle.clear();
    EndlessRepository.runInline = true;
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
      'bloriq.onboarding.v1': 'skipped',
    });
  });
  tearDown(() => EndlessRepository.runInline = false);

  testWidgets('new players do not see endless until the tutorial is done', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
    });
    await tester.pumpWidget(const BloriqApp(showIntro: false));
    await waitForHome(tester);
    expect(find.byKey(const ValueKey('home-endless')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'each clear gives a new puzzle, combo and experience, and never touches the campaign',
    (tester) async {
      await _openEndless(tester);
      expect(find.text('Path 1'), findsOneWidget);
      final seen = <String>{};
      var expectedXp = 0;
      for (var round = 0; round < 3; round++) {
        final level = _game(tester).controller.state.level;
        seen.add(puzzleFingerprint(level));
        await _solve(tester);
        final score = RunScore.of(
          minimumMoves: level.minimumMoves,
          stars: 3,
          combo: 1 + round * .1,
        ).total;
        expectedXp += score;
        expect(find.text('$score'), findsOneWidget, reason: 'round $round');
        // 같은 판을 다시 깨서 경험치를 벌 수 없다.
        expect(find.byTooltip('Try again'), findsNothing);
        await tapVisible(tester, find.byKey(const ValueKey('result-next')));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(seen, hasLength(3));
      expect(find.text('Path 4'), findsOneWidget);
      expect(find.textContaining('Combo'), findsOneWidget);

      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString(PlayerRepository.storageKey)!)['xp'],
        expectedXp,
      );
      expect(prefs.getString(ProgressRepository.storageKey), isNull);
      final collection = prefs.getString(CollectionRepository.storageKey);
      if (collection != null) {
        expect(jsonDecode(collection)['owned'], isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('restarting breaks the streak', (tester) async {
    await _openEndless(tester);
    await _solve(tester);
    await tapVisible(tester, find.byKey(const ValueKey('result-next')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Combo'), findsOneWidget);
    await tapVisible(tester, find.text('Restart'));
    expect(find.textContaining('Combo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving and returning resumes the same puzzle', (tester) async {
    await _openEndless(tester);
    final first = puzzleFingerprint(_game(tester).controller.state.level);
    await tapVisible(tester, find.byKey(const ValueKey('game-home')));
    await tester.pump(const Duration(milliseconds: 400));
    await waitForHome(tester);
    await tapVisible(tester, find.byKey(const ValueKey('home-endless')));
    for (var i = 0; i < 100 && _board.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(puzzleFingerprint(_game(tester).controller.state.level), first);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home shows the best streak after a run', (tester) async {
    await _openEndless(tester);
    await _solve(tester);
    await tapVisible(tester, find.byKey(const ValueKey('result-home')));
    await tester.pump(const Duration(milliseconds: 400));
    await waitForHome(tester);
    expect(find.textContaining('best streak 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
