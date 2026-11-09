import 'dart:ui' as ui;

import 'package:bloriq/design/star_art.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('moon garden board sprites load with transparent corners', (
    tester,
  ) async {
    await tester.runAsync(StarArt.load);
    expect(StarArt.garden.keys.toSet(), StarArt.gardenSprites.toSet());
    for (final name in StarArt.gardenSprites) {
      // 판석과 물길은 칸 끝까지 이어지므로 모서리 투명도를 보지 않는다.
      if (name.startsWith('floor') || name == 'tile_stream') {
        continue;
      }
      await tester.runAsync(() async {
        final raw = await rootBundle.load('assets/art/moon_garden/$name.png');
        final codec = await ui.instantiateImageCodec(raw.buffer.asUint8List());
        final image = (await codec.getNextFrame()).image;
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        int alpha(int x, int y) =>
            bytes.getUint8((y * image.width + x) * 4 + 3);
        for (final (x, y) in [
          (0, 0),
          (image.width - 1, 0),
          (0, image.height - 1),
          (image.width - 1, image.height - 1),
        ]) {
          expect(alpha(x, y), lessThanOrEqualTo(8), reason: name);
        }
      });
    }
  });
}
