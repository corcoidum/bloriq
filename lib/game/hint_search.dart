import 'package:flutter/foundation.dart';

import '../domain/puzzle.dart';

typedef HintResult = ({List<PuzzleMove>? moves, bool limited});

/// 캠페인, 따라 하기와 항해가 공유하는 제한된 힌트 탐색.
class HintSearch {
  const HintSearch({
    this.timeLimit = const Duration(milliseconds: 1500),
    this.maxStates = 200000,
  });

  final Duration timeLimit;
  final int maxStates;

  List<PuzzleMove>? storedSolution(PuzzleState state) {
    final level = state.level;
    final powers = level.world == 1
        ? const <PuzzlePower>{}
        : level.availablePowers;
    if (state.moves != 0 ||
        state.echo != null ||
        level.solution.isEmpty ||
        level.solution.length != level.minimumMoves ||
        !setEquals(state.powers, powers) ||
        state.blocks.length != level.blocks.length + 1 ||
        state.positionOf(Level.goalBlockId) != level.startPosition ||
        level.blocks.any(
          (block) => state.positionOf(block.id) != block.position,
        )) {
      return null;
    }
    return level.solution;
  }

  Future<HintResult> solve(PuzzleState state) async {
    if (storedSolution(state) case final solution?) {
      return (moves: solution, limited: false);
    }
    try {
      final moves = kIsWeb
          ? await PuzzleSolver(maxStates: maxStates)
                .solveCooperatively(state, timeLimit: timeLimit)
          : await compute(_solveHint, (
              state,
              maxStates,
              timeLimit,
            ), debugLabel: 'hint');
      return (moves: moves, limited: false);
    } on PuzzleSearchLimit {
      return (moves: null, limited: true);
    }
  }
}

List<PuzzleMove>? _solveHint((PuzzleState, int, Duration) request) =>
    PuzzleSolver(maxStates: request.$2)
        .solveFromState(request.$1, timeLimit: request.$3);
