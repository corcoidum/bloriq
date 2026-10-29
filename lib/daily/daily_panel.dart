import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import 'daily_repository.dart';

class DailyPanel extends StatelessWidget {
  const DailyPanel({super.key, required this.daily, required this.onPlay});
  final DailyRepository daily;
  final VoidCallback? onPlay;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final challenge = daily.today;
    final best = daily.bestMoves(challenge.date);
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
