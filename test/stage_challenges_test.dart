import 'dart:convert';

import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progress/stage_challenges.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/world_release.dart';

const _clear = StageChallenge.clear;
const _optimal = StageChallenge.optimal;
const _technique = StageChallenge.technique;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('최단 수 과제와 도움·권능 과제는 각각 판정한다', () {
    final level = releaseLevels(2).first;
    for (final (moves, powers, help, expected) in [
      (level.minimumMoves, 1, false, {_clear, _optimal}),
      (level.minimumMoves, 0, true, {_clear, _optimal}),
      (level.minimumMoves - 1, 0, false, {_clear, _optimal, _technique}),
      (level.bareHandedMoves!, 0, false, {_clear, _technique}),
      (level.minimumMoves + 1, 0, true, {_clear}),
    ]) {
      expect(
        stageChallengesForClear(
          level,
          moves: moves,
          powerUses: powers,
          usedHelp: help,
        ),
        expected,
      );
    }
  });

  test('맨손 풀이가 없는 판은 필요한 횟수만큼 권능을 쓴다', () {
    final levels = releaseLevels(2);
    for (final (id, requiredUses) in [(104, 1), (123, 2), (125, 2)]) {
      final level = levels.singleWhere((level) => level.id == id);
      for (final uses in [0, 1, 2, 3]) {
        final earned = stageChallengesForClear(
          level,
          moves: level.minimumMoves,
          powerUses: uses,
          usedHelp: true,
        );
        expect(earned, {
          _clear,
          _optimal,
          if (uses == requiredUses) _technique,
        });
      }
    }
  });

  test('세계 2~7 공개 판 150개 모두 셋째 과제를 달성할 풀이가 있다', () {
    for (var world = 2; world <= 7; world++) {
      final levels = releaseLevels(world);
      expect(levels, hasLength(25));
      for (final level in levels) {
        final bareMoves = level.bareHandedMoves;
        final earned = stageChallengesForClear(
          level,
          moves: bareMoves ?? level.solution.length,
          powerUses: bareMoves == null
              ? level.solution.where((move) => move.power != null).length
              : 0,
          usedHelp: false,
        );
        expect(earned, contains(_technique), reason: 'Stage ${level.id}');
      }
    }
  });

  test('이전 저장은 근거가 있는 과제만 소급하고 판 버전과 별을 보존한다', () async {
    final levels = releaseLevels(2);
    final entries = <Map<String, Object>>[
      {'levelId': 1, 'bestMoves': 4, 'bestStars': 3, 'completionCount': 2},
      for (final (stage, moves, revision) in [
        (101, 8, 1),
        (102, 10, 1),
        (103, 11, 2),
        (104, 12, 1),
        (123, 13, 1),
      ])
        {
          'levelId': stage,
          'revision': revision,
          'bestMoves': moves,
          'bestStars': 1,
          'completionCount': 4,
        },
    ];
    SharedPreferences.setMockInitialValues({
      ProgressRepository.storageKey: jsonEncode({
        'version': 2,
        'levels': entries,
      }),
    });
    final repo = await ProgressRepository.load();
    expect(repo.forLevel(101)!.stageChallenges, isEmpty);
    await repo.backfillStageChallenges(
      levels,
      hasBareHandedStar: (key) => key == '101:1',
    );
    final restored = await ProgressRepository.load();
    expect(restored.forLevel(1)!.stageChallenges, isEmpty);
    expect(restored.forLevel(101)!.stageChallenges, {_clear, _technique});
    expect(restored.forLevel(102)!.stageChallenges, {_clear, _optimal});
    expect(restored.forLevel(103, revision: 2)!.stageChallenges, isEmpty);
    expect(restored.forLevel(104)!.stageChallenges, {
      _clear,
      _optimal,
      _technique,
    });
    expect(restored.forLevel(123)!.stageChallenges, {
      _clear,
      _optimal,
      _technique,
    });
    expect(restored.forLevel(101)!.bestMoves, 8);
    expect(restored.forLevel(101)!.bestStars, 1);
    expect(restored.forLevel(101)!.completionCount, 4);
    expect(restored.starflowerCount(levels), 10);
  });

  test('여러 번 깨면 과제가 누적되고, 저장 재시도 후에 집계된다', () async {
    final level = releaseLevels(2).first;
    final prefs = await SharedPreferences.getInstance();
    var writable = false;
    final repo = await ProgressRepository.load(
      writer: (key, snapshot) async =>
          writable && await prefs.setString(key, snapshot),
    );
    final first = await repo.recordCompletion(
      levelId: level.id,
      moves: level.minimumMoves,
      minimumMoves: level.minimumMoves,
      maxStars: 1,
      stageChallenges: {_clear, _optimal},
    );
    expect(first.saved, isFalse);
    expect(repo.starflowerCount([level]), 0);
    writable = true;
    expect(await repo.retrySave(), isTrue);
    expect(repo.starflowerCount([level]), 2);

    final second = await repo.recordCompletion(
      levelId: level.id,
      moves: level.bareHandedMoves!,
      minimumMoves: level.minimumMoves,
      stageChallenges: {_clear, _technique},
    );
    expect(second.newStageChallenges, {_technique});
    expect(second.progress.stageChallenges, {_clear, _optimal, _technique});
    expect(second.progress.bestMoves, level.minimumMoves);
    expect((await ProgressRepository.load()).starflowerCount([level]), 3);
  });

  test('25·50·75개 달성 보상은 해당 세계에 한 번씩 지급된다', () async {
    final progression = await ProgressionRepository.load();
    var clearDust = 0;
    for (final (count, newTarget) in [
      (24, null),
      (25, 25),
      (49, null),
      (50, 50),
      (74, null),
      (75, 75),
      (75, null),
    ]) {
      final reward = await progression.recordClear(
        levelKey: '101:1',
        stars: 1,
        previousBestStars: 1,
        starflowersByWorld: {2: count, 3: 24},
      );
      expect(reward.achievements.map((a) => a.id), [
        if (newTarget != null) 'w2-starflowers-$newTarget',
      ]);
      expect(reward.achievementStardust, newTarget == 25 ? 200 : 0);
      clearDust += reward.clearStardust;
    }
    expect(progression.stardust, clearDust + 200);
    expect(progression.ownedTrails, contains(TrailIds.cloudBloom));
    expect(progression.ownedTitles, contains('cloud_bloom_keeper'));
    final restored = await ProgressionRepository.load();
    await restored.reconcileStarflowerAchievements({2: 75, 3: 24});
    expect(restored.stardust, clearDust + 200);
    expect(restored.claimedAchievements, hasLength(3));
  });

  test('시작할 때 과제를 소급하고, 소급한 별꽃의 업적도 지급한다', () async {
    seedCampaign({1, 2, 3, 4, 5}, cleared: releaseLevels(2));
    for (var load = 0; load < 2; load++) {
      final session = await GameSession.load();
      try {
        expect(session.starflowersByWorld[2], 59);
        expect(session.progression.claimedAchievements, {
          'w2-starflowers-25',
          'w2-starflowers-50',
        });
        expect(session.progression.stardust, 200);
        expect(session.progression.ownedTrails, contains(TrailIds.cloudBloom));
      } finally {
        await session.dispose();
      }
    }
  });
}
