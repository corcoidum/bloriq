import 'dart:convert';
import 'dart:io';

import 'package:bloriq/analytics/local_analytics.dart';
import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/app/play_context.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/daily/daily_repository.dart';
import 'package:bloriq/design/game_theme.dart';
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
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';
import 'support/start_game.dart';
import 'support/story_session.dart';
import 'support/world_release.dart';

const _world = 7;
const _asset = 'assets/levels/world7.json';
const _targets = [
  11,
  13,
  14,
  15,
  17,
  12,
  14,
  15,
  17,
  19,
  12,
  14,
  16,
  18,
  20,
  13,
  15,
  17,
  19,
  22,
  14,
  16,
  18,
  20,
  24,
];
const _forest = {'echoEraser', 'echoHold', 'oneWay', 'goalOnly', 'echoGate'};
const _lighthouses = {'mirrorPair', 'clockArrow', 'ice', 'shelfDoor'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final levels = solverFixtureRows(_asset).map(Level.fromJson).toList();
  const solver = PuzzleSolver(maxStates: 200000);

  test('25 published stages match their slots and the saga entry', () {
    expect(
      Worlds.parseLevels(File(_asset).readAsStringSync(), _world),
      hasLength(25),
    );
    expect(
      Saga.parse(File(Saga.asset).readAsStringSync()).world(7).playable,
      isTrue,
    );
    expect(
      levels.map((level) => level.id),
      List.generate(25, (index) => 601 + index),
    );
    expect(levels.map((level) => level.minimumMoves), _targets);
    for (final (index, level) in levels.indexed) {
      expect(level.world, _world);
      final chapter = index ~/ 5;
      expect(level.availablePowers.length, lessThanOrEqualTo(1));
      expect(level.mechanics.length, inInclusiveRange(2, 3));
      expect(
        (level.boardWidth, level.boardHeight),
        chapter == 4
            ? (6, 6)
            : index >= 13
            ? (6, 5)
            : (5, 5),
      );
      final kinds = level.mechanics.keys.toSet();
      if (chapter == 0) {
        expect(kinds, hasLength(2));
        expect(_forest.containsAll(kinds), isTrue);
        expect(level.availablePowers, hasLength(1));
      } else if (chapter == 1) {
        expect(kinds, {'mirrorPair', 'clockArrow'});
      } else if (chapter == 2) {
        expect(kinds, {'ice', 'shelfDoor'});
      } else {
        expect(kinds, hasLength(3));
        expect(_lighthouses.containsAll(kinds), isTrue);
      }
    }
    final first = Level.fromJson(
      solverFixtureRows('assets/levels/levels.json').first,
    );
    final last = levels.last;
    expect((last.startPosition.x, last.exitPosition.x), (0, 5));
    expect(last.startPosition.y, last.exitPosition.y);
    expect(first.startPosition.y, first.exitPosition.y);
    expect(last.startPosition.y, 2);
  });

  for (final level in levels) {
    test(
      'stage ${level.id} agrees with Python and replays its stored solution',
      () {
        final path = solver.solve(level, powers: level.availablePowers)!;
        expect(path, hasLength(level.minimumMoves));
        expect(level.solution.map(_input), path.map(_input));
        final controller = PuzzleController(
          level,
          powers: level.availablePowers,
        );
        for (final move in level.solution) {
          expect(controller.apply(move), isTrue, reason: '$move');
        }
        expect(controller.state.isComplete, isTrue);
        final bare = level.availablePowers.isEmpty ? path : solver.solve(level);
        expect(bare?.length, level.bareHandedMoves);
        if (level.availablePowers.isNotEmpty) {
          expect(path.any((move) => move.power != null), isTrue);
          if (bare != null) expect(bare.length, greaterThan(path.length));
        }
      },
    );
  }

  testWidgets('6×6 boards scroll with 40 px cells at 320×568 and 200% text', (
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
    for (final locale in [const Locale('ko'), const Locale('en')]) {
      for (final scale in [1.0, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final level in levels.where((level) => level.boardHeight == 6)) {
          await _pumpStage(tester, session, settings, level, locale: locale);
          final reason = '${level.id}, $locale, scale $scale';
          expect(
            releaseGame(tester).geometry.cellSize,
            greaterThanOrEqualTo(40),
            reason: reason,
          );
          final scroll = find.ancestor(
            of: releaseBoard,
            matching: find.byType(SingleChildScrollView),
          );
          expect(scroll, findsOneWidget, reason: reason);
          final position = tester
              .state<ScrollableState>(
                find
                    .descendant(of: scroll, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          expect(position.maxScrollExtent, greaterThan(0), reason: reason);
          // 보드의 블록 드래그와 구분되는 머리글에서 세로 스크롤을 시작한다.
          await tester.dragFrom(
            tester.getTopLeft(scroll) + const Offset(8, 40),
            const Offset(0, -200),
          );
          await tester.pump();
          expect(position.pixels, greaterThan(0), reason: reason);
          expect(tester.takeException(), isNull, reason: reason);
          await _closeStage(tester);
        }
      }
    }
    await disposeStorySession(tester, session);
  });

  if (const bool.fromEnvironment('BENCH_WORLD7_LEVELS')) {
    test(
      'draft hints solve without stored paths within the app budget',
      () async {
        final rows = await measureIsolateHints([
          for (final raw in solverFixtureRows(_asset))
            (
              Level.fromJson({...raw}..remove('solution')),
              raw['minimumMoves'] as int,
            ),
        ]);
        for (final row in rows) {
          expect(row['outcome'], 'solved', reason: '${row['id']}');
          expect(row['ms'], lessThanOrEqualTo(1500), reason: '${row['id']}');
        }
        File('build/design_logs/w7-hints.json')
            .writeAsStringSync(jsonEncode(rows));
      },
    );
  }

  if (const bool.fromEnvironment('CAPTURE_WORLD7_LEVELS')) {
    testWidgets('captures first and guardian boards at 360×740', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await preloadReleaseArt(tester);
      final session = await _openDraft(tester, levels);
      final settings = GameSettings(reduceMotion: true);
      addTearDown(settings.dispose);
      for (final level in levels.where(
        (level) => level.id % 5 == 1 || level.id % 5 == 0,
      )) {
        final boundary = await _pumpStage(tester, session, settings, level);
        if (releaseKey('mix-guide-1').evaluate().isNotEmpty) {
          await tapVisible(tester, releaseKey('mix-guide-next'));
        }
        expect(releaseGame(tester).controller.state.moves, 0);
        expect(
          tester.getRect(releaseKey('game-home')).top,
          greaterThanOrEqualTo(0),
          reason: '${level.id}',
        );
        await captureReleaseScreen(
          tester,
          boundary,
          'docs/screenshots/world7/levels/${level.id}.png',
        );
        await _closeStage(tester);
      }
      await disposeStorySession(tester, session);
    }, timeout: const Timeout(Duration(minutes: 5)));
  }
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);

Future<GameSession> _openDraft(WidgetTester tester, List<Level> levels) {
  seedCampaign({for (var chapter = 1; chapter <= 30; chapter++) chapter});
  return loadStorySession(tester, load: () => _draftSession(levels));
}

Future<GlobalKey> _pumpStage(
  WidgetTester tester,
  GameSession session,
  GameSettings settings,
  Level level, {
  Locale locale = const Locale('ko'),
}) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: GameTheme.dark,
        locale: locale,
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
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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
  final data = jsonDecode(
    File('assets/story/world7.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return GameSession(
    levels: [
      Level.fromJson(solverFixtureRows('assets/levels/levels.json').first),
    ],
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
