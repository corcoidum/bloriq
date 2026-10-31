import '../domain/puzzle.dart';
import '../progress/chapter_progress.dart';
import '../progress/progress_repository.dart';
import 'constellation_catalog.dart';

/// 진행 기록에서 매번 계산한 한 챕터의 별자리. 별도로 저장하지 않는다.
class ChapterConstellation {
  ChapterConstellation._({
    required this.definition,
    required this.levels,
    required this.litLevelIds,
    required this.bestStars,
  });

  final ConstellationDefinition definition;
  final List<Level> levels;

  /// 영구 저장에 성공한 완료(리비전 무관). 친구 수집 권리와 같은 근거다.
  final Set<int> litLevelIds;

  /// 현재 리비전의 최고 별. 기록이 없으면 0.
  final Map<int, int> bestStars;

  int get chapter => definition.chapter;
  int get litCount => levels.where((l) => litLevelIds.contains(l.id)).length;
  bool isLit(int levelId) => litLevelIds.contains(levelId);
  bool get complete => litCount == levels.length;
  int get stars => bestStars.values.fold(0, (total, value) => total + value);
  int get maxStars => levels.length * 3;
  bool get golden => levels.every((l) => bestStars[l.id] == 3);

  /// 과거 리비전으로만 완료해 현재 버전 기록이 없는 별문.
  bool needsNewVersion(int levelId) =>
      isLit(levelId) && (bestStars[levelId] ?? 0) == 0;

  int nodeIndexOf(int levelId) => levels.indexWhere((l) => l.id == levelId);
  List<bool> get litMask => [for (final l in levels) isLit(l.id)];
}

/// 연출이 소비하는 변화. 저장이 성공한 뒤의 두 스냅샷 차이로만 만든다.
class ConstellationEvent {
  const ConstellationEvent({
    required this.chapter,
    required this.nodeIndex,
    required this.newNode,
    required this.chapterCompleted,
    required this.becameGolden,
  });

  final int chapter;
  final int nodeIndex;
  final bool newNode;
  final bool chapterCompleted;
  final bool becameGolden;

  bool get isEmpty => !newNode && !chapterCompleted && !becameGolden;
}

class ConstellationAtlas {
  ConstellationAtlas._(this.chapters);

  final List<ChapterConstellation> chapters;

  /// 다섯 레벨짜리 챕터 중 별자리 정의가 있는 것만 포함한다.
  static ConstellationAtlas derive(
    List<Level> levels,
    ProgressRepository progress,
  ) {
    final persisted = progress.completedCampaignLevelIds;
    return ConstellationAtlas._([
      for (final group in ChapterProgress.group(levels, progress))
        if (ConstellationCatalog.forChapter(group.number) case final definition?
            when group.levels.length == definition.nodes.length)
          ChapterConstellation._(
            definition: definition,
            levels: List.unmodifiable(group.levels),
            litLevelIds: {
              for (final level in group.levels)
                if (persisted.contains(level.id)) level.id,
            },
            bestStars: {
              for (final level in group.levels)
                level.id:
                    progress
                        .forLevel(level.id, revision: level.revision)
                        ?.bestStars ??
                    0,
            },
          ),
    ]);
  }

  ChapterConstellation? forLevel(int levelId) =>
      chapters.where((c) => c.nodeIndexOf(levelId) >= 0).firstOrNull;

  ChapterConstellation? forChapter(int chapter) =>
      chapters.where((c) => c.chapter == chapter).firstOrNull;

  int get litCount => chapters.fold(0, (total, c) => total + c.litCount);

  /// 같은 레벨의 이전/이후 스냅샷을 비교한다. 별자리에 속하지 않으면 null.
  static ConstellationEvent? diff(
    ConstellationAtlas before,
    ConstellationAtlas after,
    int levelId,
  ) {
    final previous = before.forLevel(levelId);
    final next = after.forLevel(levelId);
    if (previous == null || next == null) return null;
    return ConstellationEvent(
      chapter: next.chapter,
      nodeIndex: next.nodeIndexOf(levelId),
      newNode: !previous.isLit(levelId) && next.isLit(levelId),
      chapterCompleted: !previous.complete && next.complete,
      becameGolden: !previous.golden && next.golden,
    );
  }
}
