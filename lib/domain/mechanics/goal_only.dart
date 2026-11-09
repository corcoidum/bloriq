import '../puzzle.dart';
import 'board_mechanic.dart';

class GoalOnly extends BoardMechanic {
  GoalOnly(Iterable<Position> cells) : cells = Set.unmodifiable(cells);

  factory GoalOnly.parse(Map<String, dynamic> rule) =>
      GoalOnly(parseMechanicPositions(rule));

  static const typeId = 'goalOnly';
  @override
  String get type => typeId;
  @override
  final Set<Position> cells;

  @override
  bool canEnter(PuzzleState state, String? blockId, Position target) =>
      blockId == null ||
      blockId == Level.goalBlockId ||
      !cells.contains(target);

  @override
  GoalOnly reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => GoalOnly(cells.map(point));
}
