import 'dart:convert';

import 'package:flutter/services.dart';

class Spirit {
  Spirit(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  int get stage => data['stage'] as int;
  int get chapter => (stage - 1) ~/ 5;
  int get variant => (stage - 1) % 5;
  String get family => data['family'] as String;
  bool get guardian => data['guardian'] as bool;
  String text(String field, bool ko) =>
      data['$field${ko ? 'Ko' : 'En'}'] as String;
}

/// 스토리와 퍼즐 규칙을 분리한다. 각 단계의 보상은 고정된 일대일 대응이다.
class Season {
  Season(this.spirits, this.chapters);
  final List<Spirit> spirits;
  final List<Map<String, dynamic>> chapters;
  static Future<Season> load() async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/story/season1.json'),
    ) as Map<String, dynamic>;
    final spirits = (data['spirits'] as List)
        .map((e) => Spirit(e as Map<String, dynamic>))
        .toList();
    if (spirits.length != 25 ||
        spirits.map((s) => s.id).toSet().length != 25 ||
        spirits.map((s) => s.stage).toSet().length != 25 ||
        spirits.any((s) => s.stage < 1 || s.stage > 25)) {
      throw const FormatException('Season requires 25 unique stage rewards');
    }
    return Season(
      spirits,
      (data['chapters'] as List).cast<Map<String, dynamic>>(),
    );
  }

  Spirit forStage(int stage) => spirits.singleWhere((s) => s.stage == stage);
  String chapterName(int index, bool ko) =>
      chapters[index][ko ? 'nameKo' : 'nameEn'] as String;
}
