import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../daily/daily_repository.dart';

/// 동의 이전에는 ID도 이벤트도 만들지 않는다. 외부 전송 코드는 없다.
class LocalAnalytics extends ChangeNotifier with WidgetsBindingObserver {
  LocalAnalytics._(this._preferences, this.clock);
  static const storageKey = 'bloriq.playtest.events.v1';
  static const consentKey = 'bloriq.playtest.consent.v1';
  static const buildTag = String.fromEnvironment(
    'BUILD_TAG',
    defaultValue: 'local-dev',
  );
  static const names = {
    'session_start',
    'session_end',
    'tutorial_start',
    'tutorial_complete',
    'tutorial_skip',
    'first_move',
    'first_echo',
    'level_start',
    'level_complete',
    'level_end',
    'undo_used',
    'restart_used',
    'hint_used',
    'daily_open',
    'daily_complete',
    'postcard_open',
    'postcard_share_tap',
  };
  static const fields = {
    'mode',
    'levelId',
    'revision',
    'date',
    'poolVersion',
    'moves',
    'validMoves',
    'undoCount',
    'restartCount',
    'activeMs',
    'reason',
    'replay',
    'runId',
  };
  final SharedPreferences? _preferences;
  final DateTime Function() clock;
  final List<Map<String, dynamic>> _events = [];
  final Stopwatch _sessionWatch = Stopwatch();
  String? _participant, _session, _firstDate;
  bool enabled = false, consentKnown = false, saveFailed = false;
  bool _writable = true, _disposed = false;
  bool _interrupted = false;
  int droppedEvents = 0, _pending = 0;
  final Random _random = Random.secure();
  DateTime? _lastPruned;
  Timer? _timer;
  Future<void> _queue = Future.value();
  bool _flushing = false, _dirty = false;
  int get eventCount => _events.length;
  String newId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  static Future<LocalAnalytics> load({DateTime Function()? clock}) async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
    } catch (_) {}
    final analytics = LocalAnalytics._(preferences, clock ?? DateTime.now);
    try {
      analytics.consentKnown = preferences?.containsKey(consentKey) ?? false;
      analytics.enabled = preferences?.getBool(consentKey) ?? false;
      final raw = preferences?.getString(storageKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] != 1) {
          analytics._writable = false;
          analytics.enabled = false;
        } else {
          analytics._participant = data['participantId'] as String?;
          analytics._firstDate = data['firstObservedDate'] as String?;
          analytics._interrupted =
              data['collectionInterrupted'] == true ||
              (data.containsKey('recordingEnabled') &&
                  data['recordingEnabled'] != analytics.enabled);
          analytics.droppedEvents = data['droppedEvents'] as int? ?? 0;
          for (final rawEvent in data['events'] as List? ?? []) {
            if (rawEvent is Map &&
                names.contains(rawEvent['name']) &&
                rawEvent['id'] is String &&
                rawEvent['timeUtc'] is String) {
              final event = Map<String, dynamic>.from(rawEvent);
              event.removeWhere(
                (key, _) => !{
                  'id',
                  'name',
                  'timeUtc',
                  'localDate',
                  'offsetMinutes',
                  'sessionId',
                  ...fields,
                }.contains(key),
              );
              analytics._events.add(event);
            }
          }
        }
      }
    } catch (_) {
      analytics._writable = false;
      analytics.enabled = false;
    }
    WidgetsBinding.instance.addObserver(analytics);
    if (analytics.enabled) analytics._beginSession();
    return analytics;
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed) return;
    consentKnown = true;
    if (enabled && !value) _interrupted = true;
    enabled = value && _writable;
    if (enabled) {
      _beginSession();
    } else {
      _session = null;
      _sessionWatch.stop();
      _timer?.cancel();
    }
    notifyListeners();
    try {
      saveFailed = !(await _preferences?.setBool(consentKey, enabled) ?? false);
    } catch (_) {
      saveFailed = true;
    }
    await flush();
  }

  void _beginSession() {
    if (!enabled || _disposed || _session != null) return;
    _participant ??= newId();
    _firstDate ??= localDateKey(clock());
    _session = newId();
    _sessionWatch
      ..reset()
      ..start();
    record('session_start');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_pending > 0) unawaited(flush());
    });
  }

  void record(String name, [Map<String, Object?> properties = const {}]) {
    if (!enabled || _disposed || !names.contains(name)) return;
    final now = clock();
    _events.add({
      'id': newId(),
      'name': name,
      'timeUtc': now.toUtc().toIso8601String(),
      'localDate': localDateKey(now),
      'offsetMinutes': now.timeZoneOffset.inMinutes,
      'sessionId': _session,
      for (final entry in properties.entries)
        if (fields.contains(entry.key) &&
            (entry.value is num ||
                entry.value is String ||
                entry.value is bool ||
                entry.value == null))
          entry.key: entry.value,
    });
    if (_lastPruned == null ||
        now.toUtc().difference(_lastPruned!).inMinutes >= 1) {
      _prune();
    }
    if (_events.length > 10000) {
      droppedEvents += _events.length - 10000;
      _events.removeRange(0, _events.length - 10000);
    }
    _pending++;
    if (_pending >= 20) unawaited(flush());
  }

  void _prune() {
    _lastPruned = clock().toUtc();
    final cutoff = _lastPruned!.subtract(const Duration(days: 30));
    final count = _events.length;
    _events.removeWhere(
      (event) =>
          DateTime.tryParse(event['timeUtc'] as String)?.isBefore(cutoff) ??
          true,
    );
    droppedEvents += count - _events.length;
    if (_events.length > 10000) {
      droppedEvents += _events.length - 10000;
      _events.removeRange(0, _events.length - 10000);
    }
  }

  Map<String, dynamic> snapshot() {
    _prune();
    return {
      'version': 1,
      'buildTag': buildTag,
      'contentVersion': 'echo-course2-revision2',
      'participantId': _participant,
      'firstObservedDate': _firstDate,
      'exportedAtUtc': clock().toUtc().toIso8601String(),
      'exportedLocalDate': localDateKey(clock()),
      'droppedEvents': droppedEvents,
      'collectionInterrupted': _interrupted,
      'recordingEnabled': enabled,
      'events': _events
          .map((event) => Map<String, dynamic>.from(event))
          .toList(),
    };
  }

  Future<void> flush() {
    _dirty = true;
    if (_flushing) return _queue;
    _flushing = true;
    _queue =
        () async {
          while (_dirty) {
            _dirty = false;
            final raw = jsonEncode(snapshot());
            _pending = 0;
            if (!_writable) {
              saveFailed = true;
              break;
            }
            try {
              saveFailed =
                  !(await _preferences?.setString(storageKey, raw) ?? false);
            } catch (_) {
              saveFailed = true;
            }
          }
        }().whenComplete(() {
          _flushing = false;
        });
    return _queue;
  }

  Future<void> clear() async {
    await setEnabled(false);
    _events.clear();
    _participant = null;
    _firstDate = null;
    droppedEvents = 0;
    _interrupted = false;
    await flush();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _beginSession();
      if (_session != null) _sessionWatch.start();
    } else if (state == AppLifecycleState.inactive) {
      _sessionWatch.stop();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_session != null) {
        record('session_end', {'activeMs': _sessionWatch.elapsedMilliseconds});
      }
      _session = null;
      _sessionWatch.stop();
      _timer?.cancel();
      if (_pending > 0) unawaited(flush());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    if (_session != null) {
      record('session_end', {
        'activeMs': _sessionWatch.elapsedMilliseconds,
        'reason': 'dispose',
      });
    }
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (enabled || _events.isNotEmpty) unawaited(flush());
    super.dispose();
  }
}

