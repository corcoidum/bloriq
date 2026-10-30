import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'game_session.dart';
import '../progress/chapter_progress.dart';
import '../story/companion_view.dart';

Future<int?> showLevelPicker(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  int? currentLevelId,
}) => showDialog<int>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => LevelPicker(session: session, currentLevelId: currentLevelId),
);

class LevelPicker extends StatelessWidget {
  const LevelPicker({super.key, required this.session, this.currentLevelId});
  final GameSession session;
  final int? currentLevelId;

  Widget _tile(BuildContext context, int index) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final level = session.levels[index];
    final best = session.progress.forLevel(level.id, revision: level.revision);
    final spirit = session.story.forLevel(level.id);
    final current = level.id == currentLevelId;
    if (spirit?.released == true) {
      final friend = spirit!;
      return Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: current
                ? colors.primaryInk
                : colors.outline.withValues(alpha: .3),
            width: current ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('level-${level.id}'),
          onTap: () => Navigator.pop(context, level.id),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                SpiritPortrait(
                  spirit: friend,
                  size: 52,
                  hidden: !session.collection.owns(friend.id),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.level(level.id),
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        friend.levelTitle.inLocale(t.localeName),
                        style: GameTypography.label,
                      ),
                      Semantics(
                        label: t.starsLabel(best?.bestStars ?? 0),
                        excludeSemantics: true,
                        child: Text(
                          '${'★' * (best?.bestStars ?? 0)}${'☆' * (3 - (best?.bestStars ?? 0))}',
                          style: TextStyle(color: colors.rewardInk),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  current ? Icons.near_me_rounded : Icons.chevron_right_rounded,
                  color: colors.goalInk,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Semantics(
      selected: current,
      label: current ? t.currentLevel : null,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: current
                ? colors.primaryInk
                : colors.outline.withValues(alpha: .3),
            width: current ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('level-${level.id}'),
          onTap: () => Navigator.pop(context, level.id),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  t.level(level.id),
                  textAlign: TextAlign.center,
                  style: GameTypography.label,
                ),
                if (spirit?.released == true) ...[
                  SpiritPortrait(
                    spirit: spirit!,
                    size: 36,
                    hidden: !session.collection.owns(spirit.id),
                  ),
                  Text(
                    spirit.levelTitle.inLocale(t.localeName),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Semantics(
                  label: t.starsLabel(best?.bestStars ?? 0),
                  excludeSemantics: true,
                  child: Text(
                    best == null
                        ? '☆☆☆'
                        : '${'★' * best.bestStars}${'☆' * (3 - best.bestStars)}',
                    style: TextStyle(
                      color: best == null
                          ? colors.secondaryText
                          : colors.rewardInk,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return AlertDialog(
      icon: Icon(Icons.route_rounded, color: colors.rewardInk),
      title: Text(t.journeyMap),
      content: SizedBox(
        width: 460,
        height: MediaQuery.sizeOf(context).height * .55,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final chapters = ChapterProgress.group(
              session.levels,
              session.progress,
            );
            return CustomScrollView(
              key: const ValueKey('level-grid'),
              slivers: [
                for (final chapter in chapters) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.story.chapters[chapter.number - 1].name
                                .inLocale(t.localeName),
                            style: TextStyle(color: colors.rewardInk),
                          ),
                          Text(
                            t.chapterSummary(
                              chapter.number,
                              chapter.completed,
                              chapter.levels.length,
                              chapter.stars,
                            ),
                            style: GameTypography.label,
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: chapter.completed / chapter.levels.length,
                            color: colors.goal,
                            backgroundColor: colors.goal.withValues(alpha: .12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _tile(context, (chapter.number - 1) * 5 + index),
                      ),
                      childCount: chapter.levels.length,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    );
  }
}
