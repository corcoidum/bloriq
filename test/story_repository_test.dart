import 'dart:convert';
import 'dart:io';

import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/story/collection_repository.dart';
import 'package:bloriq/story/story_catalog.dart';
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

  test('25 stable bilingual released assets and five chapter guardians', () {
    expect(catalog.spirits.length, 25);
    expect(catalog.released.length, 25);
    expect(catalog.spirits.where((s) => s.guardian).map((s) => s.levelId), [
      5,
      10,
      15,
      20,
      25,
    ]);
    for (final s in catalog.spirits) {
      expect(s.name.ko, isNotEmpty);
      expect(s.name.en, isNotEmpty);
      expect(s.memory.ko, isNotEmpty);
      expect(s.memory.en, isNotEmpty);
      if (s.released) {
        expect(File(s.asset!).existsSync(), true);
      } else {
        expect(s.asset, isNull);
      }
    }
  });

  test(
    'each released stage grants once and first completion auto equips Mori',
    () async {
      final repo = await CollectionRepository.load(catalog);
      expect((await repo.reconcile({1})).map((s) => s.id), ['s1-01']);
      expect(repo.companion?.id, 's1-01');
      expect(repo.pendingIds, {'s1-01'});
      expect(repo.memoryIds, {'s1-memory-01'});
      expect((await repo.reconcile({1, 6, 25})).map((s) => s.id), [
        's1-06',
        's1-25',
      ]);
      final restored = await CollectionRepository.load(catalog);
      expect(restored.ownedIds, {'s1-01', 's1-06', 's1-25'});
      expect(restored.pendingIds, {'s1-01', 's1-06', 's1-25'});
      await restored.acknowledge('s1-01');
      final again = await CollectionRepository.load(catalog);
      expect(again.hasSeen('s1-01'), true);
      expect(again.pendingIds, {'s1-06', 's1-25'});
    },
  );

  test(
    'backfill uses old revisions of course2, never unrelated legacy course',
    () async {
      SharedPreferences.setMockInitialValues({
        ProgressRepository.course2StorageKey: jsonEncode({
          'version': 1,
          'levels': [
            {
              'levelId': 2,
              'bestMoves': 4,
              'bestStars': 3,
              'completionCount': 2,
            },
          ],
        }),
        ProgressRepository.legacyStorageKey: jsonEncode({
          'version': 1,
          'levels': [
            {
              'levelId': 1,
              'bestMoves': 2,
              'bestStars': 3,
              'completionCount': 8,
            },
          ],
        }),
      });
      final progress = await ProgressRepository.load();
      final repo = await CollectionRepository.load(catalog);
      await repo.reconcile(progress.completedCampaignLevelIds, backfill: true);
      expect(repo.ownedIds, {'s1-02'});
      expect(progress.forLevel(2, revision: 2), isNull);
      expect(progress.forLevel(2)!.completionCount, 2);
      expect(repo.backfillPending, true);
      expect(repo.pendingIds, isEmpty);
      await repo.acknowledgeBackfill();
      await repo.reconcile(progress.completedCampaignLevelIds, backfill: true);
      expect((await CollectionRepository.load(catalog)).backfillPending, false);
    },
  );

  test('partial save and interrupted reveal recover from durable completion without recounting', () async {
    final progress = await ProgressRepository.load();
    await progress.recordCompletion(levelId: 1, moves: 2, minimumMoves: 2);
    final failed = await CollectionRepository.load(
      catalog,
      writer: (_, _) async => false,
    );
    await failed.reconcile(progress.completedCampaignLevelIds);
    expect(failed.saveFailed, true);
    expect(failed.owns('s1-01'), true);
    final restored = await CollectionRepository.load(catalog);
    await restored.reconcile(
      (await ProgressRepository.load()).completedCampaignLevelIds,
      backfill: true,
    );
    expect(restored.ownedIds, {'s1-01'});
    expect(progress.forLevel(1)!.completionCount, 1);
    final pending = await CollectionRepository.load(catalog);
    await pending.reconcile({1, 2});
    expect((await CollectionRepository.load(catalog)).pendingIds, {'s1-02'});
  });

  test(
    'retry snapshots do not increment progress and preserve companion choice',
    () async {
      var fail = true;
      final prefs = await SharedPreferences.getInstance();
      final progress = await ProgressRepository.load(
        writer: (key, value) async =>
            fail ? false : prefs.setString(key, value),
      );
      expect(
        (await progress.recordCompletion(
          levelId: 1,
          moves: 2,
          minimumMoves: 2,
        )).saved,
        false,
      );
      expect(
        progress.completedCampaignLevelIds,
        isEmpty,
        reason: 'Unsaved completion cannot grant a durable spirit',
      );
      fail = false;
      expect(await progress.retrySave(), true);
      expect(progress.completedCampaignLevelIds, {1});
      expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 1);
      final repo = await CollectionRepository.load(catalog);
      await repo.reconcile({1, 2});
      expect(await repo.equip('s1-05'), false);
      expect(await repo.equip('s1-02'), true);
      await repo.reconcile({1, 2, 3, 4, 5, 25});
      expect((await CollectionRepository.load(catalog)).companion?.id, 's1-02');
      expect(repo.owned.length, 6);
    },
  );

  test('future collection schema never overwrites source or grants speculative ownership', () async {
    const raw = '{"version":99,"privateFutureField":"keep"}';
    SharedPreferences.setMockInitialValues({
      CollectionRepository.storageKey: raw,
    });
    final repo = await CollectionRepository.load(catalog);
    expect(repo.futureSchema, true);
    expect(await repo.reconcile({1, 2, 3}), isEmpty);
    expect(await repo.retrySave(), false);
    expect(await repo.recover({1}), false);
    expect(
      (await SharedPreferences.getInstance()).getString(
        CollectionRepository.storageKey,
      ),
      raw,
    );
  });

  test('corrupt album recovery first backs up exact source; failed backup cannot overwrite', () async {
    const raw = '{broken';
    SharedPreferences.setMockInitialValues({
      CollectionRepository.storageKey: raw,
    });
    final blocked = await CollectionRepository.load(
      catalog,
      writer: (_, _) async => false,
    );
    expect(await blocked.recover({1}), false);
    expect(blocked.corrupt, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(CollectionRepository.storageKey), raw);
    final repo = await CollectionRepository.load(catalog);
    expect(repo.corrupt, true);
    expect(await repo.recover({1, 5}), true);
    expect(prefs.getString(CollectionRepository.backupKey), raw);
    expect((await CollectionRepository.load(catalog)).ownedIds, {
      's1-01',
      's1-05',
    });
  });

  test(
    'serialized grants and acknowledgements retain newest snapshot',
    () async {
      final repo = await CollectionRepository.load(catalog);
      await Future.wait([
        repo.reconcile({1}),
        repo.reconcile({1, 2}),
        repo.reconcile({1, 2, 3}),
      ]);
      await repo.acknowledge('s1-02');
      final restored = await CollectionRepository.load(catalog);
      expect(restored.owned.length, 3);
      expect(restored.pendingIds, {'s1-01', 's1-03'});
      expect(restored.hasSeen('s1-02'), true);
    },
  );
}
