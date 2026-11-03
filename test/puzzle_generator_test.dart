import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_repository.dart';
import 'package:bloriq/endless/puzzle_generator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, dynamic>> _pool() => (jsonDecode(
  File('assets/levels/daily_pool_v1.json').readAsStringSync(),
) as List).cast<Map<String, dynamic>>();

// 측정용: flutter test test/puzzle_generator_test.dart --dart-define=MEASURE_GENERATOR=true
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EndlessRepository.runInline = true;
  });
  tearDown(() => EndlessRepository.runInline = false);

  test('report success rate and time per tier', () {
    if (!const bool.fromEnvironment('MEASURE_GENERATOR')) return;
    for (final cleared in [0, 5, 15, 18, 21, 24, 27, 30, 45]) {
      final watch = Stopwatch()..start();
      var made = 0, slowest = 0;
      final moves = <int>[];
      for (var seed = 1; seed <= 60; seed++) {
        final one = Stopwatch()..start();
        final level = generatePuzzle(
          seed: seed * 7919 + cleared,
          id: 100000 + seed,
          cleared: cleared,
        );
        if (one.elapsedMilliseconds > slowest) {
          slowest = one.elapsedMilliseconds;
        }
        if (level != null) {
          made++;
          moves.add(level.minimumMoves);
        }
      }
      moves.sort();
      // ignore: avoid_print
      print(
        'cleared=$cleared made=$made/60 '
        'avg=${(watch.elapsedMilliseconds / 60).toStringAsFixed(1)}ms '
        'slowest=${slowest}ms '
        'moves=${moves.isEmpty ? '-' : '${moves.first}..${moves.last}'}',
      );
    }
  });

  group('generator', () {
    test('the same seed always builds the same puzzle', () {
      final a = generatePuzzle(seed: 42, id: 1, cleared: 20)!;
      final b = generatePuzzle(seed: 42, id: 1, cleared: 20)!;
      expect(puzzleFingerprint(a), puzzleFingerprint(b));
      final c = generatePuzzle(seed: 43, id: 1, cleared: 20)!;
      expect(puzzleFingerprint(a), isNot(puzzleFingerprint(c)));
    });

    for (final cleared in [0, 5, 15, 20, 27]) {
      test('tier at $cleared clears: solvable, in range, exact minimum', () {
        final tier = EndlessTier.forCleared(cleared);
        for (var seed = 1; seed <= 25; seed++) {
          final level = generatePuzzle(
            seed: seed * 101,
            id: 100000,
            cleared: cleared,
          );
          expect(level, isNotNull, reason: 'seed $seed');
          final solution = const PuzzleSolver().solve(level!)!;
          expect(solution.length, level.minimumMoves);
          expect(
            level.minimumMoves,
            inInclusiveRange(tier.minMoves, tier.maxMoves),
          );
          expect(level.minimumMoves, lessThanOrEqualTo(12));
          expect(level.boardWidth, tier.size);
          final controller = PuzzleController(level);
          for (final move in solution) {
            expect(controller.move(move.blockId, move.target), isTrue);
          }
          expect(controller.state.isComplete, isTrue);
        }
      });
    }

    test('early tiers have no devices; later tiers always do', () {
      for (var seed = 1; seed <= 15; seed++) {
        final easy = generatePuzzle(seed: seed, id: 1, cleared: 3)!;
        expect(easy.echoGate, isNull);
        expect(easy.oneWays, isEmpty);
        final hard = generatePuzzle(seed: seed, id: 1, cleared: 28)!;
        expect(
          hard.echoGate != null ||
              hard.echoErasers.isNotEmpty ||
              hard.echoHolds.isNotEmpty ||
              hard.oneWays.isNotEmpty ||
              hard.goalOnlyTiles.isNotEmpty,
          isTrue,
        );
      }
    });

    test('devices unlock one at a time', () {
      expect(unlockedDevices(14), isEmpty);
      expect(unlockedDevices(15), [EndlessDevice.gate]);
      expect(unlockedDevices(18), hasLength(2));
      expect(unlockedDevices(27), hasLength(5));
    });

    test('a removed gate would change the shortest path', () {
      for (var seed = 1; seed <= 20; seed++) {
        final level = generatePuzzle(seed: seed * 3, id: 1, cleared: 16)!;
        if (level.echoGate == null) continue;
        final locked = Level(
          id: 1,
          boardWidth: level.boardWidth,
          boardHeight: level.boardHeight,
          startPosition: level.startPosition,
          exitPosition: level.exitPosition,
          blocks: level.blocks,
          obstacles: [...level.obstacles, level.echoGate!],
          minimumMoves: 0,
          difficulty: 'test',
        );
        expect(
          const PuzzleSolver().solve(locked)?.length,
          isNot(level.minimumMoves),
        );
      }
    });

    test('recent puzzles are not repeated, even rotated or mirrored', () {
      final first = generatePuzzle(seed: 7, id: 1, cleared: 8)!;
      final turned = transformLevel(first, id: 1, rotation: 1, mirror: true);
      expect(puzzleFingerprint(first), puzzleFingerprint(turned));
      final again = generatePuzzle(
        seed: 7,
        id: 1,
        cleared: 8,
        recent: {puzzleFingerprint(first)},
      )!;
      expect(puzzleFingerprint(again), isNot(puzzleFingerprint(first)));
    });

    test(
      'rotating and mirroring keeps every puzzle solvable at its minimum',
      () {
        for (final raw in _pool()) {
          final level = Level.fromJson(raw);
          for (final mirror in [false, true]) {
            for (var rotation = 0; rotation < 4; rotation++) {
              final turned = transformLevel(
                level,
                id: 9,
                rotation: rotation,
                mirror: mirror,
              );
              expect(
                const PuzzleSolver().solve(turned)!.length,
                level.minimumMoves,
              );
            }
          }
        }
      },
    );
  });

  test('generation works across a real background isolate', () async {
    final level = await compute(
      runEndlessRequest,
      const EndlessRequest(seed: 99, id: 100007, cleared: 16, recent: {}),
    );
    expect(level, isNotNull);
    expect(level!.id, 100007);
    expect(const PuzzleSolver().solve(level)!.length, level.minimumMoves);
  });

  group('repository', () {
    test('different installs start on different puzzles', () async {
      final a = await EndlessRepository.load(_pool(), random: math.Random(1));
      SharedPreferences.setMockInitialValues({});
      final b = await EndlessRepository.load(_pool(), random: math.Random(2));
      expect(
        puzzleFingerprint(await a.currentPuzzle()),
        isNot(puzzleFingerprint(await b.currentPuzzle())),
      );
    });

    test('clearing advances, builds a streak and caps the combo', () async {
      final repo = await EndlessRepository.load(_pool());
      final seen = <String>{};
      expect(repo.combo, 1);
      for (var i = 0; i < 7; i++) {
        seen.add(puzzleFingerprint(await repo.currentPuzzle()));
        repo.prefetchNext();
        expect(await repo.recordClear(), isTrue);
        await repo.nextPuzzle();
      }
      expect(seen, hasLength(7));
      expect(repo.cleared, 7);
      expect(repo.streak, 7);
      expect(repo.bestStreak, 7);
      expect(repo.combo, EndlessRepository.maxCombo);
      repo.breakStreak();
      expect(repo.combo, 1);
      expect(repo.bestStreak, 7);
    });

    test('reopening resumes the same puzzle and keeps records', () async {
      final repo = await EndlessRepository.load(_pool());
      await repo.currentPuzzle();
      await repo.recordClear();
      final puzzle = await repo.nextPuzzle();
      await repo.flush();
      final again = await EndlessRepository.load(_pool());
      expect(again.cleared, 1);
      expect(again.streak, 1);
      expect(
        puzzleFingerprint(await again.currentPuzzle()),
        puzzleFingerprint(puzzle),
      );
    });

    test('a slow or failed generator falls back to a valid puzzle', () async {
      final repo = await EndlessRepository.load(_pool());
      for (final number in [0, 5, 20, 40]) {
        final level = repo.fallbackPuzzle(number);
        expect(level.id, EndlessRepository.firstId + number);
        expect(const PuzzleSolver().solve(level)!.length, level.minimumMoves);
      }
    });

    test('a failed save is reported and retry stores it', () async {
      var allow = false;
      final repo = await EndlessRepository.load(
        _pool(),
        writer: (_, _) async => allow,
      );
      await repo.currentPuzzle();
      expect(await repo.recordClear(), isFalse);
      expect(repo.saveFailed, isTrue);
      expect(repo.cleared, 1);
      allow = true;
      expect(await repo.retrySave(), isTrue);
    });

    for (final raw in ['broken', '{"version":9}']) {
      test('unreadable record is never overwritten: $raw', () async {
        SharedPreferences.setMockInitialValues({
          EndlessRepository.storageKey: raw,
        });
        final repo = await EndlessRepository.load(_pool());
        expect(repo.saveFailed, isTrue);
        await repo.currentPuzzle();
        await repo.recordClear();
        expect(
          (await SharedPreferences.getInstance()).getString(
            EndlessRepository.storageKey,
          ),
          raw,
        );
      });
    }
  });
}
