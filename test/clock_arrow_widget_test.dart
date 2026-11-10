import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/clock_arrow_art.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

const _start = Position(1, 0);
const _firstTarget = Position(2, 0);
const _goal = Level.goalBlockId;
final _board = find.byType(GameWidget<BloriqGame>);
final _phase = find.byKey(const ValueKey('clock-phase'));
final _dialog = find.byType(AlertDialog);

Level _clockBoard() {
  final cases = jsonDecode(
    File('test/fixtures/clock_arrow_fuzz.json').readAsStringSync(),
  ) as List;
  final row = cases.firstWhere((row) => row['level']['id'] == 1002);
  final level = row['level'] as Map<String, dynamic>;
  // 생성한 판은 그대로 쓰고 테스트 화면에 표시할 최소 수만 붙인다.
  return Level.fromJson({
    ...level,
    'minimumMoves': (row['solution'] as List).length,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  test(
    'live clock rotates 90 degrees in 200 ms and snaps with reduced motion',
    () {
      final controller = PuzzleController(_clockBoard());
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
      final before = _handAngles(game, ClockArrowArt.handColor);
      expect(before, hasLength(4));
      expect(controller.move(_goal, _firstTarget), isTrue);
      game.animateMove(controller.lastMove!);
      _expectTurn(game, before, 0);
      game.update(.1);
      _expectTurn(game, before, math.pi / 4);
      game.update(.1);
      _expectTurn(game, before, math.pi / 2);

      expect(controller.undo(), isTrue);
      game.clearEffects();
      expect(game.clockPhase!.value, 0);
      _expectTurn(game, before, 0);

      game.configureAppearance(colors: GameColors.dark, reduceMotion: true);
      expect(controller.move(_goal, _firstTarget), isTrue);
      game.animateMove(controller.lastMove!);
      _expectTurn(game, before, math.pi / 2);
    },
  );

  test(
    'replay shows the phase of each recorded move and leaves the state intact',
    () {
      final level = _clockBoard();
      final controller = PuzzleController(level);
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
      final before = _handAngles(game, ClockArrowArt.handColor);
      final path = const PuzzleSolver().solve(level)!;
      for (final move in path) {
        expect(controller.apply(move), isTrue);
      }
      final completed = controller.state;
      expect(game.startReplay(onFinished: () {}), isTrue);
      expect(game.clockPhase!.value, 0);
      game.update(.1);
      _expectTurn(game, before, math.pi / 4);
      game.update(.11);
      for (var step = 1; step <= path.length; step++) {
        expect(game.clockPhase!.value, step % 4, reason: 'replay move $step');
        if (step < path.length) game.update(2.5 / path.length);
      }
      game.skipReplay();
      expect(controller.state, same(completed));
      expect(game.clockPhase!.value, completed.moves % 4);
    },
  );

  testWidgets('clock heading, help, legal drag preview, undo and restart', (
    tester,
  ) async {
    const capture = bool.fromEnvironment('CAPTURE_CLOCK_RULE');
    if (capture) await tester.runAsync(_loadCaptureArt);
    final boundary = GlobalKey();
    final game = await _openBoard(tester, locale: 'ko', boundary: boundary);
    final t = AppLocalizations.of(tester.element(_board))!;
    final rule = _legend(t.clockArrowRule);
    expect(rule, findsOneWidget);
    _expectPhase(tester, t, 1);
    await tapVisible(tester, find.byTooltip(t.help));
    expect(find.descendant(of: _dialog, matching: rule), findsOneWidget);
    await tapVisible(
      tester,
      find.descendant(of: _dialog, matching: find.text(t.close)),
    );

    final drag = await _drag(tester, game, _start, const Offset(1, 0));
    final current = _handAngles(game, ClockArrowArt.handColor);
    final next = _handAngles(game, ClockArrowArt.ghostColor);
    expect(game.currentPreview?.nextState?.moves, 1);
    expect(game.controller.state.moves, 0);
    expect(next, hasLength(4));
    for (final (index, angle) in next.indexed) {
      expect(
        (angle - current[index]) % (2 * math.pi),
        closeTo(math.pi / 2, 1e-9),
      );
    }
    if (capture) await tester.runAsync(() => _capture(boundary));

    await drag.up();
    await tester.pump();
    expect(game.controller.state.goal.position, _firstTarget);
    _expectPhase(tester, t, 2);
    expect(_handAngles(game, ClockArrowArt.ghostColor), isEmpty);

    await tapVisible(tester, find.byIcon(Icons.undo_rounded));
    expect(game.controller.state.moves, 0);
    _expectPhase(tester, t, 1);
    final movedAgain = await _drag(tester, game, _start, const Offset(1, 0));
    await movedAgain.up();
    await tester.pump();
    _expectPhase(tester, t, 2);
    await tapVisible(tester, find.byIcon(Icons.refresh_rounded));
    _expectPhase(tester, t, 1);
    expect(game.controller.state.goal.position, _start);

    final blocked = await _drag(
      tester,
      game,
      const Position(1, 2),
      const Offset(1, 0),
    );
    expect(game.currentPreview?.isValid, isFalse);
    expect(_handAngles(game, ClockArrowArt.ghostColor), isEmpty);
    await blocked.up();
    await tester.pump();
    expect(game.controller.state.moves, 0);
    _expectPhase(tester, t, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final locale in ['ko', 'en']) {
    testWidgets(
      'clock heading, legend and help fit 320×568 at 200% in $locale',
      (tester) async {
        await _openBoard(tester, locale: locale);
        tester.view.physicalSize = const Size(320, 568);
        tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 32));
        }
        final context = tester.element(_board);
        final t = AppLocalizations.of(context)!;
        expect(MediaQuery.textScalerOf(context).scale(10), 20);
        _expectPhase(tester, t, 1);
        final phaseBounds = tester.getRect(_phase);
        expect(phaseBounds.left, greaterThanOrEqualTo(0));
        expect(phaseBounds.right, lessThanOrEqualTo(320));
        expect(phaseBounds.bottom, lessThan(tester.getTopLeft(_board).dy));
        final rule = _legend(t.clockArrowRule);
        expect(rule, findsOneWidget);
        await tester.ensureVisible(rule);
        await tester.pump();
        expect(tester.getRect(rule).bottom, lessThanOrEqualTo(568 - 32));

        await tapVisible(tester, find.byTooltip(t.help));
        final helpRule = find.descendant(of: _dialog, matching: rule);
        await tester.ensureVisible(helpRule);
        await tester.pump();
        expect(helpRule, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }
}

void _expectPhase(WidgetTester tester, AppLocalizations t, int phase) {
  expect(
    tester.widget<Semantics>(_phase).properties.label,
    t.clockPhaseLabel(phase, 4),
  );
  expect(
    find.descendant(of: _phase, matching: find.text('$phase/4')),
    findsOneWidget,
  );
}

Finder _legend(String text) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data == text,
);

List<double> _handAngles(BloriqGame game, Color color) {
  final canvas = TestRecordingCanvas();
  game.render(canvas);
  final angles = <double>[];
  var angle = 0.0;
  var line = 0;
  for (final call in canvas.invocations.map((call) => call.invocation)) {
    if (call.memberName == #rotate) {
      angle = call.positionalArguments.single as double;
    }
    if (call.memberName == #drawLine &&
        (call.positionalArguments.last as Paint).color.toARGB32() ==
            color.toARGB32()) {
      if (line++ % 3 == 0) angles.add(angle);
    }
  }
  return angles;
}

void _expectTurn(BloriqGame game, List<double> before, double turn) {
  final angles = _handAngles(game, ClockArrowArt.handColor);
  expect(angles, hasLength(before.length));
  for (final (index, angle) in angles.indexed) {
    expect(angle, closeTo(before[index] + turn, 1e-9));
  }
}

Future<TestGesture> _drag(
  WidgetTester tester,
  BloriqGame game,
  Position from,
  Offset direction,
) async {
  final start = tester.getTopLeft(_board) + game.geometry.center(from);
  final drag = await tester.startGesture(start);
  await drag.moveBy(direction * (game.geometry.cellSize * .68));
  await tester.pump();
  return drag;
}

Future<BloriqGame> _openBoard(
  WidgetTester tester, {
  required String locale,
  Key? boundary,
}) async {
  tester.view.physicalSize = const Size(360, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.localesTestValue = [Locale(locale)];
  addTearDown(tester.platformDispatcher.clearLocalesTestValue);
  SharedPreferences.setMockInitialValues({
    'bloriq.onboarding.v1': 'skipped',
    GameAudio.musicKey: false,
    GameAudio.effectsKey: false,
  });
  final settings = GameSettings(reduceMotion: true);
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: BloriqApp(
        settings: settings,
        firstRunIntro: false,
        loadLevels: () async => [_clockBoard()],
      ),
    ),
  );
  await waitForHome(tester);
  await tapVisible(tester, find.byKey(const ValueKey('home-play')));
  expect(_board, findsOneWidget);
  return tester.widget<GameWidget<BloriqGame>>(_board).game!;
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

Future<void> _capture(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final output = File('docs/screenshots/world4/clock-rule.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
