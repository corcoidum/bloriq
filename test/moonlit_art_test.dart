import 'package:bloriq/postcard/echo_postcard.dart';

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bloriq/art/game_art_assets.dart';
import 'package:bloriq/companions/season.dart';
import 'package:bloriq/companions/spirit_postcard.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FailOnceBundle extends CachingAssetBundle {
  bool failing = true;
  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('/blue.png') && failing) {
      failing = false;
      return Future.error(StateError('Simulated art loading failure'));
    }
    return rootBundle.load(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('separate source assets decode, core cache reuses images, frame and echo stay hollow', () async {
    final art = GameArtAssets();
    await art.loadCore();
    final blue = art.tile('blue');
    await art.loadCore();
    expect(art.tile('blue'), same(blue));
    for (final name in ['frame', 'echo']) {
      final image = art.tile(name)!;
      final pixels = (await image.toByteData())!;
      int alpha(double x, double y) => pixels.getUint8(
        ((image.height * y).floor() * image.width + (image.width * x).floor()) *
                4 +
            3,
      );
      expect(
        alpha(.5, .5),
        lessThan(20),
        reason: '$name must not paint over a cell',
      );
      if (name == 'frame') {
        for (final x in [.15, .5, .85]) {
          for (final y in [.15, .5, .85]) {
            expect(
              alpha(x, y),
              lessThan(20),
              reason: 'Frame must not overlap the 3x3/4x4 grid',
            );
          }
        }
      }
    }
    art.dispose();
  });
  test('failed common image load can retry without poisoning cache', () async {
    final art = GameArtAssets(bundle: FailOnceBundle());
    await expectLater(art.loadCore(), throwsStateError);
    await art.loadCore();
    expect(art.tile('blue'), isNotNull);
    art.dispose();
  });
  test('only current and next region retained after sequential and racing requests', () async {
    final art = GameArtAssets();
    for (var chapter = 0; chapter < 5; chapter++) {
      await art.prepareChapter(chapter);
      expect(art.background(chapter), isNotNull);
      expect(art.decodedBackgroundCount, lessThanOrEqualTo(2));
    }
    await Future.wait([
      art.prepareChapter(1),
      art.prepareChapter(3),
      art.prepareChapter(0),
    ]);
    expect(art.chapter, 0);
    expect(art.background(0), isNotNull);
    expect(art.decodedBackgroundCount, lessThanOrEqualTo(2));
    art.dispose();
  });
  test(
    'first five use actual image renderer and same geometry/rules',
    () async {
      final art = GameArtAssets();
      await art.loadCore();
      final data = jsonDecode(
        await rootBundle.loadString('assets/levels/levels.json'),
      ) as List;
      for (final value in data.take(5)) {
        final level = Level.fromJson(value as Map<String, dynamic>);
        final controller = PuzzleController(level);
        final game = BloriqGame(controller, artAssets: art)
          ..onGameResize(Vector2(330, 330));
        final before = controller.state;
        final recorder = ui.PictureRecorder();
        game.render(Canvas(recorder));
        final picture = recorder.endRecording();
        final image = await picture.toImage(330, 330);
        expect(
          await image.toByteData(format: ui.ImageByteFormat.png),
          isNotNull,
        );
        expect(controller.state, same(before));
        for (final b in before.blocks) {
          expect(
            game.geometry.cellAt(game.geometry.center(b.position)),
            b.position,
          );
        }
        image.dispose();
        picture.dispose();
      }
      art.dispose();
    },
  );
  test(
    'all 25 unique spirit rasters and art-based cards render in both sizes',
    () async {
      final art = GameArtAssets();
      await art.loadCore();
      final season = await Season.load();
      await art.prepareSpirits(season.spirits.map((s) => s.id));
      expect(
        season.spirits.map((s) => art.spirit(s.id)).toSet(),
        hasLength(25),
      );
      for (final height in [1080.0, 1920.0]) {
        final painter = SpiritCardPainter(
          spirits: season.spirits,
          heading: 'BLORIQ',
          subtitle: '25 / 25',
          colors: GameColors.light,
          artAssets: art,
        );
        final recorder = ui.PictureRecorder();
        painter.paint(Canvas(recorder), Size(1080, height));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1080, height.toInt());
        expect(
          await image.toByteData(format: ui.ImageByteFormat.png),
          isNotNull,
        );
        image.dispose();
        picture.dispose();
      }
      await art.prepareChapter(0);
      final png = await renderEchoPostcardPng(
        const EchoPostcardData(
          levelId: 1,
          moves: 2,
          bestMoves: 2,
          stars: 3,
          levelText: 'Stage 1',
          movesText: 'Moves: 2',
          bestText: 'Best: 2',
        ),
        artAssets: art,
      );
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      art.dispose();
    },
  );
}
