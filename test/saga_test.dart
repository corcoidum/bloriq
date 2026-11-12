import 'dart:convert';
import 'dart:io';

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:bloriq/world/world_text.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

Future<void> _seed(Set<int> chapters) async {
  SharedPreferences.setMockInitialValues({
    'bloriq.onboarding.v1': 'skipped',
    GameAudio.musicKey: false,
    GameAudio.effectsKey: false,
    ProgressionRepository.storageKey: jsonEncode({
      'version': 1,
      'xp': 0,
      'stardust': 0,
      'backfilled': true,
      'completedChapters': chapters.toList()..sort(),
    }),
  });
}

Future<void> _openSaga(WidgetTester tester) async {
  await openHomeJourney(tester);
  await tapVisible(
    tester,
    find.byKey(const ValueKey('journey-lightroad-story')),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Map<String, dynamic> _sagaJson() =>
    jsonDecode(File(Saga.asset).readAsStringSync()) as Map<String, dynamic>;

void main() {
  setUp(rootBundle.clear);

  group('saga registry', () {
    final saga = Saga.fromJson(_sagaJson());

    test('seven worlds: prelude, five lighthouses, the First Star', () {
      expect(saga.worlds, hasLength(7));
      expect(saga.worlds.map((w) => w.lighthouse), [null, 1, 2, 3, 4, 5, null]);
      expect(saga.world(1).playable, isTrue);
      expect(saga.world(2).playable, isTrue);
      expect(saga.next(2)!.number, 3);
      expect(saga.next(7), isNull);
    });

    test('a playable world may not follow a planned one', () {
      final data = _sagaJson();
      final worlds = (data['worlds'] as List).cast<Map<String, dynamic>>();
      worlds[2] = {...worlds[2], 'status': 'planned'};
      worlds[3] = {
        ...worlds[3],
        'status': 'playable',
        'levels': 'a.json',
        'story': 'b.json',
      };
      expect(() => Saga.fromJson(data), throwsFormatException);
    });

    test('a playable expansion world needs its assets', () {
      final data = _sagaJson();
      final worlds = (data['worlds'] as List).cast<Map<String, dynamic>>();
      worlds[1] = {...worlds[1]}..remove('levels');
      expect(() => Saga.fromJson(data), throwsFormatException);
    });
  });

  test('numbering rules extend to any world', () {
    expect(Worlds.firstLevelId(1), 1);
    expect(Worlds.firstLevelId(2), 101);
    expect(Worlds.firstLevelId(3), 201);
    expect(Worlds.worldOf(25), 1);
    expect(Worlds.worldOf(125), 2);
    expect(Worlds.worldOf(201), 3);
    expect(Worlds.stageNumber(203), 3);
    expect(Worlds.chapterOf(110), 2);
    expect(Worlds.chaptersOf(3), {11, 12, 13, 14, 15});
    expect(Worlds.isUnlocked(1, {}), true);
    expect(Worlds.isUnlocked(3, {1, 2, 3, 4, 5, 6, 7, 8, 9}), false);
    expect(Worlds.isUnlocked(3, {6, 7, 8, 9, 10}), true);
  });

  test('Korean entry labels pick the right particle', () {
    expect(
      WorldText.enter(const StoryText('구름바다 등대', 'Lighthouse')).ko,
      '구름바다 등대로',
    );
    expect(
      WorldText.enter(const StoryText('달빛 숲 정원', 'Garden')).ko,
      '달빛 숲 정원으로',
    );
    expect(WorldText.enter(const StoryText('첫 별', 'Star')).ko, '첫 별로');
  });

  testWidgets('before the lighthouse, the saga map still shows what is next', (
    tester,
  ) async {
    await _seed({1, 2});
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await _openSaga(tester);

    expect(find.text('Lighthouses lit 0 / 5'), findsOneWidget);
    expect(find.byKey(const ValueKey('saga-enter-1')), findsOneWidget);
    // 세계 2는 아직 잠겨 있지만 예고는 보인다. 더 먼 세계는 이름만 남는다.
    expect(find.byKey(const ValueKey('saga-enter-2')), findsNothing);
    expect(
      find.textContaining('a dark lighthouse waits for RIQ'),
      findsOneWidget,
    );
    expect(
      find.textContaining('an echo shaped exactly like RIQ'),
      findsNothing,
    );
  });

  testWidgets('finishing world 2 lights a lighthouse and teases world 3', (
    tester,
  ) async {
    final world3Playable = Saga.fromJson(_sagaJson()).world(3).playable;
    await _seed({for (var c = 1; c <= 10; c++) c});
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await _openSaga(tester);

    expect(find.text('Lighthouses lit 1 / 5'), findsOneWidget);
    // 지나온 세계는 풀린 수수께끼를 보여 준다.
    expect(
      find.textContaining("RIQ was not a footprint but the lighthouse"),
      findsOneWidget,
    );
    final world3 = find.byKey(const ValueKey('saga-world-3'));
    await tester.ensureVisible(world3);
    await tester.pump();
    expect(
      find.descendant(of: world3, matching: find.text('Coming soon')),
      world3Playable ? findsNothing : findsOneWidget,
    );
    expect(
      find.descendant(
        of: world3,
        matching: find.textContaining('an echo shaped exactly like RIQ'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('saga-enter-3')),
      world3Playable ? findsOneWidget : findsNothing,
    );

    // 다 마친 세계로 다시 들어갈 수 있다.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('saga-enter-2')),
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tapVisible(tester, find.byKey(const ValueKey('saga-enter-2')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('world-continue')), findsOneWidget);
  });

  testWidgets('clearing world 1 points to the next world, not stage 1', (
    tester,
  ) async {
    final levels = (jsonDecode(
      File('assets/levels/levels.json').readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    SharedPreferences.setMockInitialValues({
      'bloriq.onboarding.v1': 'skipped',
      GameAudio.musicKey: false,
      GameAudio.effectsKey: false,
      ProgressRepository.storageKey: jsonEncode({
        'version': ProgressRepository.schemaVersion,
        'levels': [
          for (final level in levels.where((l) => (l['id'] as int) < 25))
            {
              'levelId': level['id'],
              'revision': level['revision'] ?? 1,
              'bestMoves': level['minimumMoves'],
              'bestStars': 3,
              'completionCount': 1,
            },
        ],
      }),
      ProgressionRepository.storageKey: jsonEncode({
        'version': 1,
        'xp': 0,
        'stardust': 0,
        'backfilled': true,
        'completedChapters': [1, 2, 3, 4],
      }),
    });
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await openCampaignMap(tester);
    await selectOpenLevel(tester, 25);
    final board = find.byType(GameWidget<BloriqGame>);
    BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;
    for (final move in const PuzzleSolver().solve(
      game().controller.state.level,
    )!) {
      await tester.ensureVisible(board);
      await tester.pump();
      final block = game().controller.state.blocks.firstWhere(
        (b) => b.id == move.blockId,
      );
      final geometry = game().geometry;
      await tester.dragFrom(
        tester.getTopLeft(board) + geometry.center(block.position),
        Offset(
              (move.target.x - block.position.x).toDouble(),
              (move.target.y - block.position.y).toDouble(),
            ) *
            geometry.cellSize *
            .7,
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.byKey(const ValueKey('world-clear')), findsOneWidget);
    final next = find.byKey(const ValueKey('result-next'));
    expect(
      find.descendant(
        of: next,
        matching: find.text('To the Cloud-Sea Lighthouse'),
      ),
      findsOneWidget,
    );
    // 누르면 게임을 닫고 구름바다 등대 지도가 바로 열린다.
    await tapVisible(tester, next);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const ValueKey('world-continue')), findsOneWidget);
  });
}
