import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import 'companion_view.dart';
import 'story_catalog.dart';

class DiscoveryPanel extends StatelessWidget {
  const DiscoveryPanel({
    super.key,
    required this.spirit,
    required this.progress,
    required this.reduceMotion,
    required this.onSkip,
  });
  final SpiritDefinition spirit;
  final double progress;
  final bool reduceMotion;
  final VoidCallback onSkip;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!,
        colors = GameTheme.colorsOf(context);
    final wave = reduceMotion ? 0.0 : math.sin(progress.clamp(0, 1) * math.pi);
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              spirit.guardian
                  ? t.newGuardian(spirit.name.inLocale(t.localeName))
                  : t.newFriend(spirit.name.inLocale(t.localeName)),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.rewardInk,
                fontFamily: GameTypography.canvasFontFamily,
                fontSize: 24,
              ),
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              if (spirit.guardian && wave > 0)
                Container(
                  width: 120 + wave * 24,
                  height: 120 + wave * 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.reward.withValues(alpha: wave * .6),
                      width: 2,
                    ),
                  ),
                ),
              Transform.scale(
                scale: 1 + wave * .035,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Image.asset(
                      StarArt.riqHappy,
                      width: 52,
                      height: 52,
                      cacheWidth: 192,
                      excludeFromSemantics: true,
                    ),
                    SpiritPortrait(spirit: spirit, size: 112),
                  ],
                ),
              ),
            ],
          ),
          Text(
            spirit.memory.inLocale(t.localeName),
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.5),
          ),
          if (spirit.guardian) ...[
            const SizedBox(height: 8),
            Text(t.guardianEndingTitle, style: GameTypography.label),
            Text(t.guardianEnding, textAlign: TextAlign.center),
          ],
          TextButton(
            key: const ValueKey('skip-story'),
            onPressed: onSkip,
            child: Text(t.skipMemory),
          ),
        ],
      ),
    );
  }
}
