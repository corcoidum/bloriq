import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../design/arcade_components.dart';
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

Future<bool?> showGameHelp(BuildContext context, GameSettings settings) {
  final t = AppLocalizations.of(context)!;
  return showDialog<bool>(
    context: context,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => AlertDialog(
      icon: const Icon(Icons.touch_app_rounded),
      title: Text(t.help),
      content: SingleChildScrollView(child: Text(t.helpBody)),
      actions: [
        TextButton(
          key: const ValueKey('replay-tutorial'),
          onPressed: () => Navigator.pop(context, true),
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
