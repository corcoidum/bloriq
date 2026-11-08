import 'dart:convert';
import 'dart:io';

import 'package:bloriq/analytics/local_analytics.dart';
import 'package:bloriq/daily/daily_repository.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/progress/chapter_progress.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Map<String, dynamic>> pool() => (jsonDecode(
  File('assets/levels/daily_pool_v1.json').readAsStringSync(),
) as List).cast<Map<String, dynamic>>();

class FakeWatch implements Stopwatch {
  int ms = 0;
  @override
  bool isRunning = false;
  void advance(int amount) {
    if (isRunning) ms += amount;
  }

  @override
  void start() {
    isRunning = true;
  }

  @override
  void stop() {
    isRunning = false;
  }

  @override
  void reset() {
    ms = 0;
  }

  @override
  int get elapsedMilliseconds => ms;
  @override
  int get elapsedMicroseconds => ms * 1000;
  @override
  int get elapsedTicks => ms;
  @override
  int get frequency => 1000;
  @override
  Duration get elapsed => Duration(milliseconds: ms);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'Daily keeps date assignment across reload and different pool versions',
    () async {
      var now = DateTime(2026, 10, 29, 23, 59);
      final daily = await DailyRepository.load(clock: () => now, pool: pool());
      final first = daily.today;
      await daily.markPlayed(first);
      await daily.recordCompletion(first, first.level.minimumMoves);
      await daily.flush();
      final otherPool = [pool().last];
      final reloaded = await DailyRepository.load(
        clock: () => now,
        pool: otherPool,
        poolVersion: 2,
      );
      expect(reloaded.today.level.id, first.level.id);
      expect(reloaded.today.poolVersion, 1);
      now = DateTime(2026, 10, 30);
      final tomorrow = reloaded.today;
      expect(tomorrow.poolVersion, 2);
      await reloaded.recordCompletion(first, first.level.minimumMoves);
      expect(reloaded.completed('2026-10-29'), true);
      expect(reloaded.completed('2026-10-30'), false);
      expect((await ProgressRepository.load()).hasAnyProgress, false);
      await reloaded.flush();
    },
  );
  test('civil-day selection handles leap days and offset-independent day intervals', () async {
    var now = DateTime(2028, 2, 28);
    final daily = await DailyRepository.load(clock: () => now, pool: pool());
    final ids = <int>[];
    for (final date in [
      DateTime(2028, 2, 28),
      DateTime(2028, 2, 29),
      DateTime(2028, 3, 1),
      DateTime(2026, 3, 8),
      DateTime(2026, 3, 9),
    ]) {
      now = date;
      final challenge = daily.today;
      ids.add(challenge.level.id);
      final ordinal = DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).difference(DateTime.utc(1970)).inDays;
      expect(challenge.level.id, pool()[ordinal % 20]['id']);
    }
    expect(ids.take(3).toSet(), hasLength(3));
    await daily.flush();
  });
  test('seven days and streak use actual moves, retain future history after clock rollback', () async {
    var now = DateTime(2026, 10, 29);
    final daily = await DailyRepository.load(clock: () => now, pool: pool());
    final first = daily.today;
    expect(daily.streak, 0);
    await daily.markPlayed(first);
    expect(daily.streak, 1);
    now = DateTime(2026, 10, 30);
    expect(daily.streak, 1);
    await daily.markPlayed(daily.today);
    expect(daily.streak, 2);
    expect(daily.recentDays.map(localDateKey).toList(), [
      '2026-10-24',
      '2026-10-25',
      '2026-10-26',
      '2026-10-27',
      '2026-10-28',
      '2026-10-29',
      '2026-10-30',
    ]);
    now = DateTime(2026, 10, 28);
    expect(daily.streak, 0);
    expect(daily.participated('2026-10-30'), true);
    await daily.flush();
  });
  test(
    'future Daily schema is not overwritten and invalid scores are rejected',
    () async {
      final raw = jsonEncode({'version': 88, 'days': {}});
      SharedPreferences.setMockInitialValues({DailyRepository.storageKey: raw});
      final daily = await DailyRepository.load(pool: pool());
      await daily.markPlayed(daily.today);
      await daily.flush();
      expect(daily.saveFailed, true);
      expect(
        (await SharedPreferences.getInstance()).getString(
          DailyRepository.storageKey,
        ),
        raw,
      );
      expect(() => daily.recordCompletion(daily.today, 0), throwsArgumentError);
    },
  );
  test('chapter counts ignore archived revisions', () async {
    final repo = await ProgressRepository.load();
    await repo.recordCompletion(
      levelId: 2,
      revision: 1,
      moves: 4,
      minimumMoves: 4,
    );
    final levels = (jsonDecode(
      File('assets/levels/levels.json').readAsStringSync(),
    ) as List).map((raw) => Level.fromJson(raw)).toList();
    var chapters = ChapterProgress.group(levels, repo);
    expect(chapters, hasLength(5));
    expect(chapters.first.completed, 0);
    await repo.recordCompletion(
      levelId: 2,
      revision: 2,
      moves: 4,
      minimumMoves: 4,
    );
    chapters = ChapterProgress.group(levels, repo);
    expect(chapters.first.completed, 1);
    expect(chapters.first.stars, 3);
    expect(chapters.first.recommendedLevelId, 1);
  });
  test('consent gates identity and events; revoke, delete and reload preserve choice', () async {
    final analytics = await LocalAnalytics.load();
    analytics.record('level_start', {'levelId': 1});
    expect(analytics.eventCount, 0);
    expect(analytics.snapshot()['participantId'], isNull);
    expect(
      (await SharedPreferences.getInstance()).containsKey(
        LocalAnalytics.storageKey,
      ),
      false,
    );
    await analytics.setEnabled(true);
    analytics.record('first_move', {
      'levelId': 1,
      'name': 'PRIVATE',
      'path': 'PRIVATE',
    });
    final exported = analytics.snapshot();
    expect(exported['participantId'], isNotNull);
    expect(jsonEncode(exported), isNot(contains('PRIVATE')));
    final count = analytics.eventCount;
    await analytics.setEnabled(false);
    analytics.record('level_start');
    expect(analytics.eventCount, count);
    await analytics.clear();
    expect(analytics.eventCount, 0);
    expect(analytics.enabled, false);
    expect(analytics.snapshot()['participantId'], isNull);
    analytics.dispose();
    await analytics.flush();
    final loaded = await LocalAnalytics.load();
    expect(loaded.enabled, false);
    expect(loaded.consentKnown, true);
    expect(loaded.eventCount, 0);
    loaded.dispose();
  });
  test('retention and cap annotate dropped events instead of implying complete followup', () async {
    var now = DateTime(2026, 1, 1);
    final analytics = await LocalAnalytics.load(clock: () => now);
    await analytics.setEnabled(true);
    now = DateTime(2026, 2, 2);
    analytics.record('level_start');
    expect(analytics.snapshot()['droppedEvents'], greaterThan(0));
    for (var i = 0; i < 10005; i++) {
      analytics.record('undo_used');
    }
    expect(analytics.eventCount, 10000);
    await analytics.flush();
    analytics.dispose();
    await analytics.flush();
  });
  test(
    'attempt timer excludes modal and background time, with one completion',
    () async {
      final analytics = await LocalAnalytics.load();
      await analytics.setEnabled(true);
      final watch = FakeWatch();
      final attempt = AttemptRecorder(analytics, {'levelId': 1}, watch: watch);
      watch.advance(1000);
      attempt.pause();
      watch.advance(9000);
      attempt.foreground(false);
      attempt.resume();
      watch.advance(9000);
      attempt.foreground(true);
      watch.advance(2000);
      attempt.moved(echo: true);
      attempt.undo();
      attempt.moved(echo: true);
      attempt.finish('level_complete', 1);
      attempt.finish('level_complete', 1);
      final events = analytics.snapshot()['events'] as List;
      final completed = events
          .where((event) => event['name'] == 'level_complete')
          .single;
      expect(completed['activeMs'], 3000);
      expect(completed['validMoves'], 2);
      expect(completed['undoCount'], 1);
      expect(
        events.where((event) => event['name'] == 'first_echo'),
        hasLength(1),
      );
      analytics.dispose();
      await analytics.flush();
    },
  );
  test(
    'future analytics store stays untouched even after consent attempt',
    () async {
      final raw = jsonEncode({'version': 9, 'secret': 'future-format'});
      SharedPreferences.setMockInitialValues({LocalAnalytics.storageKey: raw});
      final analytics = await LocalAnalytics.load();
      await analytics.setEnabled(true);
      analytics.record('first_move');
      await analytics.flush();
      expect(analytics.enabled, false);
      expect(analytics.eventCount, 0);
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalAnalytics.storageKey,
        ),
        raw,
      );
      analytics.dispose();
    },
  );
}
