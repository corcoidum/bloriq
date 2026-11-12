import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../audio/game_audio.dart';
import '../domain/puzzle.dart';
import '../progress/last_played.dart';
import '../progress/progress_repository.dart';
import '../tutorial/echo_tutorial.dart';
import '../daily/daily_repository.dart';
import '../analytics/local_analytics.dart';
import '../story/story_catalog.dart';
import '../story/collection_repository.dart';
import '../constellation/constellation_state.dart';
import '../progression/progression_repository.dart';
import '../game/assist.dart';
import '../world/saga.dart';
import '../world/world_catalog.dart';
import '../world/world_progress.dart';
import '../world/world_theme.dart';
import '../endless/endless_pool.dart';
import '../endless/endless_repository.dart';
import '../endless/endless_rules.dart';
import '../trials/trial_catalog.dart';
import '../trials/trial_repository.dart';
import '../progression/progression_rules.dart';
import '../weekly/weekly_pool.dart';
import '../weekly/weekly_repository.dart';

/// 홈 "이어가기"가 하는 일.
enum ContinueKind {
  /// 진행 중인 세계의 다음 판.
  next,

  /// 막 열린 세계의 첫 판.
  newWorld,

  /// 모두 깼고, 별 3개가 안 된 판을 다시.
  polish,

  /// 모든 판이 별 3개라 별바다 항해로.
  voyage,

  /// 더 할 것이 없어 첫 판을 다시.
  replay,
}

/// 홈 "이어가기"가 가리키는 곳. 저장하지 않고 기록에서 매번 계산한다.
class ContinueTarget {
  const ContinueTarget(this.kind, this.world, [this.levelId]);
  final ContinueKind kind;

  /// 홈이 "지금 여기"로 보여 줄 세계.
  final int world;

  /// 열 판. [ContinueKind.voyage]일 때만 null.
  final int? levelId;
}

/// 모든 세계를 합친 진행 요약.
typedef OverallProgress = ({
  int cleared,
  int total,
  int stars,
  int friends,
  int friendTotal,
});

typedef TrialClearResult = ({bool saved, int cleared, bool newReward});
typedef WeeklyClearResult = ({bool saved, int cleared, bool newReward});

/// 홈과 게임은 하나의 기록/오디오 인스턴스를 공유한다.
class GameSession {
  GameSession({
    required List<Level> levels,
    required this.progress,
    required this.audio,
    required this.onboarding,
    required this.daily,
    required this.analytics,
    required this.story,
    required this.collection,
    required this.progression,
    required this.endless,
    TrialRepository? trialProgress,
    WeeklyRepository? weekly,
    this.saga,
    LastPlayedRepository? lastPlayed,
    Iterable<LoadedWorld> worlds = const [],
    Map<int, WorldBoardSkin> boardSkins = const {},
  }) : levels = List.unmodifiable(levels),
       trialProgress = trialProgress ?? TrialRepository.memory(),
       weekly = weekly ?? WeeklyRepository.memory(clock: daily.clock),
       lastPlayed = lastPlayed ?? LastPlayedRepository.memory(),
       worlds = Map.unmodifiable({
         for (final world in worlds) world.number: world,
       }),
       _boardSkins = Map.of(boardSkins) {
    if (levels.isEmpty) throw const FormatException('No levels');
    WidgetsBinding.instance.addObserver(audio);
    audio.setGameVisible(false);
  }

  final List<Level> levels;
  final ProgressRepository progress;

  /// 마지막으로 연 캠페인 판. 홈 "이어가기"가 막힌 판으로 돌아가는 데 쓴다.
  final LastPlayedRepository lastPlayed;
  final GameAudio audio;
  final Onboarding onboarding;
  final DailyRepository daily;
  final WeeklyRepository weekly;
  Future<WeeklyPool>? _weeklyPool;
  final LocalAnalytics analytics;
  final StoryCatalog story;
  final CollectionRepository collection;

