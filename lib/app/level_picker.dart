import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'game_session.dart';
import '../progress/chapter_progress.dart';

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
    final current = level.id == currentLevelId;
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
      title: Text(t.levels),
      content: SizedBox(
        width: 460,
        height: MediaQuery.sizeOf(context).height * .55,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = (constraints.maxWidth / (100 * scale.clamp(1, 1.6)))
                .floor()
                .clamp(1, 4);
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
                  SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisExtent: 96 + 64 * (scale - 1),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) =>
                          _tile(context, (chapter.number - 1) * 5 + index),
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
