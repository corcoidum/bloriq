import 'dart:ui' as ui;

import 'package:bloriq/design/board_material.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/board_geometry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final colors in [GameColors.light, GameColors.dark]) {
    for (final shape in [(3, 3), (4, 4), (3, 4)]) {
      test(
        'moonstone ${colors == GameColors.dark ? 'dark' : 'light'} $shape: transparent corners and recessed board inside frame',
        () async {
          final g = BoardGeometry.fit(
            available: const Size(360, 440),
            columns: shape.$1,
            rows: shape.$2,
            devicePixelRatio: 3,
          );
          final r = ui.PictureRecorder();
          final canvas = Canvas(r);
          BoardMaterial(colors).frame(canvas, g);
          canvas.save();
          canvas.translate(g.frameInset, g.frameInset);
          canvas.clipRRect(g.boardShape);
          BoardMaterial(colors).floor(canvas, g);
          canvas.restore();
          final picture = r.endRecording();
          final image = await picture.toImage(
            g.outerSize.width.ceil(),
            g.outerSize.height.ceil(),
          );
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          int alpha(int x, int y) =>
              data.getUint8((y * image.width + x) * 4 + 3);
          expect(alpha(0, 0), 0);
          expect(alpha(image.width - 1, 0), 0);
          expect(alpha(0, image.height - 1), 0);
          expect(alpha(image.width - 1, image.height - 1), 0);
          final center =
              g.center(const Position(0, 0)) +
              Offset(g.frameInset, g.frameInset);
          expect(alpha(center.dx.round(), center.dy.round()), 255);
          expect(g.framedBoardRect.left, g.frameInset);
          expect(g.stoneDepth, inInclusiveRange(3, 6));
          expect(g.positionAt(const Offset(-1, 0)), isNull);
          image.dispose();
          picture.dispose();
        },
      );
    }
  }
}
