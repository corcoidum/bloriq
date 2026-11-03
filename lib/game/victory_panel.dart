import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../progress/player_repository.dart';

/// 클리어 결과. 휴대폰 한 화면에 별 → 점수 → 경험치 → 보상 → 다음 버튼 순서로 보여 준다.
///
/// 연출은 표시만 담당한다. 별 계산과 기록 저장은 호출자가 즉시 완료한다.
class VictoryPanel extends StatelessWidget {
  const VictoryPanel({
    super.key,
    required this.progress,
    required this.stars,
    required this.isNewBest,
    required this.reduceMotion,
    required this.onSkip,
    required this.score,
    required this.award,
    required this.details,
    required this.next,
    required this.actions,
    this.reward,
    this.notices = const [],
  });

  final double progress;
  final int stars;
  final bool isNewBest;
  final bool reduceMotion;
  final VoidCallback onSkip;
  final RunScore? score;

  /// 저장이 끝나기 전이나 경험치가 없는 모드에서는 null이다.
  final XpAward? award;
  final List<String> details;
  final Widget next;
  final List<Widget> actions;

  /// 보상 한 칸. 새 친구가 있으면 친구, 아니면 별자리다.
  final Widget? reward;
  final List<Widget> notices;

  /// 2.0은 2로, 1.5는 그대로 보여 준다.
  static String _multiplier(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static double _seg(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final p = reduceMotion ? 1.0 : progress.clamp(0.0, 1.0);
    // 앞부분에서는 별문에 도착하는 판 위의 축하를 먼저 보여 준다.
    final veil = _seg(p, .3, .5);
    final content = _seg(p, .38, .56);
    return Stack(
      fit: StackFit.expand,
      children: [
        // 결과가 떠 있는 동안 아래의 게임 버튼은 눌리지 않는다.
        AbsorbPointer(
          child: ColoredBox(
            color: colors.background.withValues(alpha: .9 * veil),
          ),
        ),
        if (veil > 0)
          Opacity(
            opacity: content,
            child: Transform.translate(
              offset: Offset(0, reduceMotion ? 0 : 12 * (1 - content)),
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, box) => Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: math.min(box.maxWidth, 440),
                      child: SingleChildScrollView(
                        key: const ValueKey('result-scroll'),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: IntrinsicHeight(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: GameSpacing.large,
                                vertical: GameSpacing.medium,
                              ),
                              child: _column(
                                context,
                                t,
                                colors,
                                p,
                                box.maxHeight < 780,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (p < 1)
          SafeArea(
            child: Align(
              alignment: const Alignment(1, -.86),
              child: TextButton(
                key: const ValueKey('skip-celebration'),
                onPressed: onSkip,
                child: Text(t.skipCelebration),
              ),
            ),
          ),
      ],
    );
  }

  Widget _column(
    BuildContext context,
    AppLocalizations t,
    GameColors colors,
    double p,
    bool compact,
  ) {
    final number = NumberFormat.decimalPattern(t.localeName);
    final score = this.score;
    final count = _seg(p, .55, .9);
    final award = this.award;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: compact ? 8 : 44),
        const Spacer(),
        Semantics(
          liveRegion: true,
          child: Text(
            t.complete,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: GameTypography.canvasFontFamily,
              fontSize: compact ? 23 : 28,
              color: colors.goalInk,
            ),
          ),
        ),
        if (!compact) const SizedBox(height: GameSpacing.small),
        Semantics(
          label: t.starsLabel(stars),
          excludeSemantics: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) {
              final reveal = _seg(p, .42 + index * .1, .54 + index * .1);
              final earned = index < stars && reveal > 0;
              return Transform.scale(
                scale: index < stars
                    ? .7 + .3 * Curves.easeOutBack.transform(reveal)
                    : 1,
                child: Icon(
                  earned ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: compact ? 42 : 58,
                  color: earned ? colors.reward : colors.outline,
                ),
              );
            }),
          ),
        ),
        if (isNewBest) ...[
          const SizedBox(height: GameSpacing.tiny),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: GameSpacing.medium,
                vertical: GameSpacing.tiny,
              ),
              decoration: BoxDecoration(
                color: colors.reward.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: colors.rewardInk, size: 18),
                  const SizedBox(width: 6),
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
          ),
        ],
        if (score != null) ...[
          SizedBox(height: compact ? GameSpacing.tiny : GameSpacing.medium),
          Semantics(
            label: t.resultScore(score.total),
            excludeSemantics: true,
            child: Text(
              key: const ValueKey('result-score'),
              number.format((score.total * count).round()),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: GameTypography.canvasFontFamily,
                fontSize: compact ? 36 : 50,
                height: 1.1,
                color: colors.reward,
              ),
            ),
          ),
          Text(
            score.comboMultiplier > 1
                ? t.scoreDetailCombo(
                    number.format(score.base),
                    _multiplier(score.starMultiplier),
                    _multiplier(score.comboMultiplier),
                  )
                : t.scoreDetail(
                    number.format(score.base),
                    _multiplier(score.starMultiplier),
                  ),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.secondaryText),
          ),
        ],
        const SizedBox(height: GameSpacing.tiny),
        for (final line in details)
          Text(
            line,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.secondaryText),
          ),
        if (award != null) ...[
          SizedBox(height: compact ? GameSpacing.tiny : GameSpacing.medium),
          _XpBar(award: award, progress: _seg(p, .7, 1)),
        ],
        if (reward case final reward?) ...[
          SizedBox(height: compact ? GameSpacing.tiny : GameSpacing.medium),
          reward,
        ],
        ...notices,
        const Spacer(),
        const SizedBox(height: GameSpacing.tiny),
        next,
        const SizedBox(height: GameSpacing.small),
        Row(
          children: [
            for (final action in actions)
              Expanded(child: Center(child: action)),
          ],
        ),
      ],
    );
  }
}

