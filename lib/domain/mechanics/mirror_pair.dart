import '../puzzle.dart';
import 'board_mechanic.dart';
import 'ice.dart';

typedef MirrorShift = ({String blockId, int pair, Position from, Position to});

/// 일반 이동에 맞춰 연결된 블록을 반대쪽으로 한 칸 끌어온다.
class MirrorPair extends BoardMechanic {
  MirrorPair._(Iterable<(String, String)> pairs)
    : pairs = List.unmodifiable(pairs);

  factory MirrorPair.parse(Map<String, dynamic> rule) {
    final ids = rule['blocks'];
    if (ids case [final String first, final String second]) {
      return MirrorPair._([(first, second)]);
    }
    throw const FormatException('A mirror pair requires two block IDs');
  }

  static const typeId = 'mirrorPair';
  @override
  String get type => typeId;
  final List<(String, String)> pairs;

  @override
  MirrorPair combine(covariant MirrorPair other) =>
      MirrorPair._([...pairs, ...other.pairs]);

  @override
  void validate(Level level) {
    if (pairs.length > 2) {
      throw const FormatException('At most two mirror pairs are allowed');
    }
    final ids = {Level.goalBlockId, ...level.blocks.map((block) => block.id)};
    for (final (first, second) in pairs) {
      if (!ids.remove(first) || !ids.remove(second)) {
        throw const FormatException('Invalid or repeated mirror pair block ID');
      }
    }
  }

  ({String blockId, int pair})? partnerOf(String id) {
    for (final (index, (first, second)) in pairs.indexed) {
      if (id == first) return (blockId: second, pair: index);
      if (id == second) return (blockId: first, pair: index);
    }
    return null;
  }

  @override
  List<Block> transformMove(
    PuzzleState before,
    PuzzleMove move,
    List<Block> blocks,
  ) {
    if (move.power != null) return blocks;
    final partner = partnerOf(move.blockId);
    if (partner == null) return blocks;
    final source = before.positionOf(move.blockId)!;
    final direction = Position(
      source.x - move.target.x,
      source.y - move.target.y,
    );
    final index = blocks.indexWhere((block) => block.id == partner.blockId);
    final twin = blocks[index];
    final from = twin.position;
    final target = Position(from.x + direction.x, from.y + direction.y);
    // 방금 비운 칸과 이전 잔상은 짝의 이동이 끝날 때까지 막힌 상태다.
    if (target == source ||
        !before.canOccupy(
          twin.id,
          target,
          occupiedBlocks: blocks,
          allowNonGoalExit: true,
        ) ||
        !before.canLeave(from, direction)) {
      return blocks;
    }
    final end =
        before.level
            .mechanic<Ice>(Ice.typeId)
            ?.finishSlide(
              before,
              blocks,
              blockId: twin.id,
              landing: target,
              direction: direction,
              vacated: source,
            ) ??
        target;
    return [...blocks]..[index] = twin.at(end);
  }

  /// 화면은 이미 판정한 두 스냅샷을 읽는다. 제자리면 짝이 막힌 수다.
  MirrorShift? shiftBetween(
    PuzzleState before,
    PuzzleState after,
    String blockId,
  ) {
    final partner = partnerOf(blockId);
    if (partner == null) return null;
    final id = partner.blockId;
    return (
      blockId: id,
      pair: partner.pair,
      from: before.positionOf(id)!,
      to: after.positionOf(id)!,
    );
  }

  static MirrorShift? recordedShift(MoveRecord move) {
    if (move.power != null) return null;
    final pair = move.before.level.mechanic<MirrorPair>(typeId);
    final shift = pair?.shiftBetween(move.before, move.after, move.blockId);
    return shift == null || shift.from == shift.to ? null : shift;
  }
}
