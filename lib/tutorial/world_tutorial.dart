import 'package:flutter/material.dart';

import '../design/arcade_components.dart' show prefersReducedMotion;
import '../design/game_theme.dart';
import '../domain/mechanics/clock_arrow.dart';
import '../domain/mechanics/ice.dart';
import '../domain/mechanics/mirror_pair.dart';
import '../game/board_badge.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';

enum WorldTutorial {
  mirror(3, 'mirror-guide', MirrorPair.typeId),
  clock(4, 'clock-guide', ClockArrow.typeId),
  ice(5, 'ice-guide', Ice.typeId);

  const WorldTutorial(this.world, this.keyPrefix, this.mechanic);

  final int world;
  final String keyPrefix;
  final String mechanic;

  static WorldTutorial? forWorld(int world) =>
      values.where((guide) => guide.world == world).firstOrNull;

  List<(String, String)> cards(AppLocalizations t) => switch (this) {
    mirror => [
      (t.mirrorGuidePush, t.mirrorGuidePushBody),
      (t.mirrorGuideFollow, t.mirrorGuideFollowBody),
      (t.mirrorGuideBlocked, t.mirrorGuideBlockedBody),
    ],
    clock => [
      (t.clockGuideExit, t.clockGuideExitBody),
      (t.clockGuideTurn, t.clockGuideTurnBody),
      (t.clockGuideWait, t.clockGuideWaitBody),
    ],
    ice => [
      (t.iceGuideEnter, t.iceGuideEnterBody),
      (t.iceGuideStop, t.iceGuideStopBody),
      (t.iceGuideSetStop, t.iceGuideSetStopBody),
    ],
  };

  String replayLabel(AppLocalizations t) => switch (this) {
    mirror => t.mirrorGuideReplay,
    clock => t.clockGuideReplay,
    ice => t.iceGuideReplay,
  };
}

Future<void> showWorldTutorial(
  BuildContext context,
  GameSettings settings,
  WorldTutorial tutorial,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    animationStyle: prefersReducedMotion(context, settings)
        ? AnimationStyle.noAnimation
        : null,
    builder: (_) => _WorldTutorialCard(tutorial),
  );
}

class _WorldTutorialCard extends StatefulWidget {
  const _WorldTutorialCard(this.tutorial);

  final WorldTutorial tutorial;

  @override
  State<_WorldTutorialCard> createState() => _WorldTutorialCardState();
}

class _WorldTutorialCardState extends State<_WorldTutorialCard> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final tutorial = widget.tutorial;
    final prefix = tutorial.keyPrefix;
    final cards = tutorial.cards(t);
    final (title, body) = cards[_page];
    final last = _page == cards.length - 1;
    return AlertDialog(
      key: ValueKey('$prefix-${_page + 1}'),
      scrollable: true,
      icon: Center(
        child: SizedBox.square(
          dimension: 52,
          child: CustomPaint(painter: BoardBadge(tutorial.mechanic)),
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
            key: ValueKey('$prefix-skip'),
            onPressed: () => Navigator.pop(context),
            child: Text(t.skipTutorial),
          ),
        FilledButton(
          key: ValueKey('$prefix-next'),
          onPressed: last
              ? () => Navigator.pop(context)
              : () => setState(() => _page++),
          child: Text(last ? t.worldGuideDone : t.worldGuideNext),
        ),
      ],
    );
  }
}
