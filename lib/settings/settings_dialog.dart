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
    this.analytics,
  });

  final GameSettings settings;
  final GameAudio audio;
  final LocalAnalytics? analytics;
  final VoidCallback? onReplayIntro;

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
              Text(t.appearance, style: GameTypography.label),
              const SizedBox(height: GameSpacing.small),
              // 세로 선택 목록은 작은 화면과 큰 글꼴에서도 잘리지 않는다.
              for (final option in [
                (ThemeMode.system, t.themeSystem, Icons.brightness_auto),
                (ThemeMode.light, t.themeLight, Icons.light_mode_outlined),
                (ThemeMode.dark, t.themeDark, Icons.dark_mode_outlined),
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(option.$3),
                  title: Text(option.$2),
                  selected: widget.settings.themeMode == option.$1,
                  selectedTileColor: colors.primary.withValues(alpha: .08),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  trailing: widget.settings.themeMode == option.$1
                      ? const Icon(Icons.check_circle_outline)
                      : null,
                  onTap: () => widget.settings.setThemeMode(option.$1),
                ),
              const Divider(),
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
              if (widget.analytics case final analytics?)
                PlaytestControls(analytics: analytics),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                contentPadding: EdgeInsets.zero,
                title: Text(t.credits),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'BLORIQ',
                ),
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
