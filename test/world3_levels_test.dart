import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

const _targets = [
  [8, 10, 11, 12, 14],
  [9, 11, 12, 13, 15],
  [10, 12, 13, 14, 16],
  [11, 13, 14, 15, 17],
  [12, 14, 15, 16, 18],
];

void main() {
  final source = File('assets/levels/world3.json').readAsStringSync();
  final rows = (jsonDecode(source) as List).cast<Map<String, dynamic>>();
  final levels = Worlds.parseLevels(source, 3);
  const solver = PuzzleSolver(maxStates: 2000000);

  test('world 3 follows its chapter mechanics and rising sawtooth', () {
    expect(levels.map((level) => level.id), List.generate(25, (i) => 201 + i));
    const chapterMechanics = [
      {'mirrorPair'},
      {'mirrorPair', 'echoEraser', 'echoHold'},
      {'mirrorPair', 'oneWay', 'goalOnly'},
      {'mirrorPair', 'echoGate'},
      {'mirrorPair', 'echoGate', 'oneWay'},
    ];
    const chapterPowers = [
      <PuzzlePower>[],
      <PuzzlePower>[],
      [PuzzlePower.moonflowerLeap, PuzzlePower.moonflowerLeap],
      [PuzzlePower.lightSwap],
      <PuzzlePower>[],
    ];
    for (var chapter = 0; chapter < 5; chapter++) {
      final first = chapter * 5;
      final group = levels.sublist(first, first + 5);
      expect(
        group.expand((level) => level.mechanics.keys).toSet(),
        chapterMechanics[chapter],
      );
      expect(
        group.expand((level) => level.availablePowers),
        chapterPowers[chapter],
      );
      if (chapter > 0) {
        expect(
          group.first.minimumMoves,
          lessThan(levels[first - 1].minimumMoves),
        );
      }
      for (final (index, level) in group.indexed) {
        final reason = 'stage ${level.id}';
        final target = _targets[chapter][index];
        expect(
          level.minimumMoves,
          inInclusiveRange(target - 1, target + 1),
          reason: reason,
        );
        if (index > 0) {
          expect(
            level.minimumMoves,
            greaterThan(group[index - 1].minimumMoves),
            reason: reason,
          );
        }
        expect(
          level.boardWidth,
          inInclusiveRange(chapter == 0 ? 4 : 5, 5),
          reason: reason,
        );
        expect(
          level.boardHeight,
          inInclusiveRange(chapter >= 3 ? 5 : 4, 5),
          reason: reason,
        );
        expect(
          level.availablePowers.length,
          lessThanOrEqualTo(1),
          reason: reason,
        );
        final pair = level.mechanic<MirrorPair>(MirrorPair.typeId)!;
        expect(pair.pairs, hasLength(chapter == 3 ? 2 : 1), reason: reason);
        expect(
          pair.partnerOf(Level.goalBlockId) != null,
          chapter == 4,
          reason: reason,
        );
        if (chapter == 3) expect(level.echoGate, isNotNull, reason: reason);
      }
    }
    expect((levels.first.boardWidth, levels.first.boardHeight), (4, 4));
    expect(levels.last.minimumMoves, lessThanOrEqualTo(19));
  });

  for (final (index, level) in levels.indexed) {
    test(
      'stage ${level.id} matches BFS and every pair changes the optimum',
      () {
        final powers = level.availablePowers;
        final controller = PuzzleController(level, powers: powers);
        final best = solver.solve(level, powers: powers)!;
        final solution = const HintSearch().storedSolution(controller.state)!;
        expect(solution, hasLength(level.minimumMoves));
        expect(solution.map(_input), best.map(_input));
        for (final move in solution) {
          expect(controller.apply(move), isTrue, reason: '$move');
        }
        expect(controller.state.isComplete, isTrue);
        expect(controller.state.moves, level.minimumMoves);
        final bare = powers.isEmpty ? best : solver.solve(level);
        expect(bare?.length, level.bareHandedMoves);
        expect(level.requiredPowers, bare == null ? powers : isEmpty);
        if (powers.isNotEmpty && bare != null) {
          expect(bare.length, greaterThan(level.minimumMoves));
        }

        final json = rows[index];
        final rules = (json['specialRules'] as List)
            .cast<Map<String, dynamic>>();
        final pairIndices = [
          for (final (i, rule) in rules.indexed)
            if (rule['type'] == MirrorPair.typeId) i,
        ];
        void checkWithout(Set<int> removed) {
          final alternate = Level.fromJson({
            ...json,
            'specialRules': [
              for (final (i, rule) in rules.indexed)
                if (!removed.contains(i)) rule,
            ],
          });
          final shorterOrLonger = solver.solve(alternate, powers: powers);
          expect(
            shorterOrLonger?.length,
            isNot(level.minimumMoves),
            reason: 'without mirror rules $removed',
          );
        }

        checkWithout(pairIndices.toSet());
        if (pairIndices.length == 2) {
          for (final pair in pairIndices) {
            checkWithout({pair});
          }
        }
      },
    );
  }

  if (const bool.fromEnvironment('CAPTURE_WORLD3_LEVELS')) {
    testWidgets('captures the opener and guardian of every world 3 chapter', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.localesTestValue = [const Locale('ko')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final preload = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: SizedBox(key: preload)));
      await tester.runAsync(() async {
        await _loadCaptureArt();
        // 위젯에서 그리는 배경과 리크도 첫 캡처 전에 디코딩한다.
        final context = preload.currentContext!;
        await Future.wait([
          precacheImage(
            const ResizeImage(AssetImage(StarArt.forest), width: 1080),
            context,
          ),
          precacheImage(
            const ResizeImage(AssetImage(StarArt.riq), width: 384),
            context,
          ),
        ]);
      });
      await tester.pump();
      final settings = GameSettings(reduceMotion: true);
      addTearDown(settings.dispose);
      for (final (index, level) in levels.indexed) {
        if (index % 5 != 0 && index % 5 != 4) continue;
        rootBundle.clear();
        SharedPreferences.setMockInitialValues({
          'bloriq.onboarding.v1': 'skipped',
          GameAudio.musicKey: false,
          GameAudio.effectsKey: false,
        });
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: BloriqApp(
              loadLevels: () async => [level],
              settings: settings,
              firstRunIntro: false,
            ),
          ),
        );
        await waitForHome(tester);
        await tapVisible(tester, find.byKey(const ValueKey('home-play')));
        final board = find.byType(GameWidget<BloriqGame>);
        final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
        expect(game.controller.state.level.id, level.id);
        expect(game.controller.state.moves, 0);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => _capture(boundary, level.id));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);

Future<void> _loadCaptureArt() async {
  for (final (family, file) in [
    ('Roboto', 'NanumGothic-Regular.ttf'),
    ('NanumGothic', 'NanumGothic-Regular.ttf'),
    ('Jua', 'Jua-Regular.ttf'),
    ('GamjaFlower', 'GamjaFlower-Subset.ttf'),
    ('GowunDodum', 'GowunDodum-Regular.ttf'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file'))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  await StarArt.load();
}

Future<void> _capture(GlobalKey key, int id) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final output = File('docs/screenshots/world3/levels/$id.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
