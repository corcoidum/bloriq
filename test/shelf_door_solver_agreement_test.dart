import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/mechanics/shelf_door.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';

const _costCount = 200;

void main() {
  final cases = solverFixtureRows('test/fixtures/shelf_door_fuzz.json');
  final inputs = [
    for (final row in cases)
      (
        Level.fromJson(row['level'] as Map<String, dynamic>),
        row['solution'] as List?,
      ),
  ];
  if (const bool.fromEnvironment('BENCH_SHELF_DOOR')) {
    test('measure the app isolate on the 200 Python cost boards', () async {
      final rows = await measureIsolateHints(
        inputs.take(_costCount).map((entry) => (entry.$1, entry.$2?.length)),
      );
      final output = File('build/design_logs/shelf-door-isolate.json');
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(rows),
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
    return;
  }

  test('320 shelf boards include all mixtures and two cost board sizes', () {
    expect(inputs, hasLength(320));
    expect(cases.every((row) => row['outcome'] != 'limited'), isTrue);
    final cost = inputs.take(_costCount).map((input) => input.$1).toList();
    expect(cost.where((level) => level.boardWidth == 6), hasLength(40));
    expect(cost.every((level) => level.boardHeight == 5), isTrue);
    expect(
      cost.where((level) => level.mechanics.containsKey(Ice.typeId)),
      hasLength(100),
    );
    expect(
      cost.where((level) => level.mechanics.containsKey(MirrorPair.typeId)),
      hasLength(75),
    );
    expect(
      inputs.where(
        (entry) => entry.$1.mechanics.keys.toSet().containsAll([
          Ice.typeId,
          MirrorPair.typeId,
          ClockArrow.typeId,
        ]),
      ),
      hasLength(40),
    );
    for (final (level, _) in inputs) {
      final shelf = level.mechanic<ShelfDoor>(ShelfDoor.typeId);
      expect(shelf?.pairs.length, inInclusiveRange(1, 2));
    }
  });

  for (final (level, expected) in inputs) {
    test('shelf board ${level.id} agrees with independent Python BFS', () {
      expectSolverAgreement(level, expected);
    });
  }
}
