import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../progress/stage_challenges.dart';

/// 지도와 판 버튼에서 세 과제의 순서를 그대로 보여 준다.
class StageChallengeFlowers extends StatelessWidget {
  const StageChallengeFlowers({super.key, required this.earned});

  final Set<StageChallenge> earned;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Semantics(
      label: t.starflowerCount(earned.length, StageChallenge.values.length),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final challenge in StageChallenge.values)
            _Starflower(earned: earned.contains(challenge), size: 16),
        ],
      ),
    );
  }
}

class StageChallengeCard extends StatelessWidget {
  const StageChallengeCard({
    super.key,
    required this.level,
    required this.earned,
    this.blooming = const {},
    this.reduceMotion = false,
  });

  final Level level;
  final Set<StageChallenge> earned;
  final Set<StageChallenge> blooming;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final technique = switch (stageChallengePowerUses(level)) {
      0 => t.challengeUnassisted,
      1 => t.challengeOnePower,
      _ => t.challengeRequiredPowers,
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.echo.withValues(alpha: .10),
        border: Border.all(color: colors.echoInk.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.starflowerCount(earned.length, StageChallenge.values.length),
              textAlign: TextAlign.center,
              style: GameTypography.label.copyWith(color: colors.echoInk),
            ),
            const SizedBox(height: 4),
            for (final (challenge, objective) in [
              (StageChallenge.clear, t.challengeClear),
              (StageChallenge.optimal, t.challengeOptimal(level.minimumMoves)),
              (StageChallenge.technique, technique),
            ])
              Semantics(
                label:
                    '$objective, '
                    '${earned.contains(challenge) ? t.challengeEarned : t.challengeUnearned}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      _Starflower(
                        earned: earned.contains(challenge),
                        bloom: !reduceMotion && blooming.contains(challenge),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          objective,
                          textAlign: TextAlign.start,
                          style: GameTypography.body.copyWith(
                            fontSize: 13,
                            color: colors.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Starflower extends StatelessWidget {
  const _Starflower({
    required this.earned,
    required this.size,
    this.bloom = false,
  });

  final bool earned;
  final double size;
  final bool bloom;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final flower = Icon(
      earned ? Icons.filter_vintage_rounded : Icons.filter_vintage_outlined,
      size: size,
      color: earned ? colors.echoInk : colors.outline,
    );
    if (!bloom) return flower;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .35, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      child: flower,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
    );
  }
}
