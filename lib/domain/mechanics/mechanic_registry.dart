import 'board_mechanic.dart';
import 'clock_arrow.dart';
import 'echo_eraser.dart';
import 'echo_gate.dart';
import 'echo_hold.dart';
import 'goal_only.dart';
import 'ice.dart';
import 'mirror_pair.dart';
import 'one_way.dart';
import 'shelf_door.dart';

typedef MechanicParser = BoardMechanic Function(Map<String, dynamic>);

abstract final class MechanicRegistry {
  /// 선언 순서대로 이동 훅과 화면 표시를 적용한다.
  static const parsers = <String, MechanicParser>{
    EchoEraser.typeId: EchoEraser.parse,
    EchoHold.typeId: EchoHold.parse,
    OneWay.typeId: OneWay.parse,
    GoalOnly.typeId: GoalOnly.parse,
    EchoGate.typeId: EchoGate.parse,
    // 먼저 밀린 블록이 얼음과 책장을 지난 뒤의 배치로 짝을 판정한다.
    Ice.typeId: Ice.parse,
    ShelfDoor.typeId: ShelfDoor.parse,
    MirrorPair.typeId: MirrorPair.parse,
    ClockArrow.typeId: ClockArrow.parse,
  };

  static List<BoardMechanic> parse(Object? rules) {
    if (rules is! List) {
      throw const FormatException('Special rules must be a list');
    }
    return rules
        .map<BoardMechanic>((rule) {
          if (rule is! Map<String, dynamic> || rule['type'] is! String) {
            throw const FormatException('Unsupported special rule');
          }
          final parser = parsers[rule['type']];
          if (parser == null) {
            throw FormatException('Unsupported special rule: ${rule['type']}');
          }
          return parser(rule);
        })
        .toList(growable: false);
  }

  static Map<String, BoardMechanic> index(Iterable<BoardMechanic> mechanics) {
    final byType = <String, BoardMechanic>{};
    for (final mechanic in mechanics) {
      byType[mechanic.type] =
          byType[mechanic.type]?.combine(mechanic) ?? mechanic;
    }
    return Map.unmodifiable({
      for (final type in parsers.keys) type: ?byType.remove(type),
      ...byType,
    });
  }
}
