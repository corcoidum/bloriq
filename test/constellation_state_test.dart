import 'dart:convert';
import 'dart:io';

import 'package:bloriq/constellation/constellation_catalog.dart';
import 'package:bloriq/constellation/constellation_state.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<Level> _levels() =>
    (jsonDecode(File('assets/levels/levels.json').readAsStringSync()) as List)
        .map((e) => Level.fromJson(e as Map<String, dynamic>))
        .toList();

Future<CompletionResult> _clear(
  ProgressRepository repo,
  Level level, {
  int extraMoves = 0,
}) => repo.recordCompletion(
  levelId: level.id,
  revision: level.revision,
  moves: level.minimumMoves + extraMoves,
  minimumMoves: level.minimumMoves,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('catalog defines five nodes per chapter with valid edges', () {
    expect(ConstellationCatalog.all.map((c) => c.chapter), [1, 2, 3, 4, 5]);
    for (final c in ConstellationCatalog.all) {
      expect(c.nodes, hasLength(5));
      for (final node in c.nodes) {
        expect(node.dx, inInclusiveRange(0, 1));
        expect(node.dy, inInclusiveRange(0, 1));
      }
      for (final (a, b) in c.edges) {
        expect(a, inInclusiveRange(0, 4));
        expect(b, inInclusiveRange(0, 4));
        expect(a, isNot(b));
      }
    }
  });

  test('fresh progress shows five dormant constellations', () async {
    final atlas = ConstellationAtlas.derive(
      _levels(),
      await ProgressRepository.load(),
    );
    expect(atlas.chapters, hasLength(5));
    expect(atlas.litCount, 0);
    expect(atlas.chapters.every((c) => !c.complete && !c.golden), isTrue);
    expect(atlas.forLevel(25)!.chapter, 5);
    expect(atlas.forLevel(25)!.nodeIndexOf(25), 4);
  });

  test('first clear lights one node; replay does not light it again', () async {
    final levels = _levels();
    final repo = await ProgressRepository.load();
    final before = ConstellationAtlas.derive(levels, repo);
    await _clear(repo, levels[0], extraMoves: 2);
    final after = ConstellationAtlas.derive(levels, repo);
    final event = ConstellationAtlas.diff(before, after, 1)!;
    expect(event.newNode, isTrue);
    expect(event.nodeIndex, 0);
    expect(event.chapterCompleted, isFalse);
    expect(after.forChapter(1)!.litCount, 1);

    await _clear(repo, levels[0]);
    final again = ConstellationAtlas.derive(levels, repo);
    final replay = ConstellationAtlas.diff(after, again, 1)!;
    expect(replay.newNode, isFalse);
    expect(replay.isEmpty, isTrue);
    expect(again.forChapter(1)!.litCount, 1);
    expect(again.forChapter(1)!.stars, greaterThan(after.forChapter(1)!.stars));
  });

  test(
    'fifth clear completes the chapter and fifteen stars turn it golden',
    () async {
      final levels = _levels();
      final repo = await ProgressRepository.load();
      for (final level in levels.take(4)) {
        await _clear(repo, level, extraMoves: 3);
      }
      final before = ConstellationAtlas.derive(levels, repo);
      await _clear(repo, levels[4], extraMoves: 3);
      final complete = ConstellationAtlas.derive(levels, repo);
      final event = ConstellationAtlas.diff(before, complete, 5)!;
      expect(event.newNode && event.chapterCompleted, isTrue);
      expect(event.becameGolden, isFalse);
      expect(complete.forChapter(1)!.golden, isFalse);

      var previous = complete;
      ConstellationEvent? last;
      for (final level in levels.take(5)) {
        await _clear(repo, level);
        final next = ConstellationAtlas.derive(levels, repo);
        last = ConstellationAtlas.diff(previous, next, level.id);
        previous = next;
      }
      expect(previous.forChapter(1)!.stars, 15);
      expect(previous.forChapter(1)!.golden, isTrue);
      expect(last!.becameGolden, isTrue);
      expect(last.chapterCompleted, isFalse);
    },
  );

  test('a failed save keeps the node dark until the retry succeeds', () async {
    final levels = _levels();
    var allow = false;
    final repo = await ProgressRepository.load(writer: (_, _) async => allow);
    final before = ConstellationAtlas.derive(levels, repo);
    final result = await _clear(repo, levels[0]);
    expect(repo.saveFailed, isTrue);
    final failed = ConstellationAtlas.derive(levels, repo);
    expect(failed.forChapter(1)!.isLit(1), isFalse);
    expect(ConstellationAtlas.diff(before, failed, 1)!.newNode, isFalse);
    allow = true;
    expect(await repo.retrySave(), isTrue);
    final retried = ConstellationAtlas.derive(levels, repo);
    expect(ConstellationAtlas.diff(failed, retried, 1)!.newNode, isTrue);
    expect(result.saved, isFalse);
  });

  test('progress restores after restart without extra storage', () async {
    final levels = _levels();
    final repo = await ProgressRepository.load();
    await _clear(repo, levels[6]);
    final keys = (await SharedPreferences.getInstance()).getKeys();
    final again = ConstellationAtlas.derive(
      levels,
      await ProgressRepository.load(),
    );
    expect(again.forChapter(2)!.isLit(7), isTrue);
    expect(keys, {ProgressRepository.storageKey});
  });

  test(
    'old-revision clears stay lit but do not count toward stars or gold',
    () async {
      final levels = _levels();
      final redesigned = levels.firstWhere((l) => l.revision > 1);
      SharedPreferences.setMockInitialValues({
        ProgressRepository.storageKey: jsonEncode({
          'version': ProgressRepository.schemaVersion,
          'levels': [
            {
              'levelId': redesigned.id,
              'revision': redesigned.revision - 1,
              'bestMoves': 9,
              'bestStars': 3,
              'completionCount': 1,
            },
          ],
        }),
      });
      final atlas = ConstellationAtlas.derive(
        levels,
        await ProgressRepository.load(),
      );
      final chapter = atlas.forLevel(redesigned.id)!;
      expect(chapter.isLit(redesigned.id), isTrue);
      expect(chapter.needsNewVersion(redesigned.id), isTrue);
      expect(chapter.stars, 0);
      expect(chapter.golden, isFalse);
    },
  );

  test('levels beyond the five defined chapters are ignored', () async {
    final levels = _levels();
    final extra = [
      ...levels,
      for (final level in levels.take(5))
        Level.fromJson({
          ...(jsonDecode(File('assets/levels/levels.json').readAsStringSync())
                  as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((e) => e['id'] == level.id),
          'id': level.id + 100,
        }),
    ];
    final atlas = ConstellationAtlas.derive(
      extra,
      await ProgressRepository.load(),
    );
    expect(atlas.chapters, hasLength(5));
    expect(atlas.forLevel(101), isNull);
  });
}
