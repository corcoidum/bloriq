import 'dart:convert';
import 'dart:io';

import 'package:bloriq/dev/random_clear_seed.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/story/collection_repository.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Level> _levels() => [
  for (var world = 1; world <= Worlds.finalWorld; world++)
    ...Worlds.parseLevels(
      File('assets/levels/${world == 1 ? 'levels' : 'world$world'}.json')
          .readAsStringSync(),
      world,
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'all 175 campaign stages have consistent random clears and rewards',
    () async {
      expect(await seedRandomClearPreview(), isTrue);
      final progress = await ProgressRepository.load();
      final progression = await ProgressionRepository.load();
      final collection = await CollectionRepository.load(
        await StoryCatalog.load(),
      );
      final ratings = <int>{};
      for (final level in _levels()) {
        final record = progress.forLevel(level.id, revision: level.revision)!;
        ratings.add(record.bestStars);
        expect(
          record.bestStars,
          starRating(moves: record.bestMoves, minimumMoves: level.minimumMoves),
        );
        expect(record.completionCount, 1);
      }
      expect(progress.completedCampaignLevelIds, hasLength(175));
      expect(ratings, {1, 2, 3});
      expect(progression.completedChapters, hasLength(35));
      expect(progression.backfilled, isTrue);
      expect(progression.xp, greaterThan(0));
      expect(progression.stardust, greaterThan(0));
      expect(collection.owned, hasLength(25));
      expect(collection.pendingIds, isEmpty);
      expect(collection.backfillPending, isFalse);
      for (var world = 1; world <= Worlds.finalWorld; world++) {
        expect(Worlds.isUnlocked(world, progression.completedChapters), isTrue);
      }
      expect(progress.saveFailed, isFalse);
      expect(progression.saveFailed, isFalse);
      expect(collection.saveFailed, isFalse);
    },
  );

  test('reopening the preview preserves subsequent gameplay records', () async {
    await seedRandomClearPreview();
    final level = _levels().first;
    final progress = await ProgressRepository.load();
    await progress.recordCompletion(
      levelId: level.id,
      revision: level.revision,
      moves: level.minimumMoves,
      minimumMoves: level.minimumMoves,
    );
    final preferences = await SharedPreferences.getInstance();
    final afterPlaying = preferences.getString(ProgressRepository.storageKey);
    expect(await seedRandomClearPreview(seed: 42), isFalse);
    expect(preferences.getString(ProgressRepository.storageKey), afterPlaying);
    expect(
      progress.forLevel(level.id, revision: level.revision)!.completionCount,
      2,
    );
  });

  test(
    'existing and legacy saves are preserved without injecting test data',
    () async {
      for (final key in [
        ProgressRepository.storageKey,
        ProgressRepository.course2StorageKey,
        ProgressRepository.legacyStorageKey,
        ProgressionRepository.storageKey,
        CollectionRepository.storageKey,
      ]) {
        SharedPreferences.setMockInitialValues({key: 'existing-save'});
        expect(await seedRandomClearPreview(), isFalse);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.getKeys(), {key});
        expect(preferences.getString(key), 'existing-save');
      }
    },
  );

  test('the same build seed produces the same records', () async {
    await seedRandomClearPreview(seed: 1234);
    final first = (await SharedPreferences.getInstance()).getString(
      ProgressRepository.storageKey,
    );
    SharedPreferences.setMockInitialValues({});
    await seedRandomClearPreview(seed: 1234);
    final second = (await SharedPreferences.getInstance()).getString(
      ProgressRepository.storageKey,
    );
    expect(jsonDecode(second!), jsonDecode(first!));
  });
}
