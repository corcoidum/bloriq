import 'dart:convert';

import 'package:flutter/services.dart';

import '../constellation/constellation_catalog.dart';
import '../domain/puzzle.dart';
import '../story/story_catalog.dart';

/// 월드 2 「구름바다 등대」. 월드 1의 다섯 별자리를 모두 완성하면 열린다.
abstract final class World2 {
  static const levelsAsset = 'assets/levels/world2.json';
  static const storyAsset = 'assets/story/world2.json';
  static const firstLevelId = 101;
  static const stageCount = 25;
  static const chapterCount = 5;

  /// 월드 1 장 번호. 이 다섯 별자리가 모두 완성돼야 등대가 열린다.
  static const world1Chapters = {1, 2, 3, 4, 5};

  /// 성장 기록(`completedChapters`)에 쓰는 전역 장 번호: 월드 2의 1장 = 6.
  static int globalChapter(int chapter) => world1Chapters.length + chapter;

  static bool isUnlocked(Set<int> completedChapters) =>
      world1Chapters.every(completedChapters.contains);

  /// 월드 2에서 쓸 수 있는 권능. 별빛 길은 별도 버튼이다.
  static const boardPowers = [
    PuzzlePower.moonflowerLeap,
    PuzzlePower.lightSwap,
    PuzzlePower.seal,
    PuzzlePower.wind,
  ];

  static int chapterOf(int levelId) => (levelId - firstLevelId) ~/ 5 + 1;
  static bool contains(int levelId) =>
      levelId >= firstLevelId && levelId < firstLevelId + stageCount;

  static List<Level> parseLevels(String source) {
    final levels = (jsonDecode(source) as List<dynamic>)
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    for (var index = 0; index < levels.length; index++) {
      final level = levels[index];
      if (level.id != firstLevelId + index || level.world != 2) {
        throw const FormatException('Invalid world 2 level order');
      }
    }
    if (levels.length != stageCount) {
      throw const FormatException('World 2 needs 25 stages');
    }
    return levels;
  }

  static Future<List<Level>> loadLevels() async =>
      parseLevels(await rootBundle.loadString(levelsAsset));
}

class World2Chapter {
  World2Chapter.fromJson(Map<String, dynamic> data)
    : number = data['number'] as int,
      globalChapter = data['globalChapter'] as int,
      power = data['power'] == null
          ? null
          : PuzzlePower.byId(data['power'] as String) ??
                (throw const FormatException('Unknown power')),
      family = data['family'] as String,
      name = StoryText.fromJson(data['name']),
      familyName = StoryText.fromJson(data['familyName']),
      constellation = StoryText.fromJson(data['constellation']),
      intro = StoryText.fromJson(data['intro']),
      endingTitle = StoryText.fromJson(data['endingTitle']),
      ending = StoryText.fromJson(data['ending']);
  final int number, globalChapter;

  /// 이 장에서 배우는 권능. 마지막 장은 모든 권능을 섞으므로 null.
  final PuzzlePower? power;
  final String family;
  final StoryText name, familyName, constellation, intro, endingTitle, ending;
}

class World2Spirit {
  World2Spirit.fromJson(Map<String, dynamic> data)
    : id = data['id'] as String,
      levelId = data['levelId'] as int,
      chapter = data['chapter'] as int,
      family = data['family'] as String,
      guardian = data['guardian'] as bool,
      asset = data['asset'] as String?,
      motionKind = data['motionKind'] as String? ?? 'sway',
      name = StoryText.fromJson(data['name']),
      levelTitle = StoryText.fromJson(data['levelTitle']),
      appearance = StoryText.fromJson(data['appearance']),
      personality = StoryText.fromJson(data['personality']),
      memory = StoryText.fromJson(data['memory']),
      quote = StoryText.fromJson(data['quote']);
  final String id, family, motionKind;
  final int levelId, chapter;
  final bool guardian;

  /// 정령 그림. 아직 그림이 없으면 null이며 화면은 별 모양 자리표시를 쓴다.
  final String? asset;
  final StoryText name, levelTitle, appearance, personality, memory, quote;
}

