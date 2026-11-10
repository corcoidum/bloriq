import '../puzzle.dart';
import 'board_mechanic.dart';

/// 이동 전 시각의 화살표로 출발을 검사하는 회전 물길.
class ClockArrow extends BoardMechanic {
  ClockArrow(Map<Position, Position> arrows)
    : arrows = Map.unmodifiable(arrows);

  factory ClockArrow.parse(Map<String, dynamic> rule) =>
      ClockArrow(parseMechanicArrows(rule, 'Clock-hand'));

  static const typeId = 'clockArrow';
  static const phaseCount = 4;

  // controller와 solver가 성공한 한 수에만 moves를 한 번 늘린다.
  static int phaseAt(int moves) => moves % phaseCount;

  @override
  String get type => typeId;
  @override
  bool get reflectionSymmetric => false;
  final Map<Position, Position> arrows;
  @override
  Iterable<Position> get cells => arrows.keys;

  @override
  void validate(Level level) {
    if (arrows.isEmpty ||
        arrows.values.any(
          (direction) => !cardinalDirections.contains(direction),
        )) {
      throw const FormatException('Clock-hand rule requires cardinal arrows');
    }
  }

  @override
  bool canLeave(PuzzleState state, Position from, Position direction) {
    final arrow = arrows[from];
    if (arrow == null) return true;
    // 화면 좌표에서 (x, y)를 시계 방향 90° 돌리면 (-y, x)다.
    final Position(:x, :y) = arrow;
    return switch (phaseAt(state.moves)) {
      0 => direction == arrow,
      1 => direction.x == -y && direction.y == x,
      2 => direction.x == -x && direction.y == -y,
      _ => direction.x == y && direction.y == -x,
    };
  }

  @override
  int stateKey(PuzzleState state) => phaseAt(state.moves);

  @override
  ClockArrow reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => ClockArrow({
    for (final entry in arrows.entries)
      point(entry.key): direction(entry.value),
  });
}
