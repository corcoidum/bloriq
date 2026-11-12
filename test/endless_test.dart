import 'dart:convert';
import 'dart:io';

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_pool.dart';
import 'package:bloriq/endless/endless_repository.dart';
import 'package:bloriq/endless/endless_rules.dart';
import 'package:bloriq/endless/endless_run.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/start_game.dart';
import 'support/world_release.dart'
    show
        captureReleaseScreen,
        closeReleaseApp,
        openReleaseApp,
        releaseKey,
        waitForReleaseWidget;

class _FailingVoyageStore extends InMemorySharedPreferencesStore {
  _FailingVoyageStore(super.data) : super.withData();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;
}

EndlessPool _pool({bool includeWorlds = false}) => EndlessPool.parse(
  File(EndlessPool.asset).readAsStringSync(),
  worldSource: includeWorlds
      ? File(EndlessPool.worldAsset).readAsStringSync()
      : null,
);

VoyageRun _runAtDepth(
  EndlessPool pool,
  int depth, {
  required int seed,
  Set<int> completedWorlds = const {},
}) {
  final run = VoyageRun.start(pool, seed: seed);
  while (run.depth < depth) {
    final minimum = pool.level(run.board)!.minimumMoves;
    for (var i = 0; i < minimum; i++) {
      run.pushed();
    }
    run.clear(minimum, pool, completedWorlds: completedWorlds);
  }
  return run;
}

List<Level> _campaign() =>
    (jsonDecode(File('assets/levels/levels.json').readAsStringSync()) as List)
        .map((raw) => Level.fromJson(raw as Map<String, dynamic>))
        .toList();

Future<void> _seed({
  Set<int> chapters = const {1},
  Map<String, Object> extra = const {},
}) async {
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
    ...extra,
  });
}

