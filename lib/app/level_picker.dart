import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'game_session.dart';

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
            return GridView.builder(
              key: const ValueKey('level-grid'),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: 96 + 64 * (scale - 1),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: session.levels.length,
              itemBuilder: (context, index) {
                final level = session.levels[index];
                final best = session.progress.forLevel(level.id);
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
              },
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
