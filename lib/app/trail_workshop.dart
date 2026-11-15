import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../game/block_art.dart';
import '../game/bloriq_game.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_repository.dart';
import '../progression/progression_rules.dart';

/// 별빛 공방과 이동 잔영 고르기. 고르거나 눌러 본 잔영을 위에서 미리 보여 준다.
class TrailWorkshop extends StatefulWidget {
  const TrailWorkshop({
    super.key,
    required this.progression,
    required this.trailsHeading,
    required this.reduceMotion,
    required this.onChanged,
  });

  final ProgressionRepository progression;

  /// 공방과 보유 잔영 목록 사이에 놓는 제목.
  final Widget trailsHeading;
  final bool reduceMotion;
  final VoidCallback onChanged;

  @override
  State<TrailWorkshop> createState() => _TrailWorkshopState();
}

class _TrailWorkshopState extends State<TrailWorkshop> {
  /// 눌러 본 잔영. null이면 지금 단 잔영을 보여 준다.
  String? _preview;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final progression = widget.progression;
    final shown = _preview ?? progression.equippedTrail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: KeepAllText(
                ShopText.intro.resolve(lang),
                style: GameTypography.body.copyWith(
                  fontSize: 15,
                  color: colors.secondaryText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.auto_awesome, size: 16, color: colors.rewardInk),
            const SizedBox(width: 4),
            Text(
              '${progression.stardust}',
              key: const ValueKey('shop-balance'),
              style: GameTypography.label.copyWith(color: colors.rewardInk),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Semantics(
          label: t.trailPreview(trailById(shown)?.name.resolve(lang) ?? shown),
          child: ExcludeSemantics(
            child: TrailPreview(
              key: const ValueKey('trail-preview'),
              trailId: shown,
              reduceMotion: widget.reduceMotion,
            ),
          ),
        ),
        const SizedBox(height: 4),
        KeepAllText(
          '${t.trailPreview(trailById(shown)?.name.resolve(lang) ?? shown)}'
          ' · ${t.trailPreviewNote}',
          key: const ValueKey('trail-preview-note'),
          style: GameTypography.body.copyWith(
            fontSize: 13,
            color: colors.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in trailShop)
          _ShopRow(
            item: item,
            owned: progression.ownedTrails.contains(item.trailId),
            affordable: progression.stardust >= item.price,
            previewing: shown == item.trailId,
            onPreview: () => setState(() => _preview = item.trailId),
            onBuy: () async {
              await progression.buyTrail(item.trailId);
              if (mounted) setState(() => _preview = null);
              widget.onChanged();
            },
          ),
        widget.trailsHeading,
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final trail in trails)
              if (shopItemFor(trail.id) == null ||
                  progression.ownedTrails.contains(trail.id))
                ChoiceChip(
                  key: ValueKey('trail-${trail.id}'),
                  avatar: _Swatch(
                    BloriqGame.trailSwatch(trail.id, colors),
                    size: 14,
                  ),
                  label: Text(trail.name.resolve(lang)),
                  selected: progression.equippedTrail == trail.id,
                  onSelected: progression.ownedTrails.contains(trail.id)
                      ? (_) async {
                          await progression.equipTrail(trail.id);
                          if (mounted) setState(() => _preview = null);
                          widget.onChanged();
                        }
                      : null,
                ),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.color, {this.size = 22});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(
        color: GameTheme.colorsOf(context).outline.withValues(alpha: .5),
      ),
    ),
  );
}

class _ShopRow extends StatelessWidget {
  const _ShopRow({
    required this.item,
    required this.owned,
    required this.affordable,
    required this.previewing,
    required this.onPreview,
    required this.onBuy,
  });
  final ShopItem item;
  final bool owned, affordable, previewing;
  final VoidCallback onPreview;
  final Future<void> Function() onBuy;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final name = trailById(item.trailId)?.name.resolve(lang) ?? item.trailId;
    return ConstrainedBox(
      key: ValueKey('shop-${item.trailId}'),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Expanded(
            // 이름을 누르면 사기 전에 색을 미리 본다.
            child: InkWell(
              key: ValueKey('shop-preview-${item.trailId}'),
              borderRadius: BorderRadius.circular(12),
              onTap: onPreview,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    _Swatch(BloriqGame.trailSwatch(item.trailId, colors)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: GameTypography.label.copyWith(
                          color: colors.text,
                        ),
                      ),
                    ),
                    Icon(
                      previewing
                          ? Icons.visibility_rounded
                          : Icons.visibility_outlined,
                      size: 18,
                      color: previewing
                          ? colors.rewardInk
                          : colors.secondaryText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (owned)
            Text(
              ShopText.owned.resolve(lang),
              style: GameTypography.label.copyWith(color: colors.goalInk),
            )
          else
            FilledButton.tonalIcon(
              key: ValueKey('shop-buy-${item.trailId}'),
              onPressed: affordable ? onBuy : null,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text('${item.price}'),
            ),
        ],
      ),
    );
  }
}

