import 'dart:ui';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/board_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(393, 852),
    const Size(412, 915),
    const Size(600, 960),
    const Size(568, 320),
  ]) {
    for (final dpr in [1.0, 2.0, 3.0]) {
      for (final dimensions in [(3, 3), (4, 4), (3, 4)]) {
        test(
          '$size DPR$dpr $dimensions: centers, bounds and physical pixels agree',
          () {
            final g = BoardGeometry.fit(
              available: Size(size.width - 32, size.height),
              columns: dimensions.$1,
              rows: dimensions.$2,
              devicePixelRatio: dpr,
            );
            expect(g.cellSize * dpr, closeTo((g.cellSize * dpr).round(), 1e-8));
            expect(g.outerSize.width, lessThanOrEqualTo(size.width - 32));
            expect(g.outerSize.height, lessThanOrEqualTo(size.height));
            for (var y = 0; y < g.rows; y++) {
              for (var x = 0; x < g.columns; x++) {
                final p = Position(x, y);
                expect(g.positionAt(g.center(p)), p);
                expect(g.cellRect(p).contains(g.spriteRect(p).topLeft), true);
                expect(
                  g.cellRect(p).contains(g.spriteRect(p).bottomRight),
                  true,
                );
                expect(
                  (g.tileRect(p).center - g.center(p)).distance,
                  lessThan(1e-8),
                );
              }
            }
            expect(g.positionAt(const Offset(-.1, 0)), isNull);
            expect(g.positionAt(Offset(g.canvasSize.width, 0)), isNull);
            expect(g.positionAt(Offset(0, g.canvasSize.height)), isNull);
            expect(g.dragThreshold, g.cellSize * .24);
          },
        );
      }
    }
  }
  test('letterboxed rectangular canvas excludes margins from input', () {
    final g = BoardGeometry.canvas(
      size: const Size(400, 300),
      columns: 3,
      rows: 4,
      devicePixelRatio: 3,
    );
    expect(g.origin.dx, greaterThan(0));
    expect(g.positionAt(Offset(g.origin.dx - .01, 150)), isNull);
    expect(g.positionAt(g.center(const Position(2, 3))), const Position(2, 3));
  });
}
