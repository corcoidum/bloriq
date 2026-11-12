import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import '../progression/progression_rules.dart';
import 'weekly_pool.dart';

typedef WeeklyStage = ({String week, int index, Level level});

class WeeklyChallenge {
  WeeklyChallenge._(this.week, this._boards)
    : levels = List.unmodifiable(_boards.map(Level.fromJson));

  final String week;
  final List<Level> levels;
  final List<Map<String, dynamic>> _boards;

  int get rotation => weeklyOrdinal(week) % weeklyRewards.length;
  WeeklyStage stage(int index) =>
      (week: week, index: index, level: levels[index]);
}

class _WeekRecord {
  const _WeekRecord(this.challenge, this.bestMoves);

  final WeeklyChallenge challenge;
  final List<int?> bestMoves;

  int get cleared => bestMoves.whereType<int>().length;

  Map<String, Object> toJson() => {
    'boards': challenge._boards,
    'bestMoves': bestMoves,
  };

  static _WeekRecord fromJson(String week, Map data) {
    final boards = (data['boards'] as List).cast<Map<String, dynamic>>();
    final best = (data['bestMoves'] as List).cast<int?>();
    if (weeklyKey(DateTime.parse(week)) != week ||
        boards.length != WeeklyPool.stageCount ||
        best.length != boards.length) {
      throw const FormatException('Invalid weekly record');
    }
    final challenge = WeeklyChallenge._(week, boards);
    if (challenge.levels.map((level) => level.id).toSet().length !=
            boards.length ||
        challenge.levels.any((level) => level.minimumMoves < 1) ||
        best.indexed.any(
          (entry) =>
              entry.$2 != null &&
              entry.$2! < challenge.levels[entry.$1].minimumMoves,
        )) {
      throw const FormatException('Invalid weekly board progress');
    }
    return _WeekRecord(challenge, best);
  }
}

/// 월요일별 보드 배치와 클리어를 함께 저장한다.
class WeeklyRepository {
  WeeklyRepository._(this.clock, this._weeks, this._write);

  factory WeeklyRepository.memory({DateTime Function()? clock}) =>
      WeeklyRepository._(clock ?? DateTime.now, {}, (_) async => true);

  static const storageKey = 'bloriq.weekly.v1';
  final DateTime Function() clock;
  final Future<bool> Function(String snapshot)? _write;
  Map<String, _WeekRecord> _weeks;
  Future<void> _queue = Future.value();

  static Future<WeeklyRepository> load({
    DateTime Function()? clock,
    Future<bool> Function(String key, String snapshot)? writer,
  }) async {
    final now = clock ?? DateTime.now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = <String, _WeekRecord>{};
      if (prefs.getString(storageKey) case final raw?) {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] != 1 || data['weeks'] is! Map) {
          throw const FormatException('Invalid weekly progress');
        }
        for (final entry in (data['weeks'] as Map).entries) {
          records[entry.key as String] = _WeekRecord.fromJson(
            entry.key as String,
            entry.value as Map,
          );
        }
      }
      return WeeklyRepository._(now, records, (snapshot) async {
        var saved = false;
        try {
          saved =
              await (writer?.call(storageKey, snapshot) ??
                  prefs.setString(storageKey, snapshot));
          return saved;
        } finally {
          if (!saved) await prefs.reload();
        }
      });
    } on Object {
      // 모르는 버전이나 손상된 원문은 덮어쓰지 않는다.
      return WeeklyRepository._(now, {}, null);
    }
  }

  String get currentKey => weeklyKey(clock());
  WeeklyChallenge? forWeek(String week) => _weeks[week]?.challenge;
  int cleared(String week) => _weeks[week]?.cleared ?? 0;
  int? bestMoves(WeeklyStage stage) =>
      _weeks[stage.week]?.bestMoves[stage.index];

  Set<int> get completedRotations => {
    for (final week in _weeks.values)
      if (week.cleared == WeeklyPool.stageCount) week.challenge.rotation,
  };

  Future<WeeklyChallenge?> assign(
    String week,
    WeeklyPool pool,
    Set<int> completedWorlds,
  ) {
    final task = _queue.then((_) async {
      if (forWeek(week) case final challenge?) return challenge;
      if (_write == null) return null;
      final boards = jsonDecode(jsonEncode(pool.pick(week, completedWorlds)));
      final record = _WeekRecord.fromJson(week, {
        'boards': boards,
        'bestMoves': List<int?>.filled(WeeklyPool.stageCount, null),
      });
      return await _persist(week, record) ? record.challenge : null;
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<bool> recordClear(WeeklyStage stage, int moves) {
    final task = _queue.then((_) async {
      final record = _weeks[stage.week];
      if (record == null ||
          stage.index < 0 ||
          stage.index >= record.challenge.levels.length ||
          !identical(record.challenge.levels[stage.index], stage.level) ||
          moves < stage.level.minimumMoves) {
        throw StateError('Invalid weekly stage clear');
      }
      final previous = record.bestMoves[stage.index];
      if (previous != null && previous <= moves) return true;
      final best = List<int?>.of(record.bestMoves)..[stage.index] = moves;
      return _persist(stage.week, _WeekRecord(record.challenge, best));
    });
    _queue = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  Future<bool> _persist(String week, _WeekRecord record) async {
    final write = _write;
    if (write == null) return false;
    final next = {..._weeks, week: record};
    try {
      final saved = await write(
        jsonEncode({
          'version': 1,
          'weeks': {
            for (final entry in next.entries) entry.key: entry.value.toJson(),
          },
        }),
      );
      if (saved) _weeks = next;
      return saved;
    } on Object {
      return false;
    }
  }

  Future<void> flush() => _queue;
}
