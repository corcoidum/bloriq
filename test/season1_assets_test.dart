import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/story/story_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    '25 original portraits retain alpha and normalized small-screen silhouettes inside their slot',
    (tester) async {
      rootBundle.clear();
      final catalog = StoryCatalog.fromJson(
        jsonDecode(File('assets/story/season1.json').readAsStringSync()),
      );
      expect(catalog.released.length, 25);
      final seen = <String>{};
      for (final spirit in catalog.released) {
        expect(
          seen.add(spirit.asset!),
          true,
          reason: 'Every spirit needs its own original art',
        );
        await tester.runAsync(() async {
          final raw = await rootBundle.load(spirit.asset!);
          final codec = await ui.instantiateImageCodec(
            raw.buffer.asUint8List(),
            targetWidth: 192,
          );
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
            expect(alpha(x, y), lessThanOrEqualTo(8), reason: spirit.id);
          }
          var left = image.width, right = 0, top = image.height, bottom = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (alpha(x, y) >= 128) {
                if (x < left) left = x;
                if (x > right) right = x;
                if (y < top) top = y;
                if (y > bottom) bottom = y;
              }
            }
          }
          expect(right, greaterThan(left), reason: spirit.id);
          final scale = spirit.portraitScale, anchor = spirit.portraitAnchor;
          double project(double v, double a) => .5 + (v - a) * scale;
          expect(
            project(left / image.width, anchor.dx),
            greaterThanOrEqualTo(.02),
            reason: spirit.id,
          );
          expect(
            project((right + 1) / image.width, anchor.dx),
            lessThanOrEqualTo(.98),
            reason: spirit.id,
          );
          expect(
            project(top / image.height, anchor.dy),
            greaterThanOrEqualTo(.02),
            reason: spirit.id,
          );
          expect(
            project((bottom + 1) / image.height, anchor.dy),
            lessThanOrEqualTo(.98),
            reason: spirit.id,
          );
          image.dispose();
          codec.dispose();
        });
      }
    },
  );
}
