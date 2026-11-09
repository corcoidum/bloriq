import 'dart:convert';
import 'dart:io';

import 'package:bloriq/constellation/constellation_catalog.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sagaJson = _readJson(Saga.asset);
  final saga = Saga.fromJson(sagaJson);
  final bundled = {Saga.asset};

  test('saga story text is bilingual', () => _checkTextTree(sagaJson, 'saga'));

  for (final world in saga.worlds.where((world) => world.playable)) {
    final n = world.number;
    final firstId = (n - 1) * 100 + 1;
    final levelsAsset = world.levelsAsset ?? 'assets/levels/levels.json';
    final storyAsset = world.storyAsset ?? 'assets/story/season1.json';
    final source = File(levelsAsset).readAsStringSync();
    final levels = Worlds.parseLevels(source, n);
    final levelRows = (jsonDecode(source) as List).cast<Map<String, dynamic>>();
    final story = _readJson(storyAsset);
    final expansion = world.expansion
        ? WorldStory.fromJson(story, world: n)
        : null;
    final legacy = world.expansion ? null : StoryCatalog.fromJson(story);
    final chapters = (story['chapters'] as List).cast<Map<String, dynamic>>();
    final spirits = (story['spirits'] as List).cast<Map<String, dynamic>>();
    bundled.addAll([
      levelsAsset,
      storyAsset,
      ...spirits.map((spirit) => spirit['asset']).whereType<String>(),
      if (world.theme case final theme?)
        ...[theme.floor, theme.rock, theme.bgm].whereType<String>(),
    ]);

    group('world $n', () {
      test('25 stages and spirits with one guardian at each chapter end', () {
        expect(levels, hasLength(25));
        expect(spirits, hasLength(25));
        for (final (index, level) in levels.indexed) {
          final spirit = spirits[index];
          final id = 's$n-${(index + 1).toString().padLeft(2, '0')}';
          expect(level.id, firstId + index);
          expect(spirit['levelId'], level.id);
          expect(spirit['id'], id);
          expect(spirit['chapter'], index ~/ 5 + 1);
          expect(spirit['guardian'], (index + 1) % 5 == 0);
          expect(
            expansion?.forLevel(level.id)?.id ?? legacy?.forLevel(level.id)?.id,
            id,
          );
        }
        expect(expansion?.forLevel(firstId + 25), isNull);
        expect(legacy?.forLevel(firstId + 25), isNull);
        if (expansion != null) {
          expect(expansion.title.ko, world.title.ko);
          expect(expansion.title.en, world.title.en);
        }
      });

      test('five constellations and complete bilingual chapter text', () {
        // 세계 1의 별자리는 기존 코드에 있고 전역 장 번호는 지역 번호와 같다.
        final constellations =
            expansion?.chapters.map((chapter) => chapter.stars).toList() ??
            ConstellationCatalog.all;
        expect(chapters, hasLength(5));
        expect(constellations, hasLength(5));
        _checkText(story['prologue'], 'world $n prologue');
        _checkTextTree(story, 'world $n');
        for (final (index, chapter) in chapters.indexed) {
          final global = (n - 1) * 5 + index + 1;
          final stars = constellations[index];
          expect(chapter['number'], index + 1);
          expect(chapter[world.expansion ? 'globalChapter' : 'number'], global);
          expect(stars.chapter, global);
          expect(stars.nodes, hasLength(5));
          for (final node in stars.nodes) {
            expect(node.dx, inInclusiveRange(0, 1));
            expect(node.dy, inInclusiveRange(0, 1));
          }
          for (final (a, b) in stars.edges) {
            expect(a, inInclusiveRange(0, 4));
            expect(b, inInclusiveRange(0, 4));
          }
          for (final field in ['intro', 'endingTitle', 'ending']) {
            _checkText(chapter[field], 'chapter $global $field');
          }
        }
      });

      for (final (index, level) in levels.indexed) {
        test('stage ${level.id} has a legal shortest solution', () {
          const solver = PuzzleSolver(maxStates: 2000000);
          final powers = world.expansion
              ? level.availablePowers
              : const <PuzzlePower>{};
          final best = solver.solve(level, powers: powers);
          expect(best, hasLength(level.minimumMoves));
          final controller = PuzzleController(level, powers: powers);
          final stored = const HintSearch().storedSolution(controller.state);
          expect(stored, hasLength(level.minimumMoves));
          expect(stored!.map(_input), best!.map(_input));
          for (final move in stored) {
            expect(controller.apply(move), isTrue, reason: '$move');
          }
          expect(controller.state.isComplete, isTrue);
          expect(controller.state.moves, level.minimumMoves);
          expect(const HintSearch().storedSolution(controller.state), isNull);

          if (world.expansion) {
            expect(
              levelRows[index].keys,
              containsAll([
                'bareHandedMoves',
                'requiredPowers',
                'availablePowers',
              ]),
            );
            final bare = powers.isEmpty ? best : solver.solve(level);
            expect(bare?.length, level.bareHandedMoves);
            final required = {
              for (final power in powers)
                if (solver.solve(level, powers: {...powers}..remove(power)) ==
                    null)
                  power,
            };
            expect(required, level.requiredPowers);
            if (level.featuredPower case final featured?) {
              final without = solver.solve(
                level,
                powers: {...powers}..remove(featured),
              );
              final using = solver.solve(
                level,
                powers: powers,
                mustUse: featured,
              );
              expect(
                without == null ||
                    without.length > level.minimumMoves ||
                    using?.length == level.minimumMoves,
                isTrue,
                reason:
                    '${featured.id} must shorten or join a shortest solution',
              );
            }
          }
        });
      }
    });
  }

  test('all playable world assets are bundled', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), containsAll(bundled));
  });
}

Map<String, dynamic> _readJson(String asset) =>
    jsonDecode(File(asset).readAsStringSync()) as Map<String, dynamic>;

void _checkText(Object? value, String path) {
  expect(value, isA<Map<String, dynamic>>(), reason: path);
  final text = value as Map<String, dynamic>;
  for (final locale in ['ko', 'en']) {
    expect(text[locale], isA<String>(), reason: '$path.$locale');
    expect(
      (text[locale] as String).trim(),
      isNotEmpty,
      reason: '$path.$locale',
    );
  }
}

void _checkTextTree(Object? value, String path) {
  if (value is Map<String, dynamic>) {
    if (value.containsKey('ko') || value.containsKey('en')) {
      _checkText(value, path);
    }
    for (final entry in value.entries) {
      _checkTextTree(entry.value, '$path.${entry.key}');
    }
  } else if (value is List) {
    for (final (index, item) in value.indexed) {
      _checkTextTree(item, '$path[$index]');
    }
  }
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);
