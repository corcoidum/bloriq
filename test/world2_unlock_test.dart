import 'dart:convert';
import 'dart:io';

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

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

/// 보드 위에서 한 수를 둔다. 권능 수는 막대에서 권능을 고른 뒤 민다.
Future<void> _play(WidgetTester tester, PuzzleMove move) async {
  if (move.power case final power?) {
    await tapVisible(tester, find.byKey(ValueKey('power-${power.id}')));
  }
  final layout = _game(tester).geometry;
  final block = _game(tester).controller.state.blocks
      .firstWhere((b) => b.id == move.blockId);
  final dx = (move.target.x - block.position.x).sign.toDouble();
  final dy = (move.target.y - block.position.y).sign.toDouble();
  // 빛 교대는 방향을 보지 않으므로 축 하나만 골라 민다.
  final direction = dx != 0 ? Offset(dx, 0) : Offset(0, dy == 0 ? 1 : dy);
  await tester.ensureVisible(_board);
  await tester.pump();
  await tester.dragFrom(
    tester.getTopLeft(_board) + layout.center(block.position),
    direction * layout.cellSize * .7,
  );
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  setUp(rootBundle.clear);

  test('the lighthouse opens only with all five world 1 constellations', () {
    expect(Worlds.isUnlocked(2, {1, 2, 3, 4}), false);
    expect(Worlds.isUnlocked(2, {1, 2, 3, 4, 5}), true);
    expect(Worlds.isUnlocked(2, {2, 3, 4, 5, 6}), false);
    expect(Worlds.globalChapter(2, 1), 6);
    expect(Worlds.globalChapter(2, 5), 10);
  });

  test('the world 2 story has 5 chapters, 25 spirits and constellations', () {
    final story = WorldStory.parse(
      File('assets/story/world2.json').readAsStringSync(),
      2,
    );
    expect(story.chapters.map((c) => c.globalChapter), [6, 7, 8, 9, 10]);
    expect(story.spirits.map((s) => s.levelId).toSet(), hasLength(25));
    expect(story.forLevel(105)!.guardian, true);
    expect(story.forLevel(126), isNull);
    for (final constellation in story.chapters.map((c) => c.stars)) {
      expect(constellation.nodes, hasLength(5));
      for (final (a, b) in constellation.edges) {
        expect(a, inInclusiveRange(0, 4));
        expect(b, inInclusiveRange(0, 4));
      }
    }
    expect(story.chapters.take(4).map((c) => c.power), [
      PuzzlePower.moonflowerLeap,
      PuzzlePower.lightSwap,
      PuzzlePower.seal,
      PuzzlePower.wind,
    ]);
  });

  testWidgets('four constellations keep the teaser closed', (tester) async {
    await _seed({1, 2, 3, 4});
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    expect(find.byKey(const ValueKey('world-entry')), findsNothing);
  });

  testWidgets(
    'all five open the lighthouse; stage 1 is played with the power bar',
    (tester) async {
      await _seed({1, 2, 3, 4, 5});
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      final entry = find.byKey(const ValueKey('world-entry'));
      expect(entry, findsOneWidget);
      await tapVisible(tester, entry);
      await tester.pump(const Duration(milliseconds: 400));

      // 지도: 첫 스테이지만 열려 있다.
      final second = find.byKey(const ValueKey('world-stage-102'));
      expect(tester.widget<InkWell>(second).onTap, isNull);
      await tapVisible(tester, find.byKey(const ValueKey('world-continue')));
      await tester.pump(const Duration(milliseconds: 400));

      final controller = _game(tester).controller;
      expect(controller.state.level.id, Worlds.firstLevelId(2));
      // 첫 장은 달꽃 도약만 연다. 나머지 권능은 막대에 나오지 않는다.
      expect(controller.state.powers, {PuzzlePower.moonflowerLeap});
      expect(
        find.byKey(const ValueKey('power-moonflower_leap')),
        findsOneWidget,
      );
      for (final id in ['light_swap', 'seal', 'wind']) {
        expect(find.byKey(ValueKey('power-$id')), findsNothing);
      }

      final solution = const PuzzleSolver(maxStates: 2000000)
          .solve(controller.state.level, powers: controller.state.powers)!;
      expect(solution.any((move) => move.power != null), true);
      for (final move in solution) {
        await _play(tester, move);
      }
      expect(_game(tester).controller.state.isComplete, true);
      expect(_game(tester).controller.usedPower, true);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      final progress = await ProgressRepository.load();
      final record = progress.forLevel(Worlds.firstLevelId(2));
      expect(record?.bestStars, 3);
      final progression = await ProgressionRepository.load();
      expect(progression.xp, greaterThan(0));
      // 권능을 썼으니 맨손 별은 아니다.
      expect(progression.isBareHandedLevel('101:1'), false);
    },
  );
}
