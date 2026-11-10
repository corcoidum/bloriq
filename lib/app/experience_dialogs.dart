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

enum GameHelpAction {
  echo,
  mirror(WorldTutorial.mirror),
  clock(WorldTutorial.clock);

  const GameHelpAction([this.worldGuide]);

  final WorldTutorial? worldGuide;
}

Future<GameHelpAction?> showGameHelp(
  BuildContext context,
  GameSettings settings, {
  bool showMirrorGuide = false,
  bool showClockGuide = false,
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
          const SizedBox(height: 8),
          MechanicLegend(items: MechanicLegend.instructions(t)),
        ],
      ),
      actions: [
        if (showMirrorGuide)
          TextButton(
            key: const ValueKey('replay-mirror-guide'),
            onPressed: () =>
                Navigator.pop(dialogContext, GameHelpAction.mirror),
            child: Text(t.mirrorGuideReplay),
          ),
        if (showClockGuide)
          TextButton(
            key: const ValueKey('replay-clock-guide'),
            onPressed: () => Navigator.pop(dialogContext, GameHelpAction.clock),
            child: Text(t.clockGuideReplay),
          ),
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
