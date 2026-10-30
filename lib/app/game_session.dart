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
  }) : levels = List.unmodifiable(levels) {
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
    final daily = await DailyRepository.load(clock: clock);
    final analytics = await LocalAnalytics.load(clock: clock);
    final audio = await GameAudio.load();
    return GameSession(
      levels: levels,
      progress: progress,
      audio: audio,
      onboarding: onboarding,
      daily: daily,
      analytics: analytics,
      story: story,
      collection: collection,
    );
  }

  int get nextLevelId => levels
      .firstWhere(
        (level) =>
            progress.forLevel(level.id, revision: level.revision) == null,
        orElse: () => levels.first,
      )
      .id;

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
    analytics.dispose();
    await daily.flush();
    await audio.dispose();
  }
}
