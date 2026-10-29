import 'dart:ui';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/board_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final screen in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(393, 852),
    const Size(412, 915),
    const Size(600, 960),
  ]) {
    for (final cells in [3, 4]) {
      for (final dpr in [1.0, 2.625, 3.0]) {
        test('geometry $screen $cells DPR $dpr: centers and bounds', () {
          final g = BoardGeometry(
            columns: cells,
            rows: cells,
            available: Size(screen.width - 40, screen.height * .46),
            devicePixelRatio: dpr,
          );
          expect(g.bounds.left, greaterThanOrEqualTo(0));
          expect(g.bounds.bottom, lessThanOrEqualTo(screen.height * .46));
          for (var y = 0; y < cells; y++) {
            for (var x = 0; x < cells; x++) {
              final p = Position(x, y);
              expect(g.cellAt(g.center(p)), p);
              expect(
                (g.tileRect(p).center - g.center(p)).distance,
                lessThan(1e-8),
              );
              expect(
                g.tileRect(p).width,
                closeTo(g.cellSize - g.tileGap, 1e-8),
              );
              expect(
                g.bounds.contains(
                  g.center(p) + Offset(g.blockSize / 2, g.blockSize / 2),
                ),
                isTrue,
              );
            }
          }
          expect(g.cellAt(g.bounds.bottomRight), isNull);
          expect(g.cellAt(g.origin - const Offset(.1, .1)), isNull);
        });
      }
    }
  }
  test('rectangular letterbox input uses origin', () {
    final g = BoardGeometry(
      columns: 4,
      rows: 3,
      available: const Size(400, 400),
    );
    expect(g.origin, const Offset(0, 50));
    expect(g.cellAt(const Offset(20, 20)), isNull);
    expect(g.cellAt(const Offset(50, 100)), const Position(0, 0));
  });
}
