import 'dart:convert';

import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('모든 스테이지는 탈출 가능하고 최소 이동 수가 정확하다', () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final levels = data
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .toList();
    expect(levels, hasLength(25));
    expect(
      levels.map((level) => level.id).toList(),
      List.generate(25, (i) => i + 1),
    );

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
        controller.state.isComplete,
        isTrue,
        reason: 'Level ${level.id} solution must reach the exit',
      );
    }
  });

  test('두 번째 레벨은 잔상을 한 번 없앤 뒤 탈출한다', () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final level = Level.fromJson(data[1] as Map<String, dynamic>);
    final controller = PuzzleController(level);

    expect(controller.move('b1', const Position(1, 0)), isTrue);
    expect(controller.state.echo, const Position(1, 1));
    expect(controller.move('goal', const Position(1, 1)), isFalse);
    expect(controller.state.moves, 1);
    expect(controller.move('b1', const Position(2, 0)), isTrue);
    expect(controller.state.echo, const Position(1, 0));
    expect(controller.move('goal', const Position(1, 1)), isTrue);
    expect(controller.move('goal', const Position(2, 1)), isTrue);
    expect(controller.state.isComplete, isTrue);
  });

  test('11단계의 막다른 선택은 Undo로 복구할 수 있다', () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final controller = PuzzleController(
      Level.fromJson(data[10] as Map<String, dynamic>),
    );
    expect(controller.move('b1', const Position(1, 0)), isTrue);
    for (final block in controller.state.blocks) {
      for (final target in block.position.neighbors) {
        expect(
          MoveValidator.canMove(controller.state, block.id, target),
          isFalse,
        );
      }
    }
    expect(controller.undo(), isTrue);
    expect(controller.move('b1', const Position(2, 1)), isTrue);
  });

  test('14단계 스위치 잔상으로 열린 문에 들어가고 닫힌 문에서 나간다', () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final controller = PuzzleController(
      Level.fromJson(data[13] as Map<String, dynamic>),
    );
    expect(controller.state.isGateOpen, isFalse);
    expect(controller.move('goal', const Position(1, 1)), isFalse);
    expect(controller.move('b1', const Position(2, 0)), isTrue);
    expect(controller.state.isGateOpen, isTrue);
    expect(controller.move('goal', const Position(1, 1)), isTrue);
    expect(controller.state.isGateOpen, isFalse);
    expect(controller.state.goal.position, const Position(1, 1));
    expect(controller.move('goal', const Position(2, 1)), isTrue);
    expect(controller.state.isComplete, isTrue);
  });

  test('19단계의 성급한 전진은 막히고 Undo로 회복된다', () async {
    final data = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final controller = PuzzleController(
      Level.fromJson(data[18] as Map<String, dynamic>),
    );

    expect(controller.move('goal', const Position(3, 1)), isTrue);
    for (final block in controller.state.blocks) {
      for (final target in block.position.neighbors) {
        expect(MoveValidator.canMove(controller.state, block.id, target), isFalse);
      }
    }
    expect(controller.undo(), isTrue);
    expect(controller.move('goal', const Position(3, 3)), isTrue);
  });
}
