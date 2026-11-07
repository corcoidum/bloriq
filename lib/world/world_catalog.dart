import 'dart:convert';

import 'package:flutter/services.dart';

import '../constellation/constellation_catalog.dart';
import '../domain/puzzle.dart';
import '../story/story_catalog.dart';
import 'saga.dart';

/// 모든 세계가 따르는 번호 규칙. 세계 n은 5장 × 5스테이지이며
/// 스테이지 id는 `(n-1)*100 + 1` 부터, 전역 장 번호는 `(n-1)*5 + 1` 부터다.
/// (세계 1: 1..25 / 장 1..5, 세계 2: 101..125 / 장 6..10, 세계 3: 201..225 / 장 11..15)
abstract final class Worlds {
  static const chapterCount = 5;
  static const stagesPerChapter = 5;
  static const stageCount = chapterCount * stagesPerChapter;

  static int firstLevelId(int world) => (world - 1) * 100 + 1;
  static int worldOf(int levelId) => (levelId - 1) ~/ 100 + 1;

  /// 세계 안에서 센 스테이지 번호(1..25).
  static int stageNumber(int levelId) => (levelId - 1) % 100 + 1;

  /// 세계 안에서 센 장 번호(1..5).
  static int chapterOf(int levelId) =>
      (stageNumber(levelId) - 1) ~/ stagesPerChapter + 1;

  static bool contains(int world, int levelId) =>
      levelId >= firstLevelId(world) &&
      levelId < firstLevelId(world) + stageCount;

  /// 성장 기록(`completedChapters`)에 쓰는 전역 장 번호.
  static int globalChapter(int world, int chapter) =>
      (world - 1) * chapterCount + chapter;

  static Set<int> chaptersOf(int world) => {
    for (var chapter = 1; chapter <= chapterCount; chapter++)
      globalChapter(world, chapter),
  };

  /// 세계의 다섯 별자리를 모두 완성했는지.
  static bool isComplete(int world, Set<int> completedChapters) =>
      chaptersOf(world).every(completedChapters.contains);

  /// 앞 세계의 다섯 별자리를 모두 완성하면 다음 세계가 열린다.
  static bool isUnlocked(int world, Set<int> completedChapters) =>
      world <= 1 || isComplete(world - 1, completedChapters);

  /// 확장 세계 판 위에서 쓸 수 있는 권능. 별빛 길은 별도 버튼이다.
  static const boardPowers = [
    PuzzlePower.moonflowerLeap,
    PuzzlePower.lightSwap,
    PuzzlePower.seal,
    PuzzlePower.wind,
  ];

  static List<Level> parseLevels(String source, int world) {
    final levels = (jsonDecode(source) as List<dynamic>)
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    if (levels.length != stageCount) {
      throw FormatException('World $world needs $stageCount stages');
    }
    for (var index = 0; index < levels.length; index++) {
      final level = levels[index];
      if (level.id != firstLevelId(world) + index || level.world != world) {
        throw FormatException('Invalid world $world level order');
      }
    }
    return levels;
  }
}

class WorldChapter {
  WorldChapter.fromJson(Map<String, dynamic> data)
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
      stars = _stars(data['globalChapter'] as int, data['stars']),
      intro = StoryText.fromJson(data['intro']),
      endingTitle = StoryText.fromJson(data['endingTitle']),
      ending = StoryText.fromJson(data['ending']);
  final int number, globalChapter;

  /// 이 장에서 배우는 권능. 권능을 섞는 장은 null.
  final PuzzlePower? power;
  final String family;
  final StoryText name, familyName, constellation, intro, endingTitle, ending;

  /// 별자리 모양. 노드 순서 = 스테이지 순서, 마지막 노드 = 수호 정령.
  final ConstellationDefinition stars;

