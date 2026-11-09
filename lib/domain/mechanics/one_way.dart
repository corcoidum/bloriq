import '../puzzle.dart';
import 'board_mechanic.dart';

class OneWay extends BoardMechanic {
  OneWay(Map<Position, Position> arrows) : arrows = Map.unmodifiable(arrows);

  factory OneWay.parse(Map<String, dynamic> rule) {
    final tiles = rule['tiles'];
    if (tiles is! List || tiles.isEmpty) {
      throw const FormatException('One-way rule requires tiles');
    }
    final arrows = <Position, Position>{};
    for (final tile in tiles) {
      final point = parseMechanicPoint(tile);
      if (tile is! Map<String, dynamic> ||
          tile['dx'] is! int ||
          tile['dy'] is! int ||
          arrows.containsKey(point)) {
        throw const FormatException('Invalid or duplicate one-way tile');
      }
      arrows[point] = Position(tile['dx'] as int, tile['dy'] as int);
    }
    return OneWay(arrows);
  }

  static const typeId = 'oneWay';
  @override
  String get type => typeId;
  final Map<Position, Position> arrows;
  @override
  Iterable<Position> get cells => arrows.keys;

  @override
  void validate(Level level) {
    if (arrows.values.any(
      (direction) => !cardinalDirections.contains(direction),
    )) {
      throw const FormatException('One-way direction must be cardinal');
    }
  }

  @override
  bool canLeave(PuzzleState state, Position from, Position direction) =>
      arrows[from] == null || arrows[from] == direction;

  @override
  OneWay reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => OneWay({
    for (final entry in arrows.entries)
      point(entry.key): direction(entry.value),
  });
}