class _XpBar extends StatelessWidget {
  const _XpBar({required this.award, required this.progress});
  final XpAward award;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final leveled = award.leveledUp && progress >= 1;
    final start = award.before.fraction;
    // 레벨이 오르면 바가 끝까지 찼다가 새 레벨에서 이어서 찬다.
    final fraction = !award.leveledUp
        ? start + (award.after.fraction - start) * progress
        : progress < .6
        ? start + (1 - start) * (progress / .6)
        : award.after.fraction * ((progress - .6) / .4);
    final shown = progress >= .6 ? award.after : award.before;
    return Semantics(
      label: t.playerProgress(
        award.after.level,
        award.after.into,
        award.after.needed,
      ),
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  t.playerLevel(shown.level),
                  style: GameTypography.label.copyWith(color: colors.rewardInk),
                ),
              ),
              const SizedBox(width: GameSpacing.small),
              if (leveled)
                Flexible(
                  child: Container(
                    key: const ValueKey('result-levelup'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: GameSpacing.small,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.goal.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      t.levelUp,
                      style: GameTypography.label.copyWith(
                        color: colors.goalInk,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: GameSpacing.small),
              Expanded(
                flex: 4,
                child: Text(
                  t.xpGained(award.gained),
                  textAlign: TextAlign.end,
                  style: GameTypography.label.copyWith(color: colors.goalInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: GameSpacing.tiny),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: fraction.clamp(0.0, 1.0),
              color: colors.goal,
              backgroundColor: colors.goal.withValues(alpha: .14),
            ),
          ),
        ],
      ),
    );
  }
}

/// 결과 화면의 보상 한 칸.
class RewardCard extends StatelessWidget {
  const RewardCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });
  final Widget? trailing;
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return Semantics(
      button: onTap != null,
      liveRegion: true,
      label: subtitle == null ? title : '$title. $subtitle',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('result-reward'),
        borderRadius: BorderRadius.circular(GameSpacing.radius),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(GameSpacing.small),
          decoration: GameTheme.surfaceDecoration(
            colors,
            accent: colors.reward,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: GameSpacing.medium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: GameTypography.canvasFontFamily,
                        fontSize: 18,
                        color: colors.rewardInk,
                      ),
                    ),
                    if (subtitle case final subtitle?)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.secondaryText),
            ],
          ),
        ),
      ),
    );
  }
}
