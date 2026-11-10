import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> solverFixtureRows(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();

Position _point(List point) => Position(point[0] as int, point[1] as int);

void expectSolverAgreement(Level level, List? expected) {
  const solver = PuzzleSolver(maxStates: 2000000);
  final path = solver.solve(level, powers: level.availablePowers);
  if (expected == null) {
    expect(path, isNull);
    return;
  }
  expect(path, hasLength(expected.length));
  final controller = PuzzleController(level, powers: level.availablePowers);
  for (final (index, move) in path!.indexed) {
    final step = expected[index] as List;
    expect(move.blockId, step[0]);
    expect(controller.state.positionOf(move.blockId), _point(step[1] as List));
    expect(move.target, _point(step[2] as List));
    expect(move.power?.id, step.length == 4 ? step[3] : null);
    expect(controller.apply(move), isTrue);
  }
  expect(controller.state.isComplete, isTrue);
}

Future<List<Map<String, Object>>> measureIsolateHints(
  Iterable<(Level, int?)> cases,
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
