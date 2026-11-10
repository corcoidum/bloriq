import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/ice_art.dart';
import 'package:bloriq/game/shelf_door_art.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_SHELF_RULE');
const _goal = Level.goalBlockId;
const _start = Position(0, 0);
const _ice = Position(1, 0);
const _entrance = Position(2, 0);
const _arrival = Position(2, 4);
final _dialog = find.byType(AlertDialog);

Level _previewLevel({bool blocked = false}) {
  final row = solverFixtureRows('test/fixtures/shelf_door_fuzz.json')
      .firstWhere((row) => row['level']['id'] == 3006);
  final data = row['level'] as Map<String, dynamic>;
  final solution = row['solution'] as List;
  return Level.fromJson({
    ...data,
    if (blocked)
      'obstacles': [
        ...data['obstacles'] as List,
        {'x': _arrival.x, 'y': _arrival.y},
      ],
    'minimumMoves': solution.length,
    'solution': [
      for (final step in solution)
        {
          'blockId': step[0],
          'target': {'x': step[2][0], 'y': step[2][1]},
        },
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  test('ice approaches A, then the two shelves open over 250 ms', () {
    final controller = PuzzleController(_previewLevel());
    final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
    final entrance = game.geometry.center(_entrance);
    final arrival = game.geometry.center(_arrival);
    final initial = _draw(game);
    final a = _at(initial, entrance);
    final b = _at(initial, arrival);
    expect(a, greaterThan(0));
    expect(b, greaterThan(0));

    expect(controller.move(_goal, _ice), isTrue);
    final move = controller.lastMove!;
    final slide = IceSlide.forMove(move)!;
    expect(slide.travelSeconds, closeTo(.14, 1e-9));
    game.animateMove(move);
    game.update(.07);
    final approach = _draw(game);
    expect(_circles(approach, IceArt.frostColor), isNotEmpty);
    expect(_at(approach, entrance), a);
    expect(_at(approach, arrival), b);

    game.update(.12);
    final entry = _draw(game);
    expect(_open(entry), isTrue);
    expect(_at(entry, entrance), a + 1);
    expect(_at(entry, arrival), b);

    game.update(ShelfDoorArt.transitSeconds / 2);
    final exit = _draw(game);
    expect(_open(exit), isTrue);
    expect(_at(exit, entrance), a);
    expect(_at(exit, arrival), b + 1);

    game.update(.076);
    final stopped = _draw(game);
    expect(_open(stopped), isFalse);
    expect(_at(stopped, arrival), b + 1);
    expect(controller.state.goal.position, _arrival);

    game.configureAppearance(colors: GameColors.dark, reduceMotion: true);
    game.animateMove(move);
    final reduced = _draw(game);
    expect(_open(reduced), isFalse);
    expect(_at(reduced, arrival), b + 1);
    expect(_circles(reduced, IceArt.frostColor), isEmpty);
  });

  test('replay uses recorded shelf transits without changing puzzle state', () {
    final level = _previewLevel();
    final controller = PuzzleController(level);
    for (final move in level.solution) {
      expect(controller.apply(move), isTrue);
    }
    final completed = controller.state;
    expect(completed.isComplete, isTrue);
    final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
    expect(game.startReplay(onFinished: () {}), isTrue);
    game.update(.19);
    expect(_open(_draw(game)), isTrue);
    game.update(.125);
    expect(_open(_draw(game)), isTrue);
    game.skipReplay();
    expect(controller.state, same(completed));
  });

  testWidgets('drag previews the paired shelf with ice trail only to A', (
    tester,
  ) async {
    final boundary = await _openBoard(tester, captureArt: _capture);
    final game = releaseGame(tester);
    final t = AppLocalizations.of(tester.element(releaseBoard))!;
    await _selectLegend(tester, t);
    await _checkHelp(tester, t);

    final drag = await _drag(tester, game);
    final preview = game.currentPreview!;
    expect(preview.target, _arrival);
    expect(preview.teleport?.from, _entrance);
    expect(preview.teleport?.to, _arrival);
    expect(preview.slides, isTrue);
    expect(preview.nextState?.echo, _start);
    expect(game.controller.state.moves, 0);
    final canvas = _draw(game);
    for (var pair = 0; pair < 2; pair++) {
      expect(_circles(canvas, ShelfDoorArt.pairColor(pair)), isNotEmpty);
    }
    final dots = _circles(canvas, IceArt.previewColor);
    final entrance = game.geometry.center(_entrance);
    expect(dots.last.dx, closeTo(entrance.dx, game.geometry.cellSize * .15));
    expect(dots.every((point) => point.dy == entrance.dy), isTrue);
    if (_capture) {
      await captureReleaseScreen(
        tester,
        boundary,
        'docs/screenshots/world6/shelf-rule.png',
      );
    }
    await drag.up();
    await tester.pump();
    expect(game.controller.state.goal.position, _arrival);
    expect(game.controller.state.moves, 1);
    expect(game.controller.state.echo, _start);
    await tapVisible(tester, find.byIcon(Icons.undo_rounded));
    expect(game.controller.state.goal.position, _start);
    expect(game.controller.state.moves, 0);
    await closeReleaseApp(tester);
  });

  testWidgets('drag marks A as the actual stop when B is occupied', (
    tester,
  ) async {
    await _openBoard(tester, blocked: true);
    final game = releaseGame(tester);
    final drag = await _drag(tester, game);
    final preview = game.currentPreview!;
    expect(preview.isValid, isTrue);
    expect(preview.target, _entrance);
    expect(preview.teleport, isNull);
    await drag.up();
    await tester.pump();
    expect(game.controller.state.goal.position, _entrance);
    expect(game.controller.lastMove!.teleports, isEmpty);
    await closeReleaseApp(tester);
  });

  for (final lang in ['ko', 'en']) {
    testWidgets('shelf board, help and result fit 320×568 at 200% ($lang)', (
      tester,
    ) async {
      await _openBoard(tester, locale: Locale(lang));
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      final context = tester.element(releaseBoard);
      final t = AppLocalizations.of(context)!;
      expect(MediaQuery.textScalerOf(context).scale(10), 20);
      await _selectLegend(tester, t);
      final rule = _legend(t.shelfDoorRule);
      await tester.ensureVisible(rule);
      await tester.pump();
      expect(tester.getRect(rule).bottom, lessThanOrEqualTo(536));
      await _checkHelp(tester, t);
      await solveVisibleBoard(tester);
      final next = releaseKey('result-next');
      await waitForReleaseWidget(tester, next);
      expect(releaseVictory, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.pump();
      expect(tester.getRect(next).bottom, lessThanOrEqualTo(536));
      await closeReleaseApp(tester);
    });
  }
}

Future<GlobalKey> _openBoard(
  WidgetTester tester, {
  bool captureArt = false,
  bool blocked = false,
  Locale locale = const Locale('ko'),
}) async {
  seedCampaign({});
  final boundary = await openReleaseApp(
    tester,
    captureArt: captureArt,
    locale: locale,
    loadLevels: () async => [_previewLevel(blocked: blocked)],
  );
  await tapVisible(tester, releaseKey('home-play'));
  expect(releaseBoard, findsOneWidget);
  return boundary;
}

Finder _legend(String text) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data == text,
);

Future<void> _selectLegend(WidgetTester tester, AppLocalizations t) async {
  final chip = releaseKey('legend-shelfDoor');
  if (chip.evaluate().isNotEmpty) await tapVisible(tester, chip);
  expect(_legend(t.shelfDoorRule), findsOneWidget);
}

Future<void> _checkHelp(WidgetTester tester, AppLocalizations t) async {
  await tapVisible(tester, find.byTooltip(t.help));
  final helpRule = find.descendant(
    of: _dialog,
    matching: _legend(t.shelfDoorRule),
  );
  expect(helpRule, findsOneWidget);
  await tester.ensureVisible(helpRule);
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tapVisible(
    tester,
    find.descendant(of: _dialog, matching: find.text(t.close)),
  );
}

Future<TestGesture> _drag(WidgetTester tester, BloriqGame game) async {
  await tester.ensureVisible(releaseBoard);
  await tester.pump();
  final center = tester.getTopLeft(releaseBoard) + game.geometry.center(_start);
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(Offset(game.geometry.cellSize * .68, 0));
  await tester.pump();
  return gesture;
}

TestRecordingCanvas _draw(BloriqGame game) {
  final canvas = TestRecordingCanvas();
  game.render(canvas);
  return canvas;
}

Iterable<Offset> _translations(TestRecordingCanvas canvas) sync* {
  for (final call in canvas.invocations.map((call) => call.invocation)) {
    if (call.memberName == #translate) {
      yield Offset(
        call.positionalArguments[0] as double,
        call.positionalArguments[1] as double,
      );
    }
  }
}

int _at(TestRecordingCanvas canvas, Offset at) =>
    _translations(canvas).where((point) => (point - at).distance < 1e-8).length;

bool _open(TestRecordingCanvas canvas) => _translations(canvas).any(
  (point) => point.dy == 0 && point.dx.abs() > .001 && point.dx.abs() <= .37,
);

List<Offset> _circles(TestRecordingCanvas canvas, Color color) => [
  for (final call in canvas.invocations.map((call) => call.invocation))
    if (call.memberName == #drawCircle &&
        ((call.positionalArguments.last as Paint).color.toARGB32() &
                0xffffff) ==
            (color.toARGB32() & 0xffffff))
      call.positionalArguments.first as Offset,
];
