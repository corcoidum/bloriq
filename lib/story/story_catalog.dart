import 'dart:convert';

import 'package:flutter/services.dart';

class StoryText {
  const StoryText(this.ko, this.en);
  factory StoryText.fromJson(Map<String, dynamic> data) {
    final ko = data['ko'], en = data['en'];
    if (ko is! String || ko.isEmpty || en is! String || en.isEmpty) {
      throw const FormatException('Both story locales required');
    }
    return StoryText(ko, en);
  }
  final String ko, en;
  String inLocale(String locale) => locale.startsWith('ko') ? ko : en;
}

class SpiritDefinition {
  SpiritDefinition.fromJson(Map<String, dynamic> data)
    : id = data['id'] as String,
      memoryId = data['memoryId'] as String,
      levelId = data['levelId'] as int,
      chapter = data['chapter'] as int,
      family = data['family'] as String,
      guardian = data['guardian'] as bool,
      released = data['released'] as bool,
      asset = data['asset'] as String?,
      name = StoryText.fromJson(data['name']),
      levelTitle = StoryText.fromJson(data['levelTitle']),
      appearance = StoryText.fromJson(data['appearance']),
      personality = StoryText.fromJson(data['personality']),
      motion = StoryText.fromJson(data['motion']),
      memory = StoryText.fromJson(data['memory']),
      description = StoryText.fromJson(data['description']),
      quote = StoryText.fromJson(data['quote']);
  final String id, memoryId, family;
  final int levelId, chapter;
  final bool guardian, released;
  final String? asset;
  final StoryText name,
      levelTitle,
      appearance,
      personality,
      motion,
      memory,
      description,
      quote;
}

class StoryChapter {
  StoryChapter.fromJson(Map<String, dynamic> data)
    : number = data['number'] as int,
      name = StoryText.fromJson(data['name']),
      released = data['released'] as bool;
  final int number;
  final StoryText name;
  final bool released;
}

class StoryCatalog {
  StoryCatalog.fromJson(Map<String, dynamic> data)
    : spirits = List.unmodifiable(
        (data['spirits'] as List).map((e) => SpiritDefinition.fromJson(e)),
      ),
      chapters = List.unmodifiable(
        (data['chapters'] as List).map((e) => StoryChapter.fromJson(e)),
      ) {
    if (data['version'] != 1 ||
        spirits.length != 25 ||
        chapters.length != 5 ||
        spirits.map((s) => s.id).toSet().length != 25 ||
        spirits.map((s) => s.memoryId).toSet().length != 25 ||
        spirits.map((s) => s.levelId).toSet().length != 25) {
      throw const FormatException('Invalid season catalog');
    }
    for (var index = 0; index < spirits.length; index++) {
      final s = spirits[index];
      if (s.id != 's1-${(index + 1).toString().padLeft(2, '0')}' ||
          s.levelId != index + 1 ||
          s.chapter != index ~/ 5 + 1 ||
          s.guardian != ((index + 1) % 5 == 0) ||
          !{
            'forest',
            'starlight',
            'letter',
            'cloud',
            'memory',
          }.contains(s.family) ||
          s.released != (index < 5) ||
          (s.released && s.asset == null)) {
        throw const FormatException('Unstable spirit mapping');
      }
    }
  }
  final List<SpiritDefinition> spirits;
  final List<StoryChapter> chapters;
  List<SpiritDefinition> get released =>
      spirits.where((s) => s.released).toList(growable: false);
  SpiritDefinition? forLevel(int id) =>
      spirits.where((s) => s.levelId == id).firstOrNull;
  SpiritDefinition? byId(String? id) =>
      spirits.where((s) => s.id == id).firstOrNull;
  static Future<StoryCatalog> load() async => StoryCatalog.fromJson(
    jsonDecode(await rootBundle.loadString('assets/story/season1.json'))
        as Map<String, dynamic>,
  );
}
