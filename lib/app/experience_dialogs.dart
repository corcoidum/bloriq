import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../design/arcade_components.dart';
import '../design/star_art.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import '../settings/settings_dialog.dart';
import '../tutorial/world_tutorial.dart';
import 'intro_screen.dart';
import '../analytics/local_analytics.dart';

Future<void> showExperienceSettings(
  BuildContext context,
  GameSettings settings,
  GameAudio audio, {
  required bool resumeGame,
  LocalAnalytics? analytics,
}) async {
  final replay = await showDialog<bool>(
    context: context,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (dialogContext) => SettingsDialog(
      settings: settings,
      audio: audio,
      analytics: analytics,
      onReplayIntro: () => Navigator.pop(dialogContext, true),
    ),
  );
  if (replay != true || !context.mounted) return;
  audio.setGameVisible(false);
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      useSafeArea: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (dialogContext) => Dialog.fullscreen(
        child: IntroScreen(
          settings: settings,
          onFinished: () => Navigator.pop(dialogContext),
        ),
      ),
    );
  } finally {
    audio.setGameVisible(resumeGame);
  }
}

class GameHelpAction {
  const GameHelpAction._(this.worldGuide);
  const GameHelpAction.world(WorldTutorial guide) : this._(guide);

  static const echo = GameHelpAction._(null);

  final WorldTutorial? worldGuide;
}

Future<GameHelpAction?> showGameHelp(
  BuildContext context,
  GameSettings settings, {
  List<WorldTutorial> worldGuides = const [],
}) {
  final t = AppLocalizations.of(context)!;
  return showDialog<GameHelpAction>(
    context: context,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      icon: const Center(child: CourierPortrait(height: 70)),
      title: Text(t.help),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.helpBody),
          for (final guide in worldGuides)
            TextButton(
              key: ValueKey('replay-${guide.keyPrefix}'),
              onPressed: () =>
                  Navigator.pop(dialogContext, GameHelpAction.world(guide)),
              child: Text(guide.replayLabel(t)),
            ),
          const SizedBox(height: 8),
          MechanicLegend(items: MechanicLegend.instructions(t)),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('replay-tutorial'),
          onPressed: () => Navigator.pop(dialogContext, GameHelpAction.echo),
          child: Text(t.replayTutorial),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(t.close),
        ),
      ],
    ),
  );
}
