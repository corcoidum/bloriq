import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 마지막으로 연 캠페인 판 하나를 기억한다. 홈 "이어가기"가 막힌 판으로
/// 돌아가게 하는 데만 쓰며, 진행 기록([ProgressRepository])과는 따로 저장한다.
/// 값이 없거나 깨졌으면 null이고, 그때 홈은 기록에서 다음 판을 계산한다.
class LastPlayedRepository {
  LastPlayedRepository._(this._preferences, this._levelId);

  /// 저장소 없이 메모리에서만 기억한다(테스트용).
  LastPlayedRepository.memory([this._levelId]) : _preferences = null;

  static const storageKey = 'bloriq.lastPlayed.v1';
  static const schemaVersion = 1;

  final SharedPreferences? _preferences;
  int? _levelId;

  /// 마지막으로 연 판 id(세계 1: 1..25, 세계 2: 101..125 …).
  int? get levelId => _levelId;

  static Future<LastPlayedRepository> load() async {
    final preferences = await SharedPreferences.getInstance();
    return LastPlayedRepository._(
      preferences,
      parse(preferences.getString(storageKey)),
    );
  }

  /// 저장된 글에서 판 id를 읽는다. 모르는 판이나 깨진 값은 버린다.
  @visibleForTesting
  static int? parse(String? source) {
    if (source == null) return null;
    try {
      final data = jsonDecode(source);
      if (data is! Map || data['version'] != schemaVersion) return null;
      final id = data['levelId'];
      return id is int && id >= 1 ? id : null;
    } on FormatException {
      return null;
    }
  }

  /// 판을 열 때마다 부른다. 저장에 실패해도 플레이는 막지 않는다.
  Future<void> record(int levelId) async {
    if (levelId == _levelId) return;
    _levelId = levelId;
    try {
      await _preferences?.setString(
        storageKey,
        jsonEncode({'version': schemaVersion, 'levelId': levelId}),
      );
    } on Object catch (error) {
      debugPrint('Last played not saved: $error');
    }
  }
}
