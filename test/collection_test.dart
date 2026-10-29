import 'dart:convert';

import 'package:bloriq/companions/season.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    '25 unique bilingual spirits, five guardians and complete memories',
    () async {
      final season = await Season.load();
      expect(season.spirits, hasLength(25));
      expect(season.spirits.where((s) => s.guardian).map((s) => s.stage), [
        5,
        10,
        15,
        20,
        25,
      ]);
      expect(season.spirits.map((s) => s.family).toSet(), hasLength(5));
      for (final s in season.spirits) {
        expect(
          s.data['memoryId'],
          'memory_${s.stage.toString().padLeft(2, '0')}',
        );
        for (final field in [
          'name',
          'appearance',
          'personality',
          'motion',
          'memory',
          'description',
          'quote',
          'title',
        ]) {
          expect(s.text(field, true), isNotEmpty);
          expect(s.text(field, false), isNotEmpty);
        }
      }
    },
  );
  test(
    'first five: deterministic rewards before presentation, repeat gives none',
    () async {
      final repo = await ProgressRepository.load();
      for (var id = 1; id <= 5; id++) {
        final first = await repo.recordCompletion(
          levelId: id,
          moves: 2,
          minimumMoves: 2,
        );
        expect(first.saved, isTrue);
        expect(first.isFirstClear, isTrue);
        final restarted = await ProgressRepository.load();
        expect(restarted.spiritIds, hasLength(id));
        expect(restarted.memoryIds, hasLength(id));
        final repeat = await repo.recordCompletion(
          levelId: id,
          moves: 3,
          minimumMoves: 2,
        );
        expect(repeat.isFirstClear, isFalse);
        expect(repo.spiritIds, hasLength(id));
      }
    },
  );
  test(
    'all 25 rewards persist with selection and intro in serialized writes',
    () async {
      final repo = await ProgressRepository.load();
      await Future.wait([
        for (var id = 1; id <= 25; id++)
          repo.recordCompletion(levelId: id, moves: 2, minimumMoves: 2),
      ]);
      await Future.wait([
        repo.selectCompanion('spirit_25'),
        repo.markIntroSeen(),
      ]);
      final again = await ProgressRepository.load();
      expect(again.spiritIds, hasLength(25));
      expect(again.memoryIds, hasLength(25));
      expect(again.companionId, 'spirit_25');
      expect(again.introSeen, isTrue);
      expect(await again.selectCompanion('spirit_99'), isFalse);
      expect(again.companionId, 'spirit_25');
    },
  );
  for (final legacy in [false, true]) {
    test(
      'migrates ${legacy ? 'legacy' : 'current'} completions without modifying original records',
      () async {
        final raw = jsonEncode({
          'version': 1,
          'levels': [
            {
              'levelId': 3,
              'bestMoves': 4,
              'bestStars': 2,
              'completionCount': 7,
            },
          ],
        });
        final key = legacy
            ? ProgressRepository.legacyStorageKey
            : ProgressRepository.storageKey;
        SharedPreferences.setMockInitialValues({key: raw});
        final repo = await ProgressRepository.load();
        expect(repo.spiritIds, {'spirit_03'});
        expect(repo.memoryIds, {'memory_03'});
        expect((await SharedPreferences.getInstance()).getString(key), raw);
        expect(repo.forLevel(3)?.completionCount, legacy ? null : 7);
        expect(
          (await repo.recordCompletion(
            levelId: 3,
            moves: 2,
            minimumMoves: 2,
          )).isFirstClear,
          isFalse,
        );
      },
    );
  }
  test(
    'unknown collection version remains untouched and reports save failure',
    () async {
      final raw = jsonEncode({
        'version': 1,
        'collectionVersion': 99,
        'levels': [],
      });
      SharedPreferences.setMockInitialValues({
        ProgressRepository.storageKey: raw,
      });
      final repo = await ProgressRepository.load();
      expect(await repo.markIntroSeen(), isFalse);
      expect(
        (await SharedPreferences.getInstance()).getString(
          ProgressRepository.storageKey,
        ),
        raw,
      );
    },
  );
  test(
    'corrupt source is retained and forged rewards cannot unlock companions',
    () async {
      SharedPreferences.setMockInitialValues({
        ProgressRepository.storageKey: '{broken',
      });
      var repo = await ProgressRepository.load();
      expect(
        (await SharedPreferences.getInstance()).getString(
          '${ProgressRepository.storageKey}.corruptBackup',
        ),
        '{broken',
      );
      await repo.recordCompletion(levelId: 1, moves: 2, minimumMoves: 2);
      SharedPreferences.setMockInitialValues({
        ProgressRepository.storageKey: jsonEncode({
          'version': 1,
          'levels': [],
          'spiritIds': ['spirit_25'],
          'companionId': 'spirit_25',
        }),
      });
      repo = await ProgressRepository.load();
      expect(repo.spiritIds, isEmpty);
      expect(repo.companionId, isNull);
    },
  );
}
