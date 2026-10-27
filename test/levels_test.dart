import 'dart:convert';

import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('10개 스테이지는 모두 해결 가능하고 최소 이동 수가 정확하다', () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final levels = data
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .toList();
    expect(levels, hasLength(10));
    expect(levels.map((level) => level.id).toSet(), hasLength(10));

    for (final level in levels) {
      final solution = const PuzzleSolver().solve(level);
      expect(solution, isNotNull, reason: 'Level ${level.id} must be solvable');
      expect(
        solution!.length,
        level.minimumMoves,
        reason: 'Level ${level.id} minimumMoves',
      );
      final controller = PuzzleController(level);
      for (final move in solution) {
        expect(
          controller.move(move.blockId, move.target),
          isTrue,
          reason: 'Level ${level.id} solution contains an invalid move',
        );
      }
      expect(
        PathValidator.hasEscapePath(controller.state),
        isTrue,
        reason: 'Level ${level.id} solution must open a path',
      );
    }
  });
}
