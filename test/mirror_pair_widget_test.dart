import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/keep_all_text.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/board_badge.dart';
import 'package:bloriq/game/mirror_pair_art.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/postcard/echo_postcard.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

Level _mirrorBoard() => Level.fromJson(
  jsonDecode('''
{
  "id": 201,
  "world": 3,
  "boardWidth": 5,
  "boardHeight": 5,
  "startPosition": {"x": 1, "y": 3},
  "exitPosition": {"x": 1, "y": 2},
  "blocks": [
    {"id": "b1", "x": 1, "y": 1},
    {"id": "b2", "x": 4, "y": 1},
    {"id": "b3", "x": 3, "y": 3}
  ],
  "obstacles": [{"x": 3, "y": 0}, {"x": 0, "y": 3}, {"x": 4, "y": 4}],
  "specialRules": [
    {"type": "mirrorPair", "blocks": ["b1", "b2"]},
    {"type": "mirrorPair", "blocks": ["goal", "b3"]}
  ],
  "minimumMoves": 1,
  "difficulty": "test"
}
''') as Map<String, dynamic>,
);

const _pushed = Position(1, 1);
const _pushedTo = Position(2, 1);
const _twin = Position(4, 1);
const _twinTo = Position(3, 1);
final _board = find.byType(GameWidget<BloriqGame>);
final _badge = find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter is BoardBadge &&
      (widget.painter! as BoardBadge).type == MirrorPair.typeId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  test(
    'a twin starts after 100 ms and reduced motion moves it immediately',
    () {
      final controller = PuzzleController(_mirrorBoard());
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
      controller.move('b1', _pushedTo);
      game.animateMove(controller.lastMove!);
      final startX = game.geometry.center(_twin).dx;
      final endX = game.geometry.center(_twinTo).dx;
      expect(_solidRingXs(game).last, startX);
      game.update(.099);
      expect(_solidRingXs(game).last, startX);
      game.update(.06);
      expect(_solidRingXs(game).last, inExclusiveRange(endX, startX));
      game.update(.18);
      expect(_solidRingXs(game).last, endX);

      controller.restart();
      game.configureAppearance(colors: GameColors.dark, reduceMotion: true);
      controller.move('b1', _pushedTo);
      game.animateMove(controller.lastMove!);
      expect(_solidRingXs(game).last, endX);
    },
  );

  test('replay paints the recorded twin shift without changing game state', () {
    final controller = PuzzleController(_mirrorBoard())
      ..move('b1', _pushedTo)
      ..move('b3', const Position(3, 4));
    final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
    final completed = controller.state;
    expect(completed.isComplete, isTrue);
    expect(game.startReplay(onFinished: () {}), isTrue);
    final startX = game.geometry.center(_twin).dx;
    final endX = game.geometry.center(_twinTo).dx;
    game.update(.06);
    expect(_solidRingXs(game).last, startX);
    game.update(.30);
    expect(_solidRingXs(game).last, inExclusiveRange(endX, startX));
    game.skipReplay();
    expect(_solidRingXs(game).last, endX);
    expect(controller.state, same(completed));
  });

  test('a power drag previews the landing without a twin arrow', () {
    final controller = PuzzleController(
      _mirrorBoard(),
      powers: {PuzzlePower.wind},
    );
    final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
    game.setDrag(
      'b1',
      Offset(game.geometry.cellSize * .7, 0),
      PuzzlePower.wind,
    );
    final preview = game.currentPreview!;
    expect(preview.isValid, isTrue);
    expect(preview.target, _twinTo);
    expect(preview.nextState?.positionOf('b2'), _twin);
    expect(preview.twin, isNull);
  });

  testWidgets(
    'drag previews both outcomes, shows help, and records the postcard',
    (tester) async {
      const capture = bool.fromEnvironment('CAPTURE_MIRROR_RULE');
      if (capture) await tester.runAsync(_loadCaptureArt);
      final key = GlobalKey();
      final game = await _openBoard(tester, locale: 'ko', boundary: key);
      final rule = AppLocalizations.of(tester.element(_board))!.mirrorPairRule;
      expect(_legend(rule), findsOneWidget);
      expect(_badge, findsOneWidget);
      expect(_solidRingXs(game), hasLength(2));
      expect(
        _paintCalls(game, #drawArc, MirrorPairArt.color(1)),
        hasLength(24),
      );

      final help = find.byTooltip('게임 방법');
      await tapVisible(tester, help);
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: _legend(rule)),
        findsOneWidget,
      );
      await tapVisible(
        tester,
        find.descendant(of: dialog, matching: find.text('닫기')),
      );

      final drag = await tester.startGesture(
        _screenPoint(tester, game, _pushed),
      );
      await drag.moveBy(Offset(game.geometry.cellSize * .68, 0));
      await tester.pump();
      expect(game.currentPreview?.twin?.to, _twinTo);
      expect(game.controller.state.moves, 0);
      expect(
        _paintCalls(
          game,
          #drawLine,
          MirrorPairArt.color(0).withValues(alpha: .68),
        ),
        hasLength(3),
      );
      if (capture) await tester.runAsync(() => _capture(key));

      await drag.up();
      await tester.pump();
      expect(game.controller.state.positionOf('b1'), _pushedTo);
      expect(game.controller.state.positionOf('b2'), _twinTo);
      expect(game.controller.state.moves, 1);

      final blocked = await tester.startGesture(
        _screenPoint(tester, game, _pushedTo),
      );
      await blocked.moveBy(Offset(0, game.geometry.cellSize * .68));
      await tester.pump();
      expect(game.currentPreview?.isValid, isTrue);
      expect(game.currentPreview?.twin?.to, _twinTo);
      expect(
        _paintCalls(game, #drawLine, MirrorPairArt.color(0)),
        hasLength(2),
      );
      await blocked.cancel();

      await tester.dragFrom(
        _screenPoint(tester, game, const Position(3, 3)),
        Offset(0, game.geometry.cellSize * .68),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(game.controller.state.isComplete, isTrue);
      await tapVisible(tester, find.byKey(const ValueKey('result-more')));
      await tapVisible(tester, find.byKey(const ValueKey('result-postcard')));
      final postcard = tester.widget<EchoPostcardDialog>(
        find.byType(EchoPostcardDialog),
      );
      expect(postcard.data.mirrorSteps, [
        (pair: 0, dx: -1, dy: 0),
        (pair: 1, dx: 0, dy: -1),
      ]);
      final postcardCanvas = TestRecordingCanvas();
      EchoPostcardPainter(postcard.data)
          .paint(postcardCanvas, const Size.square(1080));
      for (var pair = 0; pair < 2; pair++) {
        expect(
          _colorCalls(postcardCanvas, #drawLine, MirrorPairArt.color(pair)),
          hasLength(3),
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  for (final locale in ['ko', 'en']) {
    testWidgets('mirror legend fits a 320×568 phone at 200% in $locale', (
      tester,
    ) async {
      await _openBoard(tester, locale: locale);
      tester.view.physicalSize = const Size(320, 568);
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 32));
      }
      final context = tester.element(_board);
      expect(MediaQuery.textScalerOf(context).scale(10), 20);
      expect(
        _legend(AppLocalizations.of(context)!.mirrorPairRule),
        findsOneWidget,
      );
      await tester.ensureVisible(_badge);
      await tester.pump();
      expect(tester.getRect(_badge).bottom, lessThanOrEqualTo(568 - 32));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}

Finder _legend(String rule) => find.byWidgetPredicate(
  (widget) => widget is KeepAllText && widget.data == rule,
);

List<Invocation> _paintCalls(BloriqGame game, Symbol method, Color color) {
  final canvas = TestRecordingCanvas();
  game.render(canvas);
  return _colorCalls(canvas, method, color);
}

List<Invocation> _colorCalls(
  TestRecordingCanvas canvas,
  Symbol method,
  Color color,
) => [
  for (final call in canvas.invocations.map((call) => call.invocation))
    if (call.memberName == method &&
        (call.positionalArguments.last as Paint).color.toARGB32() ==
            color.toARGB32())
      call,
];

List<double> _solidRingXs(BloriqGame game) => [
  for (final call in _paintCalls(game, #drawOval, MirrorPairArt.color(0)))
    (call.positionalArguments.first as Rect).center.dx,
];

Offset _screenPoint(WidgetTester tester, BloriqGame game, Position p) =>
    tester.getTopLeft(_board) + game.geometry.center(p);

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
        loadLevels: () async => [_mirrorBoard()],
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
    final output = File('docs/screenshots/world3/mirror-rule.png');
    output.parent.createSync(recursive: true);
    output.writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
