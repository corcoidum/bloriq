import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/keep_all_text.dart';
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

import 'support/start_game.dart';
import 'support/failing_save_store.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD3_RELEASE');
const _chaptersThroughWorld2 = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
final _board = find.byType(GameWidget<BloriqGame>);
final _victory = find.byType(VictoryPanel);

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'Mirror Lake shows its three cards, help replay, and first clear',
    (tester) async {
      _seed(_chaptersThroughWorld2);
      final boundary = await _openApp(tester, captureArt: true);
      final world3 = await _openLightroad(tester);
      expect(
        find.descendant(of: world3, matching: find.text('둘째 등대 · 물에 비친 잔상')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: world3, matching: find.text('0 / 25 스테이지')),
        findsOneWidget,
      );
      expect(_key('saga-enter-3'), findsOneWidget);
      await _shot(tester, boundary, 'lightroad');
      await tapVisible(tester, _key('saga-close'));

      await _enterWorld(tester, 3);
      expect(find.text('거울 호수 등대'), findsOneWidget);
      expect(_key('world-guardian-205'), findsNothing);
      await _shot(tester, boundary, 'mirror-lake-map');
      await tapVisible(tester, _key('world-continue'));
      await _waitFor(tester, _key('mirror-guide-1'));
      expect(_game(tester).controller.state.level.id, 201);
      expect(find.text('하나를 밀어 봐요'), findsOneWidget);
      await tapVisible(tester, _key('mirror-guide-next'));
      expect(find.text('짝은 반대로'), findsOneWidget);
      await _shot(tester, boundary, 'mirror-tutorial');
      await tapVisible(tester, _key('mirror-guide-next'));
      expect(find.text('막히면 제자리'), findsOneWidget);
      await tapVisible(tester, _key('mirror-guide-next'));
      expect(_key('mirror-guide-3'), findsNothing);

      final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
      expect(frame.skin?.palette?.board, const Color(0xff263d59));
      expect(
        _game(tester).controller.state.level.mechanics.keys,
        contains('mirrorPair'),
      );
      await _shot(tester, boundary, 'mirror-lake-game');
      await tapVisible(tester, find.byTooltip('게임 방법'));
      await tapVisible(tester, _key('replay-mirror-guide'));
      expect(_key('mirror-guide-1'), findsOneWidget);
      await tapVisible(tester, _key('mirror-guide-skip'));

      await tapVisible(tester, _key('game-home'));
      await waitForHome(tester);
      await _enterWorld(tester, 3);
      await tapVisible(tester, _key('world-continue'));
      expect(_key('mirror-guide-1'), findsNothing);
      await _solveVisibleBoard(tester);
      await _waitFor(tester, _key('result-next'));
      await _shot(tester, boundary, 'mirror-lake-result');
      expect((await ProgressRepository.load()).forLevel(201)?.bestStars, 3);
      await _closeApp(tester);
    },
  );

  for (final retrySave in [false, true]) {
    testWidgets('the last Cloud-Sea clear opens the second lighthouse '
        '${retrySave ? 'after retrying the save' : 'on the first save'}', (
      tester,
    ) async {
      _seed(
        _chaptersThroughWorld2.difference({10}),
        cleared: _levels(2).take(24),
      );
      final store = await FailingSaveStore.install();
      await _openApp(tester);
      await _openLightroad(tester);
      expect(_key('saga-enter-3'), findsNothing);
      await tapVisible(tester, _key('saga-close'));

      await _enterWorld(tester, 2);
      await tapVisible(tester, _key('world-continue'));
      expect(_game(tester).controller.state.level.id, 125);
      if (retrySave) store.rejectedKeys.add(ProgressRepository.storageKey);
      await _solveVisibleBoard(tester);
      if (retrySave) {
        await _waitFor(tester, _key('retry-progress'));
        expect(_key('world-clear'), findsNothing);
        store.rejectedKeys.clear();
        await tapVisible(tester, _key('retry-progress'));
      }
      await _waitFor(tester, _key('world-clear'));
      expect(
        (await ProgressionRepository.load()).completedChapters,
        contains(10),
      );
      await tapVisible(tester, _key('result-next'));
      await _waitFor(tester, _worldMap(3));
      expect(find.text('거울 호수 등대'), findsOneWidget);
      await tapVisible(tester, _key('world-close'));
      await waitForHome(tester);
      expect(
        find.descendant(
          of: _key('world-entry'),
          matching: find.text('거울 호수 등대로'),
        ),
        findsOneWidget,
      );
      final world3 = await _openLightroad(tester);
      expect(_key('saga-enter-3'), findsOneWidget);
      expect(
        find.descendant(of: world3, matching: find.text('0 / 25 스테이지')),
        findsOneWidget,
      );
      await _closeApp(tester);
    });
  }

  testWidgets('replaying a completed chapter repairs an older missing unlock', (
    tester,
  ) async {
    _seed(_chaptersThroughWorld2.difference({6}), cleared: _levels(2));
    await _openApp(tester);
    await _enterWorld(tester, 2);
    await tapVisible(tester, _key('world-continue'));
    expect(_game(tester).controller.state.level.id, 101);
    await _solveVisibleBoard(tester);
    await _waitFor(tester, _key('world-clear'));
    expect((await ProgressionRepository.load()).completedChapters, contains(6));
    await tapVisible(tester, _key('result-next'));
    await _waitFor(tester, _worldMap(3));
    await _closeApp(tester);
  });

  testWidgets(
    'clearing the guardian exposes its memory in the constellation atlas',
    (tester) async {
      _seed({..._chaptersThroughWorld2, 11}, cleared: _levels(3).take(5));
      final boundary = await _openApp(tester, captureArt: true);
      await _enterWorld(tester, 3);
      final pages = find.descendant(
        of: _worldMap(3),
        matching: find.byType(PageView),
      );
      await tester.drag(pages, const Offset(300, 0));
      await tester.pump(const Duration(milliseconds: 450));
      await _waitFor(tester, _key('world-guardian-205'));
      await tapVisible(tester, _key('world-guardian-205'));
      final atlas = _key('guardian-atlas-205');
      expect(atlas, findsOneWidget);
      expect(
        find.descendant(of: atlas, matching: find.text('별자리 도감')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: atlas, matching: find.text('고요')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: atlas,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is KeepAllText && widget.data.contains('발소리는 이어졌어'),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: atlas, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget,
      );
      await _shot(tester, boundary, 'guardian-atlas');
      await tapVisible(
        tester,
        find.descendant(of: atlas, matching: find.text('닫기')),
      );
      await tapVisible(tester, _key('world-stage-201'));
      expect(_game(tester).controller.state.level.id, 201);
      expect(_key('mirror-guide-1'), findsNothing);
      await _closeApp(tester);
    },
  );

  testWidgets('Mirror Lake play and victory fit 320×568 with 200% text', (
    tester,
  ) async {
    _seed(_chaptersThroughWorld2);
    await _openApp(tester);
    await _enterWorld(tester, 3);
    await tapVisible(tester, _key('world-continue'));
    await tapVisible(tester, _key('mirror-guide-skip'));
    tester.view.physicalSize = const Size(320, 568);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(MediaQuery.textScalerOf(tester.element(_board)).scale(10), 20);
    expect(tester.takeException(), isNull);
    await _solveVisibleBoard(tester);
    await _waitFor(tester, _key('result-next'));
    expect(_victory, findsOneWidget);
    await tester.ensureVisible(_key('result-next'));
    await tester.pump();
    expect(
      tester.getRect(_key('result-next')).bottom,
      lessThanOrEqualTo(568 - 32),
    );
    expect(tester.takeException(), isNull);
    await _closeApp(tester);
  });
}

