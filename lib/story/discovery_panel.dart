import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../l10n/app_localizations.dart';
import 'companion_view.dart';
import 'story_catalog.dart';

class DiscoveryPanel extends StatelessWidget {
  const DiscoveryPanel({
    super.key,
    required this.spirit,
    required this.chapter,
    required this.progress,
    required this.reduceMotion,
    required this.onSkip,
  });
  final SpiritDefinition spirit;
  final StoryChapter chapter;
  final double progress;
  final bool reduceMotion;
  final VoidCallback onSkip;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!,
        colors = GameTheme.colorsOf(context);
    final wave = reduceMotion ? 0.0 : math.sin(progress.clamp(0, 1) * math.pi);
    final lang = t.localeName;
    // 결과 팝업 안에서는 한 장의 작은 카드로 보여 준다: 초상화 + 이름 + 기억 한 줄.
    // 장의 마지막 수호 정령만 그 장의 결말 문장을 덧붙인다.
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: GameSpacing.small),
        padding: const EdgeInsets.fromLTRB(8, 8, 2, 8),
        decoration: BoxDecoration(
          color: colors.reward.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.reward.withValues(
              alpha: spirit.guardian ? .35 + wave * .4 : .2,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Transform.scale(
                  scale: 1 + wave * .05,
                  child: SpiritPortrait(spirit: spirit, size: 64),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          spirit.guardian
                              ? t.newGuardian(spirit.name.inLocale(lang))
                              : t.newFriend(spirit.name.inLocale(lang)),
                          style: TextStyle(
                            color: colors.rewardInk,
                            fontFamily: GameTypography.canvasFontFamily,
                            fontSize: 21,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      KeepAllText(
                        spirit.memory.inLocale(lang),
                        style: GameTypography.body.copyWith(
                          color: colors.text,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('skip-story'),
                  tooltip: t.skipMemory,
                  visualDensity: VisualDensity.compact,
                  onPressed: onSkip,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
            if (spirit.guardian) ...[
              const SizedBox(height: 6),
              Text(
                chapter.endingTitle.inLocale(lang),
                style: GameTypography.label.copyWith(color: colors.rewardInk),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  chapter.ending.inLocale(lang),
                  textAlign: TextAlign.center,
                  style: GameTypography.body.copyWith(
                    color: colors.text,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
