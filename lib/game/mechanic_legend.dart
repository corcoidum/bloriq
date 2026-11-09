import 'dart:math' as math;

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
  const MechanicLegend({
    super.key,
    required this.items,
    this.compact = false,
    this.lines = 2,
  });
  final List<LegendItem> items;

  /// [compact]일 때 설명에 쓸 수 있는 줄 수.
  final int lines;

  /// 공간이 모자랄 때 아이콘과 설명 한 칸으로 접는다.
  final bool compact;

  static const _iconSize = 32.0;
  static const _iconGap = 10.0;
  static const _rowPadding = 3.0;
  static const _chipSize = 48.0;
  static const _noteFontSize = 16.5;

  /// [notes]와 [mechanics]에서 나올 수 있는 가장 긴 설명이 들어가는 높이.
  /// [mechanics]의 항목 하나는 그 기믹이 상황에 따라 보여 주는 문구들이다.
  static double slotHeight(
    BuildContext context, {
    required double width,
    required bool compact,
    int lines = 2,
    required List<String> notes,
    required List<List<String>> mechanics,
  }) {
    double measure(String text, double fontSize, double room, int? maxLines) {
      final painter = TextPainter(
        text: TextSpan(
          text: keepAll(text),
          style: GameTypography.body.copyWith(fontSize: fontSize),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
        ellipsis: maxLines == null ? null : '…',
      )..layout(maxWidth: math.max(1.0, room));
      final height = painter.height.ceilToDouble();
      painter.dispose();
      return height;
    }

    final bodySize = GameTypography.body.fontSize!;
    var tallestNote = 0.0;
    for (final note in notes) {
      tallestNote = math.max(
        tallestNote,
        measure(note, _noteFontSize, width, compact ? lines : null),
      );
    }
    if (compact) {
      final room = mechanics.length > 1
          ? width - mechanics.length * _chipSize - _iconGap
          : width - _iconSize - _iconGap;
      var tallest = tallestNote;
      for (final texts in mechanics) {
        for (final text in texts) {
          tallest = math.max(tallest, measure(text, bodySize, room, lines));
        }
      }
      final icons = mechanics.length > 1
          ? _chipSize
          : mechanics.isEmpty
          ? 0.0
          : _iconSize;
      return math.max(icons, tallest);
    }
    var total = 0.0;
    for (final texts in mechanics) {
      var tallest = 0.0;
      for (final text in texts) {
        tallest = math.max(
          tallest,
          measure(text, bodySize, width - _iconSize - _iconGap, null),
        );
      }
      total += math.max(_iconSize, tallest) + _rowPadding * 2;
    }
    return math.max(tallestNote, total);
  }

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
    if (compact) return _CompactLegend(items: items, lines: lines);
    final colors = GameTheme.colorsOf(context);
    final style = GameTypography.body.copyWith(color: colors.text);
    if (items.length == 1 && items.single.kind == LegendKind.note) {
      return KeepAllText(
        items.single.text,
        textAlign: TextAlign.center,
        style: style.copyWith(fontSize: _noteFontSize),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: _rowPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: _iconSize,
                  child: _icon(item.kind, colors),
                ),
                const SizedBox(width: _iconGap),
                Expanded(child: KeepAllText(item.text, style: style)),
              ],
            ),
          ),
      ],
    );
  }

  static Widget _icon(LegendKind kind, GameColors colors) {
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

/// 기믹 아이콘 한 줄과 설명 한 칸. 아이콘을 누르면 그 기믹의 설명으로 바뀐다.
class _CompactLegend extends StatefulWidget {
  const _CompactLegend({required this.items, required this.lines});
  final List<LegendItem> items;
  final int lines;

  @override
  State<_CompactLegend> createState() => _CompactLegendState();
}

class _CompactLegendState extends State<_CompactLegend> {
  LegendKind? _selected;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final items = widget.items;
    final style = GameTypography.body.copyWith(color: colors.text);
    if (items.length == 1 && items.single.kind == LegendKind.note) {
      return KeepAllText(
        items.single.text,
        textAlign: TextAlign.center,
        maxLines: widget.lines,
        style: style.copyWith(fontSize: MechanicLegend._noteFontSize),
      );
    }
    // 문이 있으면 지금 상태를 알려 주는 문구가 맨 뒤에 오므로 기본으로 보여 준다.
    final current =
        items.where((item) => item.kind == _selected).firstOrNull ?? items.last;
    return Row(
      children: [
        if (items.length == 1) ...[
          SizedBox.square(
            dimension: MechanicLegend._iconSize,
            child: MechanicLegend._icon(items.single.kind, colors),
          ),
          const SizedBox(width: MechanicLegend._iconGap),
        ] else ...[
          for (final item in items)
            Semantics(
              button: true,
              selected: item.kind == current.kind,
              label: item.text,
              child: ExcludeSemantics(
                child: InkResponse(
                  key: ValueKey('legend-${item.kind.name}'),
                  radius: 24,
                  onTap: () => setState(() => _selected = item.kind),
                  child: SizedBox.square(
                    dimension: MechanicLegend._chipSize,
                    child: Center(
                      child: Opacity(
                        opacity: item.kind == current.kind ? 1 : .55,
                        child: SizedBox.square(
                          dimension: MechanicLegend._iconSize,
                          child: MechanicLegend._icon(item.kind, colors),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: MechanicLegend._iconGap),
        ],
        Expanded(
          child: KeepAllText(
            current.text,
            maxLines: widget.lines,
            style: style,
          ),
        ),
      ],
    );
  }
}
