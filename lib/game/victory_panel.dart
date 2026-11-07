import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';

/// 보드 위 가운데에 뜨는 결과 팝업 카드.
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
    required this.actions,
    this.discovery,
    this.constellation,
    this.reward,
  });

  final double progress;
  final int stars;
  final bool isNewBest;
  final bool reduceMotion;
  final VoidCallback onSkip;
  final Widget result;

  /// 카드 아래에 늘 보이는 버튼 묶음. 발견 이야기 중에도 바로 넘어갈 수 있다.
  final Widget actions;

  /// 새 친구 발견 이야기. 결과 위에 함께 보여 주고, 넘기면 접힌다.
  final Widget? discovery;

  /// 새로 켜진 별자리. 같은 결과 패널 안에 표시한다.
  final Widget? constellation;

  /// 경험치·별가루·레벨 업 같은 성장 보상.
  final Widget? reward;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final panel = reduceMotion || discovery != null
        ? 1.0
        : ((progress - .78) / .22).clamp(0.0, 1.0);
    // 리크가 별문에 들어간 뒤 카드가 가운데에서 튀어 오르듯 나타난다.
    final appear = reduceMotion || discovery != null
        ? 1.0
        : ((progress - .26) / .2).clamp(0.0, 1.0);
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colors.surface, colors.highlight, .06)!,
            colors.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colors.reward.withValues(alpha: .6),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.reward.withValues(alpha: .22),
            blurRadius: 30,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _content(context, t, colors, panel),
    );
    return Opacity(
      opacity: appear,
      child: Transform.scale(
        scale: reduceMotion
            ? 1
            : .82 + .18 * Curves.easeOutBack.transform(appear),
        child: card,
      ),
    );
  }

  Widget _content(
    BuildContext context,
    AppLocalizations t,
    GameColors colors,
    double panel,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (discovery == null) const Center(child: CourierPortrait(height: 60)),
        Semantics(
          liveRegion: true,
          child: Text(
            t.complete,
            textAlign: TextAlign.center,
            style: GameTypography.reward.copyWith(
              color: colors.goalInk,
              fontSize: 25,
            ),
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
              child: SizedBox(
                width: double.infinity,
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
                    ?reward,
                    ?discovery,
                    ?constellation,
                    result,
                    const SizedBox(height: GameSpacing.medium),
                    actions,
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
