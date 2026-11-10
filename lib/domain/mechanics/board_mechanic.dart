import '../puzzle.dart';

/// 한 레벨에 설정된 기믹. 훅은 이전 상태를 바꾸지 않는 순수 함수다.
abstract class BoardMechanic {
  const BoardMechanic();

  String get type;
  Iterable<Position> get cells => const [];
  bool get reflectionSymmetric => true;
  void validate(Level level) {}

  BoardMechanic combine(BoardMechanic other) =>
      throw FormatException('Duplicate special rule: $type');

  /// blockId가 null이면 블록 종류와 관계없는 장애물인지 확인한다.
  bool canEnter(PuzzleState state, String? blockId, Position target) => true;

  bool canLeave(PuzzleState state, Position from, Position direction) => true;

  /// 일반 이동 또는 권능 착지 후의 배치를 받는다. 블록 순서와 ID를 보존한다.
  List<Block> transformMove(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
  ) => blocks;

  /// 배치 변환 뒤에 호출된다. 일반 이동의 기본 잔상은 출발 칸이다.
  Position? nextEcho(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
    Position? echo,
  ) => echo;

  /// 위치와 권능으로 알 수 없는 값만 반환한다. 예: 회전 시각 moves % 4.
  int? stateKey(PuzzleState state) => null;

  /// 항해의 회전·반전에서 좌표와 방향을 함께 옮긴다.
  BoardMechanic reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => this;
}

Position parseMechanicPoint(Object? raw) {
  if (raw is! Map<String, dynamic> || raw['x'] is! int || raw['y'] is! int) {
    throw const FormatException('Invalid mechanism position');
  }
  return Position.fromJson(raw);
}

Set<Position> parseMechanicPositions(Map<String, dynamic> rule) {
  final raw = rule['positions'];
  if (raw is! List || raw.isEmpty) {
    throw const FormatException('Mechanism rule requires positions');
  }
  final positions = raw.map(parseMechanicPoint).toSet();
  if (positions.length != raw.length) {
    throw const FormatException('Duplicate mechanism tile');
  }
  return positions;
}

Map<Position, Position> parseMechanicArrows(
  Map<String, dynamic> rule,
  String name,
) {
  final tiles = rule['tiles'];
  if (tiles is! List || tiles.isEmpty) {
    throw FormatException('$name rule requires tiles');
  }
  final arrows = <Position, Position>{};
  for (final tile in tiles) {
    final point = parseMechanicPoint(tile);
    if (tile is! Map<String, dynamic> ||
        tile['dx'] is! int ||
        tile['dy'] is! int ||
        arrows.containsKey(point)) {
      throw FormatException('Invalid or duplicate $name tile');
    }
    arrows[point] = Position(tile['dx'] as int, tile['dy'] as int);
  }
  return arrows;
}
