import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// 모든 스테이지에 같은 이동 수 기준을 적용한다.
int starRating({required int moves, required int minimumMoves}) {
  if (minimumMoves < 1 || moves < minimumMoves) {
    throw ArgumentError('Moves must be at least the positive minimum');
  }
  if (moves == minimumMoves) return 3;
  final allowance = math.max(2, (minimumMoves + 3) ~/ 4);
  return moves <= minimumMoves + allowance ? 2 : 1;
}

class LevelProgress {
  const LevelProgress({
    required this.levelId,
    required this.bestMoves,
    required this.bestStars,
    required this.completionCount,
  });

  final int levelId;
  final int bestMoves;
  final int bestStars;
  final int completionCount;

  Map<String, Object> toJson() => {
    'levelId': levelId,
    'bestMoves': bestMoves,
    'bestStars': bestStars,
    'completionCount': completionCount,
  };

  static LevelProgress? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['levelId'];
    final moves = value['bestMoves'];
    final stars = value['bestStars'];
    final count = value['completionCount'];
    if (id is! int ||
        id < 1 ||
        moves is! int ||
        moves < 1 ||
        stars is! int ||
        stars < 1 ||
        stars > 3 ||
        count is! int ||
        count < 1) {
      return null;
    }
    return LevelProgress(
      levelId: id,
      bestMoves: moves,
      bestStars: stars,
      completionCount: count,
    );
  }
}

class CompletionResult {
  const CompletionResult({
    required this.progress,
    required this.stars,
    required this.isNewBest,
    required this.saved,
    this.isFirstClear = false,
  });

  final LevelProgress progress;
  final int stars;
  final bool isNewBest;

  /// false이면 이번 세션의 기록은 남지만 영구 저장은 실패했다.
  final bool saved;
  final bool isFirstClear;
}

/// 서버 없이 버전이 있는 JSON으로 스테이지별 기록을 보존한다.
class ProgressRepository {
  ProgressRepository._(
    this._preferences,
    this._levels,
    this._writable, {
    Set<int>? restoredStages,
    this.companionId,
    this.introSeen = false,
  }) : _restoredStages = restoredStages ?? {};

  // 같은 단계 번호라도 리디자인된 퍼즐은 이전 코스의 기록과 섞지 않는다.
  // 기존 키는 삭제하지 않아 과거 기록을 보존한다.
  static const legacyStorageKey = 'bloriq.progress.v1';
  static const storageKey = 'bloriq.progress.course2.v1';
  static const schemaVersion = 1;
  final SharedPreferences? _preferences;
  final Map<int, LevelProgress> _levels;
  final bool _writable;
  final Set<int> _restoredStages;
  String? companionId;
  bool introSeen;

  /// 완료 레코드가 보상의 원장이다. 연출 종료나 별도 보상 쓰기에 의존하지 않는다.
  Set<int> get rewardStages => {
    ..._restoredStages,
    ..._levels.keys,
  }.where((id) => id >= 1 && id <= 25).toSet();
  Set<String> get spiritIds => rewardStages
      .map((id) => 'spirit_${id.toString().padLeft(2, '0')}')
      .toSet();
  Set<String> get memoryIds => rewardStages
      .map((id) => 'memory_${id.toString().padLeft(2, '0')}')
      .toSet();

  Future<void> _writeQueue = Future.value();

