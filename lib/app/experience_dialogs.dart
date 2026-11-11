import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/star_art.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import '../settings/settings_dialog.dart';
import '../tutorial/world_tutorial.dart';
import '../world/credits_screen.dart';
import '../world/ending_screen.dart';
import 'game_session.dart';
import 'intro_screen.dart';

enum _SettingsAction { intro, ending, credits }

Future<void> showExperienceSettings(
  BuildContext context,
  GameSettings settings,
  GameSession session, {
  required bool resumeGame,
  String? resumeMusicTrack,
}) async {
  final action = await showDialog<_SettingsAction>(
    context: context,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (dialogContext) => SettingsDialog(
      settings: settings,
      audio: session.audio,
      analytics: session.analytics,
      onReplayIntro: () => Navigator.pop(dialogContext, _SettingsAction.intro),
      onReplayEnding: session.sagaComplete
          ? () => Navigator.pop(dialogContext, _SettingsAction.ending)
          : null,
      onCredits: () => Navigator.pop(dialogContext, _SettingsAction.credits),
    ),
  );
  if (action == null || !context.mounted) return;
  if (action == _SettingsAction.credits) {
    await showCredits(context, session.saga);
    return;
  }
  if (action == _SettingsAction.ending) {
    await showEnding(
      context,
      session,
      settings,
      resumeGame: resumeGame,
      resumeMusicTrack: resumeMusicTrack,
    );
    return;
  }
  final audio = session.audio;
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
