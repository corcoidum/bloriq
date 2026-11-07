import '../constellation/constellation_catalog.dart';
import '../domain/puzzle.dart';
import '../progress/progress_repository.dart';
import '../progression/progression_rules.dart';
import 'world2_catalog.dart';

/// 월드 2 스테이지 한 칸. 앞 스테이지를 깨야 다음이 열린다.
class World2StageView {
  const World2StageView({
    required this.level,
    required this.spirit,
    required this.record,
    required this.unlocked,
  });
  final Level level;
  final World2Spirit spirit;
  final LevelProgress? record;
  final bool unlocked;
  bool get cleared => record != null;
  int get stars => record?.bestStars ?? 0;
}

class World2ChapterView {
  const World2ChapterView({
    required this.chapter,
    required this.definition,
    required this.stages,
  });
  final World2Chapter chapter;
  final ConstellationDefinition definition;
  final List<World2StageView> stages;

  int get cleared => stages.where((stage) => stage.cleared).length;
  bool get complete => cleared == stages.length;
  bool get golden => complete && stages.every((stage) => stage.stars == 3);
  bool get unlocked => stages.first.unlocked;
  List<bool> get lit => [for (final stage in stages) stage.cleared];
}

/// 기록에서 매번 다시 계산하는 월드 2 진행 상황. 따로 저장하지 않는다.
class World2Atlas {
  const World2Atlas(this.chapters);

  factory World2Atlas.derive(
    List<Level> levels,
    World2Story story,
    ProgressRepository progress,
  ) {
    final stages = <World2StageView>[];
    var previousCleared = true;
    for (final level in levels) {
      final record = progress.forLevel(level.id, revision: level.revision);
      stages.add(
        World2StageView(
          level: level,
          spirit: story.forLevel(level.id)!,
          record: record,
          unlocked: previousCleared || record != null,
        ),
      );
      previousCleared = record != null;
    }
    return World2Atlas([
      for (final chapter in story.chapters)
        World2ChapterView(
          chapter: chapter,
          definition: World2Constellations.forChapter(chapter.number),
          stages: stages.sublist((chapter.number - 1) * 5, chapter.number * 5),
        ),
    ]);
  }

  final List<World2ChapterView> chapters;

  Iterable<World2StageView> get stages =>
      chapters.expand((chapter) => chapter.stages);
  int get cleared => stages.where((stage) => stage.cleared).length;

  World2ChapterView? forLevel(int levelId) =>
      World2.contains(levelId) ? chapters[World2.chapterOf(levelId) - 1] : null;

  /// 이어서 할 스테이지: 아직 못 깬 첫 스테이지, 다 깼으면 첫 스테이지.
  int get nextLevelId =>
      stages.where((stage) => !stage.cleared).firstOrNull?.level.id ??
      World2.firstLevelId;

  /// 한 스테이지 클리어 전후를 비교해 이번에 완성·황금이 된 장(전역 번호).
  static ({int? completed, int? golden}) diff(
    World2Atlas before,
    World2Atlas after,
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

/// 월드 2 맨손 별: 권능과 별빛 길 없이, 맨손 최소 수 그대로 클리어.
/// 권능 없이는 풀 수 없는 스테이지는 맨손 별이 없다.
bool isWorld2BareHanded({
  required Level level,
  required int moves,
  required bool usedPower,
  required bool usedStarlightPath,
}) =>
    !usedPower &&
    !usedStarlightPath &&
    level.bareHandedMoves != null &&
    moves <= level.bareHandedMoves!;

/// 플레이어가 가진 권능 중 월드 2 판 위에서 쓸 수 있는 것.
Set<PuzzlePower> ownedBoardPowers(bool Function(String id) hasPower) => {
  for (final power in World2.boardPowers)
    if (hasPower(power.id)) power,
};

/// 권능 이름·설명은 성장 시스템의 [powerCatalog]와 같은 문구를 쓴다.
PowerDefinition? powerDefinition(PuzzlePower power) => powerById(power.id);
