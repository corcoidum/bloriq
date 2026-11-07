import '../constellation/constellation_catalog.dart';
import '../domain/puzzle.dart';
import '../progress/progress_repository.dart';
import '../progression/progression_rules.dart';
import 'world_catalog.dart';

/// 확장 세계 스테이지 한 칸. 앞 스테이지를 깨야 다음이 열린다.
class WorldStageView {
  const WorldStageView({
    required this.level,
    required this.spirit,
    required this.record,
    required this.unlocked,
  });
  final Level level;
  final WorldSpirit spirit;
  final LevelProgress? record;
  final bool unlocked;
  bool get cleared => record != null;
  int get stars => record?.bestStars ?? 0;
}

class WorldChapterView {
  const WorldChapterView({required this.chapter, required this.stages});
  final WorldChapter chapter;
  final List<WorldStageView> stages;

  ConstellationDefinition get definition => chapter.stars;
  int get cleared => stages.where((stage) => stage.cleared).length;
  bool get complete => cleared == stages.length;
  bool get golden => complete && stages.every((stage) => stage.stars == 3);
  bool get unlocked => stages.first.unlocked;
  List<bool> get lit => [for (final stage in stages) stage.cleared];
}

/// 기록에서 매번 다시 계산하는 확장 세계 진행 상황. 따로 저장하지 않는다.
class WorldAtlas {
  const WorldAtlas(this.world, this.chapters);

  factory WorldAtlas.derive(LoadedWorld world, ProgressRepository progress) {
    final stages = <WorldStageView>[];
    var previousCleared = true;
    for (final level in world.levels) {
      final record = progress.forLevel(level.id, revision: level.revision);
      stages.add(
        WorldStageView(
          level: level,
          spirit: world.story.forLevel(level.id)!,
          record: record,
          unlocked: previousCleared || record != null,
        ),
      );
      previousCleared = record != null;
    }
    const size = Worlds.stagesPerChapter;
    return WorldAtlas(world.number, [
      for (final chapter in world.story.chapters)
        WorldChapterView(
          chapter: chapter,
          stages: stages.sublist(
            (chapter.number - 1) * size,
            chapter.number * size,
          ),
        ),
    ]);
  }

  final int world;
  final List<WorldChapterView> chapters;

  Iterable<WorldStageView> get stages =>
      chapters.expand((chapter) => chapter.stages);
  int get cleared => stages.where((stage) => stage.cleared).length;
  bool get complete => chapters.every((chapter) => chapter.complete);

  WorldChapterView? forLevel(int levelId) => Worlds.contains(world, levelId)
      ? chapters[Worlds.chapterOf(levelId) - 1]
      : null;

  /// 이어서 할 스테이지: 아직 못 깬 첫 스테이지, 다 깼으면 첫 스테이지.
  int get nextLevelId =>
      stages.where((stage) => !stage.cleared).firstOrNull?.level.id ??
      Worlds.firstLevelId(world);

  /// 한 스테이지 클리어 전후를 비교해 이번에 완성·황금이 된 장(전역 번호).
  static ({int? completed, int? golden}) diff(
    WorldAtlas before,
    WorldAtlas after,
    int levelId,
  ) {
    final previous = before.forLevel(levelId);
    final next = after.forLevel(levelId);
    if (previous == null || next == null) {
      return (completed: null, golden: null);
    }
    final global = next.chapter.globalChapter;
    return (
      completed: !previous.complete && next.complete ? global : null,
      golden: !previous.golden && next.golden ? global : null,
    );
  }
}

/// 맨손 별: 권능과 별빛 길 없이, 맨손 최소 수 그대로 클리어.
/// 권능 없이는 풀 수 없는 스테이지는 맨손 별이 없다.
bool isBareHandedClear({
  required Level level,
  required int moves,
  required bool usedPower,
  required bool usedStarlightPath,
}) =>
    !usedPower &&
    !usedStarlightPath &&
    level.bareHandedMoves != null &&
    moves <= level.bareHandedMoves!;

/// 플레이어가 가진 권능 중 확장 세계 판 위에서 쓸 수 있는 것.
Set<PuzzlePower> ownedBoardPowers(bool Function(String id) hasPower) => {
  for (final power in Worlds.boardPowers)
    if (hasPower(power.id)) power,
};

/// 권능 이름·설명은 성장 시스템의 [powerCatalog]와 같은 문구를 쓴다.
PowerDefinition? powerDefinition(PuzzlePower power) => powerById(power.id);
