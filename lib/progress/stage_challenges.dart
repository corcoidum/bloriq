import '../domain/puzzle.dart';

enum StageChallenge { clear, optimal, technique }

/// 한 번씩 소비하는 권능이 둘 다 필수인 판은 두 번까지 필요하다.
int stageChallengePowerUses(Level level) => level.solvableBareHanded
    ? 0
    : level.requiredPowers.length > 1
    ? level.requiredPowers.length
    : 1;

Set<StageChallenge> stageChallengesForClear(
  Level level, {
  required int moves,
  required int powerUses,
  required bool usedHelp,
}) {
  if (level.world < 2) return const {};
  final requiredUses = stageChallengePowerUses(level);
  return {
    StageChallenge.clear,
    if (moves <= level.minimumMoves) StageChallenge.optimal,
    if (powerUses == requiredUses && (requiredUses > 0 || !usedHelp))
      StageChallenge.technique,
  };
}
