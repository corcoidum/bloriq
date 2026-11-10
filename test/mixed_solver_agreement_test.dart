import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mechanic_solver.dart';

void main() {
  if (const bool.fromEnvironment('BENCH_MIXED')) {
    test(
      'measure the app isolate on the mixed boards and 6×6 mid-board states',
      _benchmark,
      timeout: const Timeout(Duration(minutes: 20)),
    );
    return;
  }

  final cases = solverFixtureRows('test/fixtures/mixed_fuzz.json');
  final inputs = [
    for (final row in cases)
      (
        Level.fromJson(row['level'] as Map<String, dynamic>),
        row['solution'] as List?,
      ),
  ];
  test('500 boards cover every mechanic pair, triple and power choice', () {
    expect(inputs, hasLength(500));
    expect(cases.map((row) => row['outcome']), isNot(contains('limited')));
    expect(inputs.where((input) => input.$2 == null), isNotEmpty);
    for (final (level, _) in inputs) {
      expect(level.mechanics.length, inInclusiveRange(2, 3));
      expect(level.availablePowers.length, lessThanOrEqualTo(1));
    }
    final pairs = inputs.where((input) => input.$1.mechanics.length == 2);
    final triples = inputs.where((input) => input.$1.mechanics.length == 3);
    expect(pairs, hasLength(360));
    expect({
      for (final (level, _) in pairs)
        (level.mechanics.keys.join(','), level.availablePowers.singleOrNull),
    }, hasLength(36 * 5));
    expect({
      for (final (level, _) in triples) level.mechanics.keys.join(','),
    }, hasLength(84));
  });

  for (final (level, expected) in inputs) {
    test('mixed board ${level.id} agrees with independent Python BFS', () {
      expectSolverAgreement(level, expected);
    });
  }

  test('a mixed board rejects a repeated power declaration', () {
    final raw = cases.first['level'] as Map<String, dynamic>;
    expect(
      () => Level.fromJson({
        ...raw,
        'availablePowers': ['wind', 'wind'],
      }),
      throwsFormatException,
    );
  });

  test(
    'campaign starts can return a stored path without any search budget',
    () async {
      final sample = cases.firstWhere((row) {
        final level = row['level'] as Map<String, dynamic>;
        return row['solution'] != null &&
            (level['availablePowers'] as List).isNotEmpty;
      });
      final path = (sample['solution'] as List).cast<List>();
      final mixed = {
        ...sample['level'] as Map<String, dynamic>,
        'minimumMoves': path.length,
        'solution': [
          for (final step in path)
            {
              'blockId': step[0],
              'target': {'x': (step[2] as List)[0], 'y': (step[2] as List)[1]},
              if (step.length == 4) 'power': step[3],
            },
        ],
      };
      const hint = HintSearch(timeLimit: Duration.zero, maxStates: 1);
      for (final row in [
        ...solverFixtureRows('assets/levels/world6.json'),
        mixed,
      ]) {
        final level = Level.fromJson(row);
        final state = PuzzleState.initial(level, powers: level.availablePowers);
        expect(
          hint.storedSolution(state),
          same(level.solution),
          reason: '${level.id}',
        );
        final result = await hint.solve(state);
        expect(result.limited, isFalse, reason: '${level.id}');
        expect(result.moves, same(level.solution), reason: '${level.id}');
        final controller = PuzzleController(
          level,
          powers: level.availablePowers,
        );
        expect(
          controller.apply(level.solution.first),
          isTrue,
          reason: '${level.id}',
        );
        expect(
          hint.storedSolution(controller.state),
          isNull,
          reason: '${level.id}',
        );
      }
    },
  );
}

Future<void> _benchmark() async {
  final samples = solverFixtureRows('build/design_logs/w7-mixed-python.json');
  expect(samples, hasLength(576));
  const hint = HintSearch();
  final warmup = Level.fromJson(samples.first['level'] as Map<String, dynamic>);
  await hint.solve(PuzzleState.initial(warmup, powers: warmup.availablePowers));
  final rows = <Map<String, Object>>[];

  Future<HintResult> measure(PuzzleState state, String phase) async {
    expect(hint.storedSolution(state), isNull);
    final watch = Stopwatch()..start();
    final result = await hint.solve(state);
    watch.stop();
    rows.add({
      'id': state.level.id,
      'phase': phase,
      'ms': watch.elapsedMicroseconds / 1000,
      'withinTime': watch.elapsed < hint.timeLimit,
      'outcome': result.limited
          ? 'limited'
          : result.moves == null
          ? 'unsolved'
          : 'solved',
    });
    return result;
  }

  for (final sample in samples) {
    final level = Level.fromJson(sample['level'] as Map<String, dynamic>);
    final initial = PuzzleState.initial(level, powers: level.availablePowers);
    final result = await measure(initial, 'initial');
    final python = sample['python'] as Map<String, dynamic>;
    if (!result.limited && python['outcome'] != 'limited') {
      expect(
        result.moves?.length,
        (sample['solution'] as List?)?.length,
        reason: '${level.id}',
      );
    }
    if (sample['sample'] == 'corners') {
      // 일반 이동 한 번을 적용한 뒤에도 권능을 들고 있어 중간 판 탐색을 측정할 수 있다.
      final next = PuzzleSolver.successors(initial)
          .where((edge) => edge.$1.power == null && !edge.$2.isComplete)
          .firstOrNull;
      if (next != null) await measure(next.$2, 'afterMove');
    }
  }

  final output = File('build/design_logs/w7-mixed-isolate.json');
  output.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
}
