import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../design/star_art.dart';

/// 판 아래 설명 한 줄의 종류. 보드 그림과 같은 아이콘을 쓴다.
enum LegendKind { eraser, hold, oneWay, goalOnly, gate, note }

class LegendItem {
  const LegendItem(this.kind, this.text);
  final LegendKind kind;
  final String text;
}

/// 현재 스테이지의 기믹을 아이콘과 한 줄 설명으로 보여준다.
class MechanicLegend extends StatelessWidget {
  const MechanicLegend({super.key, required this.items});
  final List<LegendItem> items;

  static const _sprites = {
    LegendKind.eraser: 'tile_dandelion',
    LegendKind.hold: 'tile_amber',
    LegendKind.oneWay: 'tile_stream',
    LegendKind.goalOnly: 'tile_clover',
    LegendKind.gate: 'switch_crystal',
  };

  static const _fallbackIcons = {
    LegendKind.eraser: Icons.close_rounded,
    LegendKind.hold: Icons.pause_rounded,
    LegendKind.oneWay: Icons.arrow_forward_rounded,
    LegendKind.goalOnly: Icons.play_arrow_rounded,
    LegendKind.gate: Icons.diamond_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final style = GameTypography.body.copyWith(color: colors.text);
    if (items.length == 1 && items.single.kind == LegendKind.note) {
      return KeepAllText(
        items.single.text,
        textAlign: TextAlign.center,
        style: style.copyWith(fontSize: 16.5),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox.square(dimension: 32, child: _icon(item.kind, colors)),
                const SizedBox(width: 10),
                Expanded(child: KeepAllText(item.text, style: style)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _icon(LegendKind kind, GameColors colors) {
    final image = StarArt.garden[_sprites[kind]];
    if (image == null) {
      return Icon(
        _fallbackIcons[kind] ?? Icons.auto_awesome,
        size: 22,
        color: colors.echoInk,
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(9),
      ),
      padding: const EdgeInsets.all(2),
      child: RawImage(image: image, fit: BoxFit.contain),
    );
  }
}
