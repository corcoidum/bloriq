import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'endless_rules.dart';
import 'endless_run.dart';

/// 항해 한 번을 마친 결과. 기록 갱신과 처음 넘은 이정표를 담는다.
class VoyageSummary {
  const VoyageSummary({
    required this.score,
    required this.boards,
    required this.perfects,
    required this.newBestScore,
    required this.newBestDepth,
    required this.newWeekBest,
    required this.milestones,
    required this.stardust,
    required this.xp,
  });
  final int score, boards, perfects, stardust, xp;
  final bool newBestScore, newBestDepth, newWeekBest;
  final List<VoyageMilestone> milestones;
}

/// 별바다 항해 기록(최고 점수·깊이, 주간 최고, 이정표)과 진행 중인 항해.
/// 서버 없이 이 기기에만 남는다.
class EndlessRepository {
  EndlessRepository._(this._preferences, this.clock);

  static const storageKey = 'bloriq.endless.v1';

  final SharedPreferences? _preferences;
  final DateTime Function() clock;
  Future<void> _queue = Future.value();
  bool saveFailed = false;

  int bestScore = 0, bestDepth = 0, voyages = 0, totalBoards = 0;
  String? _weekKey;
  int _weekBest = 0;
  final Set<String> _milestones = {};
  VoyageRun? _run;
  String? _runClearWeek;

  static Future<EndlessRepository> load({DateTime Function()? clock}) async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
    } catch (_) {}
    final repository = EndlessRepository._(preferences, clock ?? DateTime.now);
    final raw = preferences?.getString(storageKey);
    if (raw != null) {
      try {
        repository._read(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 깨진 기록은 버리고 새로 시작한다. 항해 기록은 다시 쌓을 수 있다.
      }
    }
    return repository;
  }

  void _read(Map<String, dynamic> data) {
    if (data['version'] != 1) return;
    int count(String key) =>
        data[key] is int && (data[key] as int) >= 0 ? data[key] as int : 0;
    bestScore = count('bestScore');
    bestDepth = count('bestDepth');
    voyages = count('voyages');
    totalBoards = count('totalBoards');
    if (data['weekKey'] is String) {
      _weekKey = data['weekKey'] as String;
      _weekBest = count('weekBest');
    }
    for (final id in data['milestones'] as List? ?? const []) {
      if (id is String) _milestones.add(id);
    }
    if (data['run'] case final Map<String, dynamic> run) {
      try {
        _run = VoyageRun.fromJson(run);
        if (data['runClearWeek'] case final String week) _runClearWeek = week;
      } catch (_) {
        _run = null;
      }
    }
  }

  /// 이번 주(월요일 시작)를 가리키는 키.
  String get currentWeek {
    final now = clock();
    final day = DateTime.utc(now.year, now.month, now.day);
    final monday = day.subtract(Duration(days: day.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-'
        '${monday.month.toString().padLeft(2, '0')}-'
        '${monday.day.toString().padLeft(2, '0')}';
  }

  int get harborBestScore => math.max(bestScore, _run?.score ?? 0);
  int get harborBestDepth => math.max(bestDepth, _run?.cleared ?? 0);

  int _archivedWeekBest(String week) => _weekKey == week ? _weekBest : 0;

  int get weekBest {
    final week = currentWeek;
    return math.max(
      _archivedWeekBest(week),
      _runClearWeek == week ? _run?.score ?? 0 : 0,
    );
  }

  Set<String> get claimedMilestones => Set.unmodifiable(_milestones);

  /// 저장된, 아직 끝나지 않은 항해.
  VoyageRun? get savedRun => _run;

  /// 이동과 힌트는 마지막 클리어가 속한 주를 바꾸지 않는다.
  Future<void> saveRun(VoyageRun run, {bool clearedBoard = false}) {
    if (!identical(_run, run)) _runClearWeek = null;
    _run = run;
    if (clearedBoard) _runClearWeek = currentWeek;
    return _save();
  }

  /// 기존 기록과 새 항해를 한 스냅샷에 저장한다.
  Future<bool> replaceRun(VoyageRun? expected, VoyageRun next) {
    final task = _queue.then((_) async {
      if (!identical(_run, expected)) return false;
      final score = harborBestScore;
      final depth = harborBestDepth;
      final week = currentWeek;
      final weekly = weekBest;
      final stored = await _write({
        ..._snapshot(),
        'bestScore': score,
        'bestDepth': depth,
        'weekKey': week,
        'weekBest': weekly,
        'run': next.toJson(),
        'runClearWeek': null,
      });
      if (!stored) {
        // SharedPreferences는 쓰기가 실패해도 메모리 캐시를 먼저 바꾼다.
        try {
          await _preferences?.reload();
        } catch (_) {}
        return false;
      }
      bestScore = score;
      bestDepth = depth;
      _weekKey = week;
      _weekBest = weekly;
      _run = next;
      _runClearWeek = null;
      return true;
    });
    _queue = task.then<void>((_) {});
    return task;
  }

  /// 등불이 꺼져 항해를 마친다. 기록을 갱신하고 처음 넘은 이정표를 돌려준다.
  Future<VoyageSummary> finish(VoyageRun run) async {
    final boards = run.cleared;
    final week = currentWeek;
    if (_weekKey != week) {
      _weekKey = week;
      _weekBest = 0;
    }
    final newBestScore = run.score > bestScore;
    final newBestDepth = boards > bestDepth;
    final newWeekBest =
        identical(_run, run) && _runClearWeek == week && run.score > _weekBest;
    if (newBestScore) bestScore = run.score;
    if (newBestDepth) bestDepth = boards;
    if (newWeekBest) _weekBest = run.score;
    voyages++;
    totalBoards += boards;
    final milestones = [
      for (final milestone in voyageMilestones)
        if (boards >= milestone.depth && _milestones.add(milestone.id))
          milestone,
    ];
    _run = null;
    _runClearWeek = null;
    await _save();
    return VoyageSummary(
      score: run.score,
      boards: boards,
      perfects: run.perfects,
      newBestScore: newBestScore && run.score > 0,
      newBestDepth: newBestDepth,
      newWeekBest: newWeekBest && run.score > 0,
      milestones: milestones,
      stardust: EndlessRules.voyageStardust(
        boards: boards,
        perfects: run.perfects,
      ),
      xp: EndlessRules.voyageXp(boards),
    );
  }

  Map<String, dynamic> _snapshot() => {
    'version': 1,
    'bestScore': bestScore,
    'bestDepth': bestDepth,
    'voyages': voyages,
    'totalBoards': totalBoards,
    'weekKey': _weekKey,
    'weekBest': _weekBest,
    'milestones': _milestones.toList()..sort(),
    'run': _run?.toJson(),
    'runClearWeek': _runClearWeek,
  };

  Future<bool> _write(Map<String, dynamic> snapshot) async {
    try {
      saveFailed =
          !(await _preferences?.setString(storageKey, jsonEncode(snapshot)) ??
              false);
    } catch (_) {
      saveFailed = true;
    }
    return !saveFailed;
  }

  Future<void> _save() {
    final snapshot = _snapshot();
    final task = _queue.then((_) async {
      await _write(snapshot);
    });
    _queue = task;
    return task;
  }

  Future<void> flush() => _queue;
}
