import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'trial_catalog.dart';

/// 고정 시련의 최고 이동 수를 캠페인 기록과 별도로 보존한다.
class TrialRepository {
  TrialRepository._(this._bestMoves, this._write);

  factory TrialRepository.memory() => TrialRepository._({}, (_) async => true);

  static const storageKey = 'bloriq.trials.v1';
  final Future<bool> Function(String snapshot)? _write;
  Map<int, int> _bestMoves;
  Future<void> _queue = Future.value();

  static Future<TrialRepository> load({
    Future<bool> Function(String key, String snapshot)? writer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      final records = <int, int>{};
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] != 1 || data['bestMoves'] is! Map) {
          throw const FormatException('Invalid trial progress');
        }
        for (final entry in (data['bestMoves'] as Map).entries) {
          final id = int.tryParse(entry.key as String);
          final moves = entry.value;
          if (id == null || id < 1 || moves is! int || moves < 1) {
            throw const FormatException('Invalid trial record');
          }
          records[id] = moves;
        }
      }
      return TrialRepository._(records, (snapshot) async {
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
      // 읽을 수 없는 버전이나 손상된 원문을 덮어쓰지 않는다.
      return TrialRepository._({}, null);
    }
  }

  bool get mayHaveCompletedWorld =>
      _bestMoves.length >= TrialCatalog.stagesPerWorld;

  int? bestMoves(TrialStage stage) {
    final moves = _bestMoves[stage.sourceId];
    return moves != null && stage.acceptsClear(moves) ? moves : null;
  }

  int clearedCount(Iterable<TrialStage> stages) =>
      stages.where((stage) => bestMoves(stage) != null).length;

  Future<bool> recordClear(TrialStage stage, int moves) {
    if (!stage.acceptsClear(moves) || _write == null) {
      return Future.value(false);
    }
    final task = _queue.then((_) async {
      final previous = bestMoves(stage);
      if (previous != null && previous <= moves) return true;
      final next = {..._bestMoves, stage.sourceId: moves};
      try {
        if (!await _write(
          jsonEncode({
            'version': 1,
            'bestMoves': {
              for (final entry in next.entries) '${entry.key}': entry.value,
            },
          }),
        )) {
          return false;
        }
        _bestMoves = next;
        return true;
      } on Object {
        return false;
      }
    });
    _queue = task.then<void>((_) {});
    return task;
  }

  Future<void> flush() => _queue;
}
