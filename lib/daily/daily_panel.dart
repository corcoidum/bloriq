import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import 'daily_repository.dart';

class DailyPanel extends StatelessWidget {
  const DailyPanel({
    super.key,
    required this.daily,
    required this.onPlay,
    this.compact = false,
  });
  final DailyRepository daily;
  final VoidCallback? onPlay;

  /// 홈 한 화면용 한 줄 카드. 목표와 연속 참여만 보여 준다.
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final challenge = daily.today;
    final best = daily.bestMoves(challenge.date);
    if (compact) {
      return ArcadeSurface(
        accent: colors.echo,
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Row(
          children: [
            Image.asset(
              StarArt.portal,
              height: 36,
              width: 36,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.dailyEcho,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GameTypography.label.copyWith(
                      color: colors.rewardInk,
                    ),
                  ),
                  Text(
                    best == challenge.level.minimumMoves
                        ? t.dailyPerfect
                        : '${t.dailyTarget(challenge.level.minimumMoves)} · '
                              '${t.journeyStreak(daily.streak)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: FilledButton.tonal(
                key: const ValueKey('daily-play'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: colors.echo.withValues(alpha: .18),
                  foregroundColor: colors.text,
                ),
                onPressed: onPlay,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    daily.completed(challenge.date)
                        ? t.dailyReplay
                        : t.dailyPlay,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return ArcadeSurface(
      accent: colors.echo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Image.asset(
                StarArt.portal,
                height: 46,
                width: 46,
                excludeFromSemantics: true,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.dailyEcho,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(color: colors.rewardInk),
                ),
              ),
            ],
          ),
          Text(t.dailyWalk),
          Text(
            DateFormat.yMMMd(t.localeName).format(daily.clock()),
            style: TextStyle(color: colors.secondaryText),
          ),
          const SizedBox(height: 12),
          Text(t.dailyTarget(challenge.level.minimumMoves)),
          if (best != null)
            Text(
              best == challenge.level.minimumMoves
                  ? t.dailyPerfect
                  : t.bestMoves(best),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 4,
            runSpacing: 8,
            children: [
              for (final day in daily.recentDays)
                Semantics(
                  label:
                      '${DateFormat.yMMMd(t.localeName).format(day)}, ${daily.completed(localDateKey(day))
                          ? t.dailyDone
                          : daily.participated(localDateKey(day))
                          ? t.dailyPlayed
                          : t.dailyQuiet}',
                  child: SizedBox(
                    width:
                        40 *
                        (MediaQuery.textScalerOf(context).scale(12) / 12).clamp(
                          1,
                          2,
                        ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          daily.completed(localDateKey(day))
                              ? Icons.stars_rounded
                              : daily.participated(localDateKey(day))
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          color: daily.participated(localDateKey(day))
                              ? colors.echoInk
                              : colors.secondaryText,
                          size: 24,
                        ),
                        Text(
                          '${day.month}/${day.day}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(t.dailyStreak(daily.streak)),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('daily-play'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.echo.withValues(alpha: .16),
              foregroundColor: colors.text,
            ),
            onPressed: onPlay,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: Text(
              daily.completed(challenge.date) ? t.dailyReplay : t.dailyPlay,
            ),
          ),
          if (daily.saveFailed)
            Text(t.saveError, style: TextStyle(color: colors.error)),
        ],
      ),
    );
  }
}
