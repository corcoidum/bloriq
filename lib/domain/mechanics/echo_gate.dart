import '../puzzle.dart';
import 'board_mechanic.dart';

class EchoGate extends BoardMechanic {
  const EchoGate(this.switchPosition, this.gatePosition);

  factory EchoGate.parse(Map<String, dynamic> rule) => EchoGate(
    parseMechanicPoint(rule['switch']),
    parseMechanicPoint(rule['gate']),
  );

  static const typeId = 'echoGate';
  @override
  String get type => typeId;
  final Position switchPosition;
  final Position gatePosition;
  @override
  Iterable<Position> get cells => [switchPosition, gatePosition];

  @override
  void validate(Level level) {
    // 발판 위에서 시작할 수 있지만, 닫힌 문 위에서 시작할 수는 없다.
    if (switchPosition == level.exitPosition ||
        gatePosition == level.exitPosition ||
        gatePosition == level.startPosition ||
        level.blocks.any((block) => block.position == gatePosition)) {
      throw const FormatException('Invalid switch or gate position');
    }
  }

  bool isOpen(Position? echo) => echo == switchPosition;

  @override
  bool canEnter(PuzzleState state, String? blockId, Position target) =>
      target != gatePosition || isOpen(state.echo);

  @override
  EchoGate reorient(
    Position Function(Position) point,
    Position Function(Position) direction,
  ) => EchoGate(point(switchPosition), point(gatePosition));
}
