import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/progress/player_repository.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Level> _levels() =>
    (jsonDecode(File('assets/levels/levels.json').readAsStringSync()) as List)
        .map((e) => Level.fromJson(e as Map<String, dynamic>))
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('score', () {
    test('base grows with difficulty and stars multiply it', () {
      expect(RunScore.of(minimumMoves: 5, stars: 1).total, 100);
      expect(RunScore.of(minimumMoves: 5, stars: 2).total, 150);
      expect(RunScore.of(minimumMoves: 5, stars: 3).total, 200);
      expect(RunScore.of(minimumMoves: 12, stars: 3).total, 340);
    });

    test('combo multiplies the total and rounds', () {
      expect(RunScore.of(minimumMoves: 5, stars: 3, combo: 1.5).total, 300);
      expect(RunScore.of(minimumMoves: 3, stars: 2, combo: 1.1).total, 132);
    });
  });

  group('levels', () {
    test('thresholds rise by 100 per level', () {
      expect(PlayerLevel.xpForLevel(1), 300);
      expect(PlayerLevel.xpForLevel(2), 400);
      expect(PlayerLevel.xpForLevel(10), 1200);
    });

    test('exact boundaries land on the next level at zero', () {
      expect(PlayerLevel.fromXp(0).level, 1);
      expect(PlayerLevel.fromXp(299).level, 1);
      expect(PlayerLevel.fromXp(300).level, 2);
      expect(PlayerLevel.fromXp(300).into, 0);
      expect(PlayerLevel.fromXp(699).level, 2);
      expect(PlayerLevel.fromXp(700).level, 3);
    });

    test('early levels come about every two clears', () {
      final clear = RunScore.of(minimumMoves: 5, stars: 3).total;
      expect(PlayerLevel.fromXp(clear * 2).level, 2);
      expect(PlayerLevel.fromXp(clear * 4).level, 3);
    });
  });

  group('repository', () {
    test('new players start at zero and awards survive a restart', () async {
      final levels = _levels();
      final progress = await ProgressRepository.load();
      final repo = await PlayerRepository.load(levels, progress);
      expect(repo.xp, 0);
      final award = await repo.award(350);
      expect(award.saved, isTrue);
      expect(award.leveledUp, isTrue);
      expect(award.before.level, 1);
      expect(award.after.level, 2);
      final again = await PlayerRepository.load(levels, progress);
      expect(again.xp, 350);
    });

    test('existing stars convert to experience exactly once', () async {
      final levels = _levels();
      final progress = await ProgressRepository.load();
      final first = levels.first;
      await progress.recordCompletion(
        levelId: first.id,
        revision: first.revision,
        moves: first.minimumMoves,
        minimumMoves: first.minimumMoves,
      );
      final expected = RunScore.of(
        minimumMoves: first.minimumMoves,
        stars: 3,
      ).total;
      final repo = await PlayerRepository.load(levels, progress);
      expect(repo.xp, expected);
      await repo.award(10);
      final again = await PlayerRepository.load(levels, progress);
      expect(again.xp, expected + 10);
    });

    test('a failed save keeps the session value and retry stores it', () async {
      final levels = _levels();
      final progress = await ProgressRepository.load();
      var allow = false;
      final repo = await PlayerRepository.load(
        levels,
        progress,
        writer: (_, _) async => allow,
      );
      final award = await repo.award(120);
      expect(award.saved, isFalse);
      expect(repo.saveFailed, isTrue);
      expect(repo.xp, 120);
      allow = true;
      expect(await repo.retrySave(), isTrue);
      expect(repo.saveFailed, isFalse);
    });

    for (final raw in ['not json', '{"version":99,"xp":5}', '{"version":1}']) {
      test('unreadable record is never overwritten: $raw', () async {
        SharedPreferences.setMockInitialValues({
          PlayerRepository.storageKey: raw,
        });
        final repo = await PlayerRepository.load(
          _levels(),
          await ProgressRepository.load(),
        );
        expect(repo.saveFailed, isTrue);
        await repo.award(50);
        expect(repo.xp, 50);
        expect(
          (await SharedPreferences.getInstance()).getString(
            PlayerRepository.storageKey,
          ),
          raw,
        );
      });
    }
  });
}
