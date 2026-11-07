import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

Future<void> _solve(WidgetTester tester) async {
  final solution = const PuzzleSolver().solve(
    _game(tester).controller.state.level,
  )!;
  for (final move in solution) {
    final layout = _game(tester).geometry;
    final block = _game(tester).controller.state.blocks
        .firstWhere((b) => b.id == move.blockId);
    await tester.ensureVisible(_board);
    await tester.pump();
    await tester.dragFrom(
      tester.getTopLeft(_board) + layout.center(block.position),
      Offset(
            (move.target.x - block.position.x).toDouble(),
            (move.target.y - block.position.y).toDouble(),
          ) *
          layout.cellSize *
          .7,
    );
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pump(const Duration(seconds: 3));
  await tester.pump();
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
    'a first clear grants XP and stardust and shows them in the result',
    (tester) async {
      await pumpGame(tester, const BloriqApp());
      await _solve(tester);
      expect(find.text('Our star, at last!'), findsOneWidget);
      // 첫 클리어 3별: 40 + 30 경험치, 별가루 15 + 10.
      expect(find.text('+70 XP'), findsOneWidget);
      expect(find.text('✦ +25 stardust'), findsOneWidget);
      final saved = await ProgressionRepository.load();
      expect(saved.xp, 70);
      expect(saved.stardust, 25);
    },
  );

  testWidgets('the starlight path shows a move and caps the clear at 2 stars', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      ProgressionRepository.storageKey,
      '{"version":1,"xp":0,"stardust":40,"backfilled":true}',
    );
    await pumpGame(tester, const BloriqApp());
    await tapVisible(tester, find.byKey(const ValueKey('starlight-path')));
    expect(_game(tester).hintMove, isNotNull);
    await _solve(tester);
    expect(find.text('★★☆'), findsOneWidget);
    final saved = await ProgressionRepository.load();
    expect(saved.stardust, lessThan(40 + 25));
    expect(saved.bareHanded, isEmpty);
  });
}
