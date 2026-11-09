import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/hint_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final asset in ['levels', 'world2', 'course2_baseline']) {
    test('$asset records a legal, shortest solution for every stage', () {
      final levels = jsonDecode(
        File('assets/levels/$asset.json').readAsStringSync(),
      ) as List<dynamic>;
      for (final raw in levels) {
        final level = Level.fromJson(raw as Map<String, dynamic>);
        final powers = level.world == 1
            ? const <PuzzlePower>{}
            : level.availablePowers;
        final controller = PuzzleController(level, powers: powers);
        final hint = const HintSearch().storedSolution(controller.state);
        final shortest = const PuzzleSolver(maxStates: 2000000)
            .solve(level, powers: powers)!;
        expect(
          hint,
          hasLength(level.minimumMoves),
          reason: 'level ${level.id}',
        );
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
        expect(
          controller.state.isComplete,
          isTrue,
          reason: 'level ${level.id}',
        );
        expect(const HintSearch().storedSolution(controller.state), isNull);
      }
    });
  }
}

(String, Position, PuzzlePower?) _input(PuzzleMove move) =>
    (move.blockId, move.target, move.power);
