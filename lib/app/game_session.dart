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
import '../world2/world2_catalog.dart';
import '../world2/world2_progress.dart';

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
    List<Level> world2Levels = const [],
    this.world2Story,
  }) : levels = List.unmodifiable(levels),
       world2Levels = List.unmodifiable(world2Levels) {
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

  /// 구름바다 등대(월드 2). 에셋을 읽지 못하면 비어 있고 입구도 숨긴다.
  final List<Level> world2Levels;
  final World2Story? world2Story;

  /// 월드 1 다섯 별자리를 모두 완성했고 월드 2 데이터가 준비됐는지.
  bool get world2Unlocked =>
      world2Story != null &&
      world2Levels.isNotEmpty &&
      World2.isUnlocked(progression.completedChapters);

  World2Atlas? get world2Atlas => world2Story == null || world2Levels.isEmpty
      ? null
      : World2Atlas.derive(world2Levels, world2Story!, progress);

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
    var world2Levels = const <Level>[];
    World2Story? world2Story;
    try {
      world2Levels = await World2.loadLevels();
      world2Story = await World2Story.load();
    } on Object catch (error) {
      // 월드 2가 깨져도 월드 1은 그대로 플레이할 수 있어야 한다.
      debugPrint('World 2 unavailable: $error');
      world2Levels = const [];
      world2Story = null;
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
      world2Levels: world2Levels,
      world2Story: world2Story,
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
    await audio.dispose();
  }
}
