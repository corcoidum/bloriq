import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import '../progress/progress_repository.dart';
import '../progression/progression_repository.dart';
import '../world/saga.dart';
import '../world/world_catalog.dart';

/// 테스터 빌드 표시. `--dart-define=TESTER_ALL_CLEARED=true`로 켠다.
/// 켜면 처음 실행할 때 모든 판을 깬 기록으로 시작한다. 정식 빌드에는 영향이 없다.
const testerAllCleared = bool.fromEnvironment('TESTER_ALL_CLEARED');

/// 테스터 기록을 성장 시스템에 환산할 때 쓰는 값.
class TesterSeed {
  const TesterSeed({
    required this.records,
    required this.completedChapters,
    required this.goldenChapters,
  });
  final List<BackfillRecord> records;
  final Set<int> completedChapters, goldenChapters;
}

/// 저장된 진행 기록이 없을 때만 모든 세계의 판을 깬 기록을 써 넣는다.
/// 이미 기록이 있으면 건드리지 않고 null을 돌려준다.
///
/// 마지막 세계의 끝 세 판만 별 2개로 남겨, 홈의 "별 더 모으기"와
/// 황금이 아닌 별자리도 함께 확인할 수 있게 한다.
Future<TesterSeed?> seedTesterProgress() async {
  final preferences = await SharedPreferences.getInstance();
  if (preferences.containsKey(ProgressRepository.storageKey)) return null;

  // 큰 파일은 loadString이 별도 isolate에서 풀기 때문에 바이트로 읽어 직접 푼다
  // (GameSession이 세계 레벨을 읽는 방식과 같다).
  Future<String> read(String asset) async {
    final bytes = await rootBundle.load(asset);
    return utf8.decode(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  final levels = [
    for (final item
        in jsonDecode(await read('assets/levels/levels.json')) as List)
      Level.fromJson(item as Map<String, dynamic>),
  ];
  final saga = await Saga.load();
  for (final world in saga.worlds) {
    if (!world.playable || !world.expansion) continue;
    levels.addAll(
      Worlds.parseLevels(await read(world.levelsAsset!), world.number),
    );
  }
  final weak = {for (final level in levels.reversed.take(3)) level.id};
  int starsOf(Level level) => weak.contains(level.id) ? 2 : 3;

  await preferences.setString(
    ProgressRepository.storageKey,
    jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': [
        for (final level in levels)
          {
            'levelId': level.id,
            'revision': level.revision,
            // 최소 수보다 한 수 많으면 별 2개다.
            'bestMoves': level.minimumMoves + (starsOf(level) == 3 ? 0 : 1),
            'bestStars': starsOf(level),
            'completionCount': 1,
          },
      ],
    }),
  );

  final chapters = <int>{};
  final golden = <int>{};
  for (final level in levels) {
    final chapter = Worlds.globalChapter(
      Worlds.worldOf(level.id),
      Worlds.chapterOf(level.id),
    );
    chapters.add(chapter);
  }
  for (final chapter in chapters) {
    final stages = levels.where(
      (level) =>
          Worlds.globalChapter(
            Worlds.worldOf(level.id),
            Worlds.chapterOf(level.id),
          ) ==
          chapter,
    );
    if (stages.every((level) => starsOf(level) == 3)) golden.add(chapter);
  }
  return TesterSeed(
    records: [
      for (final level in levels)
        (levelKey: '${level.id}:${level.revision}', bestStars: starsOf(level)),
    ],
    completedChapters: chapters,
    goldenChapters: golden,
  );
}
