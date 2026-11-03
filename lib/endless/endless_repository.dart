import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import 'puzzle_generator.dart';

/// [compute]로 넘기는 요청. 격리 공간으로 보낼 수 있는 값만 담는다.
class EndlessRequest {
  const EndlessRequest({
    required this.seed,
    required this.id,
    required this.cleared,
    required this.recent,
  });
  final int seed, id, cleared;
  final Set<String> recent;
}

Level? runEndlessRequest(EndlessRequest request) => generatePuzzle(
  seed: request.seed,
  id: request.id,
  cleared: request.cleared,
  recent: request.recent,
);

/// 무한 모드 기록. 캠페인·별자리·정령 기록과 완전히 분리한다.
class EndlessRepository {
  EndlessRepository._(this._preferences, this._pool, this.writer);

  static const storageKey = 'bloriq.endless.v1';
  static const schemaVersion = 1;
  static const firstId = 100000;

  /// 생성이 늦으면 이 시간만 기다리고 대체 판을 보여 준다.
  static const generationWait = Duration(milliseconds: 1500);
  static const maxCombo = 1.5;

  /// 테스트의 가짜 시간에서는 격리 공간 결과가 오지 않으므로 바로 실행한다.
  @visibleForTesting
  static bool runInline = false;

  final SharedPreferences? _preferences;
  final List<Map<String, dynamic>> _pool;
  final Future<bool> Function(String, String)? writer;
  Future<void> _queue = Future.value();
  bool _writable = true;
  bool saveFailed = false;

  int _baseSeed = 0;
  int cleared = 0;
  int streak = 0;
  int bestStreak = 0;
  bool _usedFallback = false;
  final List<String> _recent = [];
  final Set<String> _seenDevices = {};

  Level? _current;
  Future<Level?>? _prefetch;

  int get round => cleared + 1;

  /// 이번 판을 깼을 때 적용할 콤보. 연속으로 깰수록 판마다 0.1씩 오른다.
  double get combo => math.min(maxCombo, 1 + streak * .1);
  bool seenDevice(String name) => _seenDevices.contains(name);

