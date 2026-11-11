import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_pool.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/story_session.dart';

void main() {
  test(
    'the voyage search returns a limit for the published storm board',
    () async {
      final pool = EndlessPool.parse(
        File(EndlessPool.asset).readAsStringSync(),
      );
      final controller = PuzzleController(
        pool.level(const VoyageBoard(10417, 0))!,
      );
      const path = [
        ('goal', 3, 4),
        ('b3', 0, 0),
        ('goal', 2, 4),
        ('goal', 2, 3),
        ('b2', 4, 4),
        ('goal', 2, 4),
        ('b3', 1, 0),
        ('goal', 3, 4),
        ('goal', 3, 3),
        ('b3', 2, 0),
        ('b1', 0, 4),
        ('goal', 3, 2),
        ('b3', 1, 0),
        ('b1', 0, 3),
        ('b2', 3, 4),
        ('b2', 2, 4),
        ('b3', 2, 0),
        ('b1', 0, 2),
        ('b2', 1, 4),
        ('b3', 1, 0),
        ('b2', 0, 4),
        ('b3', 2, 0),
      ];
      for (final (id, x, y) in path) {
        expect(controller.move(id, Position(x, y)), isTrue);
      }
      final result = await const HintSearch().solve(controller.state);
      expect(result.limited, isTrue);
      expect(result.moves, isNull);
    },
  );

  test('a mid-board isolate hint returns the next legal move', () async {
    final level = Level(
      id: 1,
      boardWidth: 3,
      boardHeight: 1,
      startPosition: const Position(0, 0),
      exitPosition: const Position(2, 0),
      blocks: const [],
      obstacles: const [],
      minimumMoves: 2,
      difficulty: 'test',
    );
    final controller = PuzzleController(level);
    expect(controller.move(Level.goalBlockId, const Position(1, 0)), isTrue);
    final result = await const HintSearch().solve(controller.state);
    expect(result.limited, isFalse);
    expect(controller.apply(result.moves!.single), isTrue);
    expect(controller.state.isComplete, isTrue);
  });

  for (final (language, notice) in [
    ('en', 'Restart the board to try a Starlight hint from the start.'),
    ('ko', '처음부터 다시 하면 별빛 길을 쓸 수 있어요.'),
  ]) {
    testWidgets(
      'a timed-out isolate hint shows restart guidance in $language',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        SharedPreferences.setMockInitialValues({
          GameAudio.musicKey: false,
          GameAudio.effectsKey: false,
          ProgressionRepository.storageKey: jsonEncode({
            'version': 1,
            'backfilled': true,
            'stardust': 100,
          }),
        });
        const capture = bool.fromEnvironment('CAPTURE_FOUNDATION');
        if (capture && language == 'ko') await tester.runAsync(_loadCaptureArt);
        final session = await loadStorySession(tester);
        final settings = GameSettings(reduceMotion: true);
        final search = _DelayedHint();
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
            debugShowCheckedModeBanner: false,
              theme: GameTheme.dark,
              locale: Locale(language),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: GameScreen(
                session: session,
                settings: settings,
                initialLevelId: 1,
                hintSearch: search,
              ),
            ),
          ),
        );
        await tester.pump();
        final board = find.byType(GameWidget<BloriqGame>);
        final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
        await tester.dragFrom(
          tester.getTopLeft(board) +
              game.geometry.center(game.controller.state.goal.position),
          Offset(game.geometry.cellSize * .7, 0),
        );
        await tester.pump();
        expect(game.controller.state.moves, 1);

        final hint = find.byKey(const ValueKey('starlight-path'));
        final tap = tester.widget<InkWell>(hint).onTap!;
        tap();
        tap();
        await tester.pump(const Duration(milliseconds: 150));
        expect(search.calls, 1);
        expect(tester.widget<InkWell>(hint).onTap, isNull);
        expect(
          find.descendant(
            of: hint,
            matching: find.byType(CircularProgressIndicator),
          ),
          findsOneWidget,
        );
        if (capture && language == 'ko') {
        await tester.pump(const Duration(milliseconds: 250));
          await tester.runAsync(() => _capture(boundaryKey));
        }

        await tester.runAsync(search.finish);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(notice), findsOneWidget);
        expect(tester.widget<InkWell>(hint).onTap, isNotNull);
        expect(game.hintMove, isNull);
        expect(session.progression.stardust, 100);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await disposeStorySession(tester, session);
        settings.dispose();
      },
    );
  }
}

// 테스트가 버튼 상태를 확인한 뒤 실제 compute를 실행할 수 있게 지연한다.
class _DelayedHint extends HintSearch {
  _DelayedHint() : super(timeLimit: Duration.zero);

  int calls = 0;
  late PuzzleState _state;
  final _response = Completer<HintResult>();

  @override
  Future<HintResult> solve(PuzzleState state) {
    calls++;
    _state = state;
    return _response.future;
  }

  Future<void> finish() async {
    _response.complete(await super.solve(_state));
  }
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
  final directory = Directory('docs/screenshots/foundation')
    ..createSync(recursive: true);
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
  File('${directory.path}/hint-calculating.png')
      .writeAsBytesSync(bytes.buffer.asUint8List());
  image.dispose();
}
