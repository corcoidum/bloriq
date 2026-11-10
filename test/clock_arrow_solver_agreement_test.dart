import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/mechanics/clock_arrow.dart';
import 'package:bloriq/domain/mechanics/mirror_pair.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:flutter_test/flutter_test.dart';

const _costCount = 200;
const _benchmark = bool.fromEnvironment('BENCH_CLOCK_ARROW');

void main() {
  final cases = _rows('test/fixtures/clock_arrow_fuzz.json');
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
        for (final level in _rows('assets/levels/world2.json'))
          // 풀이 캐시를 비워 실제 isolate 탐색 시간만 비교한다.
          (
            Level.fromJson({...level}..remove('solution')),
            level['minimumMoves'] as int,
          ),
      ];
      final result = {
        'clock': await _measureHints(clock),
        'world2': await _measureHints(world2),
      };
      final output = File('build/design_logs/clock-arrow-isolate.json');
      output.parent.createSync(recursive: true);
      output.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(result),
      );
    }, timeout: const Timeout(Duration(minutes: 10)));
    return;
  }

  const solver = PuzzleSolver(maxStates: 2000000);
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
      final path = solver.solve(level, powers: level.availablePowers);
      final expected = row['solution'] as List?;
      if (expected == null) {
        expect(path, isNull);
        return;
      }
      expect(path, hasLength(expected.length));
      final controller = PuzzleController(level, powers: level.availablePowers);
      for (final (index, move) in path!.indexed) {
        final step = expected[index] as List;
        expect(move.blockId, step[0]);
        expect(
          controller.state.positionOf(move.blockId),
          _point(step[1] as List),
        );
        expect(move.target, _point(step[2] as List));
        expect(move.power?.id, step.length == 4 ? step[3] : null);
        expect(controller.apply(move), isTrue);
      }
      expect(controller.state.isComplete, isTrue);
    });
  }
}

List<Map<String, dynamic>> _rows(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

Position _point(List point) => Position(point[0] as int, point[1] as int);

Future<List<Map<String, Object>>> _measureHints(
  List<(Level, int?)> cases,
) async {
  const hint = HintSearch();
  final rows = <Map<String, Object>>[];
  for (final (level, expected) in cases) {
    final state = PuzzleState.initial(level, powers: level.availablePowers);
    expect(hint.storedSolution(state), isNull);
    final watch = Stopwatch()..start();
    final result = await hint.solve(state);
    watch.stop();
    if (!result.limited) {
      expect(result.moves?.length, expected, reason: 'level ${level.id}');
    }
    rows.add({
      'id': level.id,
      'ms': watch.elapsedMicroseconds / 1000,
      'outcome': result.limited
          ? 'limited'
          : result.moves == null
          ? 'unsolved'
          : 'solved',
    });
  }
  return rows;
}
