import 'dart:math' as math;
import 'dart:ui';

import '../domain/puzzle.dart';

/// Flutter 배치, Flame 그림, Preview와 터치가 공유하는 논리 좌표계.
class BoardGeometry {
  const BoardGeometry._(
    this.columns,
    this.rows,
    this.cellSize,
    this.canvasSize,
    this.origin,
    this.devicePixelRatio,
    this.frameInset,
  );

  static const defaultFrameInset = 24.0;
  static const dragFraction = .24;
  static const spriteFraction = .84;
  final int columns, rows;
  final double cellSize, devicePixelRatio, frameInset;
  final Size canvasSize;
  final Offset origin;

  factory BoardGeometry.fit({
    required Size available,
    required int columns,
    required int rows,
    double devicePixelRatio = 1,
    double frameInset = defaultFrameInset,
  }) {
    _validate(columns, rows, devicePixelRatio);
    final raw = math.min(
      math.max(0.0, available.width - frameInset * 2) / columns,
      math.max(0.0, available.height - frameInset * 2) / rows,
    );
    final cell =
        math.max(1, (raw * devicePixelRatio).floor()) / devicePixelRatio;
    return BoardGeometry._(
      columns,
      rows,
      cell,
      Size(cell * columns, cell * rows),
      Offset.zero,
      devicePixelRatio,
      frameInset,
    );
  }

  factory BoardGeometry.canvas({
    required Size size,
    required int columns,
    required int rows,
    double devicePixelRatio = 1,
  }) {
    _validate(columns, rows, devicePixelRatio);
    final raw = math.min(size.width / columns, size.height / rows);
    final cell =
        math.max(1, (raw * devicePixelRatio).floor()) / devicePixelRatio;
    return BoardGeometry._(
      columns,
      rows,
      cell,
      size,
      Offset(
        (size.width - cell * columns) / 2,
        (size.height - cell * rows) / 2,
      ),
      devicePixelRatio,
      0,
    );
  }

  static void _validate(int columns, int rows, double dpr) {
    if (columns < 1 || rows < 1 || !dpr.isFinite || dpr <= 0) {
      throw ArgumentError('Positive board dimensions and DPR required');
    }
  }

  Size get boardSize => Size(columns * cellSize, rows * cellSize);
  Size get outerSize => Size(
    canvasSize.width + frameInset * 2,
    canvasSize.height + frameInset * 2,
  );
  Rect get boardRect => origin & boardSize;
  double get dragThreshold => cellSize * dragFraction;
  double get tileGap =>
      (cellSize * .05 * devicePixelRatio).round().clamp(
        (2 * devicePixelRatio).round(),
        (6 * devicePixelRatio).round(),
      ) /
      devicePixelRatio;
  double get spriteExtent => cellSize * spriteFraction;
  Offset center(Position p) =>
      origin + Offset((p.x + .5) * cellSize, (p.y + .5) * cellSize);
  Rect cellRect(Position p) => Rect.fromLTWH(
    origin.dx + p.x * cellSize,
    origin.dy + p.y * cellSize,
    cellSize,
    cellSize,
  );
  Rect tileRect(Position p) => cellRect(p).deflate(tileGap / 2);
  Rect spriteRect(Position p) => Rect.fromCenter(
    center: center(p),
    width: spriteExtent,
    height: spriteExtent,
  );
  Position? positionAt(Offset local) {
    if (!boardRect.contains(local)) return null;
    final at = local - origin;
    return Position((at.dx / cellSize).floor(), (at.dy / cellSize).floor());
  }

  bool sameLayout(BoardGeometry other) =>
      columns == other.columns &&
      rows == other.rows &&
      canvasSize == other.canvasSize &&
      origin == other.origin &&
      cellSize == other.cellSize &&
      devicePixelRatio == other.devicePixelRatio;
}
