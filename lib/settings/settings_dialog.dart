import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import 'game_settings.dart';
import '../analytics/local_analytics.dart';
import '../analytics/playtest_controls.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.audio,
    this.onReplayIntro,
    this.onReplayEnding,
    required this.onCredits,
    this.analytics,
  });

  final GameSettings settings;
  final GameAudio audio;
  final LocalAnalytics? analytics;
  final VoidCallback? onReplayIntro;
  final VoidCallback? onReplayEnding;
  final VoidCallback onCredits;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => AlertDialog(
        icon: const Center(child: CourierPortrait(height: 64)),
        title: Text(t.settings),
        scrollable: true,
        content: SizedBox(
          width: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.motionSection, style: GameTypography.label),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reduceMotion),
                subtitle: Text(t.reduceMotionDescription),
                value: widget.settings.reduceMotion,
                onChanged: widget.settings.setReduceMotion,
              ),
              const Divider(),
              Text(t.audioSection, style: GameTypography.label),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.soundEffects),
                value: widget.audio.effectsEnabled,
                onChanged: (value) =>
                    setState(() => widget.audio.setEffectsEnabled(value)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.backgroundMusic),
                value: widget.audio.musicEnabled,
                onChanged: (value) =>
                    setState(() => widget.audio.setMusicEnabled(value)),
              ),
              if (widget.onReplayIntro != null) ...[
                const Divider(),
                Text(t.introSection, style: GameTypography.label),
                ListTile(
                  key: const ValueKey('replay-intro'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.movie_filter_outlined,
                    color: colors.echoInk,
                  ),
                  title: Text(t.replayIntro),
                  onTap: widget.onReplayIntro,
                ),
              ],
              if (widget.onReplayEnding != null)
                ListTile(
                  key: const ValueKey('replay-ending'),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.auto_awesome_rounded,
                    color: colors.reward,
                  ),
                  title: Text(t.endingReplay),
                  onTap: widget.onReplayEnding,
                ),
              if (widget.analytics case final analytics?)
                PlaytestControls(analytics: analytics),
              const Divider(),
              ListTile(
                key: const ValueKey('settings-credits'),
                leading: const Icon(Icons.info_outline_rounded),
                contentPadding: EdgeInsets.zero,
                title: Text(t.endingCredits),
                onTap: widget.onCredits,
              ),
              if (widget.settings.saveFailed)
                Text(
                  t.settingsSaveError,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
        ],
      ),
    );
  }
}
