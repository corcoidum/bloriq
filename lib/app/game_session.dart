import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../audio/game_audio.dart';
import '../domain/puzzle.dart';
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
    this.saga,
    Iterable<LoadedWorld> worlds = const [],
    Map<int, WorldBoardSkin> boardSkins = const {},
  }) : levels = List.unmodifiable(levels),
       worlds = Map.unmodifiable({
         for (final world in worlds) world.number: world,
       }),
       _boardSkins = Map.unmodifiable(boardSkins) {
    if (levels.isEmpty) throw const FormatException('No levels');
    WidgetsBinding.instance.addObserver(audio);
    audio.setGameVisible(false);
  }

  final List<Level> levels;
  final ProgressRepository progress;
  final GameAudio audio;
  final Onboarding onboarding;
  final DailyRepository daily;
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
  bool _mirrorGuideShown = false;

  LoadedWorld? world(int number) => worlds[number];
  WorldBoardSkin? boardSkin(int number) => _boardSkins[number];

  /// 첫 판 기록과 세션 상태로 안내를 관리한다.
  bool takeMirrorGuide(Level level) {
    if (_mirrorGuideShown ||
        level.id != Worlds.firstLevelId(3) ||
        progress.forLevel(level.id, revision: level.revision) != null) {
      return false;
    }
    _mirrorGuideShown = true;
    return true;
  }

  /// 앞 세계의 다섯 별자리를 모두 완성했고 이 세계 데이터가 준비됐는지.
  bool worldUnlocked(int number) =>
      number == 1 ||
      (worlds.containsKey(number) &&
          Worlds.isUnlocked(number, progression.completedChapters));

  WorldAtlas? worldAtlas(int number) => switch (worlds[number]) {
    final world? => WorldAtlas.derive(world, progress),
    null => null,
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
    final analytics = await LocalAnalytics.load(clock: clock);
    final audio = await GameAudio.load();
    final endless = await EndlessRepository.load(clock: clock);
    Saga? saga;
    final worlds = <LoadedWorld>[];
    final boardSkins = <int, WorldBoardSkin>{};
    try {
      saga = await Saga.load();
    } on Object catch (error) {
      debugPrint('Saga unavailable: $error');
    }
    for (final info in saga?.worlds ?? const <SagaWorld>[]) {
      if (!info.playable) continue;
      try {
        if (info.expansion) worlds.add(await LoadedWorld.load(info));
        if (info.theme case final theme?) {
          boardSkins[info.number] = await theme.loadBoardSkin();
        }
      } on Object catch (error) {
        // 한 세계가 깨져도 나머지 세계는 그대로 플레이할 수 있어야 한다.
        debugPrint('World ${info.number} unavailable: $error');
      }
    }
    return GameSession(
      levels: levels,
      progress: progress,
      audio: audio,
      onboarding: onboarding,
      daily: daily,
      analytics: analytics,
      story: story,
      collection: collection,
      progression: progression,
      endless: endless,
      saga: saga,
      worlds: worlds,
      boardSkins: boardSkins,
    );
  }

  int get nextLevelId => levels
      .firstWhere(
        (level) =>
            progress.forLevel(level.id, revision: level.revision) == null,
        orElse: () => levels.first,
      )
      .id;

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
    await progress.flush();
    await collection.flush();
    await progression.flush();
    analytics.dispose();
    await daily.flush();
    await endless.flush();
    await audio.dispose();
    for (final skin in _boardSkins.values) {
      skin.dispose();
    }
  }
}
