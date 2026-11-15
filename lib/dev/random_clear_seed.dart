import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import '../progress/progress_repository.dart';
import '../progression/progression_repository.dart';
import '../story/collection_repository.dart';
import '../story/story_catalog.dart';
import '../tutorial/echo_tutorial.dart';
import '../world/world_catalog.dart';

/// 일반 main.dart에서는 호출하지 않는다. 테스트 앱의 최초 실행에만 기록을 만든다.
const randomClearPreviewKey = 'bloriq.preview.random-clear.v1';

Future<bool> seedRandomClearPreview({int seed = 20261115}) async {
  final preferences = await SharedPreferences.getInstance();
  final state = preferences.getString(randomClearPreviewKey);
  if (state == 'complete') return false;

  // 다른 진입점에서 생긴 실제 진행 기록은 덮어쓰지 않는다.
  // 준비 중 저장이 끊긴 경우에만 동일한 시드로 초기화를 이어 간다.
  if (state != 'pending' &&
      [
        ProgressRepository.storageKey,
        ProgressRepository.course2StorageKey,
        ProgressRepository.legacyStorageKey,
        ProgressionRepository.storageKey,
        CollectionRepository.storageKey,
      ].any(preferences.containsKey)) {
    return false;
  }

  final levels = <Level>[];
  for (var world = 1; world <= Worlds.finalWorld; world++) {
    final asset = world == 1 ? 'levels' : 'world$world';
    levels.addAll(
      Worlds.parseLevels(
        await rootBundle.loadString('assets/levels/$asset.json'),
        world,
      ),
    );
  }

  final random = math.Random(seed);
  final records = <LevelProgress>[];
  for (final level in levels) {
    final stars = 1 + random.nextInt(3);
    final allowance = math.max(2, (level.minimumMoves + 3) ~/ 4);
    // 별 수와 최소 이동 수가 서로 모순되지 않는 가짜 클리어 기록.
    final moves = switch (stars) {
      3 => level.minimumMoves,
      2 => level.minimumMoves + 1 + random.nextInt(allowance),
      _ => level.minimumMoves + allowance + 1 + random.nextInt(6),
    };
    records.add(
      LevelProgress(
        levelId: level.id,
        revision: level.revision,
        bestMoves: moves,
        bestStars: stars,
        completionCount: 1,
      ),
    );
  }

  final starsById = {
    for (final record in records) record.levelId: record.bestStars,
  };
  final completedChapters = <int>{};
  final goldenChapters = <int>{};
  for (var world = 1; world <= Worlds.finalWorld; world++) {
    for (var chapter = 1; chapter <= Worlds.chapterCount; chapter++) {
      final global = Worlds.globalChapter(world, chapter);
      completedChapters.add(global);
      if (levels
          .where(
            (level) =>
                level.world == world && Worlds.chapterOf(level.id) == chapter,
          )
          .every((level) => starsById[level.id] == 3)) {
        goldenChapters.add(global);
      }
    }
  }

  await _requireSaved(preferences.setString(randomClearPreviewKey, 'pending'));
  await _requireSaved(
    preferences.setString(
      ProgressRepository.storageKey,
      jsonEncode({
        'version': ProgressRepository.schemaVersion,
        'levels': records.map((record) => record.toJson()).toList(),
      }),
    ),
  );

  // 기존 보상 환산 API로 경험치·별가루·권능을 맞춘다. 저장 형식은 그대로 쓴다.
  final progression = await ProgressionRepository.load();
  await progression.backfill(
    records: [
      for (final record in records)
        (
          levelKey: '${record.levelId}:${record.revision}',
          bestStars: record.bestStars,
        ),
    ],
    completedChapters: completedChapters,
    goldenChapters: goldenChapters,
  );
  if (progression.saveFailed) {
    throw StateError('Could not save preview rewards');
  }

  final collection = await CollectionRepository.load(await StoryCatalog.load());
  await collection.reconcile(
    records.map((record) => record.levelId).toSet(),
    backfill: true,
  );
  await _requireSaved(collection.acknowledgeBackfill());
  await _requireSaved(preferences.setString(Onboarding.storageKey, 'skipped'));
  await _requireSaved(preferences.setString(randomClearPreviewKey, 'complete'));
  return true;
}

Future<void> _requireSaved(Future<bool> write) async {
  if (!await write) throw StateError('Could not save preview progress');
}
