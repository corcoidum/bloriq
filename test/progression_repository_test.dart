import 'dart:convert';

import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProgressionRepository> _load() async =>
    ProgressionRepository.load(await SharedPreferences.getInstance());

Future<Map<String, dynamic>> _stored() async {
  final prefs = await SharedPreferences.getInstance();
  return jsonDecode(prefs.getString(ProgressionRepository.storageKey)!)
      as Map<String, dynamic>;
}

List<BackfillRecord> _allThreeStars() => [
  for (var id = 1; id <= 25; id++) (levelKey: '$id:1', bestStars: 3),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh state starts at level 1 with the moonlight trail', () async {
    final repo = await _load();
    expect(repo.xp, 0);
    expect(repo.level, 1);
    expect(repo.stardust, 0);
    expect(repo.claimedLevels, isEmpty);
    expect(repo.powers, isEmpty);
    expect(repo.ownedTrails, {'moonlight'});
    expect(repo.equippedTrail, 'moonlight');
    expect(repo.title, isNull);
    expect(repo.bonds, isEmpty);
    expect(repo.bareHanded, isEmpty);
    expect(repo.backfilled, false);
    expect(repo.corrupt, false);
    expect(repo.saveFailed, false);
  });

  test('first clear, replay and star upgrade grant xp and stardust', () async {
    final repo = await _load();
    var reward = await repo.recordClear(
      levelKey: '1:1',
      stars: 2,
      previousBestStars: null,
    );
    expect(reward.firstClear, true);
    expect(reward.xpGained, 60);
    expect(reward.clearStardust, 20);
    expect(reward.levelsGained, isEmpty);
    expect(reward.bareHanded, false);
    expect(reward.saved, true);

    reward = await repo.recordClear(
      levelKey: '1:1',
      stars: 2,
      previousBestStars: 2,
    );
    expect(reward.xpGained, 5);
    expect(reward.clearStardust, 10);

    reward = await repo.recordClear(
      levelKey: '1:1',
      stars: 3,
      previousBestStars: 2,
    );
    expect(reward.xpGained, 15);
    expect(reward.clearStardust, 15);
    expect(reward.bareHanded, true);
    expect(reward.newBareHanded, true);
    expect(reward.totalXp, 80);
    expect(reward.totalStardust, 45);
    expect(repo.bareHanded, {'1:1'});

    reward = await repo.recordClear(
      levelKey: '1:1',
      stars: 3,
      previousBestStars: 3,
    );
    expect(reward.bareHanded, true);
    expect(reward.newBareHanded, false);

    final hinted = await repo.recordClear(
      levelKey: '2:1',
      stars: 3,
      previousBestStars: null,
      usedHint: true,
    );
    expect(hinted.bareHanded, false);
    expect(repo.isBareHandedLevel('2:1'), false);

    final restored = await _load();
    expect(restored.xp, repo.xp);
    expect(restored.stardust, repo.stardust);
    expect(restored.bareHanded, {'1:1'});
  });

  test('daily clear grants streak xp', () async {
    final repo = await _load();
    expect((await repo.recordDailyClear(1)).xpGained, 30);
    expect((await repo.recordDailyClear(3)).xpGained, 40);
    final reward = await repo.recordDailyClear(20);
    expect(reward.xpGained, 55);
    expect(reward.totalXp, 125);
    expect(reward.levelsGained.map((l) => l.level), [2]);
    expect(reward.stardustGained, 50);
    expect(repo.stardust, 50);
  });

  test('constellation grants xp and power once per chapter', () async {
    final repo = await _load();
    var reward = await repo.recordClear(
      levelKey: '4:1',
      stars: 3,
      previousBestStars: null,
    );
    expect(reward.newPower, isNull);
    expect(repo.powers, isEmpty);

    reward = await repo.recordClear(
      levelKey: '5:1',
      stars: 3,
      previousBestStars: null,
      constellationCompletedChapter: 1,
      constellationGoldenChapter: 1,
    );
    expect(reward.xpGained, 70 + 120 + 200);
    expect(reward.newPower?.id, 'moonflower_leap');
    expect(repo.hasPower('moonflower_leap'), true);
    expect(repo.completedChapters, {1});
    expect(repo.goldenChapters, {1});

    reward = await repo.recordClear(
      levelKey: '5:1',
      stars: 3,
      previousBestStars: 3,
      constellationCompletedChapter: 1,
      constellationGoldenChapter: 1,
    );
    expect(reward.xpGained, 5);
    expect(reward.newPower, isNull);
    expect((await _load()).powers.map((p) => p.id), ['moonflower_leap']);
  });

  test('multi-level jump applies every track reward in order', () async {
    final repo = await _load();
    // 70 + 70 + 120 + 200 = 460 xp → 레벨 4 (420..639), 레벨 2·3·4 보상.
    await repo.recordClear(levelKey: '1:1', stars: 3, previousBestStars: null);
    final reward = await repo.recordClear(
      levelKey: '2:1',
      stars: 3,
      previousBestStars: null,
      constellationCompletedChapter: 1,
      constellationGoldenChapter: 1,
    );
    expect(reward.totalXp, 460);
    expect(reward.level, 4);
    expect(reward.standing.xpIntoLevel, 40);
    expect(reward.levelsGained.map((l) => l.level), [2, 3, 4]);
    expect(reward.levelsGained[0].reward, isA<StardustBundle>());
    expect(reward.newTrails, ['petal']);
    expect(reward.newTitles, ['crescent_apprentice']);
    expect(reward.clearStardust, 25);
    expect(reward.stardustGained, 25 + 50);
    expect(repo.stardust, 25 + 25 + 50);
    expect(repo.claimedLevels, {2, 3, 4});
    expect(repo.ownedTrails, {'moonlight', 'petal'});
    expect(repo.ownedTitles, {'crescent_apprentice'});
    expect(repo.title, 'crescent_apprentice');

    final restored = await _load();
    expect(restored.level, 4);
    expect(restored.claimedLevels, {2, 3, 4});
    expect(restored.title, 'crescent_apprentice');
    expect(await restored.equipTrail('petal'), true);
    expect(await restored.equipTrail('meteor'), false);
    expect(await restored.setTitle('moon_guardian'), false);
    expect(await restored.setTitle(null), true);
    expect((await _load()).equippedTrail, 'petal');
    expect((await _load()).title, isNull);
  });

  test('bond thresholds and level ups follow companion clears', () async {
    final repo = await _load();
    final levelUps = <int?>[];
    for (var i = 0; i < 25; i++) {
      final reward = await repo.recordClear(
        levelKey: '1:1',
        stars: 1,
        previousBestStars: i == 0 ? null : 1,
        companionId: 's1-11',
        companionFamily: 'letter',
      );
      levelUps.add(reward.bondLevelUp);
    }
    expect(repo.bondClears('s1-11'), 25);
    expect(repo.bondLevel('s1-11'), 5);
    expect(
      {
        for (var i = 0; i < 25; i++)
          if (levelUps[i] != null) i + 1: levelUps[i],
      },
      {3: 2, 8: 3, 15: 4, 25: 5},
    );
    expect(repo.bondLevel('s1-02'), 1);
    expect(
      repo.abilitiesFor(companionId: 's1-11', companionFamily: 'letter'),
      const FamilyAbilities(extraMemoryLine: true),
    );
    expect((await _load()).bonds, {'s1-11': 25});
  });

  test('forest bond Lv3 adds 20% stardust from the next clear', () async {
    final repo = await _load();
    final dust = <int>[];
    for (var i = 0; i < 9; i++) {
      final reward = await repo.recordClear(
        levelKey: '1:1',
        stars: 3,
        previousBestStars: i == 0 ? null : 3,
        companionId: 's1-01',
        companionFamily: 'forest',
      );
      dust.add(reward.clearStardust);
    }
    expect(dust.first, 25);
    expect(dust[7], 15); // 8번째 클리어로 Lv3 이 된다.
    expect(dust[8], 18);
  });

  test('cloud bond Lv3 unlocks the mist trail', () async {
    final repo = await _load();
    expect(await repo.equipTrail('mist'), false);
    final trails = <List<String>>[];
    for (var i = 0; i < 8; i++) {
      final reward = await repo.recordClear(
        levelKey: '16:1',
        stars: 1,
        previousBestStars: i == 0 ? null : 1,
        companionId: 's1-16',
        companionFamily: 'cloud',
      );
      trails.add(reward.newTrails);
    }
    expect(trails.last, contains('mist'));
    expect(trails.take(7).every((t) => !t.contains('mist')), true);
    expect(repo.ownedTrails, contains('mist'));
    expect(await repo.equipTrail('mist'), true);
  });

  test('memory bond Lv3 shows minimum moves', () async {
    final repo = await _load();
    for (var i = 0; i < 8; i++) {
      await repo.recordClear(
        levelKey: '21:1',
        stars: 1,
        previousBestStars: i == 0 ? null : 1,
        companionId: 's1-21',
        companionFamily: 'memory',
      );
    }
    expect(
      repo
          .abilitiesFor(companionId: 's1-21', companionFamily: 'memory')
          .showMinimumMoves,
      true,
    );
  });

  group('starlight path', () {
    test('costs 20 stardust and needs enough of it', () async {
      final repo = await _load();
      expect(await repo.useStarlightPath(freeUsedThisAttempt: false), isNull);
      await repo.recordClear(
        levelKey: '1:1',
        stars: 3,
        previousBestStars: null,
      );
      expect(repo.stardust, 25);
      final quote = await repo.useStarlightPath(freeUsedThisAttempt: false);
      expect(quote, const StarlightPathQuote(StarlightPathSource.stardust, 20));
      expect(repo.stardust, 5);
      expect((await _load()).stardust, 5);
    });

    test('starlight companion at bond Lv3 lowers the cost to 15', () async {
      final repo = await _load();
      for (var i = 0; i < 8; i++) {
        await repo.recordClear(
          levelKey: '6:1',
          stars: 3,
          previousBestStars: i == 0 ? null : 3,
          companionId: 's1-06',
          companionFamily: 'starlight',
        );
      }
      expect(
        repo.quoteStarlightPath(
          freeUsedThisAttempt: false,
          companionId: 's1-06',
          companionFamily: 'starlight',
        ),
        const StarlightPathQuote(StarlightPathSource.stardust, 15),
      );
      expect(
        repo.quoteStarlightPath(
          freeUsedThisAttempt: false,
          companionId: 's1-01',
          companionFamily: 'forest',
        ),
        const StarlightPathQuote(StarlightPathSource.stardust, 20),
      );
    });

    test('caps the clear at 2 stars and is never bare-handed', () async {
      final repo = await _load();
      final reward = await repo.recordClear(
        levelKey: '3:1',
        stars: 3,
        previousBestStars: null,
        usedStarlightPath: true,
      );
      expect(reward.starsAwarded, 2);
      expect(reward.xpGained, 60);
      expect(reward.clearStardust, 20);
      expect(reward.bareHanded, false);
      expect(repo.bareHanded, isEmpty);
    });

    test('free once per attempt after the power, then charges', () async {
      final repo = await _load();
      await repo.backfill(
        records: _allThreeStars(),
        completedChapters: {1, 2, 3, 4, 5},
        goldenChapters: {1, 2, 3, 4, 5},
      );
      expect(repo.hasPower('starlight_path'), true);
      expect(repo.starlightCharges, 2);
      final stardust = repo.stardust;
      expect(
        await repo.useStarlightPath(freeUsedThisAttempt: false),
        const StarlightPathQuote(StarlightPathSource.free, 0),
      );
      expect(repo.starlightCharges, 2);
      expect(
        await repo.useStarlightPath(freeUsedThisAttempt: true),
        const StarlightPathQuote(StarlightPathSource.charge, 0),
      );
      expect(repo.starlightCharges, 1);
      expect(repo.stardust, stardust);
      expect((await _load()).starlightCharges, 1);
    });
  });

  test('spendStardust only succeeds with enough balance', () async {
    final repo = await _load();
    await repo.recordClear(levelKey: '1:1', stars: 3, previousBestStars: null);
    expect(await repo.spendStardust(26), false);
    expect(await repo.spendStardust(-1), false);
    expect(await repo.spendStardust(25), true);
    expect(repo.stardust, 0);
    expect((await _load()).stardust, 0);
  });

  group('backfill', () {
    test('grants records, constellations and powers exactly once', () async {
      final repo = await _load();
      final reward = await repo.backfill(
        records: _allThreeStars(),
        completedChapters: {1, 2, 3, 4, 5},
        goldenChapters: {1, 2, 3, 4, 5},
      );
      // 25*70 + 5*120 + 5*200 = 3350 → 레벨 12 (3300..3839).
      expect(reward!.xpGained, 3350);
      expect(repo.xp, 3350);
      expect(repo.level, 12);
      expect(reward.levelsGained.map((l) => l.level), [
        for (var l = 2; l <= 12; l++) l,
      ]);
      expect(reward.clearStardust, 25 * 25);
      expect(reward.stardustGained, 625 + 50 + 80 + 100 + 120);
      expect(repo.stardust, 975);
      expect(reward.newPowers.map((p) => p.id), [
        'moonflower_leap',
        'light_swap',
        'seal',
        'wind',
        'starlight_path',
      ]);
      expect(repo.ownedTrails, {'moonlight', 'petal', 'firefly'});
      expect(repo.ownedTitles, {
        'crescent_apprentice',
        'garden_keeper',
        'star_navigator',
      });
      expect(repo.backfilled, true);
      expect(repo.bareHanded, isEmpty);

      expect(
        await repo.backfill(
          records: _allThreeStars(),
          completedChapters: {1, 2, 3, 4, 5},
          goldenChapters: {1, 2, 3, 4, 5},
        ),
        isNull,
      );
      expect(repo.xp, 3350);
      expect(repo.stardust, 975);

      final restored = await _load();
      expect(restored.backfilled, true);
      expect(
        await restored.backfill(
          records: _allThreeStars(),
          completedChapters: {1, 2, 3, 4, 5},
          goldenChapters: {1, 2, 3, 4, 5},
        ),
        isNull,
      );
      expect(restored.xp, 3350);
      expect(restored.stardust, 975);
      expect(restored.powers.length, 5);
    });

    test('does not regrant clears already recorded live', () async {
      final repo = await _load();
      await repo.recordClear(
        levelKey: '1:1',
        stars: 2,
        previousBestStars: null,
        constellationCompletedChapter: 1,
      );
      expect(repo.xp, 60 + 120);
      final reward = await repo.backfill(
        records: [
          (levelKey: '1:1', bestStars: 3),
          (levelKey: '2:1', bestStars: 1),
          (levelKey: '3:1', bestStars: 0),
        ],
        completedChapters: {1},
        goldenChapters: {},
      );
      expect(reward!.xpGained, 15 + 50);
      expect(reward.clearStardust, 15);
      expect(reward.newPowers, isEmpty);
      expect(repo.powers.map((p) => p.id), ['moonflower_leap']);
    });

    test('a new player is marked backfilled with nothing granted', () async {
      final repo = await _load();
      final reward = await repo.backfill(
        records: const [],
        completedChapters: const {},
        goldenChapters: const {},
      );
      expect(reward!.xpGained, 0);
      expect(repo.backfilled, true);
      expect((await _stored())['backfilled'], true);
    });
  });

  group('persistence safety', () {
    test(
      'corrupt data is not overwritten until recovery backs it up',
      () async {
        SharedPreferences.setMockInitialValues({
          ProgressionRepository.storageKey: '{broken',
        });
        final repo = await _load();
        expect(repo.corrupt, true);
        expect(repo.writable, false);
        expect(repo.saveFailed, true);
        final reward = await repo.recordClear(
          levelKey: '1:1',
          stars: 3,
          previousBestStars: null,
        );
        expect(reward.saved, false);
        expect(reward.xpGained, 0);
        expect(repo.xp, 0);
        expect(
          await repo.backfill(
            records: _allThreeStars(),
            completedChapters: const {},
            goldenChapters: const {},
          ),
          isNull,
        );
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(ProgressionRepository.storageKey), '{broken');

        expect(await repo.recover(), true);
        expect(prefs.getString(ProgressionRepository.backupKey), '{broken');
        expect(repo.corrupt, false);
        expect(repo.backfilled, false);
        final backfill = await repo.backfill(
          records: [(levelKey: '1:1', bestStars: 3)],
          completedChapters: const {},
          goldenChapters: const {},
        );
        expect(backfill!.xpGained, 70);
        expect((await _load()).xp, 70);
      },
    );

    test('wrongly typed fields count as corrupt', () async {
      for (final bad in [
        {'version': 1, 'xp': 'lots'},
        {'version': 1, 'xp': -1},
        {'version': 1, 'ownedTrails': 'petal'},
        {
          'version': 1,
          'bonds': {'s1-01': 'many'},
        },
        {'version': 1, 'backfilled': 'yes'},
        {'version': '1'},
        [1, 2],
      ]) {
        SharedPreferences.setMockInitialValues({
          ProgressionRepository.storageKey: jsonEncode(bad),
        });
        final repo = await _load();
        expect(repo.corrupt, true, reason: '$bad');
        expect(repo.xp, 0);
        expect(repo.ownedTrails, {'moonlight'});
      }
    });

    test('a future schema is left untouched and not recoverable', () async {
      final raw = jsonEncode({'version': 2, 'xp': 9999});
      SharedPreferences.setMockInitialValues({
        ProgressionRepository.storageKey: raw,
      });
      final repo = await _load();
      expect(repo.futureSchema, true);
      expect(repo.corrupt, false);
      expect(await repo.recover(), false);
      await repo.recordDailyClear(1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ProgressionRepository.storageKey), raw);
    });

    test('unknown fields survive a save and invalid picks fall back', () async {
      SharedPreferences.setMockInitialValues({
        ProgressionRepository.storageKey: jsonEncode({
          'version': 1,
          'xp': 10,
          'equippedTrail': 'meteor',
          'title': 'moon_guardian',
          'futureField': {'keep': true},
        }),
      });
      final repo = await _load();
      expect(repo.corrupt, false);
      expect(repo.xp, 10);
      expect(repo.equippedTrail, 'moonlight');
      expect(repo.title, isNull);
      await repo.recordDailyClear(1);
      final stored = await _stored();
      expect(stored['futureField'], {'keep': true});
      expect(stored['xp'], 40);
      expect(stored['version'], 1);
    });

    test('a failing writer reports saveFailed', () async {
      final prefs = await SharedPreferences.getInstance();
      final repo = await ProgressionRepository.load(
        prefs,
        (_, _) async => false,
      );
      final reward = await repo.recordDailyClear(1);
      expect(reward.saved, false);
      expect(repo.saveFailed, true);
      expect(repo.xp, 30);
    });
  });
}
