import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import 'constellation_atlas.dart';
import 'constellation_state.dart';

/// 승리 패널 안의 작은 별자리 띠. 새 팝업을 열지 않고 결과 화면에 함께 보인다.
///
/// [progress]는 승리 연출 진행도(0..1)다. 별빛은 결과 패널이 나타난 뒤 내려온다.
class VictoryConstellation extends StatelessWidget {
  const VictoryConstellation({
    super.key,
    required this.chapter,
    required this.levelId,
    required this.progress,
    required this.reduceMotion,
    required this.guardianAsset,
    this.event,
    this.pending = false,
    this.onOpen,
  });

  final ChapterConstellation chapter;
  final int levelId;
  final double progress;
  final bool reduceMotion;
  final String? guardianAsset;
  final ConstellationEvent? event;

  /// 저장이 실패해 아직 켜지지 않은 별.
  final bool pending;
  final VoidCallback? onOpen;

  static double _seg(double value, double start, double end) =>
      ((value - start) / (end - start)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final name = chapter.definition.name(t);
    final event = this.event;
    final p = reduceMotion ? 1.0 : progress.clamp(0.0, 1.0);
    final node = chapter.nodeIndexOf(levelId);
    final caption = pending
        ? t.constellationPending
        : event == null
        ? null
        : event.becameGolden
        ? t.constellationGoldenTitle(name)
        : event.chapterCompleted
        ? t.constellationCompleteTitle(name)
        : event.newNode
        ? t.constellationNewStar(name)
        : null;
    if (caption == null) return const SizedBox.shrink();
    final animatingNode = event != null && event.newNode;
    return Semantics(
      container: true,
      liveRegion: true,
      label: '$caption. ${constellationSummary(t, chapter)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: GameSpacing.small),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              key: const ValueKey('victory-constellation'),
              height: 76,
              width: 168,
              child: ConstellationArt(
                chapter: chapter,
                guardianAsset: guardianAsset,
                pendingNode: pending ? node : null,
                highlightNode: animatingNode ? node : null,
                spark: animatingNode ? _seg(p, .78, .90) : null,
                nodeReveal: animatingNode ? _seg(p, .88, .97) : 1,
                lineReveal: animatingNode ? _seg(p, .90, 1) : 1,
                silhouetteReveal: event?.chapterCompleted == true
                    ? _seg(p, .92, 1)
                    : 1,
                golden: event?.becameGolden == true
                    ? _seg(p, .86, 1)
                    : (chapter.golden ? 1 : 0),
              ),
            ),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: GameTypography.label.copyWith(color: colors.rewardInk),
            ),
            if (onOpen != null &&
                (event?.chapterCompleted == true ||
                    event?.becameGolden == true))
              TextButton.icon(
                key: const ValueKey('result-constellation'),
                onPressed: onOpen,
                icon: const Icon(Icons.auto_awesome),
                label: Text(t.viewConstellation),
              ),
          ],
        ),
      ),
    );
  }
}
