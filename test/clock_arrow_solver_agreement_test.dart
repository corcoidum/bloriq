import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';

const _costCount = 200;
const _benchmark = bool.fromEnvironment('BENCH_CLOCK_ARROW');

void main() {
  final cases = solverFixtureRows('test/fixtures/clock_arrow_fuzz.json');
  if (_benchmark) {
    test('measure the real isolate hint on the Python cost sample', () async {
      final clock = [
        for (final row in cases.take(_costCount))
          (
            Level.fromJson(row['level'] as Map<String, dynamic>),
            (row['solution'] as List?)?.length,
          ),
      ];
      final world2 = [
        for (final level in solverFixtureRows('assets/levels/world2.json'))
          // 풀이 캐시를 비워 실제 isolate 탐색 시간만 비교한다.
          (
            Level.fromJson({...level}..remove('solution')),
            level['minimumMoves'] as int,
          ),
      ];
      final result = {
        'clock': await measureIsolateHints(clock),
        'world2': await measureIsolateHints(world2),
      };
      final output = File('build/design_logs/clock-arrow-isolate.json');
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(result),
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
    return;
  }

  test('the fixture covers 320 clock boards and mixed mirror pairs', () {
    expect(cases, hasLength(320));
    final levels = [
      for (final row in cases)
        Level.fromJson(row['level'] as Map<String, dynamic>),
    ];
    expect(
      levels.where((level) => level.mechanics.containsKey(ClockArrow.typeId)),
      hasLength(320),
    );
    expect(
      levels
          .where((level) => level.mechanics.containsKey(MirrorPair.typeId))
          .length,
      greaterThanOrEqualTo(90),
    );
    for (final level in levels.take(_costCount)) {
      final clock = level.mechanic<ClockArrow>(ClockArrow.typeId)!;
      expect((level.boardWidth, level.boardHeight), (5, 5));
      expect(level.blocks.length, inInclusiveRange(2, 3));
      expect(clock.cells.length, inInclusiveRange(2, 4));
      expect(level.mechanics, hasLength(2));
    }
    expect(cases.any((row) => row['outcome'] == 'unsolved'), isTrue);
    expect(cases.any((row) => row['outcome'] == 'limited'), isFalse);
  });

  for (final row in cases) {
    final level = Level.fromJson(row['level'] as Map<String, dynamic>);
    test('clock board ${level.id} agrees with independent Python BFS', () {
      expectSolverAgreement(level, row['solution'] as List?);
    });
  }
}
