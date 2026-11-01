import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import 'narrative_controller.dart';
import 'story_catalog.dart';

class SpiritPortrait extends StatelessWidget {
  const SpiritPortrait({
    super.key,
    required this.spirit,
    this.size = 96,
    this.hidden = false,
  });
  final SpiritDefinition spirit;
  final double size;
  final bool hidden;
  @override
  Widget build(BuildContext context) {
    final image = ClipRect(
      child: SizedBox(
        width: size,
        height: size,
        child: Transform.translate(
          offset: Offset(
            (.5 - spirit.portraitAnchor.dx) * size * spirit.portraitScale,
            (.5 - spirit.portraitAnchor.dy) * size * spirit.portraitScale,
          ),
          child: Transform.scale(
            scale: spirit.portraitScale,
            child: Image.asset(
              spirit.asset!,
              width: size,
              height: size,
              fit: BoxFit.contain,
              cacheWidth: 384,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
    return hidden
        ? ColorFiltered(
            colorFilter: ColorFilter.mode(
              GameTheme.colorsOf(context).secondaryText.withValues(alpha: .45),
              BlendMode.srcIn,
            ),
            child: image,
          )
        : image;
  }
}

class JourneyCompanions extends StatefulWidget {
  const JourneyCompanions({
    super.key,
    required this.companion,
    required this.reduceMotion,
    this.narrative,
    this.compact = false,
    this.inline = false,
    this.onAlbum,
  });
  final SpiritDefinition? companion;

  /// [inline]은 게임 화면용 한 줄 배치다. 작은 초상과 대사를 나란히 둔다.
  final bool reduceMotion, compact, inline;
  final NarrativeController? narrative;
  final VoidCallback? onAlbum;
  @override
  State<JourneyCompanions> createState() => _JourneyCompanionsState();
}

class _JourneyCompanionsState extends State<JourneyCompanions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  @override
  void initState() {
    super.initState();
    widget.narrative?.addListener(_react);
    if (!widget.reduceMotion) _motion.forward();
  }

  @override
  void didUpdateWidget(JourneyCompanions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.narrative != widget.narrative) {
      oldWidget.narrative?.removeListener(_react);
      widget.narrative?.addListener(_react);
    }
    if (widget.reduceMotion) {
      _motion.stop();
    } else if (oldWidget.companion?.id != widget.companion?.id) {
      _motion.forward(from: 0);
    }
  }

  void _react() {
    if (!mounted) return;
    if (!widget.reduceMotion) _motion.forward(from: 0);
    setState(() {});
  }

  @override
  void dispose() {
    widget.narrative?.removeListener(_react);
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final reaction = widget.narrative?.reaction ?? CompanionReaction.idle;
    final asset = switch (reaction) {
      CompanionReaction.blocked => StarArt.riqThinking,
      CompanionReaction.echo ||
      CompanionReaction.memory => StarArt.riqSurprised,
      CompanionReaction.gate ||
      CompanionReaction.complete ||
      CompanionReaction.welcome => StarArt.riqHappy,
      _ => StarArt.riq,
    };
    final size = widget.inline
        ? (widget.compact ? 38.0 : 46.0)
        : widget.compact
        ? 44.0
        : 88.0;
    final showNames = !widget.compact && !widget.inline;
    final speech = Text(
      switch (reaction) {
        CompanionReaction.echo => t.riqEcho,
        CompanionReaction.blocked => t.riqBlocked,
        CompanionReaction.gate => t.riqGate,
        CompanionReaction.welcome || CompanionReaction.complete => t.riqWelcome,
        _ => t.riqIdle,
      },
      textAlign: widget.inline ? TextAlign.start : TextAlign.center,
      maxLines: widget.inline ? 2 : null,
      overflow: widget.inline ? TextOverflow.ellipsis : null,
      style: TextStyle(
        color: GameTheme.colorsOf(context).rewardInk,
        fontSize: 13,
      ),
    );
    Widget character(Widget image, String label) => Semantics(
      image: true,
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          image,
          if (showNames)
            Text(
              label,
              style: TextStyle(
                color: GameTheme.colorsOf(context).secondaryText,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, child) {
          final wave = widget.reduceMotion
              ? 0.0
              : math.sin(_motion.value * math.pi);
          return Transform.translate(
            offset: Offset(0, -wave * 3),
            child: Transform.rotate(
              angle:
                  wave *
                  (reaction == CompanionReaction.blocked ? .06 : .025) *
                  ((widget.narrative?.lookDirection ?? 1) < 0 ? -1 : 1),
              child: child,
            ),
          );
        },
        child: Flex(
          direction: widget.inline ? Axis.horizontal : Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                character(
                  Image.asset(
                    asset,
                    width: size,
                    height: size,
                    cacheWidth: 384,
                    excludeFromSemantics: true,
                  ),
                  t.riqName,
                ),
                if (widget.companion case final friend?) ...[
                  SizedBox(width: widget.inline ? 4 : 12),
                  if (widget.onAlbum == null)
                    character(
                      SpiritPortrait(spirit: friend, size: size),
                      friend.name.inLocale(t.localeName),
                    )
                  else
                    InkWell(
                      key: const ValueKey('companion-album'),
                      onTap: widget.onAlbum,
                      borderRadius: BorderRadius.circular(16),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        child: character(
                          _friendMotion(friend, size),
                          friend.name.inLocale(t.localeName),
                        ),
                      ),
                    ),
                ],
              ],
            ),
            if ((widget.inline || !widget.compact) && widget.narrative != null)
              if (widget.inline)
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: speech,
                  ),
                )
              else
                Padding(padding: const EdgeInsets.only(top: 6), child: speech),
          ],
        ),
      ),
    );
  }

  Widget _friendMotion(SpiritDefinition friend, double size) => AnimatedBuilder(
    animation: _motion,
    child: SpiritPortrait(spirit: friend, size: size),
    builder: (_, child) {
      final wave = widget.reduceMotion
          ? 0.0
          : math.sin(_motion.value * math.pi);
      final floating = friend.motionKind == 'float';
      final bowing = friend.motionKind == 'bow';
      return Transform.translate(
        offset: Offset(
          friend.motionKind == 'wave' ? wave * 2 : 0,
          wave *
              (floating
                  ? -4
                  : bowing
                  ? 2
                  : -1),
        ),
        child: Transform.rotate(
          angle: wave * (friend.motionKind == 'tilt' ? .07 : .025),
          child: Transform.scale(
            scale: bowing ? 1 - .02 * wave : 1,
            child: child,
          ),
        ),
      );
    },
  );
}
