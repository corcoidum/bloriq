import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import 'game_settings.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.audio,
  });

  final GameSettings settings;
  final GameAudio audio;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) => AlertDialog(
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
                  trailing: widget.settings.themeMode == option.$1
                      ? const Icon(Icons.check_circle_outline)
                      : null,
                  onTap: () => widget.settings.setThemeMode(option.$1),
                ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reduceMotion),
                subtitle: Text(t.reduceMotionDescription),
                value: widget.settings.reduceMotion,
                onChanged: widget.settings.setReduceMotion,
              ),
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
