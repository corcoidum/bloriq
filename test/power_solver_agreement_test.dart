import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

/// tools/power_fuzz_fixture.py 가 Python 검증기로 푼 무작위 판을 Dart solver 로
/// 다시 풀어, 두 구현의 권능 규칙이 같은지 확인한다.
void main() {
  final cases = jsonDecode(
    File('test/fixtures/power_fuzz.json').readAsStringSync(),
  ) as List<dynamic>;
  const solver = PuzzleSolver(maxStates: 400000);

  test('fixture exercises the powers', () {
    expect(cases, hasLength(40));
    expect(
      cases.where((c) => c['bare'] == null || c['powered'] < c['bare']),
      hasLength(greaterThan(20)),
    );
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