  static Future<ProgressRepository> load() async {
    SharedPreferences? preferences;
    final restoredStages = <int>{};
    try {
      preferences = await SharedPreferences.getInstance();
      // 이전 코스의 기록은 현재 퍼즐 최고 기록과 섞지 않고 수집 보상만 복구한다.
      try {
        final legacy = jsonDecode(
          preferences.getString(legacyStorageKey) ?? '{}',
        );
        if (legacy is Map &&
            legacy['version'] == 1 &&
            legacy['levels'] is List) {
          for (final value in legacy['levels'] as List) {
            final entry = LevelProgress.fromJson(value);
            if (entry != null) restoredStages.add(entry.levelId);
          }
        }
      } catch (_) {
        /* 과거 코스의 손상은 현재 코스 시작을 막지 않는다. */
      }
      final raw = preferences.getString(storageKey);
      if (raw == null) {
        return ProgressRepository._(
          preferences,
          {},
          true,
          restoredStages: restoredStages,
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] is! int) {
        throw const FormatException('Invalid progress envelope');
      }
      // 알 수 없는 새 버전은 읽거나 덮어쓰지 않아 데이터 손실을 막는다.
      if (decoded['version'] != schemaVersion) {
        return ProgressRepository._(preferences, {}, false);
      }
      if (decoded['collectionVersion'] != null &&
          decoded['collectionVersion'] != 1) {
        return ProgressRepository._(preferences, {}, false);
      }
      final values = decoded['levels'];
      if (values is! List) {
        throw const FormatException('Invalid progress records');
      }
      final levels = <int, LevelProgress>{};
      for (final value in values) {
        final entry = LevelProgress.fromJson(value);
        if (entry != null) levels[entry.levelId] = entry;
      }
      final selected = decoded['companionId'];
      final repository = ProgressRepository._(
        preferences,
        levels,
        true,
        restoredStages: restoredStages,
        companionId: selected is String ? selected : null,
        introSeen: decoded['introSeen'] == true,
      );
      if (!repository.spiritIds.contains(repository.companionId)) {
        repository.companionId = null;
      }
      return repository;
    } catch (_) {
      // 손상 원본을 보존한 뒤 새 진행을 허용한다.
      if (preferences != null) {
        try {
          final raw = preferences.getString(storageKey);
          if (raw != null) {
            final backedUp = await preferences.setString(
              '$storageKey.corruptBackup',
              raw,
            );
            if (!backedUp) {
              return ProgressRepository._(
                preferences,
                {},
                false,
                restoredStages: restoredStages,
              );
            }
          }
        } catch (_) {
          return ProgressRepository._(preferences, {}, false);
        }
      }
      return ProgressRepository._(
        preferences,
        {},
        preferences != null,
        restoredStages: restoredStages,
      );
    }
  }

  LevelProgress? forLevel(int levelId) => _levels[levelId];

  Future<CompletionResult> recordCompletion({
    required int levelId,
    required int moves,
    required int minimumMoves,
  }) async {
    if (levelId < 1) throw ArgumentError.value(levelId, 'levelId');
    final stars = starRating(moves: moves, minimumMoves: minimumMoves);
    final previous = _levels[levelId];
    final isNewBest = previous == null || moves < previous.bestMoves;
    final progress = LevelProgress(
      levelId: levelId,
      bestMoves: isNewBest ? moves : previous.bestMoves,
      bestStars: previous == null ? stars : math.max(stars, previous.bestStars),
      completionCount: (previous?.completionCount ?? 0) + 1,
    );
    _levels[levelId] = progress;

    final saved = await _persist();
    return CompletionResult(
      progress: progress,
      stars: stars,
      isNewBest: isNewBest,
      saved: saved,
      isFirstClear: previous == null && !_restoredStages.contains(levelId),
    );
  }

  Future<bool> selectCompanion(String? id) async {
    if (id != null && !spiritIds.contains(id)) return false;
    companionId = id;
    return _persist();
  }

  Future<bool> markIntroSeen() async {
    introSeen = true;
    return _persist();
  }

  Future<bool> _persist() async {
    final snapshot = jsonEncode({
      'version': schemaVersion,
      'collectionVersion': 1,
      'levels': _levels.values.map((entry) => entry.toJson()).toList(),
      'spiritIds': spiritIds.toList()..sort(),
      'memoryIds': memoryIds.toList()..sort(),
      'companionId': companionId,
      'introSeen': introSeen,
    });
    var saved = false;
    final write = _writeQueue.then((_) async {
      if (!_writable || _preferences == null) return;
      try {
        saved = await _preferences.setString(storageKey, snapshot);
      } catch (_) {
        saved = false;
      }
    });
    _writeQueue = write;
    await write;
    return saved;
  }
}
