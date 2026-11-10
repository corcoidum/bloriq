import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/ice.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';

const _costCount = 200;

void main() {
  final cases = solverFixtureRows('test/fixtures/ice_fuzz.json');
  final inputs = [
    for (final row in cases)
      (
        Level.fromJson(row['level'] as Map<String, dynamic>),
        row['solution'] as List?,
      ),
  ];
  if (const bool.fromEnvironment('BENCH_ICE')) {
    test('measure the app isolate on the 200 Python cost boards', () async {
      final rows = await measureIsolateHints(
        inputs.take(_costCount).map((entry) => (entry.$1, entry.$2?.length)),
      );
      final output = File('build/design_logs/ice-isolate.json');
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(rows),
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
    return;
  }

  test('320 ice boards include 30 triple mixes and 200 cost boards', () {
    expect(inputs, hasLength(320));
    expect(
      inputs.where((entry) => entry.$1.mechanics.containsKey(Ice.typeId)),
      hasLength(320),
    );
    expect(
      inputs.where(
        (entry) =>
            entry.$1.mechanics.containsKey(MirrorPair.typeId) &&
            entry.$1.mechanics.containsKey(ClockArrow.typeId),
      ),
      hasLength(30),
    );
    for (final (level, _) in inputs.take(_costCount)) {
      expect((level.boardWidth, level.boardHeight), (5, 5));
      expect(level.blocks.length, inInclusiveRange(2, 3));
      expect(
        level.mechanic<Ice>(Ice.typeId)!.cells.length,
        inInclusiveRange(2, 4),
      );
      expect(level.mechanics, hasLength(2));
    }
    expect(cases.any((row) => row['outcome'] == 'unsolved'), isTrue);
    expect(cases.any((row) => row['outcome'] == 'limited'), isFalse);
  });
  for (final (level, expected) in inputs) {
    test('ice board ${level.id} agrees with independent Python BFS', () {
      expectSolverAgreement(level, expected);
    });
  }
}
