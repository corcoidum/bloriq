import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import '../progress/progress_repository.dart';

String localDateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
DateTime civilDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

class DailyChallenge {
  const DailyChallenge(this.date, this.poolVersion, this.level);
  final String date;
  final int poolVersion;
  final Level level;
}

/// 날짜별 배치 스냅샷을 보관하므로 풀 업데이트도 이미 배정한 퍼즐을 바꾸지 않는다.
class DailyRepository {
  DailyRepository._(
    this._preferences,
    this.pool,
    this.poolVersion,
    this.clock,
    this._days,
    this._writable,
  );
  static const storageKey = 'bloriq.daily.v1';
  final SharedPreferences? _preferences;
  final List<Map<String, dynamic>> pool;
  final int poolVersion;
  final DateTime Function() clock;
  final Map<String, Map<String, dynamic>> _days;
  final bool _writable;
  bool saveFailed = false;
  Future<void> _queue = Future.value();

  static Future<DailyRepository> load({
    DateTime Function()? clock,
    List<Map<String, dynamic>>? pool,
    int poolVersion = 1,
  }) async {
    final source =
        pool ??
        (jsonDecode(
          await rootBundle.loadString('assets/levels/daily_pool_v1.json'),
        ) as List).cast<Map<String, dynamic>>();
    if (source.isEmpty) throw const FormatException('Empty daily pool');
    for (final raw in source) {
      Level.fromJson(raw);
    }
    SharedPreferences? preferences;
    final days = <String, Map<String, dynamic>>{};
    var writable = true;
    try {
      preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(storageKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is Map && data['version'] == 1 && data['days'] is Map) {
          for (final entry in (data['days'] as Map).entries) {
            try {
              final day = Map<String, dynamic>.from(entry.value as Map);
              final date = DateTime.parse(entry.key as String);
              if (localDateKey(date) != entry.key ||
                  day['poolVersion'] is! int) {
                continue;
              }
              Level.fromJson(Map<String, dynamic>.from(day['level'] as Map));
              if (day['played'] is! bool ||
                  day['completions'] is! int ||
                  (day['completions'] as int) < 0) {
                continue;
              }
              if (day['bestMoves'] != null &&
                  (day['bestMoves'] is! int || (day['bestMoves'] as int) < 1)) {
                continue;
              }
              days[entry.key as String] = day;
            } catch (_) {
              /* 손상된 날짜 하나만 제외한다. */
            }
          }
        } else if (data is Map && data['version'] != 1) {
          writable = false;
        }
      }
    } catch (_) {
      writable = false;
    }
    return DailyRepository._(
      preferences,
      List.unmodifiable(source),
      poolVersion,
      clock ?? DateTime.now,
      days,
      writable,
    );
  }

  DailyChallenge get today => forDate(clock());
  DailyChallenge forDate(DateTime date) {
    final key = localDateKey(date);
    if (!_days.containsKey(key)) {
      final ordinal = civilDay(date).difference(DateTime.utc(1970)).inDays;
      final raw = jsonDecode(
        jsonEncode(pool[ordinal % pool.length]),
      ) as Map<String, dynamic>;
      _days[key] = {
        'poolVersion': poolVersion,
        'level': raw,
        'played': false,
        'completions': 0,
        'bestMoves': null,
      };
      unawaited(_save());
    }
    final data = _days[key]!;
    return DailyChallenge(
      key,
      data['poolVersion'] as int,
      Level.fromJson(Map<String, dynamic>.from(data['level'] as Map)),
    );
  }

  bool participated(String date) => _days[date]?['played'] == true;
  bool completed(String date) => (_days[date]?['completions'] as int? ?? 0) > 0;
  int? bestMoves(String date) => _days[date]?['bestMoves'] as int?;
  List<DateTime> get recentDays => List.generate(
    7,
    (i) => civilDay(clock()).subtract(Duration(days: 6 - i)),
  );
  int get streak {
    var day = civilDay(clock());
    if (!participated(localDateKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var count = 0;
    while (participated(localDateKey(day))) {
      count++;
      day = day.subtract(const Duration(days: 1));
    }
    return count;
  }

  Future<void> markPlayed(DailyChallenge challenge) async {
    final day = _days[challenge.date];
    if (day == null || day['played'] == true) return;
    day['played'] = true;
    await _save();
  }

  Future<CompletionResult> recordCompletion(
    DailyChallenge challenge,
    int moves,
  ) async {
    final day = _days[challenge.date];
    if (day == null) throw StateError('Daily assignment missing');
    final stars = starRating(
      moves: moves,
      minimumMoves: challenge.level.minimumMoves,
    );
    final previous = bestMoves(challenge.date);
    day['played'] = true;
    day['completions'] = (day['completions'] as int) + 1;
    day['bestMoves'] = previous == null || moves < previous ? moves : previous;
    final best = day['bestMoves'] as int;
    await _save();
    return CompletionResult(
      progress: LevelProgress(
        levelId: challenge.level.id,
        revision: challenge.level.revision,
        bestMoves: best,
        bestStars: starRating(
          moves: best,
          minimumMoves: challenge.level.minimumMoves,
        ),
        completionCount: day['completions'] as int,
      ),
      stars: stars,
      isNewBest: previous == null || moves < previous,
      saved: !saveFailed,
    );
  }

  Future<void> _save() {
    final snapshot = jsonEncode({'version': 1, 'days': _days});
    _queue = _queue.then((_) async {
      try {
        saveFailed =
            !_writable ||
            !(await _preferences?.setString(storageKey, snapshot) ?? false);
      } catch (_) {
        saveFailed = true;
      }
    });
    return _queue;
  }

  Future<void> flush() => _queue;
}
