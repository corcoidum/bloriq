import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the archived course records a legal, shortest solution per stage', () {
    final levels = jsonDecode(
      File('assets/levels/course2_baseline.json').readAsStringSync(),
    ) as List<dynamic>;
    for (final raw in levels) {
      final level = Level.fromJson(raw as Map<String, dynamic>);
      final controller = PuzzleController(level);
      final hint = const HintSearch().storedSolution(controller.state);
      final shortest = const PuzzleSolver(maxStates: 2000000).solve(level)!;
      expect(hint, hasLength(level.minimumMoves), reason: 'level ${level.id}');
      expect(
        hint!.map(_input),
        shortest.map(_input),
        reason: 'level ${level.id}',
      );
      for (final move in hint) {
        expect(
          controller.apply(move),
          isTrue,
          reason: 'level ${level.id}, $move',
        );
      }
      expect(controller.state.isComplete, isTrue, reason: 'level ${level.id}');
      expect(const HintSearch().storedSolution(controller.state), isNull);
    }
  });
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);