  /// 별지기 레벨·별가루·권능·유대. 처음 열 때 기존 기록을 한 번 환산한다.
  final ProgressionRepository progression;

  /// 별바다 항해(끝없는 모드) 기록과 진행 중인 항해.
  final EndlessRepository endless;
  Future<EndlessPool>? _endlessPool;

  /// 끝없는 모드 판 묶음. 처음 항해를 열 때 한 번 읽는다.
  Future<EndlessPool> get endlessPool => _endlessPool ??= EndlessPool.load();

  final TrialRepository trialProgress;
  Future<TrialCatalog>? _trialCatalog;

  /// 판 목록은 제작 때 굽고, 기기에서는 필요할 때 읽기만 한다.
  Future<TrialCatalog> get trialCatalog =>
      _trialCatalog ??= TrialCatalog.load();

  bool canPlayTrials(int world, {int? chapter}) =>
      worldUnlocked(world) &&
      (chapter == null
          ? Worlds.isComplete(world, progression.completedChapters)
          : progression.goldenChapters.contains(
              Worlds.globalChapter(world, chapter),
            ));

  Future<TrialClearResult> recordTrialClear(TrialStage stage, int moves) async {
    final stages = (await trialCatalog).forWorld(stage.world);
    if (!stages.contains(stage) ||
        !(canPlayTrials(stage.world) ||
            canPlayTrials(stage.world, chapter: stage.chapter))) {
      throw StateError('Trial is unavailable: ${stage.sourceId}');
    }
    final stored = await trialProgress.recordClear(stage, moves);
    final cleared = trialProgress.clearedCount(stages);
    final reward = stored && cleared == TrialCatalog.stagesPerWorld
        ? await progression.awardTrialReward(stage.world)
        : TrialRewardStatus.alreadyOwned;
    return (
      saved: stored && reward != TrialRewardStatus.saveFailed,
      cleared: cleared,
      newReward: reward == TrialRewardStatus.granted,
    );
  }

  Future<void> _restoreTrialRewards() async {
    if (!trialProgress.mayHaveCompletedWorld) return;
    try {
      final catalog = await trialCatalog;
      for (final world in trialRewards.keys) {
        if (trialProgress.clearedCount(catalog.forWorld(world)) ==
            TrialCatalog.stagesPerWorld) {
          await progression.awardTrialReward(world);
        }
      }
    } on Object catch (error) {
      debugPrint('Trials unavailable: $error');
    }
  }

  Future<WeeklyChallenge?> openWeekly(String week) async {
    if (weekly.forWeek(week) case final saved?) return saved;
    final WeeklyPool pool;
    try {
      pool = await (_weeklyPool ??= WeeklyPool.load(daily));
    } on Object {
      _weeklyPool = null;
      rethrow;
    }
    final chapters = progression.completedChapters;
    return weekly.assign(week, pool, {
      for (var world = 1; world <= Worlds.finalWorld; world++)
        if (Worlds.isComplete(world, chapters)) world,
    });
  }

  Future<WeeklyClearResult> recordWeeklyClear(
    WeeklyStage stage,
    int moves,
  ) async {
    final stored = await weekly.recordClear(stage, moves);
    final cleared = weekly.cleared(stage.week);
    final reward = stored && cleared == WeeklyPool.stageCount
        ? await progression.awardWeeklyReward(
            weekly.forWeek(stage.week)!.rotation,
          )
        : WeeklyRewardStatus.alreadyOwned;
    return (
      saved: stored && reward != WeeklyRewardStatus.saveFailed,
      cleared: cleared,
      newReward: reward == WeeklyRewardStatus.granted,
    );
  }

  /// 세계 1의 첫 별자리를 완성하면 별바다 항해가 열린다.
  bool get endlessUnlocked =>
      progression.completedChapters.contains(EndlessRules.unlockChapter);

