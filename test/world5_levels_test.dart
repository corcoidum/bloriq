import 'dart:convert';
import 'dart:io';

import 'package:bloriq/analytics/local_analytics.dart';
import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/app/play_context.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/daily/daily_repository.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
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
import 'support/story_session.dart';
import 'support/world_release.dart';

const _world = 5;
const _levelAsset = 'assets/levels/world5.json';
const _targets = [
  [9, 11, 12, 14, 15],
  [10, 12, 14, 15, 17],
  [11, 13, 14, 16, 18],
  [11, 13, 15, 17, 19],
  [12, 14, 16, 18, 20],
];
const _chapters = [
  {'ko': '서리 입구', 'en': 'Frost Entrance'},
  {'ko': '고드름 회랑', 'en': 'Icicle Corridor'},
  {'ko': '얼음 거울', 'en': 'Ice Mirrors'},
  {'ko': '눈보라 갈림길', 'en': 'Blizzard Fork'},
  {'ko': '기억 보존 장치', 'en': 'Memory Keeper'},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final levels = releaseLevels(_world);
  const solver = PuzzleSolver(maxStates: 200000);

  test(
    'the five draft chapters follow their slot and publication limits',
    () async {
      final saga = Saga.parse(File(Saga.asset).readAsStringSync());
      expect(saga.world(_world).playable, isFalse);
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      expect(manifest.listAssets(), isNot(contains(_levelAsset)));
      expect(
        levels.map((level) => level.id),
        List.generate(25, (index) => 401 + index),
      );
      expect(
        levels.map((level) => level.minimumMoves),
        _targets.expand((chapter) => chapter),
      );
      expect(
        levels
            .where((level) => level.availablePowers.isNotEmpty)
            .map((level) => level.id),
        [406, 408],
      );
      for (final level in levels) {
        expect((level.boardWidth, level.boardHeight), (5, 5));
        expect(level.blocks, hasLength(2));
        final ice = level.mechanic<Ice>(Ice.typeId)!;
        expect(ice.positions.length, inInclusiveRange(1, 7));
        expect(level.availablePowers.length, lessThanOrEqualTo(1));
      }
    },
  );

  for (final level in levels) {
    test(
      'stage ${level.id} has a matching shortest path with at least two ice turns',
      () {
        final powers = level.availablePowers;
        final controller = PuzzleController(level, powers: powers);
        final path = solver.solve(level, powers: powers)!;
        expect(path, hasLength(level.minimumMoves));
        expect(level.solution.map(_input), path.map(_input));
        var slideTurns = 0;
        var sharedSlide = false;
        for (final move in level.solution) {
          expect(controller.apply(move), isTrue, reason: '$move');
          final record = controller.lastMove!;
          final primary = record.to != record.landing;
          final twin = MirrorPair.recordedShift(record);
          final twinSlides = twin != null && !twin.from.isAdjacentTo(twin.to);
          if (primary || twinSlides) slideTurns++;
          sharedSlide |= primary && twinSlides;
        }
        expect(controller.state.isComplete, isTrue);
        expect(slideTurns, greaterThanOrEqualTo(2));
        if (level.mechanics.containsKey(MirrorPair.typeId)) {
          expect(sharedSlide, isTrue);
        }
        final bare = powers.isEmpty ? path : solver.solve(level);
        expect(bare?.length, level.bareHandedMoves);
        expect(level.requiredPowers, bare == null ? powers : isEmpty);
        if (powers.isNotEmpty) {
          expect(powers, {PuzzlePower.wind});
          expect(level.featuredPower, PuzzlePower.wind);
          expect(path.any((move) => move.power == PuzzlePower.wind), isTrue);
          if (bare != null) {
            expect(bare.length, greaterThan(level.minimumMoves));
          }
        }
      },
    );
  }

  if (const bool.fromEnvironment('BENCH_WORLD5_LEVELS')) {
    test(
      'native isolate hints solve all 25 stages without the saved path',
      () async {
        final rows = solverFixtureRows(_levelAsset);
        final cases = [
          for (final row in rows)
            (
              Level.fromJson({...row}..remove('solution')),
              row['minimumMoves'] as int,
            ),
        ];
        final results = await measureIsolateHints(cases);
        expect(
          results.where((row) => row['outcome'] == 'solved'),
          hasLength(25),
        );
        final output = File('build/design_logs/w5-hints.json');
        output.parent.createSync(recursive: true);
        output.writeAsStringSync(jsonEncode(results));
      },
    );
  }

  if (const bool.fromEnvironment('CAPTURE_WORLD5_LEVELS')) {
    testWidgets('captures every first and guardian board at 360×740', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await preloadReleaseArt(tester);
      seedCampaign({for (var chapter = 1; chapter <= 20; chapter++) chapter});
      final session = await loadStorySession(
        tester,
        load: () => _draftSession(levels),
      );
      final settings = GameSettings(reduceMotion: true);
      addTearDown(settings.dispose);
      for (final level in levels.where((level) {
        final slot = Worlds.stageNumber(level.id) % Worlds.stagesPerChapter;
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
                play: const PlayContext.world(_world),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        final state = releaseGame(tester).controller.state;
        expect(state.level.id, level.id);
        expect(state.moves, 0);
        expect(state.powers, level.availablePowers);
        expect(state.level.mechanics, contains(Ice.typeId));
        await captureReleaseScreen(
          tester,
          boundary,
          'docs/screenshots/world5/levels/${level.id}.png',
        );
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
  final forest = solverFixtureRows('assets/levels/levels.json');
  // 장 이름을 표시할 테스트 이야기. 공개 앱의 번들에는 들어가지 않는다.
  final data = jsonDecode(
    File('assets/story/world4.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  data['worldId'] = 'w5';
  for (final (index, chapter) in (data['chapters'] as List).indexed) {
    chapter['globalChapter'] = Worlds.globalChapter(_world, index + 1);
    chapter['name'] = _chapters[index];
  }
  for (final (index, spirit) in (data['spirits'] as List).indexed) {
    spirit['id'] = 's5-${(index + 1).toString().padLeft(2, '0')}';
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
