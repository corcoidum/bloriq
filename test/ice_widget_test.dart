import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/ice_art.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_ICE_RULE');
const _goal = Level.goalBlockId;
const _start = Position(1, 0);
const _landing = Position(2, 0);
const _stop = Position(3, 0);
const _exit = Position(3, 1);
final _dialog = find.byType(AlertDialog);

Level _previewLevel() {
  final row = solverFixtureRows('test/fixtures/ice_fuzz.json')
      .firstWhere((row) => row['level']['id'] == 2263);
  return Level.fromJson({
    ...row['level'] as Map<String, dynamic>,
    'minimumMoves': (row['solution'] as List).length,
    'availablePowers': <String>[],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  test('ice travel is 70 ms per cell with frost and a backward recoil', () {
    final controller = PuzzleController(_previewLevel());
    expect(controller.move(_goal, _landing), isTrue);
    final move = controller.lastMove!;
    final slide = IceSlide.forMove(move)!;
    expect(slide.travelSeconds, closeTo(.14, 1e-9));
    final canvas = TestRecordingCanvas();
    const end = Offset(120, 0);
    Offset at(double seconds) =>
        slide.draw(canvas, Offset.zero, end, 60, seconds / slide.seconds);
    expect(at(.07).dx, closeTo(60, 1e-9));
    expect(at(.14).dx, closeTo(120, 1e-9));
    expect(at(.20).dx, lessThan(120));
    expect(at(slide.seconds).dx, closeTo(120, 1e-9));
    expect(_dots(canvas, IceArt.frostColor), isNotEmpty);

    final game = BloriqGame(controller)..onGameResize(Vector2(300, 240));
    game.animateMove(move);
    game.update(.07);
    expect(_dots(_render(game), IceArt.frostColor), isNotEmpty);
    game.configureAppearance(colors: GameColors.dark, reduceMotion: true);
    game.animateMove(move);
    expect(_dots(_render(game), IceArt.frostColor), isEmpty);
    expect(controller.state.goal.position, _stop);
  });

  test(
    'replay animates a recorded ice move without changing the final state',
    () {
      final controller = PuzzleController(_previewLevel());
      expect(controller.move(_goal, _landing), isTrue);
      expect(controller.move(_goal, _exit), isTrue);
      final finalState = controller.state;
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 240));
      expect(game.startReplay(onFinished: () {}), isTrue);
      game.update(.07);
      expect(_dots(_render(game), IceArt.frostColor), isNotEmpty);
      game.skipReplay();
      expect(controller.state, same(finalState));
    },
  );

  testWidgets('drag shows the ice stop and trajectory, then moves one turn', (
    tester,
  ) async {
    final boundary = await _openBoard(tester, captureArt: _capture);
    final game = releaseGame(tester);
    final t = AppLocalizations.of(tester.element(releaseBoard))!;
    expect(_legend(t.iceRule), findsOneWidget);
    await _checkHelp(tester, t);

    final drag = await _drag(tester, game, _start, const Offset(1, 0));
    final preview = game.currentPreview!;
    expect(preview.target, _stop);
    expect(preview.slides, isTrue);
    expect(preview.nextState?.echo, _start);
    expect(game.controller.state.moves, 0);
    final dots = _dots(_render(game), IceArt.previewColor);
    final firstIce = game.geometry.center(_landing);
    final stop = game.geometry.center(_stop);
    expect(dots.last.dx, greaterThan(firstIce.dx));
    expect(dots.last.dx, closeTo(stop.dx, game.geometry.cellSize * .15));
    expect(dots.every((point) => point.dy == stop.dy), isTrue);
    if (_capture) {
      await captureReleaseScreen(
        tester,
        boundary,
        'docs/screenshots/world5/ice-rule.png',
      );
    }

    await drag.up();
    await tester.pump();
    expect(game.controller.state.goal.position, _stop);
    expect(game.controller.state.moves, 1);
    expect(game.controller.state.echo, _start);
    expect(_dots(_render(game), IceArt.previewColor), isEmpty);
    await tapVisible(tester, find.byIcon(Icons.undo_rounded));
    expect(game.controller.state.goal.position, _start);
    expect(game.controller.state.moves, 0);
    await closeReleaseApp(tester);
  });

  for (final lang in ['ko', 'en']) {
    testWidgets('ice board, help and result fit 320×568 at 200% ($lang)', (
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
      final rule = _legend(t.iceRule);
      await tester.ensureVisible(rule);
      await tester.pump();
      expect(tester.getRect(rule).bottom, lessThanOrEqualTo(536));
      await _checkHelp(tester, t);

      final game = releaseGame(tester);
      for (final (from, direction) in [
        (_start, const Offset(1, 0)),
        (_stop, const Offset(0, 1)),
      ]) {
        final drag = await _drag(tester, game, from, direction);
        await drag.up();
        await tester.pump();
      }
      expect(game.controller.state.moves, 2);
      expect(game.controller.state.isComplete, isTrue);
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
  Locale locale = const Locale('ko'),
}) async {
  seedCampaign({});
  final boundary = await openReleaseApp(
    tester,
    captureArt: captureArt,
    locale: locale,
    loadLevels: () async => [_previewLevel()],
  );
  await tapVisible(tester, releaseKey('home-play'));
  expect(releaseBoard, findsOneWidget);
  return boundary;
}

Future<void> _checkHelp(WidgetTester tester, AppLocalizations t) async {
  await tapVisible(tester, find.byTooltip(t.help));
  final helpRule = find.descendant(of: _dialog, matching: _legend(t.iceRule));
  expect(helpRule, findsOneWidget);
  await tester.ensureVisible(helpRule);
  await tester.pump();
  expect(tester.takeException(), isNull);
  await tapVisible(
    tester,
    find.descendant(of: _dialog, matching: find.text(t.close)),
  );
}

Finder _legend(String text) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data == text,
);

Future<TestGesture> _drag(
  WidgetTester tester,
  BloriqGame game,
  Position from,
  Offset direction,
) async {
  await tester.ensureVisible(releaseBoard);
  await tester.pump();
  final center = tester.getTopLeft(releaseBoard) + game.geometry.center(from);
  final gesture = await tester.startGesture(center);
  await gesture.moveBy(direction * game.geometry.cellSize * .68);
  await tester.pump();
  return gesture;
}

TestRecordingCanvas _render(BloriqGame game) {
  final canvas = TestRecordingCanvas();
  game.render(canvas);
  return canvas;
}

List<Offset> _dots(TestRecordingCanvas canvas, Color color) => [
  for (final call in canvas.invocations.map((call) => call.invocation))
    if (call.memberName == #drawCircle &&
        ((call.positionalArguments.last as Paint).color.toARGB32() &
                0xffffff) ==
            (color.toARGB32() & 0xffffff))
      call.positionalArguments.first as Offset,
];
