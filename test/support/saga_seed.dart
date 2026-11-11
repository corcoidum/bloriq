import 'dart:convert';
import 'dart:io';

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/progress/last_played.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'world_release.dart';

List<Level> _worldOne() =>
    (jsonDecode(File('assets/levels/levels.json').readAsStringSync()) as List)
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .toList();

/// 세계 1부터 [throughWorld]까지 모두 깨고(0이면 새 플레이어), 다음 세계에서 [extra]판을 더 깬 기록.
/// [stars]에 적은 판만 별 수를 낮춘다. [lastPlayed]는 마지막으로 연 판이다.
void seedSaga({
  required int throughWorld,
  int extra = 0,
  Map<int, int> stars = const {},
  int? lastPlayed,
}) {
  final cleared = [
    if (throughWorld >= 1) ..._worldOne(),
    for (var world = 2; world <= throughWorld; world++) ...releaseLevels(world),
    if (extra > 0) ...releaseLevels(throughWorld + 1).take(extra),
  ];
  SharedPreferences.setMockInitialValues({
    'bloriq.onboarding.v1': 'skipped',
    GameAudio.musicKey: false,
    GameAudio.effectsKey: false,
    if (lastPlayed != null)
      LastPlayedRepository.storageKey: jsonEncode({
        'version': LastPlayedRepository.schemaVersion,
        'levelId': lastPlayed,
      }),
    ProgressionRepository.storageKey: jsonEncode({
      'version': 1,
      'backfilled': true,
      'completedChapters': [
        for (
          var chapter = 1;
          chapter <= throughWorld * 5 + extra ~/ 5;
          chapter++
        )
          chapter,
      ],
    }),
    ProgressRepository.storageKey: jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': [
        for (final level in cleared)
          {
            'levelId': level.id,
            'revision': level.revision,
            'bestMoves': level.minimumMoves,
            'bestStars': stars[level.id] ?? 3,
            'completionCount': 1,
          },
      ],
    }),
  });
}
