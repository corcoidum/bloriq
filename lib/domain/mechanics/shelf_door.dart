import '../puzzle.dart';
import 'board_mechanic.dart';
import 'clock_arrow.dart';
import 'echo_gate.dart';
import 'ice.dart';
import 'one_way.dart';

class ShelfDoor extends BoardMechanic {
  ShelfDoor(Iterable<(Position, Position)> pairs)
    : pairs = List.unmodifiable(pairs);

  factory ShelfDoor.parse(Map<String, dynamic> rule) {
    final raw = rule['pairs'];
    if (raw is! List || raw.isEmpty || raw.length > 2) {
      throw const FormatException('Shelf doors require one or two pairs');
    }
    return ShelfDoor(
      raw.map((pair) {
        if (pair is! Map<String, dynamic>) {
          throw const FormatException('Invalid shelf door pair');
        }
        return (parseMechanicPoint(pair['a']), parseMechanicPoint(pair['b']));
      }),
    );
  }

  static const typeId = 'shelfDoor';
  final List<(Position, Position)> pairs;

  @override
  String get type => typeId;
  @override
  Iterable<Position> get cells sync* {
    for (final (a, b) in pairs) {
      yield a;
      yield b;
    }
  }

  // 바위와 클로버는 책장 문을 막을 수 있다. 금지 조합은 아래에서 검사한다.
  @override
  bool get hasExclusiveCells => false;

  @override
  void validate(Level level) {
    if (pairs.isEmpty ||
        pairs.length > 2 ||
        cells.toSet().length != 2 * pairs.length) {
      throw const FormatException('Invalid or repeated shelf door endpoints');
    }
    final forbidden = {
      level.exitPosition,
      for (final type in [
        Ice.typeId,
        OneWay.typeId,
        ClockArrow.typeId,
        EchoGate.typeId,
      ])
        ...?level.mechanics[type]?.cells,
    };
    if (cells.any(forbidden.contains)) {
      throw const FormatException('Overlapping shelf door tile');
    }
  }

  @override
  List<Block> transformMove(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks, {
    List<MoveTeleport>? teleports,
  }) {
    if (move.power == PuzzlePower.lightSwap) return blocks;
    final index = blocks.indexWhere((block) => block.id == move.blockId);
    final block = blocks[index];
    final end = finishTeleport(
      before,
      blocks,
      block,
      vacated: before.positionOf(move.blockId)!,
      teleports: teleports,
    );
    if (end == block.position) return blocks;
    return [...blocks]..[index] = block.at(end);
  }

  /// [blocks]에는 이 블록이 착지한 위치가 이미 반영되어 있다.
  Position finishTeleport(
    PuzzleState before,
    List<Block> blocks,
    Block block, {
    required Position vacated,
    List<MoveTeleport>? teleports,
  }) {
    final landing = block.position;
    for (final (a, b) in pairs) {
      final target = landing == a ? b : (landing == b ? a : null);
      if (target == null) continue;
      if (target == vacated ||
          !before.canOccupy(block.id, target, occupiedBlocks: blocks)) {
        break;
      }
      teleports?.add((blockId: block.id, from: landing, to: target));
      return target;
    }
    return landing;
  }

  @override
  ShelfDoor reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => ShelfDoor(pairs.map((pair) => (point(pair.$1), point(pair.$2))));
}