/// 블록 하나가 미끄러지며 남기는 빛을 작은 판에서 되풀이해 보여 준다.
class TrailPreview extends StatefulWidget {
  const TrailPreview({
    super.key,
    required this.trailId,
    required this.reduceMotion,
  });

  final String trailId;
  final bool reduceMotion;

  @override
  State<TrailPreview> createState() => _TrailPreviewState();
}

class _TrailPreviewState extends State<TrailPreview>
    with SingleTickerProviderStateMixin {
  /// 움직임을 줄였을 때 보여 주는 멈춘 장면: 막 도착해 빛이 남아 있는 순간.
  static const _still = .36;

  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );

  @override
  void initState() {
    super.initState();
    _play();
  }

  @override
  void didUpdateWidget(TrailPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trailId != widget.trailId ||
        oldWidget.reduceMotion != widget.reduceMotion) {
      _play();
    }
  }

  /// 고를 때마다 세 번 보여 주고 멈춘다.
  void _play() {
    _slide.stop();
    if (widget.reduceMotion) {
      _slide.value = _still;
    } else {
      _slide
        ..value = 0
        ..repeat(count: 3).whenCompleteOrCancel(() {
          if (mounted && !_slide.isAnimating) _slide.value = _still;
        });
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return SizedBox(
      height: 64,
      child: CustomPaint(
        painter: _TrailPreviewPainter(
          progress: _slide,
          colors: colors,
          trailId: widget.trailId,
        ),
      ),
    );
  }
}

class _TrailPreviewPainter extends CustomPainter {
  _TrailPreviewPainter({
    required Animation<double> progress,
    required this.colors,
    required this.trailId,
  }) : _progress = progress,
       super(repaint: progress);

  final Animation<double> _progress;
  final GameColors colors;
  final String trailId;

  static const _travel = .32;

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(area, const Radius.circular(14)),
      Paint()..color = colors.boardSurface,
    );
    final cell = math.min(size.height * .68, size.width / 6);
    final y = size.height / 2;
    final columns = (size.width / (cell * 1.12)).floor().clamp(3, 9);
    final step = size.width / columns;
    final tile = Paint()..color = colors.outline.withValues(alpha: .16);
    for (var index = 0; index < columns; index++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(step * (index + .5), y),
            width: cell * .92,
            height: cell * .92,
          ),
          Radius.circular(cell * .2),
        ),
        tile,
      );
    }
    final start = Offset(step * .5, y);
    final end = Offset(step * (columns - .5), y);
    final p = _progress.value;
    final motion = (p / _travel).clamp(0.0, 1.0);
    final at = Offset.lerp(start, end, Curves.easeOutCubic.transform(motion))!;
    final color = BloriqGame.trailSwatch(trailId, colors);
    final lights = trailId == TrailIds.firstStarlight
        ? BloriqGame.firstStarlightColors
        : null;
    Shader tail(double alpha) => LinearGradient(
      colors: lights != null
          ? [for (final light in lights) light.withValues(alpha: alpha)]
          : [
              color.withValues(alpha: alpha * .2),
              color.withValues(alpha: alpha),
            ],
    ).createShader(Rect.fromPoints(start, end).inflate(1));

    if (motion < 1) {
      final fade = 1 - motion;
      canvas.drawCircle(
        start,
        cell * (.3 + .22 * motion),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, cell * .05 * fade)
          ..color = color.withValues(alpha: .7 * fade),
      );
      if ((at - start).distance > 1) {
        canvas.drawLine(
          start,
          at,
          Paint()
            ..shader = tail(.55 * fade + .2)
            ..strokeWidth = cell * .46
            ..strokeCap = StrokeCap.round,
        );
      }
    } else {
      final rest = ((p - _travel) / (1 - _travel)).clamp(0.0, 1.0);
      final glow = 1 - Curves.easeIn.transform((rest / .7).clamp(0.0, 1.0));
      if (glow > 0) {
        canvas.drawLine(
          start,
          end,
          Paint()
            ..shader = tail(.5 * glow)
            ..strokeWidth = cell * .3
            ..strokeCap = StrokeCap.round,
        );
      }
      final ring = (rest / .3).clamp(0.0, 1.0);
      if (ring < 1) {
        canvas.drawCircle(
          end,
          cell * (.34 + .36 * Curves.easeOutCubic.transform(ring)),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.5, cell * .05 * (1 - ring))
            ..color = color.withValues(alpha: .6 * (1 - ring)),
        );
      }
    }
    BlockArt.block(canvas, at, cell, colors, goal: false);
  }

  @override
  bool shouldRepaint(_TrailPreviewPainter oldDelegate) =>
      oldDelegate.trailId != trailId || oldDelegate.colors != colors;
}
