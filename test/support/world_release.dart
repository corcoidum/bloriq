import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/victory_panel.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/world/saga_map.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:bloriq/world/world_map.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'start_game.dart';

final releaseBoard = find.byType(GameWidget<BloriqGame>);
final releaseVictory = find.byType(VictoryPanel);

Finder releaseKey(String value) => find.byKey(ValueKey(value));

void seedCampaign(Set<int> chapters, {Iterable<Level> cleared = const []}) {
  SharedPreferences.setMockInitialValues({
    'bloriq.onboarding.v1': 'skipped',
    GameAudio.musicKey: false,
    GameAudio.effectsKey: false,
    ProgressionRepository.storageKey: jsonEncode({
      'version': 1,
      'backfilled': true,
      'completedChapters': chapters.toList()..sort(),
    }),
    ProgressRepository.storageKey: jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': [
        for (final level in cleared)
          {
            'levelId': level.id,
            'revision': level.revision,
            'bestMoves': level.minimumMoves,
            'bestStars': 3,
            'completionCount': 1,
          },
      ],
    }),
  });
}

List<Level> releaseLevels(int world) => Worlds.parseLevels(
  File('assets/levels/world$world.json').readAsStringSync(),
  world,
);

Future<GlobalKey> openReleaseApp(
  WidgetTester tester, {
  bool captureArt = false,
  Locale locale = const Locale('ko'),
  Future<List<Level>> Function()? loadLevels,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [locale];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  if (captureArt) await preloadReleaseArt(tester);
  final settings = GameSettings(reduceMotion: true);
  addTearDown(settings.dispose);
  final boundary = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: BloriqApp(
        settings: settings,
        firstRunIntro: false,
        loadLevels: loadLevels,
      ),
    ),
  );
  await waitForHome(tester);
  return boundary;
}

Future<void> closeReleaseApp(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<Finder> openLightroad(WidgetTester tester, int world) async {
  final mapButton = releaseKey('saga-map');
  await waitForReleaseWidget(tester, mapButton.hitTestable());
  await tapVisible(tester, mapButton);
  final node = releaseKey('saga-world-$world');
  await tester.scrollUntilVisible(
    node,
    160,
    scrollable: find
        .descendant(of: find.byType(SagaMap), matching: find.byType(Scrollable))
        .first,
  );
  await Scrollable.ensureVisible(tester.element(node), alignment: .8);
  await tester.pump();
  return node;
}

Finder releaseWorldMap(int world) => find.byWidgetPredicate(
  (widget) => widget is WorldMap && widget.world == world,
);

Future<void> enterReleaseWorld(WidgetTester tester, int world) async {
  final entry = releaseKey('world-entry');
  await waitForReleaseWidget(tester, entry.hitTestable());
  await tapVisible(tester, entry);
  await waitForReleaseWidget(tester, releaseWorldMap(world));
}

Future<void> waitForReleaseWidget(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 120 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}

BloriqGame releaseGame(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(releaseBoard).game!;

Future<void> solveVisibleBoard(WidgetTester tester) async {
  final game = releaseGame(tester);
  final controller = game.controller;
  final level = controller.state.level;
  expect(level.solution, hasLength(level.minimumMoves));
  for (final (index, move) in level.solution.indexed) {
    if (move.power case final power?) {
      await tapVisible(tester, releaseKey('power-${power.id}'));
    }
    await tester.ensureVisible(releaseBoard);
    await tester.pump();
    final layout = game.geometry;
    final source = controller.state.positionOf(move.blockId)!;
    final dx = (move.target.x - source.x).sign.toDouble();
    final dy = (move.target.y - source.y).sign.toDouble();
    // 빛 교대에는 드래그 방향이 영향을 주지 않는다.
    final direction = dx != 0 ? Offset(dx, 0) : Offset(0, dy);
    await tester.dragFrom(
      tester.getTopLeft(releaseBoard) + layout.center(source),
      direction * layout.cellSize * .74,
    );
    await tester.pump();
    expect(
      controller.state.moves,
      index + 1,
      reason: 'stage ${level.id}, $move',
    );
  }
  expect(controller.state.isComplete, isTrue);
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> preloadReleaseArt(WidgetTester tester) async {
  final preload = GlobalKey();
  await tester.pumpWidget(MaterialApp(home: SizedBox(key: preload)));
  await tester.runAsync(() => _loadArt(preload.currentContext!));
  await tester.pump();
}

Future<void> _loadArt(BuildContext context) async {
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
  await Future.wait([
    precacheImage(
      const ResizeImage(AssetImage(StarArt.forest), width: 1080),
      context,
    ),
    for (final asset in [StarArt.riq, StarArt.riqHappy])
      precacheImage(ResizeImage(AssetImage(asset), width: 384), context),
  ]);
}

Future<void> captureReleaseScreen(
  WidgetTester tester,
  GlobalKey key,
  String path,
) async {
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File(path);
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
