import 'support/art_test_assets.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:bloriq/companions/spirit_art.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(prepareMoonlitArt);
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      GameAudio.musicKey: false,
      GameAudio.effectsKey: false,
    });
  });
  testWidgets(
    'first five stages: real gestures, intro, rewards, collection, companion, restart',
    (tester) async {
      const capture = bool.fromEnvironment('CAPTURE_V51');
      final boundary = GlobalKey();
      Future<void> screenshot(String name) async {
        if (!capture) return;
        await tester.pump();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('docs/screenshots/v51/$name.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      if (capture) {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Directory('docs/screenshots/v51').createSync(recursive: true);
        final data = ByteData.sublistView(
          File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
              .readAsBytesSync(),
        );
        for (final name in ['Roboto', 'Ahem']) {
          await (FontLoader(name)..addFont(Future.value(data))).load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      final board = find.byType(GameWidget<BloriqGame>);
      Future<void> ready() async {
        for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 300));
      }

      Future<void> tap(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pump();
        await tester.tap(f);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
      }

      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const BloriqApp()),
      );
      await ready();
      expect(find.byTooltip('Skip intro'), findsOneWidget);
      for (var id = 1; id <= 5; id++) {
        final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
        for (final move in const PuzzleSolver().solve(
          game.controller.state.level,
        )!) {
          await tester.ensureVisible(board);
          await tester.pump();
          final from = game.controller.state.blocks
              .singleWhere((b) => b.id == move.blockId)
              .position;
          final g = game.geometry;
          await tester.dragFrom(
            tester.getTopLeft(board) + g.center(from),
            Offset(
              (move.target.x - from.x) * g.cellSize,
              (move.target.y - from.y) * g.cellSize,
            ),
          );
          await tester.pump(const Duration(milliseconds: 100));
          if (id == 1 && game.controller.state.moves == 1) {
            expect(find.textContaining('Wow! A light remains'), findsOneWidget);
          }
        }
        await tester.pump(const Duration(milliseconds: 1800));
        await tester.pump();
        expect(game.controller.state.isComplete, isTrue);
        expect(
          find.text(
            id == 5
                ? 'A guardian has awakened!'
                : 'A memory spirit has awakened!',
          ),
          findsOneWidget,
        );
        expect((await ProgressRepository.load()).spiritIds, hasLength(id));
        if (id == 1 || id == 5) {
          await tester.ensureVisible(
            find.text(
              id == 5
                  ? 'A guardian has awakened!'
                  : 'A memory spirit has awakened!',
            ),
          );
          await tester.pump();
          await screenshot('reward-stage-$id');
        }
        if (id < 5) await tap(find.text('Next level'));
      }
      await tap(find.byTooltip('Spirit collection'));
      expect(find.textContaining('5 / 25'), findsOneWidget);
      expect(find.text('Saebom'), findsNothing);
      await screenshot('collection-first-five');
      await tap(find.text('Lumi'));
      await screenshot('spirit-detail');
      await tap(find.text('Travel together'));
      await tap(find.byTooltip('Close'));
      expect((await ProgressRepository.load()).companionId, 'spirit_01');
      expect(
        tester
            .widgetList<SpiritArt>(find.byType(SpiritArt))
            .any((w) => w.spirit?.id == 'spirit_01'),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        RepaintBoundary(key: boundary, child: const BloriqApp()),
      );
      await ready();
      expect(find.byTooltip('Skip intro'), findsNothing);
      expect(
        tester
            .widgetList<SpiritArt>(find.byType(SpiritArt))
            .any((w) => w.spirit?.id == 'spirit_01'),
        isTrue,
      );
      await tap(find.byTooltip('How to play'));
      await tap(find.text('Replay intro'));
      await tap(find.text('Skip')); // 원화 영상에서 기존 조작 인트로로 진입한다.
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byTooltip('Skip intro'), findsOneWidget);
      await tap(find.byTooltip('Skip intro'));
      expect(find.byTooltip('Skip intro'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