class AttemptRecorder {
  AttemptRecorder(this.analytics, this.properties, {Stopwatch? watch})
    : _watch = watch ?? Stopwatch() {
    _watch.start();
    analytics.record('level_start', data);
  }
  final LocalAnalytics analytics;
  final Map<String, Object?> properties;
  late final String runId = analytics.newId();
  final Stopwatch _watch;
  int validMoves = 0, undoCount = 0, restartCount = 0, _pauses = 0;
  bool _foreground = true, finished = false, _echo = false;
  Map<String, Object?> get data => {...properties, 'runId': runId};
  void pause() {
    _pauses++;
    _watch.stop();
  }

  void resume() {
    if (_pauses > 0) _pauses--;
    _sync();
  }

  void foreground(bool active) {
    _foreground = active;
    _sync();
  }

  void _sync() {
    if (!finished && _foreground && _pauses == 0) {
      _watch.start();
    } else {
      _watch.stop();
    }
  }

  void moved({required bool echo}) {
    validMoves++;
    if (validMoves == 1) analytics.record('first_move', data);
    if (echo && !_echo) {
      _echo = true;
      analytics.record('first_echo', data);
    }
  }

  void undo() {
    undoCount++;
    analytics.record('undo_used', data);
  }

  void restart() {
    restartCount++;
    analytics.record('restart_used', data);
  }

  void finish(String name, int moves, {String? reason}) {
    if (finished) return;
    finished = true;
    _watch.stop();
    analytics.record(name, {
      ...data,
      'moves': moves,
      'validMoves': validMoves,
      'undoCount': undoCount,
      'restartCount': restartCount,
      'activeMs': _watch.elapsedMilliseconds,
      'reason': ?reason,
    });
    unawaited(analytics.flush());
  }
}
