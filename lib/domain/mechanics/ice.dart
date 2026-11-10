import '../puzzle.dart';
import 'board_mechanic.dart';

/// 첫 착지가 얼음이면 같은 방향으로 더 이동한다.
class Ice extends BoardMechanic {
  Ice(Set<Position> positions) : positions = Set.unmodifiable(positions);

  factory Ice.parse(Map<String, dynamic> rule) =>
      Ice(parseMechanicPositions(rule));

  static const typeId = 'ice';
  final Set<Position> positions;

  @override
  String get type => typeId;

  @override
  Iterable<Position> get cells => positions;

  @override
  void validate(Level level) {
    if (positions.isEmpty) {
      throw const FormatException('Ice rule requires positions');
    }
  }

  @override
  List<Block> transformMove(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
  ) {
    if (move.power == PuzzlePower.wind ||
        move.power == PuzzlePower.lightSwap ||
        !positions.contains(move.target)) {
      return blocks;
    }
    final source = before.positionOf(move.blockId)!;
    final end = finishSlide(
      before,
      blocks,
      blockId: move.blockId,
      landing: move.target,
      direction: Position(
        (move.target.x - source.x).sign,
        (move.target.y - source.y).sign,
      ),
      vacated: source,
    );
    if (end == move.target) return blocks;
    final index = blocks.indexWhere((block) => block.id == move.blockId);
    return [...blocks]..[index] = blocks[index].at(end);
  }

  /// [landing]은 이미 진입을 검사한 칸이다. 짝은 주 이동 후 배치를 본다.
  Position finishSlide(
    PuzzleState before,
    List<Block> blocks, {
    required String blockId,
    required Position landing,
    required Position direction,
    required Position vacated,
  }) {
    var at = landing;
    while (positions.contains(at)) {
      if (blockId == Level.goalBlockId && at == before.level.exitPosition) {
        break;
      }
      final next = Position(at.x + direction.x, at.y + direction.y);
      if (next == vacated ||
          !before.canOccupy(blockId, next, occupiedBlocks: blocks)) {
        break;
      }
      at = next;
    }
    return at;
  }

  @override
  Ice reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => Ice(positions.map(point).toSet());
}
