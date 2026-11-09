import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter_test/flutter_test.dart';

/// Python이 만든 기본 또는 지정한 기믹 표본을 같은 권능 조합으로 다시 푼다.
void main() {
  const powerFixture = 'test/fixtures/power_fuzz.json';
  const mirrorFixture = 'test/fixtures/mirror_pair_fuzz.json';
  const fixture = String.fromEnvironment('MECHANIC_FIXTURE');
  for (final path
      in fixture.isEmpty ? [powerFixture, mirrorFixture] : [fixture]) {
    group(path, () => _testFixture(path, powerFixture, mirrorFixture));
  }
}

void _testFixture(String fixture, String powerFixture, String mirrorFixture) {
  final cases = jsonDecode(File(fixture).readAsStringSync()) as List<dynamic>;
  const solver = PuzzleSolver(maxStates: 400000);

  test('fixture covers the configured mechanics and powers', () {
    expect(cases, isNotEmpty);
    if (fixture == powerFixture) {
      expect(cases, hasLength(40));
      expect(
        cases.where((c) => c['bare'] == null || c['powered'] < c['bare']),
        hasLength(greaterThan(20)),
      );
    }
    if (fixture == mirrorFixture) {
      expect(cases, hasLength(greaterThanOrEqualTo(300)));
      final pairs = [
        for (final row in cases)
          Level.fromJson(row['level'] as Map<String, dynamic>)
              .mechanic<MirrorPair>(MirrorPair.typeId),
      ];
      expect(pairs, everyElement(isNotNull));
      expect(
        pairs.any((pair) => pair?.partnerOf(Level.goalBlockId) != null),
        isTrue,
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
