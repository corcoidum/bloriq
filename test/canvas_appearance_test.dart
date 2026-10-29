import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/block_art.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Level sampleLevel() => Level(
  id: 2,
  boardWidth: 3,
  boardHeight: 3,
  startPosition: const Position(0, 1),
  exitPosition: const Position(2, 1),
  blocks: const [Block(id: 'a', position: Position(0, 0))],
  obstacles: const [Position(2, 0)],
  minimumMoves: 2,
  difficulty: 'beginner',
);

Future<Uint8List> renderPixels(BloriqGame game) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(game.backgroundColor(), BlendMode.src);
  game.render(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(300, 300);
  final bytes = await image.toByteData();
  final result = Uint8List.fromList(bytes!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared block artwork keeps saturated fill after drawing its translucent shadow', () async {
    for (final colors in [GameColors.light, GameColors.dark]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(colors.tileTop, BlendMode.src);
      BlockArt.block(canvas, const Offset(50, 50), 100, colors);
      final picture = recorder.endRecording();
      final image = await picture.toImage(100, 100);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (50 * 100 + 25) * 4;
      expect(
        bytes.getUint8(offset + 1) - bytes.getUint8(offset),
        greaterThan(60),
      );
      expect(bytes.getUint8(offset + 3), 255);
      image.dispose();
      picture.dispose();
    }
  });

  test('theme changes keep an active drag, echo, state and undo history', () {
    final controller = PuzzleController(sampleLevel());
    final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
    controller.move('a', const Position(1, 0));
    final state = controller.state;
    final history = controller.moveHistory;
    game.setDrag('goal', const Offset(60, 0));
    final target = game.currentPreview!.target;

    game.configureAppearance(colors: GameColors.dark, reduceMotion: true);

    expect(game.backgroundColor(), GameColors.dark.background);
    expect(game.currentPreview!.target, target);
    expect(controller.state, same(state));
    expect(controller.moveHistory, history);
    expect(controller.canUndo, isTrue);
    expect(controller.undo(), isTrue);
    expect(controller.state.moves, 0);
  });

  test(
    'both themes render the same board state with different palettes',
    () async {
      final controller = PuzzleController(sampleLevel());
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
      controller.move('a', const Position(1, 0));
      final state = controller.state;
      game.configureAppearance(colors: GameColors.light, reduceMotion: true);
      final light = await renderPixels(game);
      game.configureAppearance(colors: GameColors.dark, reduceMotion: true);
      final dark = await renderPixels(game);
      expect(light, isNot(orderedEquals(dark)));
      expect(controller.state, same(state));
    },
  );

  test(
    'reduced motion removes idle and celebration motion from canvas',
    () async {
      final controller = PuzzleController(sampleLevel());
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
      game.configureAppearance(colors: GameColors.dark, reduceMotion: true);
      final idle = await renderPixels(game);
      game.update(.8);
      expect(await renderPixels(game), orderedEquals(idle));

      controller.move('goal', const Position(1, 1));
      controller.move('goal', const Position(2, 1));
      final completed = controller.state;
      game.setCelebrationProgress(.15, isNewBest: true);
      final before = await renderPixels(game);
      game.update(.8);
      game.setCelebrationProgress(.5, isNewBest: true);
      expect(await renderPixels(game), orderedEquals(before));
      game.setCelebrationProgress(1, isNewBest: true);
      expect(await renderPixels(game), orderedEquals(before));
      expect(controller.state, same(completed));
    },
  );

  test(
    'one presentation clock controls burst and skip without changing result',
    () async {
      final controller = PuzzleController(sampleLevel());
      final game = BloriqGame(controller)..onGameResize(Vector2(300, 300));
      controller.move('goal', const Position(1, 1));
      controller.move('goal', const Position(2, 1));
      final completed = controller.state;
      game.setCelebrationProgress(.4, isNewBest: true);
      final burst = await renderPixels(game);
      game.update(.2);
      expect(game.celebrationProgress, .4);
      game.setCelebrationProgress(1, isNewBest: true);
      expect(await renderPixels(game), isNot(orderedEquals(burst)));
      expect(controller.state, same(completed));
      expect(controller.moveHistory, hasLength(2));
      game.clearEffects();
      expect(game.celebrationProgress, 1);
      expect(controller.state, same(completed));
    },
  );
}
