import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import 'stage_challenges.dart';

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
    this.revision = 1,
    required this.bestMoves,
    required this.bestStars,
    required this.completionCount,
    this.stageChallenges = const {},
  });

  final int levelId;
  final int revision;
  final int bestMoves;
  final int bestStars;
  final int completionCount;
  final Set<StageChallenge> stageChallenges;

  LevelProgress withStageChallenges(Set<StageChallenge> earned) =>
      LevelProgress(
        levelId: levelId,
        revision: revision,
        bestMoves: bestMoves,
        bestStars: bestStars,
        completionCount: completionCount,
        stageChallenges: Set.unmodifiable(earned),
      );

  Map<String, Object> toJson() => {
    'levelId': levelId,
    'revision': revision,
    'bestMoves': bestMoves,
    'bestStars': bestStars,
    'completionCount': completionCount,
    if (stageChallenges.isNotEmpty)
      'stageChallenges': [
        for (final challenge in StageChallenge.values)
          if (stageChallenges.contains(challenge)) challenge.name,
      ],
  };

  static LevelProgress? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['levelId'];
    final revision = value['revision'] ?? 1;
    final moves = value['bestMoves'];
    final stars = value['bestStars'];
    final count = value['completionCount'];
    final challenges = value['stageChallenges'];
    if (revision is! int ||
        revision < 1 ||
        id is! int ||
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
      revision: revision,
      bestMoves: moves,
      bestStars: stars,
      completionCount: count,
      stageChallenges: Set.unmodifiable({
        if (challenges is List)
          for (final challenge in StageChallenge.values)
            if (challenges.contains(challenge.name)) challenge,
      }),
    );
  }
}

class CompletionResult {
  const CompletionResult({
    required this.progress,
    required this.stars,
    required this.isNewBest,
    required this.saved,
    this.newStageChallenges = const {},
  });

  final LevelProgress progress;
  final int stars;
  final bool isNewBest;
  final Set<StageChallenge> newStageChallenges;

  /// false이면 이번 세션의 기록은 남지만 영구 저장은 실패했다.
  final bool saved;
}

/// 서버 없이 버전이 있는 JSON으로 스테이지별 기록을 보존한다.
class ProgressRepository {
  ProgressRepository._(
    this._preferences,
    this._levels,
    this._writable, {
    this.writer,
  }) {
    saveFailed = !_writable;
    _persistedLevels = Map.of(_levels);
  }

  // 같은 단계 번호라도 리디자인된 퍼즐은 이전 코스의 기록과 섞지 않는다.
  // 기존 키는 삭제하지 않아 과거 기록을 보존한다.
  static const legacyStorageKey = 'bloriq.progress.v1';
  static const course2StorageKey = 'bloriq.progress.course2.v1';
  static const storageKey = 'bloriq.progress.v2';
  static const schemaVersion = 2;
  final SharedPreferences? _preferences;
  final Future<bool> Function(String, String)? writer;
  final Map<String, LevelProgress> _levels;
  late Map<String, LevelProgress> _persistedLevels;
  final bool _writable;
  Future<void> _writeQueue = Future.value();

