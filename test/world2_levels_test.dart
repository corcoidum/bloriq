import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:bloriq/world/world_progress.dart';
import 'package:flutter_test/flutter_test.dart';

/// tools/validate_levels.py (check_world) 가 기록한 권능 프로필을 Dart
/// solver 가 그대로 재현하는지 확인한다. 두 solver 가 같은 규칙을 쓴다는 증거다.
void main() {
  const asset = 'assets/levels/world2.json';
  final levels = Worlds.parseLevels(File(asset).readAsStringSync(), 2);
  final raw = jsonDecode(File(asset).readAsStringSync()) as List;
  const solver = PuzzleSolver(maxStates: 2000000);

  test('25 stages on 4x4–5x5 boards with a rising curve', () {
    expect(levels, hasLength(25));
    for (final level in levels) {
      expect(level.boardWidth, inInclusiveRange(4, 5));
      expect(level.boardHeight, inInclusiveRange(4, 5));
    }
    // minimumMoves 는 그 스테이지가 여는 권능(한두 개)을 쓸 때의 최단 수다.
    // 톱니 곡선: 장마다 첫 판은 새 권능을 익히도록 쉽게 열고, 다섯째 수호 정령
    // 판에서 정점을 찍는다. 마지막 판은 월드 1 마지막(16수)보다 깊다.
    final minima = [for (final level in levels) level.minimumMoves];
    expect(minima.first, inInclusiveRange(6, 9));
    expect(minima.last, greaterThan(16));
    for (var chapter = 0; chapter < 5; chapter++) {
      final opener = minima[chapter * 5];
      final peak = minima[chapter * 5 + 4];
      expect(opener, lessThan(peak), reason: 'chapter ${chapter + 1}');
      expect(
        minima.sublist(chapter * 5, chapter * 5 + 5).reduce(math.min),
        opener,
        reason: 'chapter ${chapter + 1} opens with its easiest stage',
      );
    }
    expect(minima.last, greaterThanOrEqualTo(minima.first + 4));
    // 장마다 한 권능, 마지막 장은 두 권능만 연다.
    for (var i = 0; i < 25; i++) {
      final powers = levels[i].availablePowers;
      expect(
        powers,
        hasLength(i < 20 ? 1 : 2),
        reason: 'stage ${levels[i].id}',
      );
      expect(
        powers,
        contains(levels[i].featuredPower),
        reason: '${levels[i].id}',
      );
    }
    double average(int chapter) =>
        minima.sublist(chapter * 5, chapter * 5 + 5).reduce((a, b) => a + b) /
        5;
    for (var chapter = 1; chapter < 5; chapter++) {
      expect(
        average(chapter),
        greaterThanOrEqualTo(average(chapter - 1)),
        reason: 'chapter ${chapter + 1}',
      );
    }
    expect(average(4), greaterThan(average(0)));
    // 맨손 최단 수는 언제나 권능 최단 수보다 길다(권능이 실제로 도움이 된다).
    for (final level in levels) {
      if (level.bareHandedMoves case final bare?) {
        expect(bare, greaterThan(level.minimumMoves), reason: '${level.id}');
      }
    }
    // 장마다 수호 정령 스테이지는 그 장의 권능이 꼭 필요하다.
    for (var chapter = 0; chapter < 5; chapter++) {
      expect(levels[chapter * 5 + 4].requiredPowers, isNotEmpty);
    }
    expect(
      levels.where((level) => level.requiredPowers.isEmpty),
      hasLength(greaterThanOrEqualTo(15)),
      reason: 'most stages stay solvable bare-handed',
    );
  });

  test('every stage records whether it is solvable bare-handed', () {
    for (final item in raw) {
      final json = item as Map<String, dynamic>;
      expect(
        json.containsKey('bareHandedMoves'),
        true,
        reason: '${json['id']}',
      );
      expect(json.containsKey('requiredPowers'), true, reason: '${json['id']}');
    }
    for (final level in levels) {
      expect(
        level.solvableBareHanded,
        level.requiredPowers.isEmpty,
        reason: 'stage ${level.id}',
      );
    }
  });

  for (final level in levels) {
    test('stage ${level.id}: Dart solver agrees with the Python validator', () {
      // 스테이지가 여는 권능만 쓸 수 있다.
      final all = level.availablePowers;
      expect(all, isNotEmpty);
      final best = solver.solve(level, powers: all);
      expect(best, isNotNull);
      expect(best!.length, level.minimumMoves);
      final bare = solver.solve(level);
      expect(bare?.length, level.bareHandedMoves);
      final required = {
        for (final power in all)
          if (solver.solve(level, powers: {...all}..remove(power)) == null)
            power,
      };
      expect(required, level.requiredPowers);
      // 최단 해를 그대로 재생하면 출구에 닿는다.
      final controller = PuzzleController(level, powers: all);
      for (final move in best) {
        expect(controller.apply(move), true, reason: '$move');
      }
      expect(controller.state.isComplete, true);
      expect(controller.state.moves, level.minimumMoves);
      // 강조한 권능은 최단 수를 줄이거나 해를 가능하게 한다.
      if (level.featuredPower case final featured?) {
        final without = solver.solve(level, powers: {...all}..remove(featured));
        final using = solver.solve(level, powers: all, mustUse: featured);
        expect(
          without == null ||
              without.length > level.minimumMoves ||
              using?.length == level.minimumMoves,
          true,
          reason: '${featured.id} must shorten or join a shortest solution',
        );
      }
    });
  }

  test('bare-handed star needs no powers and the bare optimum', () {
    final bareLevel = levels.firstWhere((l) => l.bareHandedMoves != null);
    expect(
      isBareHandedClear(
        level: bareLevel,
        moves: bareLevel.bareHandedMoves!,
        usedPower: false,
        usedStarlightPath: false,
      ),
      true,
    );
    expect(
      isBareHandedClear(
        level: bareLevel,
        moves: bareLevel.bareHandedMoves!,
        usedPower: true,
        usedStarlightPath: false,
      ),
      false,
    );
    final required = levels.firstWhere((l) => l.bareHandedMoves == null);
    expect(
      isBareHandedClear(
        level: required,
        moves: 99,
        usedPower: false,
        usedStarlightPath: false,
      ),
      false,
    );
  });
}
