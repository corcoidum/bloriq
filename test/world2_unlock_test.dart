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

  test('world 2 introduces its four powers in chapter order', () {
    final story = WorldStory.parse(
      File('assets/story/world2.json').readAsStringSync(),
      2,
    );
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
    await openHomeJourney(tester);
    final world = find.byKey(const ValueKey('journey-world-2'));
    expect(tester.widget<InkWell>(world).onTap, isNull);
  });

  testWidgets(
    'all five open the lighthouse; stage 1 is played with the power bar',
    (tester) async {
      await _seed({1, 2, 3, 4, 5});
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      await openHomeJourney(tester);
      final entry = find.byKey(const ValueKey('journey-world-2'));
      expect(entry, findsOneWidget);
      await tapVisible(tester, entry);
      await tester.pump(const Duration(milliseconds: 400));

      // 지도: 첫 장은 다섯 판을 아무 순서로나 할 수 있다.
      final fifth = find.byKey(const ValueKey('world-stage-105'));
      expect(tester.widget<InkWell>(fifth).onTap, isNotNull);
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

  testWidgets('stuck players get a key hint and can follow the solution', (
    tester,
  ) async {
    await _seed({1, 2, 3, 4, 5});
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await openHomeJourney(tester);
    await tapVisible(tester, find.byKey(const ValueKey('journey-world-2')));
    await tester.pump(const Duration(milliseconds: 400));
    await tapVisible(tester, find.byKey(const ValueKey('world-continue')));
    await tester.pump(const Duration(milliseconds: 400));

    // 세 번 다시 시작하면 도움 버튼이 나타난다.
    expect(find.byKey(const ValueKey('stuck-help')), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tapVisible(tester, find.text('Restart'));
    }
    await tapVisible(tester, find.byKey(const ValueKey('stuck-help')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('help-key')), findsOneWidget);
    expect(find.textContaining('Moonflower Leap'), findsWidgets);

    // 풀이 따라 하기: 매 수마다 빛 화살표가 다음 최단 수를 가리킨다.
    await tapVisible(tester, find.byKey(const ValueKey('help-guide')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('guide-banner')), findsOneWidget);
    for (var step = 0; step < 30; step++) {
      final game = _game(tester);
      if (game.controller.state.isComplete) break;
      final hint = game.hintMove!;
      final dx = (hint.to.x - hint.from.x).sign.toDouble();
      final dy = (hint.to.y - hint.from.y).sign.toDouble();
      final direction = dx != 0 ? Offset(dx, 0) : Offset(0, dy == 0 ? 1 : dy);
      await tester.ensureVisible(_board);
      await tester.pump();
      await tester.dragFrom(
        tester.getTopLeft(_board) + game.geometry.center(hint.from),
        direction * game.geometry.cellSize * .7,
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
    final controller = _game(tester).controller;
    expect(controller.state.isComplete, true);
    expect(controller.state.moves, controller.state.level.minimumMoves);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    // 최소 수로 깼어도 풀이를 따라갔으니 별 1개만 남는다.
    final progress = await ProgressRepository.load();
    expect(progress.forLevel(Worlds.firstLevelId(2))?.bestStars, 1);
  });
}
