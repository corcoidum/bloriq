import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/failing_save_store.dart';

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
      expect(find.text('+25 stardust'), findsOneWidget);
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

  testWidgets('restarting after the starlight path keeps the 2-star cap', (
    tester,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      ProgressionRepository.storageKey,
      '{"version":1,"xp":0,"stardust":40,"backfilled":true}',
    );
    await pumpGame(tester, const BloriqApp());
    expect(find.byKey(const ValueKey('assist-cap-badge')), findsNothing);
    await tapVisible(tester, find.byKey(const ValueKey('starlight-path')));
    expect(_game(tester).hintMove, isNotNull);
    expect(find.byKey(const ValueKey('assist-cap-badge')), findsOneWidget);

    // 예전에는 다시 시작하면 별빛 길을 안 쓴 것처럼 3별을 받을 수 있었다.
    // "별 2개까지" 안내 스낵바가 버튼을 가리지 않게 사라질 때까지 기다린다.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tapVisible(tester, find.byIcon(Icons.refresh_rounded));
    expect(_game(tester).hintMove, isNull);
    expect(find.byKey(const ValueKey('assist-cap-badge')), findsOneWidget);
    expect(find.text('Max ★2'), findsOneWidget);

    await _solve(tester);
    expect(find.text('★★☆'), findsOneWidget);
    final saved = await ProgressionRepository.load();
    // 별빛 길 값(20)은 돌려받지 않고, 2별 첫 클리어 별가루(20)만 받는다.
    expect(saved.stardust, 40 - 20 + 20);
    expect(saved.bareHanded, isEmpty);
    expect(saved.assistCap('1:1'), 3);
  });

  testWidgets(
    'retrying both clear writes grants rewards once and clears help',
    (tester) async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        ProgressionRepository.storageKey,
        '{"version":1,"xp":0,"stardust":40,"backfilled":true}',
      );
      final store = await FailingSaveStore.install();
      await pumpGame(tester, const BloriqApp());
      await tapVisible(tester, find.byKey(const ValueKey('starlight-path')));
      expect(_game(tester).hintMove, isNotNull);

      store.rejectedKeys.add(ProgressRepository.storageKey);
      await _solve(tester);
      final retry = find.byKey(const ValueKey('retry-progress'));
      expect(retry, findsOneWidget);
      await tapVisible(tester, retry);
      expect(retry, findsOneWidget);

      store.rejectedKeys
        ..remove(ProgressRepository.storageKey)
        ..add(ProgressionRepository.storageKey);
      await tapVisible(tester, retry);
      expect(retry, findsOneWidget);

      store.rejectedKeys.clear();
      await tapVisible(tester, retry);
      expect(retry, findsNothing);
      final campaign = await ProgressRepository.load();
      final growth = await ProgressionRepository.load();
      expect(campaign.forLevel(1)?.completionCount, 1);
      expect(campaign.forLevel(1)?.bestStars, 2);
      expect(growth.xp, 60);
      expect(growth.stardust, 40);
      expect(growth.assistCap('1:1'), 3);
      expect(growth.bareHanded, isEmpty);
    },
  );
}