  static Future<ProgressRepository> load({
    Future<bool> Function(String, String)? writer,
  }) async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
      final rawV2 = preferences.getString(storageKey);
      final raw = rawV2 ?? preferences.getString(course2StorageKey);
      if (raw == null) {
        return ProgressRepository._(preferences, {}, true, writer: writer);
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] is! int) {
        return ProgressRepository._(preferences, {}, false, writer: writer);
      }
      // 알 수 없는 새 버전은 읽거나 덮어쓰지 않아 데이터 손실을 막는다.
      if (decoded['version'] != (rawV2 == null ? 1 : schemaVersion)) {
        return ProgressRepository._(preferences, {}, false, writer: writer);
      }
      final values = decoded['levels'];
      if (values is! List) {
        return ProgressRepository._(preferences, {}, false, writer: writer);
      }
      final levels = <String, LevelProgress>{};
      var valid = true;
      for (final value in values) {
        final entry = LevelProgress.fromJson(value);
        if (entry != null) {
          levels['${entry.levelId}:${entry.revision}'] = entry;
        } else {
          valid = false;
        }
      }
      final repository = ProgressRepository._(
        preferences,
        levels,
        valid,
        writer: writer,
      );
      if (rawV2 == null) await repository._persist();
      return repository;
    } catch (_) {
      // 손상된 JSON 또는 플랫폼 저장소 오류가 게임 시작을 막지 않는다.
      return ProgressRepository._(preferences, {}, false, writer: writer);
    }
  }

  bool get hasAnyProgress => _levels.isNotEmpty;

  /// 수집 권리는 성공적으로 읽거나 쓴 스냅샷만 근거로 삼는다.
  Set<int> get completedCampaignLevelIds =>
      Set.unmodifiable(_persistedLevels.values.map((record) => record.levelId));
  Future<bool> retrySave() => _persist();
  Future<void> flush() => _writeQueue;
  bool get hasHistoricalStorage =>
      _preferences?.containsKey(legacyStorageKey) == true ||
      _preferences?.containsKey(course2StorageKey) == true ||
      _preferences?.containsKey(storageKey) == true;
  bool saveFailed = false;
  LevelProgress? forLevel(int levelId, {int revision = 1}) =>
      _levels['$levelId:$revision'];

  /// 업적은 지금 플레이할 수 있는 판의 저장된 기록만 센다.
  int starflowerCount(Iterable<Level> levels) => levels.fold(0, (sum, level) {
    final record = _persistedLevels['${level.id}:${level.revision}'];
    return sum + (record?.stageChallenges.length ?? 0);
  });

  Future<void> backfillStageChallenges(
    Iterable<Level> levels, {
    required bool Function(String levelKey) hasBareHandedStar,
  }) async {
    if (!_writable) return;
    var changed = false;
    for (final level in levels) {
      if (level.world < 2) continue;
      final key = '${level.id}:${level.revision}';
      final record = _levels[key];
      if (record == null ||
          record.stageChallenges.contains(StageChallenge.clear)) {
        continue;
      }
      final uses = stageChallengePowerUses(level);
      // 권능마다 한 번만 쓸 수 있다. 필수 권능만 있는 판의 클리어는 사용 횟수도 증명한다.
      final provenTechnique = uses == 0
          ? hasBareHandedStar(key)
          : level.requiredPowers.length == uses &&
                level.availablePowers.length == uses;
      _levels[key] = record.withStageChallenges({
        ...record.stageChallenges,
        StageChallenge.clear,
        if (record.bestMoves <= level.minimumMoves) StageChallenge.optimal,
        if (provenTechnique) StageChallenge.technique,
      });
      changed = true;
    }
    if (changed) await _persist();
  }

  Future<bool> _persist() async {
    final snapshotLevels = Map.of(_levels);
    final snapshot = jsonEncode({
      'version': schemaVersion,
      'levels': snapshotLevels.values.map((entry) => entry.toJson()).toList(),
    });
    var saved = false;
    final write = _writeQueue.then((_) async {
      if (!_writable || _preferences == null) return;
      try {
        saved =
            await (writer?.call(storageKey, snapshot) ??
                _preferences.setString(storageKey, snapshot));
        if (saved) _persistedLevels = snapshotLevels;
      } catch (_) {
        saved = false;
      }
    });
    _writeQueue = write;
    await write;
    saveFailed = !saved;
    return saved;
  }

  Future<CompletionResult> recordCompletion({
    required int levelId,
    int revision = 1,
    required int moves,
    required int minimumMoves,
    int maxStars = 3,
    Set<StageChallenge> stageChallenges = const {},
  }) async {
    if (revision < 1 || levelId < 1) {
      throw ArgumentError.value(levelId, 'levelId');
    }
    // 힌트나 풀이 따라 하기로 깬 판은 [maxStars]까지만 별을 남긴다.
    final stars = math.min(
      starRating(moves: moves, minimumMoves: minimumMoves),
      maxStars,
    );
    final previous = forLevel(levelId, revision: revision);
    final previousChallenges =
        previous?.stageChallenges ?? const <StageChallenge>{};
    final isNewBest = previous == null || moves < previous.bestMoves;
    final progress = LevelProgress(
      levelId: levelId,
      revision: revision,
      bestMoves: isNewBest ? moves : previous.bestMoves,
      bestStars: previous == null ? stars : math.max(stars, previous.bestStars),
      completionCount: (previous?.completionCount ?? 0) + 1,
      stageChallenges: Set.unmodifiable({
        ...previousChallenges,
        ...stageChallenges,
      }),
    );
    _levels['$levelId:$revision'] = progress;

    final saved = await _persist();
    return CompletionResult(
      progress: progress,
      stars: stars,
      isNewBest: isNewBest,
      saved: saved,
      newStageChallenges: Set.unmodifiable(
        stageChallenges.difference(previousChallenges),
      ),
    );
  }
}
