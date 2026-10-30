import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import 'local_analytics.dart';

class PlaytestControls extends StatefulWidget {
  const PlaytestControls({super.key, required this.analytics});
  final LocalAnalytics analytics;
  @override
  State<PlaytestControls> createState() => _PlaytestControlsState();
}

class _PlaytestControlsState extends State<PlaytestControls> {
  bool _exporting = false, _failed = false;
  Future<void> _export() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _failed = false;
    });
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      await widget.analytics.flush();
      final bytes = Uint8List.fromList(
        utf8.encode(jsonEncode(widget.analytics.snapshot())),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/json')],
          fileNameOverrides: ['bloriq-playtest.json'],
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _clear() async {
    final t = AppLocalizations.of(context)!;
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.deleteTestData),
        content: Text(t.deleteTestDataBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(t.close),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(t.deleteTestData),
          ),
        ],
      ),
    );
    if (yes == true) await widget.analytics.clear();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: widget.analytics,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(),
          Text(t.playtestTitle, style: GameTypography.label),
          SwitchListTile(
            key: const ValueKey('analytics-consent'),
            contentPadding: EdgeInsets.zero,
            title: Text(t.playtestConsent),
            subtitle: Text(t.playtestPrivacy),
            value: widget.analytics.enabled,
            onChanged: widget.analytics.setEnabled,
          ),
          Text(t.playtestCount(widget.analytics.eventCount)),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('export-playtest'),
                onPressed: _exporting ? null : _export,
                icon: const Icon(Icons.ios_share),
                label: Text(t.exportTestData),
              ),
              TextButton(onPressed: _clear, child: Text(t.deleteTestData)),
            ],
          ),
          if (_failed || widget.analytics.saveFailed)
            Text(
              t.playtestError,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
