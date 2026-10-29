import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/art/game_art_assets.dart';
import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_MOONLIT');
  setUp(() => rootBundle.clear());
  testWidgets('capture actual moonlit first-five gameplay and collection', (
    tester,
  ) async {
    if (!capture) return;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = ByteData.sublistView(
      File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
          .readAsBytesSync(),
    );
    for (final name in ['Roboto', 'Ahem']) {
      await (FontLoader(name)..addFont(Future.value(font))).load();
    }
    await (FontLoader('CormorantGaramond')..addFont(
          rootBundle.load('assets/art/moonlit/fonts/CormorantGaramond.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    Directory('docs/screenshots/moonlit').createSync(recursive: true);
    final art = GameArtAssets.shared;
    await tester.runAsync(() async {
      await art.loadCore();
      await art.prepareChapter(0);
      await art.prepareSpirits([
        for (var i = 1; i <= 25; i++) 'spirit_${i.toString().padLeft(2, '0')}',
      ]);
    });
    final key = GlobalKey();
    final board = find.byType(GameWidget<BloriqGame>);
    Future<void> save(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final render =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final image = await render.toImage();
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('docs/screenshots/moonlit/$name.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    }

    Future<void> tap(Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      SharedPreferences.setMockInitialValues({
        GameAudio.musicKey: false,
        GameAudio.effectsKey: false,
      });
      await tester.runAsync(() => art.prepareChapter(0));
      final settings = await GameSettings.load();
      await settings.setThemeMode(mode);
      await settings.setReduceMotion(true);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BloriqApp(settings: settings),
        ),
      );
      for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await save('${mode.name}-stage-1');
      for (var id = 1; id <= 5; id++) {
        final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
        if (id == 5) {
          await tester.ensureVisible(board);
          await tester.pump();
          await save('${mode.name}-stage-5');
        }
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
            await save('${mode.name}-echo');
          }
        }
        await tester.pump(const Duration(milliseconds: 1800));
        await tester.pump();
        expect(game.controller.state.isComplete, isTrue);
        if (id == 1 || id == 5) {
          await tester.ensureVisible(find.text('Next level'));
          await tester.pump();
          await save('${mode.name}-reward-$id');
        }
        if (id < 5) await tap(find.text('Next level'));
      }
      await tap(find.byTooltip('Spirit collection'));
      await save('${mode.name}-collection');
      await tap(find.text('Lumi'));
      await save('${mode.name}-detail');
      await tap(find.text('Travel together'));
      await tap(find.byTooltip('Close'));
      await tap(find.text('Next level'));
      await tester.runAsync(() => art.prepareChapter(1));
      await tester.pump();
      await tester.ensureVisible(board);
      await tester.pump();
      await save('${mode.name}-stage-6');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      settings.dispose();
    }
  });
}
