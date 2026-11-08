import 'dart:convert';
import 'dart:io';

import 'package:bloriq/story/story_catalog.dart';
import 'package:bloriq/story/collection_repository.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StoryCatalog catalog;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    catalog = StoryCatalog.fromJson(
      jsonDecode(File('assets/story/season1.json').readAsStringSync()),
    );
  });
  test('old five friends expand to 25, preserve buddy/seen state and show only one backfill summary', () async {
    final prefs = await SharedPreferences.getInstance();
    final original = {
      'version': 1,
      'owned': [
        for (var i = 1; i <= 5; i++) 's1-${i.toString().padLeft(2, '0')}',
      ],
      'memories': [
        for (var i = 1; i <= 5; i++)
          's1-memory-${i.toString().padLeft(2, '0')}',
      ],
      'seen': ['s1-01', 's1-05'],
      'pending': ['s1-02'],
      'equipped': 's1-05',
      'backfillPending': false,
      'futureOptionalField': 'keep',
    };
    await prefs.setString(
      CollectionRepository.storageKey,
      jsonEncode(original),
    );
    final progress = await ProgressRepository.load();
    for (var id = 1; id <= 25; id++) {
      await progress.recordCompletion(
        levelId: id,
        revision: 1,
        moves: 2,
        minimumMoves: 2,
      );
    }
    final repo = await CollectionRepository.load(catalog);
    final added = await repo.reconcile(
      progress.completedCampaignLevelIds,
      backfill: true,
    );
    expect(added.length, 20);
    expect(repo.owned.length, 25);
    expect(repo.memoryIds.length, 25);
    expect(repo.companion?.id, 's1-05');
    expect(repo.hasSeen('s1-01'), true);
    expect(repo.pendingIds, {'s1-02'});
    expect(repo.backfillPending, true);
    for (var chapter = 1; chapter <= 5; chapter++) {
      expect(repo.chapterComplete(chapter), true);
      expect(repo.inChapter(chapter).length, 5);
    }
    await repo.acknowledgeBackfill();
    final restored = await CollectionRepository.load(catalog);
    expect(
      await restored.reconcile(
        progress.completedCampaignLevelIds,
        backfill: true,
      ),
      isEmpty,
    );
    expect(restored.backfillPending, false);
    expect(restored.companion?.id, 's1-05');
    expect(
      jsonDecode(
        prefs.getString(CollectionRepository.storageKey)!,
      )['futureOptionalField'],
      'keep',
    );
    expect((await ProgressRepository.load()).forLevel(25)!.completionCount, 1);
  });
  test('unpublished definition cannot grant a placeholder; stage IDs and chapter mapping are validated', () async {
    final raw = jsonDecode(
      File('assets/story/season1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    raw['spirits'][24]['released'] = false;
    raw['spirits'][24]['asset'] = null;
    final hidden = StoryCatalog.fromJson(raw);
    final repo = await CollectionRepository.load(hidden);
    expect(await repo.reconcile({25}), isEmpty);
    raw['spirits'][24]['memoryId'] = 's1-memory-24';
    expect(() => StoryCatalog.fromJson(raw), throwsFormatException);
  });
  test('partial write on newly released guardians recovers from progress without duplicate completions', () async {
    final progress = await ProgressRepository.load();
    for (final id in [10, 15, 20, 25]) {
      await progress.recordCompletion(levelId: id, moves: 2, minimumMoves: 2);
    }
    final failed = await CollectionRepository.load(
      catalog,
      writer: (_, _) async => false,
    );
    await failed.reconcile(progress.completedCampaignLevelIds);
    expect(failed.saveFailed, true);
    final restored = await CollectionRepository.load(catalog);
    await restored.reconcile(
      (await ProgressRepository.load()).completedCampaignLevelIds,
      backfill: true,
    );
    expect(restored.owned.map((s) => s.levelId), [10, 15, 20, 25]);
    for (final id in [10, 15, 20, 25]) {
      expect(progress.forLevel(id)!.completionCount, 1);
    }
  });
}
