import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';

/// 연출은 표시만 담당한다. 별 계산과 기록 저장은 호출자가 즉시 완료한다.
class VictoryPanel extends StatelessWidget {
  const VictoryPanel({
    super.key,
    required this.progress,
    required this.stars,
    required this.isNewBest,
    required this.reduceMotion,
    required this.onSkip,
    required this.result,
  });

  final double progress;
  final int stars;
  final bool isNewBest;
  final bool reduceMotion;
  final VoidCallback onSkip;
  final Widget result;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final panel = reduceMotion ? 1.0 : ((progress - .78) / .22).clamp(0.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            t.complete,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(color: colors.goalInk, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: GameSpacing.small),
        Semantics(
          label: t.starsLabel(stars),
          excludeSemantics: true,
          child: SizedBox(
            height: math.max(44, MediaQuery.textScalerOf(context).scale(34)),
            child: progress >= 1 || reduceMotion
                ? Center(
                    child: Text(
                      '${'★' * stars}${'☆' * (3 - stars)}',
                      style: GameTypography.reward.copyWith(
                        color: colors.rewardInk,
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (index) {
                      final reveal = ((progress - (.42 + index * .14)) / .12)
                          .clamp(0.0, 1.0);
                      final earned = index < stars;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Transform.scale(
                          scale: earned
                              ? .8 + .2 * Curves.easeOutBack.transform(reveal)
                              : 1,
                          child: Icon(
                            earned && reveal > 0
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 36,
                            color: earned && reveal > 0
                                ? colors.reward
                                : colors.outline,
                          ),
                        ),
                      );
                    }),
                  ),
          ),
        ),
        if (progress < 1 && !reduceMotion)
          TextButton.icon(
            key: const ValueKey('skip-celebration'),
            onPressed: onSkip,
            icon: const Icon(Icons.skip_next_rounded),
            label: Text(t.skipCelebration),
          ),
        if (panel > 0)
          Opacity(
            opacity: panel,
            child: Transform.translate(
              offset: Offset(0, reduceMotion ? 0 : 8 * (1 - panel)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(GameSpacing.page),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(GameSpacing.radius),
                  border: Border.all(
                    color: isNewBest
                        ? colors.reward.withValues(alpha: .7)
                        : colors.outline.withValues(alpha: .3),
                  ),
                ),
                child: Column(
                  children: [
                    if (isNewBest) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colors.reward.withValues(alpha: .14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.scale(
                              scale: reduceMotion
                                  ? 1
                                  : 1 + .12 * math.sin(panel * math.pi),
                              child: Icon(
                                Icons.auto_awesome,
                                color: colors.rewardInk,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                t.newBest,
                                style: GameTypography.label.copyWith(
                                  color: colors.rewardInk,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: GameSpacing.small),
                    ],
                    result,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
