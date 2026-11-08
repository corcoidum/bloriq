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

import 'support/start_game.dart';

EndlessPool _pool() =>
    EndlessPool.parse(File(EndlessPool.asset).readAsStringSync());

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
      expect([1, 5, 6, 15, 16, 35, 36, 500].map(EndlessRules.tierForDepth), [
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

  group('voyage run', () {
    late final EndlessPool pool;
    setUpAll(() => pool = _pool());

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