  /// 판마다 얼마나 막혀 있는지(앱을 켜 둔 동안만). 막히면 도움을 권한다.
  final StruggleTracker struggle = StruggleTracker();

  /// 모든 세계를 꿰는 사가(assets/worlds/saga.json). 읽지 못하면 null이며
  /// 확장 세계와 빛길 지도도 숨긴다.
  final Saga? saga;

  /// 불러온 확장 세계(세계 2부터). 에셋이 깨진 세계는 빠지고 입구도 숨긴다.
  final Map<int, LoadedWorld> worlds;
  final Map<int, WorldBoardSkin> _boardSkins;
  final _boardSkinLoads = <int, Future<WorldBoardSkin?>>{};
  final _shownWorldGuides = <int>{};
  bool _disposed = false;

  LoadedWorld? world(int number) => worlds[number];
  WorldBoardSkin? boardSkin(int number) => _boardSkins[number];

  /// 현재 플레이할 세계의 텍스처만 디코딩해 홈이 모든 그림을 기다리지 않게 한다.
  Future<WorldBoardSkin?> prepareBoardSkin(int number) async {
    if (_disposed) return null;
    final loaded = _boardSkins[number];
    if (loaded != null) return loaded;
    final theme = saga?.world(number).theme;
    if (theme == null) return null;
    return _boardSkinLoads.putIfAbsent(number, () async {
      final skin = await theme.loadBoardSkin();
      if (_disposed) {
        skin.dispose();
        return null;
      }
      return _boardSkins[number] = skin;
    });
  }

  /// 첫 판 기록과 세션 상태로 안내를 관리한다.
  bool takeWorldGuide(Level level) {
    if (level.id != Worlds.firstLevelId(level.world) ||
        progress.forLevel(level.id, revision: level.revision) != null) {
      return false;
    }
    return _shownWorldGuides.add(level.world);
  }

  /// 앞 세계의 다섯 별자리를 모두 완성했고 이 세계 데이터가 준비됐는지.
  bool worldUnlocked(int number) =>
      number == 1 ||
      (worlds.containsKey(number) &&
          Worlds.isUnlocked(number, progression.completedChapters));

  bool get sagaComplete =>
      worldUnlocked(Worlds.finalWorld) &&
      Worlds.isComplete(Worlds.finalWorld, progression.completedChapters);

  WorldAtlas? worldAtlas(int number) => switch (worlds[number]) {
    final world? => WorldAtlas.derive(world, progress),
    null => null,
  };

  Map<int, int> get starflowersByWorld => {
    for (final world in worlds.values)
      world.number: progress.starflowerCount(world.levels),
  };

  /// 세계 안에서 깬 스테이지 수(사가 지도 진행 표시).
  int clearedInWorld(int number) =>
      number == 1 ? completedCount : worldAtlas(number)?.cleared ?? 0;

  /// 홈 입구가 가리킬 확장 세계: 열린 세계 중 아직 다 못 마친 첫 세계,
  /// 모두 마쳤으면 마지막으로 열린 세계. 열린 확장 세계가 없으면 null.
  int? get currentExpansionWorld {
    final open = [
      for (final number in worlds.keys.toList()..sort())
        if (worldUnlocked(number)) number,
    ];
    return open
            .where(
              (number) =>
                  !Worlds.isComplete(number, progression.completedChapters),
            )
            .firstOrNull ??
        open.lastOrNull;
  }