  static Future<EndlessRepository> load(
    List<Map<String, dynamic>> pool, {
    Future<bool> Function(String, String)? writer,
    math.Random? random,
  }) async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
    } catch (_) {}
    final repo = EndlessRepository._(preferences, pool, writer);
    try {
      final raw = preferences?.getString(storageKey);
      if (raw == null) {
        // 설치마다 다른 시드로 시작해 첫판부터 서로 다르다.
        repo._baseSeed = (random ?? math.Random()).nextInt(1 << 30);
      } else {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] != schemaVersion) {
          throw const FormatException('Endless schema');
        }
        repo._baseSeed = data['seed'] as int;
        repo.cleared = data['cleared'] as int;
        repo.streak = data['streak'] as int;
        repo.bestStreak = data['bestStreak'] as int;
        repo._usedFallback = data['fallback'] == true;
        repo._recent.addAll((data['recent'] as List).cast<String>());
        repo._seenDevices.addAll((data['seen'] as List).cast<String>());
      }
    } catch (_) {
      // 손상되거나 미래 버전인 기록은 덮어쓰지 않는다.
      repo._writable = false;
      repo.saveFailed = true;
      repo._baseSeed = (random ?? math.Random()).nextInt(1 << 30);
    }
    if (preferences == null) repo.saveFailed = true;
    return repo;
  }

  EndlessRequest _request(int number, Set<String> recent) => EndlessRequest(
    seed: _baseSeed * 31 + number * 7919,
    id: firstId + number,
    cleared: number,
    recent: recent,
  );

  Future<Level?> _generate(EndlessRequest request) async {
    if (runInline) return runEndlessRequest(request);
    try {
      return await compute(runEndlessRequest, request);
    } catch (_) {
      return null;
    }
  }

  /// 지금 판. 앱을 다시 켜도 같은 시드로 같은 판이 나온다.
  Future<Level> currentPuzzle() async {
    if (_current case final level?) return level;
    Level? level;
    if (!_usedFallback) {
      level = await _generate(_request(cleared, _recent.toSet()))
          .timeout(generationWait, onTimeout: () => null);
    }
    _usedFallback = level == null;
    return _current = level ?? fallbackPuzzle(cleared);
  }

  /// 다음 판을 미리 만들어 "다음"을 누르면 바로 보이게 한다.
  void prefetchNext() {
    final current = _current;
    if (current == null || _prefetch != null) return;
    final recent = {..._recent, puzzleFingerprint(current)};
    _prefetch = _generate(_request(cleared + 1, recent));
  }

  /// 현재 판을 깼다. 기록을 저장하고 저장 성공 여부를 돌려준다.
  Future<bool> recordClear() async {
    if (_current case final level?) {
      _recent.add(puzzleFingerprint(level));
      if (_recent.length > 30) _recent.removeAt(0);
    }
    cleared++;
    streak++;
    bestStreak = math.max(bestStreak, streak);
    return retrySave();
  }

  /// [recordClear] 다음에 부른다.
  Future<Level> nextPuzzle() async {
    final pending = _prefetch;
    _prefetch = null;
    _current = null;
    Level? level;
    if (pending != null) {
      level = await pending.timeout(generationWait, onTimeout: () => null);
    }
    if (level != null && level.id == firstId + cleared) {
      _usedFallback = false;
      return _current = level;
    }
    _usedFallback = true;
    unawaited(retrySave());
    return _current = fallbackPuzzle(cleared);
  }

  /// 다시 시작하면 연속 기록이 끊긴다.
  void breakStreak() {
    if (streak == 0) return;
    streak = 0;
    unawaited(retrySave());
  }

  void markDeviceSeen(String name) {
    if (_seenDevices.add(name)) unawaited(retrySave());
  }

  /// 생성이 늦거나 실패했을 때 쓰는 판. 검증된 Daily 판을 돌리고 뒤집어 재사용한다.
  Level fallbackPuzzle(int number) {
    final tier = EndlessTier.forCleared(number);
    final levels = _pool.map(Level.fromJson).toList();
    bool hasDevice(Level level) =>
        level.echoGate != null ||
        level.echoErasers.isNotEmpty ||
        level.echoHolds.isNotEmpty ||
        level.oneWays.isNotEmpty ||
        level.goalOnlyTiles.isNotEmpty;
    final simple = levels.where((level) => !hasDevice(level)).toList();
    final choices = tier.devices == 0 && simple.isNotEmpty ? simple : levels;
    final mix = (_baseSeed + number * 13).abs();
    for (var offset = 0; offset < choices.length; offset++) {
      final level = transformLevel(
        choices[(mix + offset) % choices.length],
        id: firstId + number,
        rotation: (mix + offset) % 4,
        mirror: (mix + offset).isOdd,
      );
      if (!_recent.contains(puzzleFingerprint(level))) return level;
    }
    return transformLevel(
      choices[mix % choices.length],
      id: firstId + number,
      rotation: mix % 4,
      mirror: mix.isOdd,
    );
  }

  Future<bool> retrySave() async {
    final snapshot = jsonEncode({
      'version': schemaVersion,
      'seed': _baseSeed,
      'cleared': cleared,
      'streak': streak,
      'bestStreak': bestStreak,
      'fallback': _usedFallback,
      'recent': _recent,
      'seen': _seenDevices.toList()..sort(),
    });
    var saved = false;
    final task = _queue.then((_) async {
      if (!_writable || _preferences == null) return;
      try {
        saved =
            await (writer?.call(storageKey, snapshot) ??
                _preferences.setString(storageKey, snapshot));
      } catch (_) {}
    });
    _queue = task;
    await task;
    saveFailed = !saved;
    return saved;
  }

  Future<void> flush() => _queue;
}