/// assets/story/world2.json. 월드 1 [StoryCatalog]와 섞지 않아 기존 도감
/// 규칙(정령 25명, 레벨 1..25)을 그대로 둔다.
class World2Story {
  World2Story.fromJson(Map<String, dynamic> data)
    : title = StoryText.fromJson(data['title']),
      prologue = StoryText.fromJson(data['prologue']),
      chapters = List.unmodifiable(
        (data['chapters'] as List).map(
          (e) => World2Chapter.fromJson(e as Map<String, dynamic>),
        ),
      ),
      spirits = List.unmodifiable(
        (data['spirits'] as List).map(
          (e) => World2Spirit.fromJson(e as Map<String, dynamic>),
        ),
      ) {
    if (data['version'] != 1 ||
        data['worldId'] != 'w2' ||
        chapters.length != World2.chapterCount ||
        spirits.length != World2.stageCount) {
      throw const FormatException('Invalid world 2 story');
    }
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      if (chapter.number != index + 1 ||
          chapter.globalChapter != World2.globalChapter(index + 1)) {
        throw const FormatException('World 2 chapter order');
      }
    }
    for (var index = 0; index < spirits.length; index++) {
      final spirit = spirits[index];
      if (spirit.id != 's2-${(index + 1).toString().padLeft(2, '0')}' ||
          spirit.levelId != World2.firstLevelId + index ||
          spirit.chapter != index ~/ 5 + 1 ||
          spirit.guardian != ((index + 1) % 5 == 0) ||
          spirit.family != chapters[index ~/ 5].family) {
        throw const FormatException('Unstable world 2 spirit mapping');
      }
    }
  }

  final StoryText title, prologue;
  final List<World2Chapter> chapters;
  final List<World2Spirit> spirits;

  World2Chapter chapter(int number) => chapters[number - 1];
  World2Spirit? forLevel(int levelId) =>
      World2.contains(levelId) ? spirits[levelId - World2.firstLevelId] : null;

  static Future<World2Story> load() async {
    final bytes = await rootBundle.load(World2.storyAsset);
    return World2Story.fromJson(
      jsonDecode(utf8.decode(bytes.buffer.asUint8List()))
          as Map<String, dynamic>,
    );
  }
}

/// 월드 2 별자리. 월드 1 [ConstellationCatalog]와 같은 규칙(노드 순서 =
/// 스테이지 순서, 마지막 노드 = 수호 정령)이며 장 번호는 전역 번호 6..10이다.
/// 이름은 l10n 대신 [World2Chapter.constellation]에서 가져온다.
abstract final class World2Constellations {
  static const all = [
    // 구름다리자리: 끊긴 계단 위로 놓인 아치
    ConstellationDefinition(
      chapter: 6,
      nodes: [
        Offset(.12, .72),
        Offset(.28, .40),
        Offset(.50, .26),
        Offset(.72, .40),
        Offset(.88, .72),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 4)],
    ),
    // 쌍등불자리: 서로 마주 보는 두 등불
    ConstellationDefinition(
      chapter: 7,
      nodes: [
        Offset(.22, .24),
        Offset(.22, .70),
        Offset(.78, .24),
        Offset(.78, .70),
        Offset(.50, .46),
      ],
      edges: [(0, 1), (2, 3), (0, 4), (4, 3), (1, 4), (4, 2)],
    ),
    // 자물쇠별자리: 고리와 열쇠 구멍
    ConstellationDefinition(
      chapter: 8,
      nodes: [
        Offset(.32, .40),
        Offset(.50, .16),
        Offset(.68, .40),
        Offset(.66, .78),
        Offset(.34, .78),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0), (0, 2)],
    ),
    // 돛자리: 돛대와 바람을 받은 돛
    ConstellationDefinition(
      chapter: 9,
      nodes: [
        Offset(.40, .82),
        Offset(.40, .16),
        Offset(.80, .62),
        Offset(.18, .82),
        Offset(.82, .84),
      ],
      edges: [(0, 1), (1, 2), (2, 0), (3, 0), (0, 4)],
    ),
    // 큰등대자리: 등대 몸통과 꼭대기 등불
    ConstellationDefinition(
      chapter: 10,
      nodes: [
        Offset(.32, .86),
        Offset(.68, .86),
        Offset(.62, .40),
        Offset(.38, .40),
        Offset(.50, .12),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 0), (3, 4), (4, 2)],
    ),
  ];

  static ConstellationDefinition forChapter(int chapter) => all[chapter - 1];
}