  static Future<GameSession> load({
    Future<List<Level>> Function()? loadLevels,
    void Function(Onboarding)? onOnboardingReady,
    DateTime Function()? clock,
  }) async {
    final progress = await ProgressRepository.load();
    final onboarding = await Onboarding.load(
      returningPlayer: progress.hasAnyProgress || progress.hasHistoricalStorage,
    );
    onOnboardingReady?.call(onboarding);
    final levels = loadLevels != null
        ? await loadLevels()
        : (jsonDecode(await rootBundle.loadString('assets/levels/levels.json'))
                  as List<dynamic>)
              .map((item) => Level.fromJson(item as Map<String, dynamic>))
              .toList();
    if (levels.isEmpty ||
        levels.map((level) => level.id).toSet().length != levels.length) {
      throw const FormatException('Empty or duplicate levels');
    }
    final story = await StoryCatalog.load();
    final collection = await CollectionRepository.load(story);
    if (!progress.saveFailed) {
      await collection.reconcile(
        progress.completedCampaignLevelIds,
        backfill: true,
      );
    }
    final progression = await ProgressionRepository.load();
    if (!progress.saveFailed && !progression.backfilled) {
      final atlas = ConstellationAtlas.derive(levels, progress);
      await progression.backfill(
        records: [
          for (final level in levels)
            if (progress.forLevel(level.id, revision: level.revision)
                case final record?)
              (
                levelKey: '${level.id}:${level.revision}',
                bestStars: record.bestStars,
              ),
        ],
        completedChapters: {
          for (final chapter in atlas.chapters)
            if (chapter.complete) chapter.definition.chapter,
        },
        goldenChapters: {
          for (final chapter in atlas.chapters)
            if (chapter.golden) chapter.definition.chapter,
        },
      );
    }
    final daily = await DailyRepository.load(clock: clock);
    final weekly = await WeeklyRepository.load(clock: clock);
    // 클리어와 보상 사이에 앱이 종료됐으면 다음 실행에서 이어서 지급한다.
    for (final rotation in weekly.completedRotations) {
      await progression.awardWeeklyReward(rotation);
    }
    final analytics = await LocalAnalytics.load(clock: clock);
    final audio = await GameAudio.load();
    final endless = await EndlessRepository.load(clock: clock);
    Saga? saga;
    final worlds = <LoadedWorld>[];
    try {
      saga = await Saga.load();
    } on Object catch (error) {
      debugPrint('Saga unavailable: $error');
    }
    for (final info in saga?.worlds ?? const <SagaWorld>[]) {
      if (!info.playable) continue;
      try {
        if (info.expansion) worlds.add(await LoadedWorld.load(info));
      } on Object catch (error) {
        // 한 세계가 깨져도 나머지 세계는 그대로 플레이할 수 있어야 한다.
        debugPrint('World ${info.number} unavailable: $error');
      }
    }
    final session = GameSession(
      levels: levels,
      progress: progress,
      lastPlayed: await LastPlayedRepository.load(),
      audio: audio,
      onboarding: onboarding,
      daily: daily,
      weekly: weekly,
      analytics: analytics,
      story: story,
      collection: collection,
      progression: progression,
      endless: endless,
      trialProgress: await TrialRepository.load(),
      saga: saga,
      worlds: worlds,
    );
    await progress.backfillStageChallenges(
      worlds.expand((world) => world.levels),
      hasBareHandedStar: progression.isBareHandedLevel,
    );
    await progression.reconcileStarflowerAchievements(
      session.starflowersByWorld,
    );
    await session._restoreTrialRewards();
    return session;
  }

  int get nextLevelId => levels
      .firstWhere(
        (level) =>
            progress.forLevel(level.id, revision: level.revision) == null,
        orElse: () => levels.first,
      )
      .id;

  /// 열려 있는 세계 번호(세계 1 포함), 작은 번호부터.
  List<int> get openWorlds => [
    1,
    for (final number in worlds.keys.toList()..sort())
      if (worldUnlocked(number)) number,
  ];

