import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Python이 만든 기본 또는 지정한 기믹 표본을 같은 권능 조합으로 다시 푼다.
void main() {
  const fixture = String.fromEnvironment(
    'MECHANIC_FIXTURE',
    defaultValue: 'test/fixtures/power_fuzz.json',
  );
  final cases = jsonDecode(File(fixture).readAsStringSync()) as List<dynamic>;
  const solver = PuzzleSolver(maxStates: 400000);

  test('fixture exercises the powers', () {
    expect(cases, isNotEmpty);
    if (fixture == 'test/fixtures/power_fuzz.json') {
      expect(cases, hasLength(40));
      expect(
        cases.where((c) => c['bare'] == null || c['powered'] < c['bare']),
        hasLength(greaterThan(20)),
      );
    }
  });

  for (final raw in cases) {
    final data = raw as Map<String, dynamic>;
    final level = Level.fromJson(data['level'] as Map<String, dynamic>);
    test('random board ${level.id}', () {
      expect(
        solver.solve(level, powers: PuzzlePower.values.toSet())?.length,
        data['powered'],
      );
      expect(solver.solve(level)?.length, data['bare']);
      final single = data['single'] as Map<String, dynamic>;
      for (final power in PuzzlePower.values) {
        expect(
          solver.solve(level, powers: {power})?.length,
          single[power.id],
          reason: power.id,
        );
      }
    });
  }
}
