import '../puzzle.dart';
import 'board_mechanic.dart';

class EchoEraser extends BoardMechanic {
  EchoEraser(Iterable<Position> cells) : cells = Set.unmodifiable(cells);

  factory EchoEraser.parse(Map<String, dynamic> rule) =>
      EchoEraser(parseMechanicPositions(rule));

  static const typeId = 'echoEraser';
  @override
  String get type => typeId;
  @override
  final Set<Position> cells;

  @override
  Position? nextEcho(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
    Position? echo,
  ) => cells.contains(before.positionOf(move.blockId)) ? null : echo;

  @override
  EchoEraser reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => EchoEraser(cells.map(point));
}
