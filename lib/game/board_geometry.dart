import 'dart:math' as math;
import 'dart:ui';

import '../domain/puzzle.dart';

/// Flutter, Flame, 터치 판정이 공유하는 논리 픽셀 좌표 모델.
class BoardGeometry {
  BoardGeometry({
    required this.columns,
    required this.rows,
    required Size available,
    double devicePixelRatio = 1,
  }) {
    assert(columns > 0 && rows > 0);
    final ratio = devicePixelRatio > 0 ? devicePixelRatio : 1.0;
    final raw = math.max(
      0.0,
      math.min(available.width / columns, available.height / rows),
    );
    // 셀 크기만 물리 픽셀에 맞춘다. 셀마다 반올림하면 누적 오차가 생긴다.
    cellSize = (raw * ratio + 1e-8).floorToDouble() / ratio;
    boardSize = Size(cellSize * columns, cellSize * rows);
    origin = Offset(
      (available.width - boardSize.width) / 2,
      (available.height - boardSize.height) / 2,
    );
  }
  final int columns;
  final int rows;
  late final double cellSize;
  late final Size boardSize;
  late final Offset origin;
  double get tileGap => cellSize * .06;
  double get blockSize => cellSize * .86;
  double get dragThreshold => cellSize * .24;
  Rect get bounds => origin & boardSize;
  Offset center(Position cell) =>
      origin + Offset((cell.x + .5) * cellSize, (cell.y + .5) * cellSize);
  Rect tileRect(Position cell) => Rect.fromCenter(
    center: center(cell),
    width: cellSize - tileGap,
    height: cellSize - tileGap,
  );
  Position? cellAt(Offset point) {
    if (cellSize <= 0 || !bounds.contains(point)) return null;
    return Position(
      ((point.dx - origin.dx) / cellSize).floor(),
      ((point.dy - origin.dy) / cellSize).floor(),
    );
  }
}
