import 'dart:convert';
import 'dart:io';

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
import 'support/world_release.dart';

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
    'a first clear shows stars only; growth records stay out of the result',
    (tester) async {
      await pumpGame(tester, const BloriqApp());
      await _solve(tester);
      expect(find.text('Our star, at last!'), findsOneWidget);
      expect(find.text('★★★'), findsOneWidget);
      expect(find.textContaining('XP'), findsNothing);
      expect(find.textContaining('stardust'), findsNothing);
      // 저장 형식은 그대로라 기록은 계속 쌓인다. 화면만 보여 주지 않는다.
      final saved = await ProgressionRepository.load();
      expect(saved.xp, 70);
      expect(saved.stardust, 25);
    },
  );

  testWidgets(
    'a joined spirit shows in the journey; old perks leave no trace',
    (tester) async {
      final levels = (jsonDecode(
        File('assets/levels/levels.json').readAsStringSync(),
      ) as List).cast<Map<String, dynamic>>();
      seedCampaign({1}, cleared: levels.take(5).map(Level.fromJson));
      final prefs = await SharedPreferences.getInstance();
      // 옛 기록의 별가루·황금 별자리·유대는 읽기만 하고 화면에 쓰지 않는다.
      await prefs.setString(
        ProgressionRepository.storageKey,
        jsonEncode({
          'version': ProgressionRepository.schemaVersion,
          'backfilled': true,
          'stardust': 40,
          'completedChapters': [1],
          'goldenChapters': [1],
          'claimedAchievements': ['golden-1'],
          'bonds': {'s1-01': 8},
        }),
      );
      await openReleaseApp(tester);
      final backfill = releaseKey('dismiss-backfill');
      if (backfill.evaluate().isNotEmpty) await tapVisible(tester, backfill);

      await openHomeJourney(tester, tab: 'spirits');
      expect(find.text('함께하는 정령 1 / 5'), findsOneWidget);
      expect(find.text('루나벨'), findsOneWidget);
      expect(releaseKey('atlas-golden-benefit'), findsNothing);
      expect(releaseKey('journey-tab-rewards'), findsNothing);
      expect(releaseKey('player-level'), findsNothing);

      await openCampaignMap(tester);
      await selectOpenLevel(tester, 6);
      await waitForReleaseWidget(tester, _board);
      // 힌트 버튼에는 값이 없다.
      expect(
        find.descendant(
          of: releaseKey('starlight-path'),
          matching: find.byType(Text),
        ),
        findsNothing,
      );
      await _solve(tester);
      expect(find.textContaining('경험치'), findsNothing);
      expect(find.textContaining('별가루'), findsNothing);
      await closeReleaseApp(tester);
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
    // 값은 없다. 쓰면 별 상한만 알린다.
    expect(find.byKey(const ValueKey('starlight-price')), findsNothing);
    expect(find.byKey(const ValueKey('starlight-note')), findsNothing);
    await tapVisible(tester, find.byKey(const ValueKey('starlight-path')));
    expect(_game(tester).hintMove, isNotNull);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byKey(const ValueKey('starlight-note')), findsOneWidget);
    expect((await ProgressionRepository.load()).stardust, 40);
    await _solve(tester);
    expect(find.text('★★☆'), findsOneWidget);
    final saved = await ProgressionRepository.load();
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
    expect(find.text('Max ★2'), findsNothing);

    await _solve(tester);
    expect(find.text('★★☆'), findsOneWidget);
    final saved = await ProgressionRepository.load();
    // 별빛 길은 값이 없다. 2별 첫 클리어 기록(20)만 더해진다.
    expect(saved.stardust, 40 + 20);
    expect(saved.bareHanded, isEmpty);
    expect(saved.assistCap('1:1'), 3);
  });
}
