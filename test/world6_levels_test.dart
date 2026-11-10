import 'dart:convert';
import 'dart:io';

import 'package:bloriq/analytics/local_analytics.dart';
import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/app/play_context.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/daily/daily_repository.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/echo_gate.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/mechanics/shelf_door.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_repository.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';
import 'support/start_game.dart';
import 'support/story_session.dart';
import 'support/world_release.dart';

const _world = 6;
const _levelAsset = 'assets/levels/world6.json';
const _targets = [
  [10, 12, 13, 14, 16],
  [10, 12, 14, 15, 17],
  [11, 13, 15, 16, 18],
  [12, 14, 15, 17, 19],
  [12, 15, 16, 18, 21],
];
const _extras = [
  null,
  Ice.typeId,
  MirrorPair.typeId,
  ClockArrow.typeId,
  EchoGate.typeId,
];
const _chapters = [
  {'ko': '열람실', 'en': 'Reading Room'},
  {'ko': '접힌 복도', 'en': 'Folded Corridor'},
  {'ko': '거꾸로 꽂힌 책', 'en': 'Upside-Down Books'},
  {'ko': '시계 서가', 'en': 'Clock Shelves'},
  {'ko': '첫 잔상의 책', 'en': 'Book of the First Echo'},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final levels = releaseLevels(_world);
  const solver = PuzzleSolver(maxStates: 200000);

  test('all 25 published stages match the five slots', () async {
    final saga = Saga.parse(File(Saga.asset).readAsStringSync());
    expect(saga.world(_world).playable, isTrue);
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    expect(manifest.listAssets(), contains(_levelAsset));
    expect(
      levels.map((level) => level.id),
      List.generate(25, (index) => 501 + index),
    );
    expect(
      levels.map((level) => level.minimumMoves),
      _targets.expand((chapter) => chapter),
    );
    for (final (index, level) in levels.indexed) {
      final chapter = index ~/ Worlds.stagesPerChapter;
      expect(
        (level.boardWidth, level.boardHeight),
        (level.id >= 519 ? 6 : 5, 5),
      );
      expect(level.blocks, hasLength(2));
      expect(level.mechanics.keys.toSet(), {
        ShelfDoor.typeId,
        ?_extras[chapter],
      });
      final shelf = level.mechanic<ShelfDoor>(ShelfDoor.typeId)!;
      expect(shelf.pairs, hasLength(chapter == 2 || chapter == 4 ? 2 : 1));
      expect(
        level.availablePowers,
        level.id == 523 ? {PuzzlePower.lightSwap} : isEmpty,
      );
    }
  });

  for (final (index, level) in levels.indexed) {
    test(
      'stage ${level.id} replays its shortest path and teaches its shelf rule',
      () {
        final powers = level.availablePowers;
        final shortest = solver.solve(level, powers: powers)!;
        expect(shortest, hasLength(level.minimumMoves));
        expect(level.solution.map(_input), shortest.map(_input));
        final controller = PuzzleController(level, powers: powers);
        for (final move in level.solution) {
          expect(controller.apply(move), isTrue, reason: '$move');
        }
        expect(controller.state.isComplete, isTrue);
        _expectChapterIdea(
          level,
          controller.moveHistory,
          index ~/ Worlds.stagesPerChapter,
        );
        final bare = powers.isEmpty ? shortest : solver.solve(level);
        expect(bare?.length, level.bareHandedMoves);
        expect(level.requiredPowers, bare == null ? powers : isEmpty);
        if (powers.isNotEmpty) {
          expect(level.featuredPower, PuzzlePower.lightSwap);
          expect(
            shortest.any((move) => move.power == PuzzlePower.lightSwap),
            isTrue,
          );
          if (bare != null) {
            expect(bare.length, greaterThan(level.minimumMoves));
          }
        }
      },
    );
  }

  testWidgets('523 can clear with a light swap onto a shelf in the game', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = await _openDraft(tester, levels);
    final settings = GameSettings(reduceMotion: true);
    addTearDown(settings.dispose);
    final level = levels.singleWhere((level) => level.id == 523);
    await _pumpStage(tester, session, settings, level);
    final controller = releaseGame(tester).controller;
    expect(controller.state.powers, {PuzzlePower.lightSwap});
    await solveVisibleBoard(tester);
    final swap = controller.moveHistory.singleWhere(
      (move) => move.power == PuzzlePower.lightSwap,
    );
    expect(
      level.mechanic<ShelfDoor>(ShelfDoor.typeId)!.cells,
      contains(swap.landing),
    );
    expect(swap.to, swap.landing);
    expect(swap.teleports, isEmpty);
    await waitForReleaseWidget(tester, releaseKey('result-next'));
    await _closeStage(tester);
    await disposeStorySession(tester, session);
  });

  testWidgets('6×5 boards retain 40 px cells at 320×568 with scaled text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final session = await _openDraft(tester, levels);
    final settings = GameSettings(reduceMotion: true);
    addTearDown(settings.dispose);
    for (final scale in [1.0, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      for (final level in levels.where((level) => level.boardWidth == 6)) {
        await _pumpStage(tester, session, settings, level);
        final geometry = releaseGame(tester).geometry;
        final reason = 'stage ${level.id}, text scale $scale';
        expect(geometry.cellSize, greaterThanOrEqualTo(40), reason: reason);
        expect(
          tester.getRect(releaseBoard).width,
          geometry.cellSize * 6,
          reason: reason,
        );
        expect(
          tester.getRect(releaseBoard).bottom,
          lessThanOrEqualTo(536),
          reason: reason,
        );
        expect(
          find.ancestor(
            of: releaseBoard,
            matching: find.byType(SingleChildScrollView),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull, reason: reason);
        await _closeStage(tester);
      }
    }
    await disposeStorySession(tester, session);
  });

  if (const bool.fromEnvironment('BENCH_WORLD6_LEVELS')) {
    test(
      'all draft stages solve in the hint isolate without stored paths',
      () async {
        final cases = [
          for (final row in solverFixtureRows(_levelAsset))
            (
              Level.fromJson({...row}..remove('solution')),
              row['minimumMoves'] as int,
            ),
        ];
        final results = await measureIsolateHints(cases);
        for (final row in results) {
          expect(row['outcome'], 'solved', reason: 'stage ${row['id']}');
          expect(
            row['ms'],
            lessThanOrEqualTo(1500),
            reason: 'stage ${row['id']}',
          );
        }
        final output = File('build/design_logs/w6-hints.json');
        output.parent.createSync(recursive: true);
        output.writeAsStringSync(jsonEncode(results));
      },
    );
  }

  if (const bool.fromEnvironment('CAPTURE_WORLD6_LEVELS')) {
    testWidgets('captures every first and guardian board at 360×740', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await preloadReleaseArt(tester);
      final session = await _openDraft(tester, levels);
      final settings = GameSettings(reduceMotion: true);
      addTearDown(settings.dispose);
      for (final level in levels.where((level) {
        final slot = Worlds.stageNumber(level.id) % Worlds.stagesPerChapter;
        return slot == 1 || slot == 0;
      })) {
        final boundary = await _pumpStage(tester, session, settings, level);
        if (level.id == Worlds.firstLevelId(_world)) {
          await tapVisible(tester, releaseKey('shelf-guide-skip'));
        }
        final state = releaseGame(tester).controller.state;
        expect(state.moves, 0);
        expect(state.powers, level.availablePowers);
        await captureReleaseScreen(
          tester,
          boundary,
          'docs/screenshots/world6/levels/${level.id}.png',
        );
        await _closeStage(tester);
      }
      await disposeStorySession(tester, session);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);

void _expectChapterIdea(Level level, List<MoveRecord> moves, int chapter) {
  final shelf = level.mechanic<ShelfDoor>(ShelfDoor.typeId)!;
  int pairOf(Position position) => shelf.pairs.indexWhere(
    (pair) => position == pair.$1 || position == pair.$2,
  );
  final hops = moves.expand((move) => move.teleports);
  switch (chapter) {
    case 0:
      expect(hops.any((hop) => hop.blockId == Level.goalBlockId), isTrue);
      expect(
        moves.any(
          (move) => pairOf(move.landing) >= 0 && move.teleports.isEmpty,
        ),
        isTrue,
      );
    case 1:
      expect(
        moves.any(
          (move) => move.teleports.any((hop) => hop.from != move.landing),
        ),
        isTrue,
      );
    case 2:
      expect(
        moves.any(
          (move) =>
              move.teleports.map((hop) => pairOf(hop.from)).toSet().length == 2,
        ),
        isTrue,
      );
    case 3:
      final clock = level.mechanic<ClockArrow>(ClockArrow.typeId)!;
      final firstHop = moves.indexWhere(
        (move) => move.teleportOf(Level.goalBlockId) != null,
      );
      expect(firstHop, greaterThanOrEqualTo(0));
      expect(
        moves
            .skip(firstHop + 1)
            .any(
              (move) =>
                  move.blockId == Level.goalBlockId &&
                  clock.cells.contains(move.from),
            ),
        isTrue,
      );
    case 4:
      expect(hops.map((hop) => pairOf(hop.from)).toSet(), {0, 1});
      expect(
        moves.any(
          (move) =>
              move.before.isGateOpen &&
              move.after.goal.position == level.echoGate,
        ),
        isTrue,
      );
  }
}

Future<GameSession> _openDraft(WidgetTester tester, List<Level> levels) {
  seedCampaign({for (var chapter = 1; chapter <= 25; chapter++) chapter});
  return loadStorySession(tester, load: () => _draftSession(levels));
}

Future<GlobalKey> _pumpStage(
  WidgetTester tester,
  GameSession session,
  GameSettings settings,
  Level level,
) async {
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
          play: const PlayContext.world(_world),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump();
  expect(releaseGame(tester).controller.state.level.id, level.id);
  return boundary;
}

Future<void> _closeStage(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<GameSession> _draftSession(List<Level> levels) async {
  final saga = Saga.parse(File(Saga.asset).readAsStringSync());
  final catalog = await StoryCatalog.load();
  final forest = solverFixtureRows('assets/levels/levels.json');
  // 게임 화면 검토에만 쓰는 장 이름과 정령 ID다.
  final data = jsonDecode(
    File('assets/story/world5.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  data['worldId'] = 'w6';
  for (final (index, chapter) in (data['chapters'] as List).indexed) {
    chapter['globalChapter'] = Worlds.globalChapter(_world, index + 1);
    chapter['name'] = _chapters[index];
    chapter['power'] = index == 4 ? PuzzlePower.lightSwap.id : null;
  }
  for (final (index, spirit) in (data['spirits'] as List).indexed) {
    spirit['id'] = 's6-${(index + 1).toString().padLeft(2, '0')}';
    spirit['levelId'] = levels[index].id;
    spirit['levelTitle'] = _chapters[index ~/ Worlds.stagesPerChapter];
  }
  return GameSession(
    levels: [Level.fromJson(forest.first)],
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
        info: saga.world(_world),
        levels: levels,
        story: WorldStory.fromJson(data, world: _world),
      ),
    ],
  );
}