  /// 홈 "이어가기"가 갈 곳. 마지막으로 열었다가 못 깬 판이 있으면 그 판,
  /// 없으면 가장 멀리 온 세계의 열린 판, 앞 세계에 남은 판,
  /// 별 3개가 안 된 판 순서로 찾는다.
  ContinueTarget get continueTarget {
    final open = openWorlds;
    final atlases = <int, WorldAtlas>{
      for (final number in open) number: ?worldAtlas(number),
    };
    WorldStageView? openStage(int number) => atlases[number]?.stages
        .where((stage) => stage.unlocked && !stage.cleared)
        .firstOrNull;

    // 마지막으로 연 판을 아직 못 깼으면 그 판으로 돌아간다.
    final last = lastPlayed.levelId;
    if (last != null) {
      final first = levels.where((level) => level.id == last).firstOrNull;
      final world = first != null ? 1 : Worlds.worldOf(last);
      final stuck = first != null
          ? progress.forLevel(last, revision: first.revision) == null
          : atlases[world]?.stages.any(
                  (stage) =>
                      stage.level.id == last &&
                      stage.unlocked &&
                      !stage.cleared,
                ) ??
                false;
      if (stuck) return ContinueTarget(ContinueKind.next, world, last);
    }

    final current = currentExpansionWorld;
    if (current != null) {
      if (openStage(current) case final stage?) {
        return ContinueTarget(
          atlases[current]!.cleared == 0
              ? ContinueKind.newWorld
              : ContinueKind.next,
          current,
          stage.level.id,
        );
      }
    }
    if (completedCount < levels.length) {
      return ContinueTarget(ContinueKind.next, 1, nextLevelId);
    }
    for (final number in open) {
      if (openStage(number) case final stage?) {
        return ContinueTarget(ContinueKind.next, number, stage.level.id);
      }
    }
    for (final level in levels) {
      final stars =
          progress.forLevel(level.id, revision: level.revision)?.bestStars ?? 0;
      if (stars < 3) return ContinueTarget(ContinueKind.polish, 1, level.id);
    }
    for (final number in open) {
      final stage = atlases[number]?.stages
          .where((stage) => stage.cleared && stage.stars < 3)
          .firstOrNull;
      if (stage != null) {
        return ContinueTarget(ContinueKind.polish, number, stage.level.id);
      }
    }
    return endlessUnlocked
        ? ContinueTarget(ContinueKind.voyage, open.last)
        : ContinueTarget(ContinueKind.replay, 1, levels.first.id);
  }

  /// 모든 세계를 합친 판·별·친구 수. 아직 잠긴 세계도 전체 수에 넣는다.
  OverallProgress get overall {
    var cleared = completedCount;
    var total = levels.length;
    var stars = totalStars;
    var friends = collection.owned.length;
    var friendTotal = story.released.length;
    for (final world in worlds.values) {
      final atlas = WorldAtlas.derive(world, progress);
      total += world.levels.length;
      friendTotal += world.levels.length;
      cleared += atlas.cleared;
      friends += atlas.cleared;
      stars += atlas.stages.fold(0, (sum, stage) => sum + stage.stars);
    }
    return (
      cleared: cleared,
      total: total,
      stars: stars,
      friends: friends,
      friendTotal: friendTotal,
    );
  }

  StoryChapter get recommendedChapter => story.chapterForLevel(
    completedCount == levels.length ? levels.last.id : nextLevelId,
  );
  int completedInChapter(int number) => levels
      .where(
        (l) =>
            story.forLevel(l.id)?.chapter == number &&
            progress.forLevel(l.id, revision: l.revision) != null,
      )
      .length;
  int get completedCount => levels
      .where(
        (level) =>
            progress.forLevel(level.id, revision: level.revision) != null,
      )
      .length;
  int get totalStars => levels.fold(
    0,
    (total, level) =>
        total +
        (progress.forLevel(level.id, revision: level.revision)?.bestStars ?? 0),
  );

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await progress.flush();
    await collection.flush();
    await progression.flush();
    analytics.dispose();
    await daily.flush();
    await weekly.flush();
    await endless.flush();
    await trialProgress.flush();
    await audio.dispose();
    for (final skin in _boardSkins.values) {
      skin.dispose();
    }
    _boardSkins.clear();
    _boardSkinLoads.clear();
  }
}
