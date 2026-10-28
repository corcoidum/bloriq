import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';

/// 이전 코스 기반 회귀 테스트는 별도 fixture를 사용한다.
Future<List<Level>> loadLegacyLevels() async {
  final json = jsonDecode(
    File('assets/levels/legacy_levels.json').readAsStringSync(),
  ) as List<dynamic>;
  return json
      .map((item) => Level.fromJson(item as Map<String, dynamic>))
      .toList();
}