/// 화면의 판을 [move] 한 수만큼 끌어 민다.
Future<void> _drag(WidgetTester tester, PuzzleMove move) async {
  final board = find.byType(GameWidget<BloriqGame>);
  final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
  final block = game.controller.state.blocks.firstWhere(
    (b) => b.id == move.blockId,
  );
  final geometry = game.geometry;
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

BloriqGame _game(WidgetTester tester) => tester
    .widget<GameWidget<BloriqGame>>(find.byType(GameWidget<BloriqGame>))
    .game!;

void main() {
  setUp(rootBundle.clear);

  group('rules', () {
    test('depth climbs through four seas', () {
      expect([1, 3, 4, 10, 11, 22, 23, 500].map(EndlessRules.tierForDepth), [
        1,
        1,
        2,
        2,
        3,
        3,
        4,
        4,
      ]);
      expect(() => EndlessRules.tierForDepth(0), throwsArgumentError);
    });

    test('perfect streaks multiply the score up to ×5', () {
      expect(EndlessRules.multiplier(perfect: false, combo: 3), 1);
      expect(EndlessRules.multiplier(perfect: true, combo: 1), 2);
      expect(EndlessRules.multiplier(perfect: true, combo: 3), 4);
      expect(EndlessRules.multiplier(perfect: true, combo: 9), 5);
      expect(
        EndlessRules.boardPoints(minimum: 8, perfect: true, combo: 2),
        240,
      );
      expect(EndlessRules.refill(perfect: true), 3);
      expect(EndlessRules.refill(perfect: false), 1);
      expect(EndlessRules.waste(pushes: 7, minimum: 9), 0);
      expect(EndlessRules.waste(pushes: 12, minimum: 9), 3);
    });
  });

  group('board transforms', () {
    test('every rotation and mirror keeps the shortest path', () {
      final solver = const PuzzleSolver(maxStates: 2000000);
      for (final level in _campaign()) {
        final base = solver.solve(level)!.length;
        for (var symmetry = 1; symmetry < 8; symmetry++) {
          final moved = transformLevel(level, symmetry);
          expect(
            solver.solve(moved)!.length,
            base,
            reason: 'level ${level.id} symmetry $symmetry',
          );
        }
      }
    });

    test('a quarter turn swaps the board size and turns arrows', () {
      final level = _campaign().firstWhere((l) => l.oneWays.isNotEmpty);
      final turned = transformLevel(level, 1);
      expect(turned.boardWidth, level.boardHeight);
      expect(turned.boardHeight, level.boardWidth);
      final (tile, direction) = (
        level.oneWays.keys.first,
        level.oneWays.values.first,
      );
      final moved = Position(level.boardHeight - 1 - tile.y, tile.x);
      expect(turned.oneWays[moved], Position(-direction.y, direction.x));
    });
  });

  group('pool', () {
    late final EndlessPool pool;
    setUpAll(() => pool = _pool());

    test('is bundled and fills all four seas', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains(EndlessPool.asset),
      );
      for (var tier = 1; tier <= 4; tier++) {
        expect(pool.tiers[tier], isNotEmpty, reason: 'tier $tier');
      }
      expect(pool.length, greaterThanOrEqualTo(500));
    });

    test('boards are bare-handed and their recorded minimum is exact', () {
      final solver = const PuzzleSolver(maxStates: 2000000);
      for (final list in pool.tiers.values) {
        // 판이 많아 단계마다 고르게 일부만 다시 푼다(전체는 tools/validate 로).
        for (var i = 0; i < list.length; i += 9) {
          final level = list[i];
          expect(
            solver.solve(level, powers: const {})!.length,
            level.minimumMoves,
            reason: 'board ${level.id}',
          );
        }
      }
    });

    test('the same voyage always draws the same boards', () {
      final a = pool.pick(seed: 42, depth: 7, used: {});
      final b = pool.pick(seed: 42, depth: 7, used: {});
      expect((a.id, a.symmetry), (b.id, b.symmetry));
      expect(pool.tiers[2]!.map((l) => l.id), contains(a.id));
    });
  });

  group('world mechanic seas', () {
    late final EndlessPool pool;
    setUpAll(() => pool = _pool(includeWorlds: true));

    test('adds 120 bare-handed boards per mechanic after the v1 IDs', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains(EndlessPool.worldAsset),
      );
      final v1Ids =
          pool.tiers.values
              .expand((list) => list)
              .map((level) => level.id)
              .toList()
            ..sort();
      expect(v1Ids, hasLength(530));
      expect(pool.length, 1010);
      final solver = const PuzzleSolver(maxStates: 1000000);
      for (final sea in MechanicSea.values) {
        final levels = pool.seas[sea]!;
        expect(levels, hasLength(120));
        for (final level in levels) {
          expect(level.id, greaterThan(v1Ids.last));
          expect(level.mechanics.keys, contains(sea.mechanic));
          expect(level.availablePowers, isEmpty);
          expect(level.minimumMoves, inInclusiveRange(6, 14));
        }
        for (var index = 0; index < levels.length; index += 24) {
          final level = levels[index];
          for (final symmetry in [0, 1, if (sea != MechanicSea.clock) 7]) {
            final board = pool.level(VoyageBoard(level.id, symmetry))!;
            expect(
              solver.solve(board),
              hasLength(level.minimumMoves),
              reason: '${sea.name} ${level.id}, symmetry $symmetry',
            );
          }
        }
      }
    });

    test('only completed worlds enter every third slot starting at sea 6', () {
      final seen = <int>{};
      final selected = <MechanicSea>{};
      for (var depth = 1; depth <= 36; depth++) {
        final mirror = pool.pick(
          seed: 42,
          depth: depth,
          used: {},
          completedWorlds: {3},
        );
        final board = pool.pick(
          seed: 42,
          depth: depth,
          used: seen,
          completedWorlds: {3, 4},
        );
        final sea = pool.seaOf(board.id);
        expect(
          board.toJson(),
          pool
              .pick(seed: 42, depth: depth, used: seen, completedWorlds: {4, 3})
              .toJson(),
        );
        final slot = depth >= 6 && depth % 3 == 0;
        expect(pool.seaOf(mirror.id), slot ? MechanicSea.mirror : null);
        if (slot) {
          expect(sea, isIn([MechanicSea.mirror, MechanicSea.clock]));
          selected.add(sea!);
          if (sea == MechanicSea.clock) expect(board.symmetry, lessThan(4));
        } else {
          expect(sea, isNull);
          expect(
            board.toJson(),
            pool.pick(seed: 42, depth: depth, used: seen).toJson(),
          );
        }
        expect(seen.add(board.id), isTrue);
      }
      expect(selected, {MechanicSea.mirror, MechanicSea.clock});
    });

    test(
      'same seed and eligibility repeat the draw and prefer unused boards',
      () {
        final list = pool.seas[MechanicSea.ice]!;
        final used = {for (final level in list.skip(1)) level.id};
        final first = pool.pick(
          seed: 78,
          depth: 6,
          used: used,
          completedWorlds: {5, 7},
        );
        final second = pool.pick(
          seed: 78,
          depth: 6,
          used: used,
          completedWorlds: {7, 5},
        );
        expect(first.toJson(), second.toJson());
        expect(first.id, list.first.id);
        expect(
          pool.seaOf(
            pool
                .pick(seed: 78, depth: 6, used: {}, completedWorlds: {1, 2, 7})
                .id,
          ),
          isNull,
        );
      },
    );

    test(
      'a v1 save keeps the exact board and counters even at a new sea slot',
      () async {
        final legacy = _pool();
        final original = _runAtDepth(legacy, 6, seed: 138)
          ..pushed()
          ..hinted();
        final snapshot = original.toJson();
        await _seed(
          extra: {
            EndlessRepository.storageKey: jsonEncode({
              'version': 1,
              'run': snapshot,
            }),
          },
        );
        final restored = (await EndlessRepository.load()).savedRun!;
        expect(
          restored.replaceUnavailableBoard(pool, completedWorlds: {3, 4, 5, 6}),
          isFalse,
        );
        expect(restored.toJson(), snapshot);
        final oldLevel = legacy.level(original.board)!;
        final level = pool.level(restored.board)!;
        expect(level.startPosition, oldLevel.startPosition);
        expect(level.exitPosition, oldLevel.exitPosition);
        expect(
          level.blocks.map((block) => block.position),
          oldLevel.blocks.map((block) => block.position),
        );
        expect(
          restored.lanternFor(level.minimumMoves),
          original.lanternFor(oldLevel.minimumMoves),
        );
      },
    );

    test(
      'a saved mechanic board is kept only while its world is completed',
      () {
        final original = _runAtDepth(pool, 6, seed: 42, completedWorlds: {6})
          ..pushed()
          ..hinted();
        final restored = VoyageRun.fromJson(original.toJson());
        expect(
          restored.replaceUnavailableBoard(pool, completedWorlds: {6}),
          isFalse,
        );
        expect(restored.toJson(), original.toJson());
        expect(
          restored.replaceUnavailableBoard(pool, completedWorlds: {3}),
          isTrue,
        );
        expect(pool.seaOf(restored.board.id), MechanicSea.mirror);
        expect(restored.depth, original.depth);
        expect(restored.score, original.score);
        expect(restored.pushes, original.pushes);
        expect(restored.hintsSpent, original.hintsSpent);
      },
    );
  });

  group('voyage run', () {
    late final EndlessPool pool;
    setUpAll(() => pool = _pool());

    test('the first 30 boards climb from basic moves to paired mechanics', () {
      for (final seed in [1, 42, 2026]) {
        final run = VoyageRun.start(pool, seed: seed);
        final seen = <int>{};
        for (var depth = 1; depth <= 30; depth++) {
          final (minMoves, maxMoves, minRules, maxRules) = switch (depth) {
            <= 3 => (4, 6, 0, 0),
            <= 10 => (6, 9, 1, 1),
            <= 22 => (9, 12, 1, 2),
            _ => (12, 16, 2, 2),
          };
          final level = pool.level(run.board)!;
          final reason = 'seed $seed, sea $depth';
          expect(run.depth, depth, reason: reason);
          expect(seen.add(level.id), isTrue, reason: reason);
          expect(
            level.minimumMoves,
            inInclusiveRange(minMoves, maxMoves),
            reason: reason,
          );
          expect(
            level.mechanics.length,
            inInclusiveRange(minRules, maxRules),
            reason: reason,
          );
          for (var push = 0; push < level.minimumMoves; push++) {
            run.pushed();
          }
          run.clear(level.minimumMoves, pool);
        }
      }
    });

    test('a saved calm board resumes at sea 5 before picking a new tier', () {
      // 이전 곡선에서는 5번째 바다도 기믹 없는 판이었다.
      final oldRun = VoyageRun.start(pool, seed: 42)
        ..depth = 5
        ..pushed();
      final resumed = VoyageRun.fromJson(oldRun.toJson());
      expect(resumed.board.toJson(), oldRun.board.toJson());
      expect(resumed.pushes, 1);
      final oldLevel = pool.level(resumed.board)!;
      expect(oldLevel.mechanics, isEmpty);
      resumed.clear(oldLevel.minimumMoves, pool);
      expect(resumed.depth, 6);
      expect(pool.level(resumed.board)!.mechanics, hasLength(1));
    });

    test('wasted pushes burn the lantern and a perfect clear refills it', () {
      final run = VoyageRun.start(pool, seed: 5);
      final minimum = pool.level(run.board)!.minimumMoves;
      expect(run.lanternFor(minimum), EndlessRules.startLantern);
      for (var i = 0; i < minimum + 3; i++) {
        run.pushed();
      }
      expect(run.lanternFor(minimum), EndlessRules.startLantern - 3);
      final result = run.clear(minimum, pool);
      expect(result.perfect, isFalse);
      expect(result.points, minimum * 10);
      expect(run.lanternAtStart, EndlessRules.startLantern - 3 + 1);
      expect(run.combo, 0);
      expect(run.depth, 2);

      final next = pool.level(run.board)!.minimumMoves;
      for (var i = 0; i < next; i++) {
        run.pushed();
      }
      final perfect = run.clear(next, pool);
      expect(perfect.perfect, isTrue);
      expect(perfect.multiplier, 2);
      expect(run.lanternAtStart, EndlessRules.startLantern - 3 + 1 + 3);
      expect(run.combo, 1);
    });

    test('the lantern never overflows and goes out at zero', () {
      final run = VoyageRun.start(pool, seed: 9);
      for (var i = 0; i < 6; i++) {
        final minimum = pool.level(run.board)!.minimumMoves;
        for (var m = 0; m < minimum; m++) {
          run.pushed();
        }
        run.clear(minimum, pool);
      }
      expect(run.lanternAtStart, EndlessRules.maxLantern);
      final minimum = pool.level(run.board)!.minimumMoves;
      for (var m = 0; m < minimum + EndlessRules.maxLantern - 1; m++) {
        run.pushed();
      }
      expect(run.isOut(minimum), isFalse);
      run.pushed();
      expect(run.isOut(minimum), isTrue);
    });

    test('a starlight move costs light and breaks the perfect', () {
      final run = VoyageRun.start(pool, seed: 3);
      final minimum = pool.level(run.board)!.minimumMoves;
      expect(run.canHint(minimum), isTrue);
      run.hinted();
      expect(run.lanternFor(minimum), EndlessRules.startLantern - 2);
      for (var m = 0; m < minimum; m++) {
        run.pushed();
      }
      expect(run.clear(minimum, pool).perfect, isFalse);
      run.lanternAtStart = EndlessRules.hintCost;
      expect(run.canHint(pool.level(run.board)!.minimumMoves), isFalse);
    });

    test('survives a save and reload mid-board', () {
      final run = VoyageRun.start(pool, seed: 11)
        ..pushed()
        ..pushed();
      final copy = VoyageRun.fromJson(
        jsonDecode(jsonEncode(run.toJson())) as Map<String, dynamic>,
      );
      expect(copy.pushes, 2);
      expect(copy.board.id, run.board.id);
      expect(copy.board.symmetry, run.board.symmetry);
      expect(copy.lanternAtStart, run.lanternAtStart);
      expect(
        () => VoyageRun.fromJson({...run.toJson(), 'depth': 0}),
        throwsFormatException,
      );
    });
  });

  group('records', () {
    test('best, weekly best and milestones are kept once', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime(2026, 11, 8); // 일요일
      final repo = await EndlessRepository.load(clock: () => now);
      final pool = _pool();
      final run = VoyageRun.start(pool, seed: 1)
        ..depth = 27
        ..score = 900
        ..perfects = 4;
      await repo.saveRun(run, clearedBoard: true);
      final first = await repo.finish(run);
      expect(first.newBestScore, isTrue);
      expect(first.newBestDepth, isTrue);
      expect(first.milestones.map((m) => m.depth), [10, 25]);
      expect(first.stardust, 26 * 2 + 4);
      expect(first.xp, 26 * 6);
      expect(repo.weekBest, 900);

      final second = await repo.finish(
        VoyageRun.start(pool, seed: 2)
          ..depth = 30
          ..score = 400,
      );
      expect(second.newBestScore, isFalse);
      expect(second.newBestDepth, isTrue);
      expect(second.milestones, isEmpty);

      now = DateTime(2026, 11, 9); // 월요일: 새 주
      expect(repo.weekBest, 0);
      final reloaded = await EndlessRepository.load(clock: () => now);
      expect(reloaded.bestScore, 900);
      expect(reloaded.bestDepth, 29);
      expect(reloaded.voyages, 2);
      expect(reloaded.claimedMilestones, {'depth10', 'depth25'});
    });

    test(
      'legacy progress counts immediately and weekly score rolls on Monday',
      () async {
        final run = VoyageRun.start(_pool(), seed: 8)
          ..depth = 45
          ..score = 12000;
        await _seed(
          extra: {
            EndlessRepository.storageKey: jsonEncode({
              'version': 1,
              'run': run.toJson(),
            }),
          },
        );
        var now = DateTime(2026, 11, 8);
        final repo = await EndlessRepository.load(clock: () => now);
        final saved = repo.savedRun!;
        expect(repo.harborBestScore, 12000);
        expect(repo.harborBestDepth, 44);
        expect(repo.weekBest, 0);
        await repo.saveRun(saved, clearedBoard: true);
        expect(repo.weekBest, 12000);
        expect(
          (await EndlessRepository.load(clock: () => now)).weekBest,
          12000,
        );
        now = DateTime(2026, 11, 9);
        await repo.saveRun(saved);
        expect(repo.weekBest, 0);
        saved
          ..depth += 1
          ..score += 500;
        await repo.saveRun(saved, clearedBoard: true);
        expect(repo.weekBest, 12500);

        final next = VoyageRun.start(_pool(), seed: 10);
        final competing = VoyageRun.start(_pool(), seed: 11);
        expect(
          await Future.wait([
            repo.replaceRun(saved, next),
            repo.replaceRun(saved, competing),
          ]),
          [true, false],
        );
        final restored = await EndlessRepository.load(clock: () => now);
        expect(restored.savedRun?.seed, next.seed);
        expect(restored.savedRun?.depth, 1);
        expect(restored.bestScore, 12500);
        expect(restored.bestDepth, 45);
        expect(restored.weekBest, 12500);
        expect(restored.voyages, 0);
        expect(restored.claimedMilestones, isEmpty);
      },
    );

    test(
      'a failed replacement keeps the original run and disk snapshot',
      () async {
        final pool = _pool();
        final run = VoyageRun.start(pool, seed: 8)..depth = 45;
        final original = jsonEncode({'version': 1, 'run': run.toJson()});
        SharedPreferences.setMockInitialValues({});
        SharedPreferencesStorePlatform.instance = _FailingVoyageStore({
          'flutter.${EndlessRepository.storageKey}': original,
        });
        addTearDown(() => SharedPreferences.setMockInitialValues({}));
        final repo = await EndlessRepository.load();
        final saved = repo.savedRun!;
        expect(
          await repo.replaceRun(saved, VoyageRun.start(pool, seed: 9)),
          isFalse,
        );
        expect(repo.saveFailed, isTrue);
        expect(repo.savedRun, same(saved));
        expect(
          (await SharedPreferences.getInstance()).getString(
            EndlessRepository.storageKey,
          ),
          original,
        );
      },
    );

    test(
      'an unfinished voyage is restored, a corrupt one is dropped',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repo = await EndlessRepository.load();
        await repo.saveRun(VoyageRun.start(_pool(), seed: 4)..pushed());
        expect((await EndlessRepository.load()).savedRun?.pushes, 1);

        SharedPreferences.setMockInitialValues({
          EndlessRepository.storageKey:
              '{"version":1,"bestScore":5,"run":{"x":1}}',
        });
        final broken = await EndlessRepository.load();
        expect(broken.bestScore, 5);
        expect(broken.savedRun, isNull);
      },
    );

    test('voyage rewards reach the shared progression', () async {
      SharedPreferences.setMockInitialValues({});
      final progression = await ProgressionRepository.load();
      final reward = await progression.recordVoyage(
        xp: 60,
        stardust: 25,
        rewards: voyageMilestones[1].rewards,
      );
      expect(reward.xpGained, 60);
      expect(progression.stardust, 25 + 100);
      expect(progression.ownedTrails, contains('tide'));
    });
  });

  group('screen', () {
    for (final (chapterCount, sea, seaName) in [
      (19, MechanicSea.mirror, '거울 바다'),
      (20, MechanicSea.clock, '시계 바다'),
    ]) {
      testWidgets(
        'crossing sea 5 after $chapterCount chapters shows ${sea.name}',
        (tester) async {
          const capture = bool.fromEnvironment('CAPTURE_ENDLESS_V2');
          final pool = _pool(includeWorlds: true);
          final seed = Iterable<int>.generate(64).firstWhere(
            (seed) =>
                pool.seaOf(
                  pool
                      .pick(
                        seed: seed,
                        depth: 6,
                        used: {},
                        completedWorlds: {3, 4},
                      )
                      .id,
                ) ==
                MechanicSea.clock,
          );
          final run = _runAtDepth(_pool(), 5, seed: seed);
          await _seed(
            chapters: {
              for (var chapter = 1; chapter <= chapterCount; chapter++) chapter,
            },
            extra: {
              EndlessRepository.storageKey: jsonEncode({
                'version': 1,
                'run': run.toJson(),
              }),
            },
          );
          final boundary = await openReleaseApp(
            tester,
            captureArt: capture && sea == MechanicSea.clock,
          );
          await tapVisible(tester, releaseKey('home-voyage'));
          await waitForReleaseWidget(tester, releaseKey('endless-resume'));
          await tapVisible(tester, releaseKey('endless-resume'));
          final level = _game(tester).controller.state.level;
          expect(level.id, run.board.id);
          expect(find.text('5번째 바다'), findsOneWidget);
          for (final move in const PuzzleSolver().solve(level)!) {
            await _drag(tester, move);
          }
          await tester.pump(const Duration(seconds: 2));
          expect(find.text('6번째 바다 · $seaName'), findsOneWidget);
          final saved = (await EndlessRepository.load()).savedRun!;
          expect(pool.seaOf(saved.board.id), sea);
          expect(
            _game(tester).controller.state.level.mechanics.keys,
            contains(sea.mechanic),
          );
          if (capture && sea == MechanicSea.clock) {
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 400));
            await captureReleaseScreen(
              tester,
              boundary,
              'docs/screenshots/endless/v2-clock-sea.png',
            );
          }
          tester.view.physicalSize = const Size(320, 568);
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('6번째 바다 · $seaName'), findsOneWidget);
          expect(_game(tester).geometry.cellSize, greaterThanOrEqualTo(40));
          await closeReleaseApp(tester);
        },
      );
    }

    testWidgets('Sea 45 shows progress and new voyage requires confirmation', (
      tester,
    ) async {
      final run = VoyageRun.start(_pool(), seed: 8)
        ..depth = 45
        ..score = 12000;
      await _seed(
        extra: {
          EndlessRepository.storageKey: jsonEncode({
            'version': 1,
            'run': run.toJson(),
          }),
        },
      );
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      final newVoyage = find.byKey(const ValueKey('endless-new'));
      for (var i = 0; i < 50 && newVoyage.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(find.text('Continue voyage · Sea 45'), findsOneWidget);
      expect(find.text('44 cleared · 12000 pts'), findsOneWidget);
      expect(find.text('12000'), findsOneWidget);
      expect(find.text('44'), findsOneWidget);

      final start = tester.widget<OutlinedButton>(newVoyage).onPressed!;
      start();
      start();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('endless-cancel-new')),
      );
      expect(find.text('Continue voyage · Sea 45'), findsOneWidget);
      await tapVisible(tester, newVoyage);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect((await EndlessRepository.load()).savedRun?.depth, 45);

      await tapVisible(tester, newVoyage);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('endless-confirm-new')),
      );
      expect(find.text('Sea 1'), findsOneWidget);
      final restored = await EndlessRepository.load();
      expect(restored.savedRun?.depth, 1);
      expect(restored.bestDepth, 44);
      expect(restored.bestScore, 12000);
      expect(restored.voyages, 0);
    });

    testWidgets('the voyage stays locked until the first constellation', (
      tester,
    ) async {
      await _seed(chapters: {});
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      expect(find.byKey(const ValueKey('endless-screen')), findsNothing);
      expect(find.text(EndlessText.locked.en), findsWidgets);
    });

    testWidgets('sail, cross a board and move on to the next sea', (
      tester,
    ) async {
      await _seed();
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byKey(const ValueKey('endless-start')).evaluate().isNotEmpty) {
          break;
        }
      }
      await tapVisible(tester, find.byKey(const ValueKey('endless-start')));
      expect(find.text('Sea 1'), findsOneWidget);

      final level = _game(tester).controller.state.level;
      for (final move in const PuzzleSolver().solve(level)!) {
        await _drag(tester, move);
      }
      expect(find.byKey(const ValueKey('endless-flash')), findsOneWidget);
      expect(find.text('Perfect!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Sea 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('endless-combo')), findsOneWidget);
      expect(find.text('Score ${level.minimumMoves * 20}'), findsOneWidget);
      final saved = (await EndlessRepository.load()).savedRun!;
      expect(saved.depth, 2);
      expect(saved.lanternAtStart, EndlessRules.startLantern + 3);
    });

    testWidgets('a small phone with large text still fits the voyage', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final pool = _pool();
      final run = VoyageRun.start(pool, seed: 8);
      while (run.depth < 40) {
        final minimum = pool.level(run.board)!.minimumMoves;
        for (var i = 0; i < minimum; i++) {
          run.pushed();
        }
        run.clear(minimum, pool);
      }
      await _seed(
        extra: {
          EndlessRepository.storageKey: jsonEncode({
            'version': 1,
            'run': run.toJson(),
          }),
        },
      );
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find
            .byKey(const ValueKey('endless-resume'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byKey(const ValueKey('endless-resume')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('endless-combo')), findsOneWidget);
      final geometry = _game(tester).geometry;
      expect(geometry.cellSize, greaterThanOrEqualTo(40));
    });

    testWidgets('the lantern goes out and the voyage is scored', (
      tester,
    ) async {
      final pool = _pool();
      final run = VoyageRun.start(pool, seed: 21)..lanternAtStart = 1;
      final level = pool.level(run.board)!;
      for (var i = 0; i < level.minimumMoves; i++) {
        run.pushed();
      }
      await _seed(
        extra: {
          EndlessRepository.storageKey: jsonEncode({
            'version': 1,
            'bestScore': 0,
            'run': run.toJson(),
          }),
        },
      );
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      expect(find.textContaining('Continue voyage'), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find
            .byKey(const ValueKey('endless-resume'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
      await tapVisible(tester, find.byKey(const ValueKey('endless-resume')));
      // 최단 수를 이미 다 썼으니 한 번만 더 밀어도 등불이 꺼진다.
      await _drag(tester, const PuzzleSolver().solve(level)!.first);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('endless-over')), findsOneWidget);
      expect(find.text('The lantern went out'), findsOneWidget);
      expect((await EndlessRepository.load()).savedRun, isNull);
      expect((await EndlessRepository.load()).voyages, 1);

      await tapVisible(tester, find.byKey(const ValueKey('endless-again')));
      expect(find.text('Sea 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('endless-over')), findsNothing);
    });
  });
}
