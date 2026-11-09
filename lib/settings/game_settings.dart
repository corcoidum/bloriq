import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 퍼즐 상태를 소유하지 않는 표시 설정. 테마는 늘 다크라 설정하지 않는다.
class GameSettings extends ChangeNotifier {
  GameSettings({SharedPreferences? preferences, bool reduceMotion = false})
    : // 외부 주입용 매개변수와 읽기 전용 getter를 내부 상태에서 분리한다.
      // ignore: prefer_initializing_formals
      _preferences = preferences,
      // ignore: prefer_initializing_formals
      _reduceMotion = reduceMotion;

  static const reduceMotionKey = 'bloriq.settings.reduceMotion';

  final SharedPreferences? _preferences;
  bool _reduceMotion;
  bool _saveFailed = false;
  bool _disposed = false;
  Future<void> _writeQueue = Future.value();

  bool get reduceMotion => _reduceMotion;
  bool get saveFailed => _saveFailed;

  static Future<GameSettings> load() async {
    SharedPreferences? preferences;
    var reduceMotion = false;
    try {
      preferences = await SharedPreferences.getInstance();
      try {
        reduceMotion = preferences.getBool(reduceMotionKey) ?? false;
      } catch (_) {}
    } catch (_) {
      // 저장소를 사용할 수 없어도 기본 야간 테마로 실행할 수 있다.
    }
    return GameSettings(preferences: preferences, reduceMotion: reduceMotion);
  }

  Future<void> setReduceMotion(bool enabled) {
    if (_disposed) return Future.value();
    _reduceMotion = enabled;
    notifyListeners();
    return _save();
  }

  Future<void> _save() {
    final reduceMotion = _reduceMotion;
    // 빠른 연속 선택도 요청 순서대로 저장해 마지막 선택을 복원한다.
    _writeQueue = _writeQueue.then((_) async {
      var saved = false;
      final preferences = _preferences;
      try {
        if (preferences != null) {
          saved = await preferences.setBool(reduceMotionKey, reduceMotion);
        }
      } catch (_) {
        // 현재 세션의 선택은 유지하고 UI에서 저장 실패를 안내한다.
      }
      if (!_disposed && _saveFailed == saved) {
        _saveFailed = !saved;
        notifyListeners();
      }
    });
    return _writeQueue;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