void _seed(Set<int> chapters, {Iterable<Level> cleared = const []}) {
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

List<Level> _levels(int world) => Worlds.parseLevels(
  File('assets/levels/world$world.json').readAsStringSync(),
  world,
);

Future<GlobalKey> _openApp(
  WidgetTester tester, {
  bool captureArt = false,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [const Locale('ko')];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  if (_capture && captureArt) {
    final preload = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: SizedBox(key: preload)));
    await tester.runAsync(() => _loadArt(preload.currentContext!));
    await tester.pump();
  }
  final settings = GameSettings(reduceMotion: true);
  addTearDown(settings.dispose);
  final boundary = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: BloriqApp(settings: settings, firstRunIntro: false),
    ),
  );
  await waitForHome(tester);
  return boundary;
}

Future<void> _closeApp(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<Finder> _openLightroad(WidgetTester tester) async {
  final mapButton = _key('saga-map');
  await _waitFor(tester, mapButton.hitTestable());
  await tapVisible(tester, mapButton);
  final node = _key('saga-world-3');
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

Finder _worldMap(int world) => find.byWidgetPredicate(
  (widget) => widget is WorldMap && widget.world == world,
);

Future<void> _enterWorld(WidgetTester tester, int world) async {
  final entry = _key('world-entry');
  await _waitFor(tester, entry.hitTestable());
  await tapVisible(tester, entry);
  await _waitFor(tester, _worldMap(world));
}

Future<void> _waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 120 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(finder, findsOneWidget);
}

BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

Future<void> _solveVisibleBoard(WidgetTester tester) async {
  final game = _game(tester);
  final controller = game.controller;
  final level = controller.state.level;
  expect(level.solution, hasLength(level.minimumMoves));
  for (final (index, move) in level.solution.indexed) {
    if (move.power case final power?) {
      await tapVisible(tester, _key('power-${power.id}'));
    }
    await tester.ensureVisible(_board);
    await tester.pump();
    final layout = game.geometry;
    final source = controller.state.positionOf(move.blockId)!;
    final dx = (move.target.x - source.x).sign.toDouble();
    final dy = (move.target.y - source.y).sign.toDouble();
    // 빛 교대에는 드래그 방향이 영향을 주지 않는다.
    final direction = dx != 0 ? Offset(dx, 0) : Offset(0, dy);
    await tester.dragFrom(
      tester.getTopLeft(_board) + layout.center(source),
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
    for (final asset in [StarArt.riq, StarArt.riqHappy])
      precacheImage(ResizeImage(AssetImage(asset), width: 384), context),
  ]);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (!_capture) return;
  expect(tester.takeException(), isNull);
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final output = File('docs/screenshots/world3/$name.png');
      output.parent.createSync(recursive: true);
      output.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}
