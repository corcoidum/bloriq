import 'dart:convert';
import 'dart:io';

import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/daily/daily_repository.dart';
import 'package:bloriq/endless/endless_pool.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:bloriq/weekly/weekly_pool.dart';
import 'package:bloriq/weekly/weekly_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/world_release.dart';

List<Map<String, dynamic>> _boards(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

List<int> _ids(List<Map<String, dynamic>> boards) => [
  for (final board in boards) board['id'] as int,
];

Set<String> _mechanics(List<Map<String, dynamic>> boards) => {
  for (final board in boards)
    for (final rule in board['specialRules'] as List) rule['type'] as String,
};

const _week = '2026-11-09';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WeeklyPool pool;
  setUpAll(() {
    pool = WeeklyPool(
      daily: _boards('assets/levels/daily_pool_v1.json'),
      voyage: [
        ..._boards(EndlessPool.asset),
        ..._boards(WeeklyPool.worldAsset),
      ],
    );
  });
  setUp(() => seedCampaign({}));

  test('local Mondays include days across New Year', () {
    expect(weeklyKey(DateTime(2023, 12, 31, 23, 59)), '2023-12-25');
    expect(weeklyKey(DateTime(2024, 1, 1)), '2024-01-01');
    expect(weeklyKey(DateTime(2026, 1, 1)), '2025-12-29');
    expect(weeklyKey(DateTime(2026, 1, 4, 23, 59)), '2025-12-29');
    expect(weeklyKey(DateTime(2026, 1, 5)), '2026-01-05');
    expect(
      nextWeeklyBoundary(DateTime(2025, 12, 31, 23)),
      DateTime(2026, 1, 5),
    );
    expect(
      nextWeeklyBoundary(DateTime.utc(2026, 1, 5)),
      DateTime.utc(2026, 1, 12),
    );
    expect(weeklyOrdinal('2026-01-05') - weeklyOrdinal('2025-12-29'), 1);
  });

  test('five unique boards depend only on week and completed worlds', () {
    final first = pool.pick(_week, {1, 2, 3});
    final reordered = WeeklyPool(
      daily: pool.daily.reversed.toList(),
      voyage: pool.voyage.reversed.toList(),
    );
    expect(_ids(reordered.pick(_week, {3, 2, 1})), _ids(first));
    expect(_ids(first).toSet(), hasLength(5));
    expect(_ids(pool.pick('2026-11-16', {1, 2, 3})), isNot(_ids(first)));
    expect(_ids(first).where(_ids(pool.daily).contains), hasLength(2));
    final basic = pool.pick(_week, {});
    expect(_ids(basic).where(_ids(pool.voyage).contains), hasLength(5));
    expect(_mechanics(basic), isEmpty);
    expect(_mechanics(first), contains('mirrorPair'));
    expect(
      _mechanics(first),
      isNot(contains(anyOf('clockArrow', 'ice', 'shelfDoor'))),
    );
    final all = pool.pick(_week, {1, 2, 3, 4, 5, 6, 7});
    expect(_ids(all).where(_ids(pool.daily).contains), hasLength(2));
  });

  test(
    'week snapshots and best moves survive rollback and a new pool',
    () async {
      var now = DateTime(2026, 11, 15, 23, 59);
      final repo = await WeeklyRepository.load(clock: () => now);
      expect(repo.currentKey, _week);
      final first = (await repo.assign(repo.currentKey, pool, {}))!;
      final moveCount = first.levels.first.minimumMoves;
      expect(await repo.recordClear(first.stage(0), moveCount + 1), isTrue);
      expect(await repo.recordClear(first.stage(0), moveCount), isTrue);
      expect(await repo.recordClear(first.stage(0), moveCount + 2), isTrue);

      now = DateTime(2026, 11, 16);
      final newer = (await repo.assign(repo.currentKey, pool, {1, 2, 3}))!;
      expect(newer.week, '2026-11-16');
      expect(
        newer.levels.map((level) => level.id),
        isNot(first.levels.map((level) => level.id)),
      );
      expect(repo.cleared(newer.week), 0);

      now = DateTime(2026, 11, 12);
      final restored = await WeeklyRepository.load(clock: () => now);
      expect(restored.currentKey, _week);
      final reopened = (await restored.assign(
        restored.currentKey,
        const WeeklyPool(daily: [], voyage: []),
        {1, 2, 3, 4, 5, 6},
      ))!;
      expect(
        reopened.levels.map((level) => level.id),
        first.levels.map((level) => level.id),
      );
      expect(restored.bestMoves(reopened.stage(0)), moveCount);
      expect(restored.cleared(_week), 1);
      expect(restored.forWeek(newer.week), isNotNull);
    },
  );

  test('12 distinct cosmetics cycle and each is granted once', () async {
    final trails = weeklyRewards
        .whereType<TrailUnlock>()
        .map((r) => r.trailId)
        .toSet();
    final titles = weeklyRewards
        .whereType<TitleUnlock>()
        .map((r) => r.titleId)
        .toSet();
    expect(weeklyRewards, hasLength(12));
    expect(trails, hasLength(6));
    expect(titles, hasLength(6));
    expect(trails.every((id) => trailById(id) != null), isTrue);
    expect(titles.every((id) => titleById(id) != null), isTrue);

    final session = await GameSession.load();
    addTearDown(session.dispose);
    final prefs = await SharedPreferences.getInstance();
    final campaignBefore = prefs.getString(ProgressRepository.storageKey);
    final start = DateTime.utc(2026, 11, 9);
    for (final offset in [0, 1, 12]) {
      final week = weeklyKey(start.add(Duration(days: 7 * offset)));
      final challenge = (await session.openWeekly(week))!;
      expect(challenge.rotation, (weeklyOrdinal(_week) + offset) % 12);
      for (final (index, level) in challenge.levels.indexed) {
        final result = await session.recordWeeklyClear(
          challenge.stage(index),
          level.minimumMoves,
        );
        expect(result, (
          saved: true,
          cleared: index + 1,
          newReward: index == 4 && offset < 12,
        ));
      }
      final stage = challenge.stage(4);
      expect(await session.recordWeeklyClear(stage, stage.level.minimumMoves), (
        saved: true,
        cleared: 5,
        newReward: false,
      ));
    }
    final restored = await GameSession.load();
    addTearDown(restored.dispose);
    expect(restored.weekly.cleared(_week), 5);
    expect(restored.progression.ownedTrails.intersection(trails), hasLength(1));
    expect(restored.progression.ownedTitles.intersection(titles), hasLength(1));
    expect(prefs.getString(ProgressRepository.storageKey), campaignBefore);
    expect(prefs.getString(DailyRepository.storageKey), isNull);
  });

  test(
    'startup grants a reward when the five clears were saved first',
    () async {
      final repo = await WeeklyRepository.load();
      final challenge = (await repo.assign(_week, pool, {}))!;
      for (final (index, level) in challenge.levels.indexed) {
        expect(
          await repo.recordClear(challenge.stage(index), level.minimumMoves),
          isTrue,
        );
      }

      final session = await GameSession.load();
      addTearDown(session.dispose);
      final owned = switch (weeklyRewards[challenge.rotation]) {
        TrailUnlock(:final trailId) => session.progression.ownedTrails.contains(
          trailId,
        ),
        TitleUnlock(:final titleId) => session.progression.ownedTitles.contains(
          titleId,
        ),
        _ => false,
      };
      expect(owned, isTrue);
      final stage = session.weekly.forWeek(_week)!.stage(0);
      expect(await session.recordWeeklyClear(stage, stage.level.minimumMoves), (
        saved: true,
        cleared: 5,
        newReward: false,
      ));
    },
  );
}
