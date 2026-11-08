import 'dart:ui' as ui;

import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/game/block_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'courier and Echo ship as distinct, genuinely transparent sprites',
    (tester) async {
      await tester.runAsync(StarArt.load);
      expect(StarArt.courierImage, isNotNull);
      expect(StarArt.echoImage, isNotNull);
      expect(StarArt.portalImage, isNotNull);
      expect(StarArt.forestImage, isNotNull);
      for (final image in [
        StarArt.courierImage!,
        StarArt.echoImage!,
        StarArt.portalImage!,
      ]) {
        expect(image.width, lessThanOrEqualTo(384));
        final bytes = await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        );
        expect(
          bytes!.getUint8(3),
          0,
          reason:
              'Sprites must not cover the board with an opaque image square',
        );
      }
      Future<int> bodyAlpha(ui.Image image) async {
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return bytes!.getUint8(
          ((image.height * .62).floor() * image.width +
                      (image.width * .31).floor()) *
                  4 +
              3,
        );
      }

      expect(
        await tester.runAsync(() => bodyAlpha(StarArt.echoImage!)),
        lessThan(50),
        reason: 'Echo has an empty center, not another solid friend',
      );
      expect(
        await tester.runAsync(() => bodyAlpha(StarArt.courierImage!)),
        greaterThan(150),
      );
    },
  );

  testWidgets(
    'ordinary friends remain visually distinct from the mint courier',
    (tester) async {
      await tester.runAsync(StarArt.load);
      Future<List<int>> render(bool goal) async {
        final recorder = ui.PictureRecorder();
        BlockArt.block(
          Canvas(recorder),
          const Offset(50, 50),
          100,
          GameColors.dark,
          goal: goal,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(100, 100);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        final result = bytes!.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return result;
      }

      final mint = await tester.runAsync(() => render(true));
      final friend = await tester.runAsync(() => render(false));
      expect(mint, isNot(orderedEquals(friend!)));
    },
  );
}
