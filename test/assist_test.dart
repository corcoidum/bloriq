import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/assist.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:bloriq/world/world_progress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

LoadedWorld _world2() {
  final saga = Saga.parse(File(Saga.asset).readAsStringSync());
  final info = saga.world(2);
  return LoadedWorld(
    info: info,
    levels: Worlds.parseLevels(File(info.levelsAsset!).readAsStringSync(), 2),
    story: WorldStory.parse(File(info.storyAsset!).readAsStringSync(), 2),
  );
}

Future<ProgressRepository> _progress(
  List<int> cleared,
  LoadedWorld world,
) async {
  SharedPreferences.setMockInitialValues({
    ProgressRepository.storageKey: jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': [
        for (final id in cleared)
          {
            'levelId': id,
            'revision': world.levels.firstWhere((l) => l.id == id).revision,
            'bestMoves': 99,
            'bestStars': 1,
            'completionCount': 1,
          },
      ],
    }),
  });
  return ProgressRepository.load();
}

void main() {
  group('chapters open in any order', () {
    final world = _world2();

    test('a fresh world opens all of chapter 1 and nothing else', () async {
      final atlas = WorldAtlas.derive(world, await _progress([], world));
      expect(atlas.chapters[0].stages.every((s) => s.unlocked), true);
      expect(atlas.chapters[1].unlocked, false);
      expect(atlas.nextLevelId, 101);
    });

    test(
      'stuck on one stage, three clears still open the next chapter',
      () async {
        // 102에 막혀도 101·103·104를 깨면 2장이 통째로 열린다.
        final two = WorldAtlas.derive(
          world,
          await _progress([101, 103], world),
        );
        expect(two.chapters[1].unlocked, false);
        expect(two.nextLevelId, 102);
        final three = WorldAtlas.derive(
          world,
          await _progress([101, 103, 104], world),
        );
        expect(three.chapters[1].stages.every((s) => s.unlocked), true);
        expect(three.chapters[2].unlocked, false);
        expect(three.isUnlocked(110), true);
        expect(three.isUnlocked(111), false);
        // 별자리는 다섯 판을 모두 깨야 완성된다.
        expect(three.chapters[0].complete, false);
      },
    );

    test('a cleared stage stays open even in a locked chapter', () async {
      final atlas = WorldAtlas.derive(
        world,
        await _progress([101, 112], world),
      );
      expect(atlas.isUnlocked(112), true);
      expect(atlas.isUnlocked(111), false);
    });
  });

  group('struggle tracker', () {
    test('three restarts or three minutes count as stuck', () {
      var now = DateTime(2026, 11, 8, 9);
      final tracker = StruggleTracker(clock: () => now);
      expect(tracker.untilStuck(112), isNull);
      tracker.opened(112);
      expect(tracker.isStuck(112), false);
      tracker
        ..restarted(112)
        ..restarted(112);
      expect(tracker.isStuck(112), false);
      tracker.restarted(112);
      expect(tracker.isStuck(112), true);
      tracker.cleared(112);
      tracker.opened(112);
      now = now.add(const Duration(minutes: 2));
      expect(tracker.untilStuck(112), const Duration(minutes: 1));
      // 다른 판에 갔다 와도 처음 연 시각은 그대로다.
      tracker.opened(112);
      now = now.add(const Duration(minutes: 1));
      expect(tracker.isStuck(112), true);
    });
  });

  test('assisted clears cap the stars', () {
    expect(assistedStarCap(followedSolution: true, usedHint: true), 1);
    expect(assistedStarCap(followedSolution: false, usedHint: true), 2);
    expect(assistedStarCap(followedSolution: false, usedHint: false), 3);
  });

  group('key hint', () {
    final world = _world2();
    Level level(int id) => world.levels.firstWhere((l) => l.id == id);
    List<PuzzleMove> solve(Level l) =>
        const PuzzleSolver(maxStates: 2000000)
            .solve(l, powers: l.availablePowers)!;

    test('stage 12 names the required seal and when to use it', () {
      final stage = level(112);
      final hint = keyHint(stage, solve(stage));
      expect(hint.ko, contains('봉인이 꼭 필요해요'));
      expect(hint.ko, contains('9번째 수쯤'));
      expect(hint.en, contains('Seal'));
    });

    test('every world 2 stage gets a hint', () {
      for (final stage in world.levels) {
        final hint = keyHint(stage, solve(stage));
        expect(hint.ko, isNotEmpty, reason: '${stage.id}');
        expect(hint.ko, isNot(contains('null')), reason: '${stage.id}');
      }
    });
  });

  test('a capped completion stores the capped stars', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressRepository.load();
    final result = await progress.recordCompletion(
      levelId: 112,
      moves: 15,
      minimumMoves: 15,
      maxStars: 1,
    );
    expect(result.stars, 1);
    expect(progress.forLevel(112)!.bestStars, 1);
  });
}
