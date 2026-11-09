import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../design/arcade_components.dart';
import '../design/star_art.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import '../settings/settings_dialog.dart';
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

enum GameHelpAction { echo, mirror }

Future<GameHelpAction?> showGameHelp(
  BuildContext context,
  GameSettings settings, {
  bool showMirrorGuide = false,
}) {
  final t = AppLocalizations.of(context)!;
  return showDialog<GameHelpAction>(
    context: context,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => AlertDialog(
      icon: const Center(child: CourierPortrait(height: 70)),
      title: Text(t.help),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.helpBody),
            const SizedBox(height: 8),
            MechanicLegend(items: MechanicLegend.instructions(t)),
          ],
        ),
      ),
      actions: [
        if (showMirrorGuide)
          TextButton(
            key: const ValueKey('replay-mirror-guide'),
            onPressed: () => Navigator.pop(context, GameHelpAction.mirror),
            child: Text(t.mirrorGuideReplay),
          ),
        TextButton(
          key: const ValueKey('replay-tutorial'),
          onPressed: () => Navigator.pop(context, GameHelpAction.echo),
          child: Text(t.replayTutorial),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    ),
  );
}
