import '../puzzle.dart';
import 'board_mechanic.dart';

class EchoHold extends BoardMechanic {
  EchoHold(Iterable<Position> cells) : cells = Set.unmodifiable(cells);

  factory EchoHold.parse(Map<String, dynamic> rule) =>
      EchoHold(parseMechanicPositions(rule));

  static const typeId = 'echoHold';
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
  ) => cells.contains(before.positionOf(move.blockId)) ? before.echo : echo;

  @override
  EchoHold reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => EchoHold(cells.map(point));
}
