import 'package:bloriq/endless/endless_rules.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('level curve', () {
    test('each level costs 100 + 40*(n-1)', () {
      expect([1, 2, 3, 4, 10].map(xpToNextLevel), [100, 140, 180, 220, 460]);
      expect([1, 2, 3, 4, 5].map(totalXpForLevel), [0, 100, 240, 420, 640]);
      for (var level = 1; level < 40; level++) {
        expect(
          totalXpForLevel(level + 1) - totalXpForLevel(level),
          xpToNextLevel(level),
        );
      }
    });

    test('levelForXp returns level and progress inside it', () {
      expect(
        levelForXp(0),
        const LevelStanding(level: 1, xpIntoLevel: 0, xpForNextLevel: 100),
      );
      expect(levelForXp(99).level, 1);
      expect(levelForXp(99).xpRemaining, 1);
      expect(
        levelForXp(100),
        const LevelStanding(level: 2, xpIntoLevel: 0, xpForNextLevel: 140),
      );
      expect(levelForXp(239).xpIntoLevel, 139);
      expect(levelForXp(240).level, 3);
      expect(levelForXp(330).progress, closeTo(0.5, 1e-9));
      expect(levelForXp(-5).level, 1);
      for (var level = 1; level < 40; level++) {
        expect(levelForXp(totalXpForLevel(level)).level, level);
        expect(
          levelForXp(totalXpForLevel(level) - 1).level,
          level - 1 < 1 ? 1 : level - 1,
        );
      }
    });
  });

  group('xp sources', () {
    test('campaign first clear, star upgrade and replay', () {
      expect(campaignClearXp(stars: 1), 50);
      expect(campaignClearXp(stars: 3), 70);
      expect(campaignClearXp(stars: 3, previousBestStars: 1), 30);
      expect(campaignClearXp(stars: 2, previousBestStars: 1), 15);
      expect(campaignClearXp(stars: 3, previousBestStars: 3), 5);
      expect(campaignClearXp(stars: 1, previousBestStars: 3), 5);
      expect(() => campaignClearXp(stars: 0), throwsArgumentError);
      expect(() => campaignClearXp(stars: 4), throwsArgumentError);
    });

    test('daily clear streak bonus is capped at +25', () {
      expect(dailyClearXp(0), 30);
      expect(dailyClearXp(1), 30);
      expect(dailyClearXp(2), 35);
      expect(dailyClearXp(5), 50);
      expect(dailyClearXp(6), 55);
      expect(dailyClearXp(7), 55);
      expect(dailyClearXp(365), 55);
    });

    test('constellation completion and golden', () {
      expect(XpRules.constellationCompleted, 120);
      expect(XpRules.constellationGolden, 200);
    });
  });

  group('stardust', () {
    test('stars*5 plus 10 on first clear, forest +20% rounded up', () {
      expect(clearStardust(stars: 3), 25);
      expect(clearStardust(stars: 1), 15);
      expect(clearStardust(stars: 3, forestBonus: true), 30);
      expect(clearStardust(stars: 1, forestBonus: true), 18);
      expect(applyForestBonus(7), 9);
      expect(applyForestBonus(0), 0);
    });

    test('replays pay 1, upgrades pay only the new stars', () {
      expect(clearStardust(stars: 2, previousBestStars: 2), 1);
      expect(clearStardust(stars: 3, previousBestStars: 3), 1);
      expect(clearStardust(stars: 1, previousBestStars: 3), 1);
      expect(clearStardust(stars: 3, previousBestStars: 1), 10);
      expect(clearStardust(stars: 3, previousBestStars: 2), 5);
      expect(
        clearStardust(stars: 3, previousBestStars: 2, forestBonus: true),
        6,
      );
    });

    test('a stage pays at most 25 whatever order the stars come in', () {
      final direct = clearStardust(stars: 3);
      final stepped =
          clearStardust(stars: 1) +
          clearStardust(stars: 2, previousBestStars: 1) +
          clearStardust(stars: 3, previousBestStars: 2);
      expect(direct, 25);
      expect(stepped, 25);
    });

    test('golden constellation pays 100', () {
      expect(StardustRules.goldenConstellation, 100);
    });
  });

  group('starlight workshop', () {
    test('shop items are known trails, unique, priced and ascending', () {
      final ids = trailShop.map((item) => item.trailId).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final item in trailShop) {
        expect(trailById(item.trailId), isNotNull);
        expect(item.price, greaterThan(0));
        expect(shopItemFor(item.trailId), same(item));
      }
      final prices = trailShop.map((item) => item.price).toList();
      expect(prices, [...prices]..sort());
      expect(shopItemFor(TrailIds.moonlight), isNull);
      expect(shopItemFor(TrailIds.goldForest), isNull);
    });
  });

  group('golden worlds', () {
    test('chapters map to worlds of five', () {
      expect(worldOfChapter(1), 1);
      expect(worldOfChapter(5), 1);
      expect(worldOfChapter(6), 2);
      expect(worldOfChapter(15), 3);
    });

    test('each released world has a golden-sky trail achievement', () {
      for (final (world, trail) in [
        (1, TrailIds.goldForest),
        (2, TrailIds.goldCloud),
        (3, TrailIds.goldMirror),
      ]) {
        final achievement = achievements.singleWhere(
          (a) => a.kind == AchievementKind.worldGolden && a.world == world,
        );
        expect(achievement.target, 5);
        expect(
          achievement.rewards.whereType<TrailUnlock>().single.trailId,
          trail,
        );
        expect(TrailIds.isGolden(trail), true);
      }
    });
  });

  group('reward track', () {
    test('covers levels 2..20 once each with valid ids', () {
      expect(rewardTrack.map((e) => e.level), [
        for (var l = 2; l <= 20; l++) l,
      ]);
      expect(rewardForLevel(1), isNull);
      expect(rewardForLevel(21), isNull);
      final trailUnlocks = <String>[];
      final titleUnlocks = <String>[];
      var charges = 0;
      for (final entry in rewardTrack) {
        switch (entry.reward) {
          case StardustBundle(:final amount):
            expect(amount, greaterThan(0));
          case TrailUnlock(:final trailId):
            trailUnlocks.add(trailId);
          case TitleUnlock(:final titleId):
            titleUnlocks.add(titleId);
          case StarlightCharge(charges: final n):
            charges += n;
        }
      }
      expect(trailUnlocks, [TrailIds.petal, TrailIds.firefly, TrailIds.meteor]);
      expect(trailUnlocks.every((id) => trailById(id) != null), true);
      final achievementTitles = {
        for (final achievement in achievements)
          for (final reward in achievement.rewards)
            if (reward case TitleUnlock(:final titleId)) titleId,
      };
      final voyageTitles = {
        for (final milestone in voyageMilestones)
          for (final reward in milestone.rewards)
            if (reward case TitleUnlock(:final titleId)) titleId,
      };
      expect({
        ...titleUnlocks,
        ...achievementTitles,
        ...voyageTitles,
        for (final reward in weeklyRewards)
          if (reward case TitleUnlock(:final titleId)) titleId,
      }, titles.map((t) => t.id).toSet());
      expect(charges, greaterThan(0));
    });

    test('trails and titles are bilingual, moonlight is the default', () {
      expect(trails.map((t) => t.id), [
        'moonlight',
        'petal',
        'firefly',
        'meteor',
        'mist',
        'aurora',
        'starfall',
        'first_starlight',
        'tide',
        'rose',
        'ember',
        'lilac',
        'jade',
        'silver',
        'gold_forest',
        'gold_cloud',
        'gold_mirror',
        'weekly_moonlight',
        'weekly_ripple',
        'weekly_amber',
        'weekly_frost',
        'weekly_nebula',
        'weekly_daybreak',
      ]);
      expect(defaultTrailId, 'moonlight');
      expect(titles.length, 27);
      for (final text in [
        ...trails.map((t) => t.name),
        ...titles.map((t) => t.name),
      ]) {
        expect(text.ko, isNotEmpty);
        expect(text.en, isNotEmpty);
      }
      expect(titleById('garden_keeper')!.name.resolve('ko'), '정원지기');
      expect(titleById('garden_keeper')!.name.resolve('en'), 'Garden Keeper');
      expect(titleById('mirror_lake_keeper')!.name.ko, '호수의 거울지기');
      expect(
        titleById('mirror_lake_keeper')!.name.en,
        'Mirror Keeper of the Lake',
      );
      final clocktower = titleById('clocktower_bellkeeper')!.name;
      expect(clocktower.ko, '멈춘 시각의 종지기');
      expect(clocktower.en, 'Bellkeeper of the Still Hour');
      final iceCave = titleById('frost_memory_keeper')!.name;
      expect(iceCave.ko, '서리 속 기억 지기');
      expect(iceCave.en, 'Keeper of Frostbound Memories');
      final librarian = titleById('first_echo_librarian')!.name;
      expect(librarian.ko, '첫 잔상의 사서');
      expect(librarian.en, 'Librarian of the First Echo');
      expect(titleById('first_star_echo')!.name.ko, '첫 별의 잔상');
      expect(trailById(TrailIds.firstStarlight)!.name.ko, '첫 별빛');
    });
  });

  group('powers', () {
    test('one power per chapter, only starlight path active in world 1', () {
      expect(powerCatalog.map((p) => p.id), [
        'moonflower_leap',
        'light_swap',
        'seal',
        'wind',
        'starlight_path',
      ]);
      expect([1, 2, 3, 4, 5].map((c) => powerForChapter(c)!.id), [
        'moonflower_leap',
        'light_swap',
        'seal',
        'wind',
        'starlight_path',
      ]);
      expect(powerForChapter(6), isNull);
      expect(powerCatalog.where((p) => p.activeInWorld1).map((p) => p.id), [
        'starlight_path',
      ]);
      expect(powerById('seal')!.name.ko, '봉인');
      expect(powerById('moonflower_leap')!.name.ko, '달꽃 도약');
      for (final power in powerCatalog) {
        expect(power.name.en, isNotEmpty);
        expect(power.description.ko, isNotEmpty);
        expect(power.description.en, isNotEmpty);
      }
    });
  });

  group('starlight path', () {
    test('cost and discount', () {
      expect(starlightPathCost(), 20);
      expect(starlightPathCost(starlightDiscount: true), 15);
      expect(starlightPathCost(goldenConstellations: 1), 18);
      expect(starlightPathCost(goldenConstellations: 5), 10);
      expect(starlightPathCost(goldenConstellations: 6), 10);
      expect(
        starlightPathCost(starlightDiscount: true, goldenConstellations: 6),
        5,
      );
    });

    test('free once per attempt, then charges, then stardust', () {
      expect(
        starlightPathQuote(
          powerUnlocked: true,
          freeUsedThisAttempt: false,
          charges: 2,
          goldenConstellations: 2,
        ),
        const StarlightPathQuote(StarlightPathSource.free, 0),
      );
      expect(
        starlightPathQuote(
          powerUnlocked: true,
          freeUsedThisAttempt: true,
          charges: 1,
          goldenConstellations: 2,
        ),
        const StarlightPathQuote(StarlightPathSource.charge, 0),
      );
      expect(
        starlightPathQuote(
          powerUnlocked: false,
          freeUsedThisAttempt: false,
          charges: 0,
        ),
        const StarlightPathQuote(StarlightPathSource.stardust, 20),
      );
      expect(
        starlightPathQuote(
          powerUnlocked: true,
          freeUsedThisAttempt: true,
          charges: 0,
          starlightDiscount: true,
        ),
        const StarlightPathQuote(StarlightPathSource.stardust, 15),
      );
    });

    test('caps the clear at 2 stars and breaks bare-handed', () {
      expect(capAssistedStars(3, usedStarlightPath: true), 2);
      expect(capAssistedStars(2, usedStarlightPath: true), 2);
      expect(capAssistedStars(1, usedStarlightPath: true), 1);
      expect(capAssistedStars(3, usedStarlightPath: false), 3);
      expect(isBareHanded(stars: 3, usedHint: false), true);
      expect(isBareHanded(stars: 2, usedHint: false), false);
      expect(isBareHanded(stars: 3, usedHint: true), false);
      expect(
        isBareHanded(stars: 3, usedHint: false, usedStarlightPath: true),
        false,
      );
    });
  });

  group('bonds', () {
    test('companion first-clear XP scales with bond and the letter family', () {
      for (final family in SpiritFamily.values) {
        expect(companionFirstClearXp(family, 1), 5);
      }
      expect(companionFirstClearXp(SpiritFamily.forest, 4), 5);
      expect(companionFirstClearXp(SpiritFamily.forest, 5), 10);
      expect(companionFirstClearXp(SpiritFamily.letter, 2), 5);
      expect(companionFirstClearXp(SpiritFamily.letter, 3), 10);
      expect(companionFirstClearXp(SpiritFamily.letter, 5), 15);
    });

    test('thresholds 0/3/8/15/25 map to Lv1..5', () {
      const expected = {
        0: 1,
        2: 1,
        3: 2,
        7: 2,
        8: 3,
        14: 3,
        15: 4,
        24: 4,
        25: 5,
        100: 5,
      };
      expected.forEach((clears, level) {
        expect(bondLevelForClears(clears), level, reason: '$clears clears');
      });
      expect(clearsToNextBond(0), 3);
      expect(clearsToNextBond(3), 5);
      expect(clearsToNextBond(24), 1);
      expect(clearsToNextBond(25), isNull);
    });

    test('family abilities switch on at Lv3', () {
      expect(SpiritFamily.tryParse('cloud'), SpiritFamily.cloud);
      expect(SpiritFamily.tryParse('dragon'), isNull);
      expect(
        FamilyAbilities.of(SpiritFamily.forest, 3),
        const FamilyAbilities(stardustBonus: true),
      );
      expect(
        FamilyAbilities.of(SpiritFamily.starlight, 4),
        const FamilyAbilities(starlightDiscount: true),
      );
      expect(
        FamilyAbilities.of(SpiritFamily.letter, 3),
        const FamilyAbilities(extraMemoryLine: true),
      );
      expect(
        FamilyAbilities.of(SpiritFamily.cloud, 5),
        const FamilyAbilities(mistTrail: true),
      );
      expect(
        FamilyAbilities.of(SpiritFamily.memory, 3),
        const FamilyAbilities(showMinimumMoves: true),
      );
      for (final family in SpiritFamily.values) {
        expect(FamilyAbilities.of(family, 2), FamilyAbilities.none);
      }
      expect(FamilyAbilities.of(null, 5), FamilyAbilities.none);
    });
  });
}