  static ConstellationDefinition _stars(int chapter, Object? data) {
    final map = data as Map<String, dynamic>;
    final nodes = [
      for (final node in map['nodes'] as List)
        Offset(
          ((node as List)[0] as num).toDouble(),
          (node[1] as num).toDouble(),
        ),
    ];
    final edges = [
      for (final edge in map['edges'] as List)
        ((edge as List)[0] as int, edge[1] as int),
    ];
    final inside = nodes.every(
      (node) => node.dx >= 0 && node.dx <= 1 && node.dy >= 0 && node.dy <= 1,
    );
    final linked = edges.every(
      (edge) =>
          edge.$1 >= 0 &&
          edge.$1 < nodes.length &&
          edge.$2 >= 0 &&
          edge.$2 < nodes.length,
    );
    if (nodes.length != Worlds.stagesPerChapter || !inside || !linked) {
      throw const FormatException('Invalid constellation stars');
    }
    return ConstellationDefinition(
      chapter: chapter,
      nodes: nodes,
      edges: edges,
    );
  }
}

class WorldSpirit {
  WorldSpirit.fromJson(Map<String, dynamic> data)
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

/// 확장 세계 하나의 이야기(assets/story/worldN.json). 세계 1 [StoryCatalog]와
/// 섞지 않아 기존 도감 규칙(정령 25명, 레벨 1..25)을 그대로 둔다.
class WorldStory {
  WorldStory.fromJson(Map<String, dynamic> data, {required this.world})
    : title = StoryText.fromJson(data['title']),
      prologue = StoryText.fromJson(data['prologue']),
      chapters = List.unmodifiable(
        (data['chapters'] as List).map(
          (e) => WorldChapter.fromJson(e as Map<String, dynamic>),
        ),
      ),
      spirits = List.unmodifiable(
        (data['spirits'] as List).map(
          (e) => WorldSpirit.fromJson(e as Map<String, dynamic>),
        ),
      ) {
    if (data['version'] != 1 ||
        data['worldId'] != 'w$world' ||
        chapters.length != Worlds.chapterCount ||
        spirits.length != Worlds.stageCount) {
      throw FormatException('Invalid world $world story');
    }
    for (var index = 0; index < chapters.length; index++) {
      final chapter = chapters[index];
      if (chapter.number != index + 1 ||
          chapter.globalChapter != Worlds.globalChapter(world, index + 1)) {
        throw FormatException('World $world chapter order');
      }
    }
    for (var index = 0; index < spirits.length; index++) {
      final spirit = spirits[index];
      final chapter = index ~/ Worlds.stagesPerChapter;
      if (spirit.id != 's$world-${(index + 1).toString().padLeft(2, '0')}' ||
          spirit.levelId != Worlds.firstLevelId(world) + index ||
          spirit.chapter != chapter + 1 ||
          spirit.guardian != ((index + 1) % Worlds.stagesPerChapter == 0) ||
          spirit.family != chapters[chapter].family) {
        throw FormatException('Unstable world $world spirit mapping');
      }
    }
  }

  final int world;
  final StoryText title, prologue;
  final List<WorldChapter> chapters;
  final List<WorldSpirit> spirits;

  WorldChapter chapter(int number) => chapters[number - 1];
  WorldSpirit? forLevel(int levelId) => Worlds.contains(world, levelId)
      ? spirits[levelId - Worlds.firstLevelId(world)]
      : null;

  static WorldStory parse(String source, int world) => WorldStory.fromJson(
    jsonDecode(source) as Map<String, dynamic>,
    world: world,
  );
}

/// 불러온 확장 세계: 사가 정보 + 25스테이지 + 이야기.
class LoadedWorld {
  LoadedWorld({
    required this.info,
    required List<Level> levels,
    required this.story,
  }) : levels = List.unmodifiable(levels) {
    if (!info.expansion || story.world != info.number) {
      throw const FormatException('World data mismatch');
    }
  }

  final SagaWorld info;
  final List<Level> levels;
  final WorldStory story;

  int get number => info.number;

  static Future<LoadedWorld> load(SagaWorld info) async {
    final levels = Worlds.parseLevels(
      await rootBundle.loadString(info.levelsAsset!),
      info.number,
    );
    final bytes = await rootBundle.load(info.storyAsset!);
    final story = WorldStory.parse(
      utf8.decode(bytes.buffer.asUint8List()),
      info.number,
    );
    return LoadedWorld(info: info, levels: levels, story: story);
  }
}
