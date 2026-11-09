import 'package:flutter/material.dart';

import '../design/arcade_components.dart' show prefersReducedMotion;
import '../design/game_theme.dart';
import '../domain/mechanics/mirror_pair.dart';
import '../game/board_badge.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';

Future<void> showMirrorTutorial(BuildContext context, GameSettings settings) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => const _MirrorTutorialCard(),
  );
}

class _MirrorTutorialCard extends StatefulWidget {
  const _MirrorTutorialCard();

  @override
  State<_MirrorTutorialCard> createState() => _MirrorTutorialCardState();
}

class _MirrorTutorialCardState extends State<_MirrorTutorialCard> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final cards = [
      (t.mirrorGuidePush, t.mirrorGuidePushBody),
      (t.mirrorGuideFollow, t.mirrorGuideFollowBody),
      (t.mirrorGuideBlocked, t.mirrorGuideBlockedBody),
    ];
    final (title, body) = cards[_page];
    final last = _page == cards.length - 1;
    return AlertDialog(
      key: ValueKey('mirror-guide-${_page + 1}'),
      scrollable: true,
      icon: const Center(
        child: SizedBox.square(
          dimension: 52,
          child: CustomPaint(painter: BoardBadge(MirrorPair.typeId)),
        ),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${_page + 1} / ${cards.length}', style: GameTypography.label),
          const SizedBox(height: 10),
          // 세계 1 튜토리얼과 같은 안내 문구 위젯을 쓴다.
          MechanicLegend(items: [LegendItem(LegendKind.note, body)]),
        ],
      ),
      actions: [
        if (!last)
          TextButton(
            key: const ValueKey('mirror-guide-skip'),
            onPressed: () => Navigator.pop(context),
            child: Text(t.skipTutorial),
          ),
        FilledButton(
          key: const ValueKey('mirror-guide-next'),
          onPressed: last
              ? () => Navigator.pop(context)
              : () => setState(() => _page++),
          child: Text(last ? t.mirrorGuideDone : t.mirrorGuideNext),
        ),
      ],
    );
  }
}
