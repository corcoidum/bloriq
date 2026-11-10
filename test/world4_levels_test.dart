import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/analytics/local_analytics.dart';
import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/app/play_context.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/daily/daily_repository.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_repository.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/story/collection_repository.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:bloriq/tutorial/echo_tutorial.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';

const _targets = [
  [9, 11, 12, 13, 15],
  [10, 12, 13, 14, 16],
  [11, 13, 14, 15, 17],
  [11, 13, 15, 16, 18],
  [12, 14, 16, 17, 19],
];

void main() {
  final source = File('assets/levels/world4.json').readAsStringSync();
  final levels = Worlds.parseLevels(source, 4);
  const solver = PuzzleSolver(maxStates: 200000);

  test('Clocktower follows its mechanic distribution and chapter sawtooth', () {
    expect(
      levels.map((level) => level.id),
      orderedEquals(List.generate(25, (i) => 301 + i)),
    );
    const extras = [
      <String>{},
      {'echoEraser', 'echoHold'},
      {'echoGate'},
      {'mirrorPair'},
      {'echoGate', 'oneWay'},
    ];
    for (final (chapter, targets) in _targets.indexed) {
      final first = chapter * 5;
      final group = levels.sublist(first, first + 5);
      expect(group.expand((level) => level.mechanics.keys).toSet(), {
        ClockArrow.typeId,
        ...extras[chapter],
      });
      if (chapter > 0) {
        expect(
          group.first.minimumMoves,
          lessThan(levels[first - 1].minimumMoves),
        );
      }
      for (final (index, level) in group.indexed) {
        final reason = 'stage ${level.id}';
        expect(level.minimumMoves, targets[index], reason: reason);
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
          inInclusiveRange(chapter >= 2 ? 5 : 4, 5),
          reason: reason,
        );
        expect(
          level.availablePowers.length,
          lessThanOrEqualTo(1),
          reason: reason,
        );
        expect(level.blocks.length, inInclusiveRange(2, 3), reason: reason);
        final clock = level.mechanic<ClockArrow>(ClockArrow.typeId)!;
        expect(clock.arrows.length, inInclusiveRange(2, 4), reason: reason);
        if (chapter == 4) {
          expect(clock.arrows.values.toSet(), hasLength(1), reason: reason);
        }
      }
    }
    expect((levels.first.boardWidth, levels.first.boardHeight), (4, 4));
    expect(
      levels
          .where((level) => level.availablePowers.isNotEmpty)
          .map((level) => level.id),
      [316, 318],
    );
    expect(
      levels
          .where((level) => level.mechanics.containsKey('mirrorPair'))
          .map((level) => level.id),
      [317, 319],
    );
  });

  for (final level in levels) {
    test(
      'stage ${level.id} replays the Python shortest solution within the app state cap',
      () {
        final powers = level.availablePowers;
        final controller = PuzzleController(level, powers: powers);
        final solution = const HintSearch().storedSolution(controller.state)!;
        final shortest = solver.solve(level, powers: powers)!;
        expect(solution, hasLength(level.minimumMoves));
        expect(solution.map(_input), shortest.map(_input));
        for (final move in solution) {
          expect(controller.apply(move), isTrue, reason: '$move');
        }
        expect(controller.state.isComplete, isTrue);
        final bare = powers.isEmpty ? shortest : solver.solve(level);
        expect(bare?.length, level.bareHandedMoves);
        expect(level.requiredPowers, bare == null ? powers : isEmpty);
        if (powers.isNotEmpty) {
          expect(powers, {PuzzlePower.seal});
          expect(level.featuredPower, PuzzlePower.seal);
          expect(
            solution.any((move) => move.power == PuzzlePower.seal),
            isTrue,
          );
          if (bare != null) {
            expect(bare.length, greaterThan(level.minimumMoves));
          }
        }
      },
    );
  }

  if (const bool.fromEnvironment('BENCH_WORLD4_LEVELS')) {
    test(
      'the native hint path solves all draft stages without the stored path',
      () async {
        final rows = (jsonDecode(source) as List).cast<Map<String, dynamic>>();
        final results = <Map<String, num>>[];
        for (final row in rows) {
          final level = Level.fromJson({...row}..remove('solution'));
          final state = PuzzleState.initial(
            level,
            powers: level.availablePowers,
          );
          const hints = HintSearch();
          expect(hints.storedSolution(state), isNull);
          final watch = Stopwatch()..start();
          final result = await hints.solve(state);
          watch.stop();
          expect(result.limited, isFalse, reason: 'stage ${level.id}');
          expect(
            result.moves,
            hasLength(level.minimumMoves),
            reason: 'stage ${level.id}',
          );
          results.add({'id': level.id, 'ms': watch.elapsedMicroseconds / 1000});
        }
        final file = File('build/design_logs/w4-hints.json');
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(jsonEncode(results));
      },
    );
  }

  if (const bool.fromEnvironment('CAPTURE_WORLD4_LEVELS')) {
    testWidgets('captures the opening and guardian stages in the draft world', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final preload = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: SizedBox(key: preload)));
      await tester.runAsync(() async {
        await _loadCaptureArt();
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
      SharedPreferences.setMockInitialValues({
        'bloriq.onboarding.v1': 'skipped',
        GameAudio.musicKey: false,
        GameAudio.effectsKey: false,
        ProgressionRepository.storageKey: jsonEncode({
          'version': 1,
          'backfilled': true,
          'completedChapters': [
            for (var chapter = 1; chapter <= 15; chapter++) chapter,
          ],
        }),
      });
      final session = await loadStorySession(
        tester,
        load: () => _draftSession(levels),
      );
      final settings = GameSettings(reduceMotion: true);
      addTearDown(settings.dispose);
      for (final level in levels.where((level) {
        final slot = Worlds.stageNumber(level.id) % 5;
        return slot == 1 || slot == 0;
      })) {
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: GameTheme.dark,
              locale: const Locale('ko'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: GameScreen(
                session: session,
                settings: settings,
                initialLevelId: level.id,
                play: const PlayContext.world(4),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        if (level.id == Worlds.firstLevelId(4)) {
          await tapVisible(
            tester,
            find.byKey(const ValueKey('clock-guide-skip')),
          );
        }
        final board = find.byType(GameWidget<BloriqGame>);
        final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
        expect(game.controller.state.level.id, level.id);
        expect(game.controller.state.powers, level.availablePowers);
        expect(game.controller.state.moves, 0);
        expect(find.byKey(const ValueKey('clock-phase')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => _capture(boundary, level.id));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
      await disposeStorySession(tester, session);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);

Future<GameSession> _draftSession(List<Level> levels) async {
  final saga = Saga.parse(File(Saga.asset).readAsStringSync());
  final catalog = await StoryCatalog.load();
  final forest =
      jsonDecode(File('assets/levels/levels.json').readAsStringSync()) as List;
  // 스크린샷을 위해 검증된 이야기 스키마에 테스트용 장 이름과 번호만 넣는다.
  const chapters = [
    {'ko': '태엽 마당', 'en': 'Winding Yard'},
    {'ko': '톱니 회랑', 'en': 'Gear Hall'},
    {'ko': '종지기의 다락', 'en': 'Bellkeeper’s Attic'},
    {'ko': '추의 계단', 'en': 'Pendulum Stair'},
    {'ko': '멈춘 자정', 'en': 'Frozen Midnight'},
  ];
  final data = jsonDecode(
    File('assets/story/world3.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  data['worldId'] = 'w4';
  for (final (index, chapter) in (data['chapters'] as List).indexed) {
    chapter['globalChapter'] = Worlds.globalChapter(4, index + 1);
    chapter['name'] = chapters[index];
  }
  for (final (index, spirit) in (data['spirits'] as List).indexed) {
    spirit['id'] = 's4-${(index + 1).toString().padLeft(2, '0')}';
    spirit['levelId'] = levels[index].id;
    spirit['levelTitle'] = chapters[index ~/ Worlds.stagesPerChapter];
  }
  return GameSession(
    levels: [Level.fromJson(forest.first as Map<String, dynamic>)],
    progress: await ProgressRepository.load(),
    audio: await GameAudio.load(),
    onboarding: await Onboarding.load(returningPlayer: true),
    daily: await DailyRepository.load(),
    analytics: await LocalAnalytics.load(),
    story: catalog,
    collection: await CollectionRepository.load(catalog),
    progression: await ProgressionRepository.load(),
    endless: await EndlessRepository.load(),
    saga: saga,
    worlds: [
      LoadedWorld(
        info: saga.world(4),
        levels: levels,
        story: WorldStory.fromJson(data, world: 4),
      ),
    ],
  );
}

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
    final output = File('docs/screenshots/world4/levels/$id.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
