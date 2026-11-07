import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../world2/world2_catalog.dart';
import '../world2/world2_progress.dart';

/// 월드 2 보드 위의 작은 권능 막대. 권능을 고른 뒤 블록을 밀면 그 권능으로
/// 움직인다. 한 스테이지에 한 번씩이며, 다시 누르면 선택을 취소한다.
class PowerBar extends StatelessWidget {
  const PowerBar({
    super.key,
    required this.owned,
    this.stage,
    required this.remaining,
    required this.armed,
    required this.enabled,
    required this.onToggle,
  });

  /// 성장 기록에서 가져온, 플레이어가 가진 권능.
  final Set<PuzzlePower> owned;

  /// 이 스테이지가 여는 권능. null 이면 네 권능을 모두 보여 준다.
  final Set<PuzzlePower>? stage;

  /// 이번 시도에서 아직 쓰지 않은 권능.
  final Set<PuzzlePower> remaining;
  final PuzzlePower? armed;
  final bool enabled;
  final ValueChanged<PuzzlePower> onToggle;

  static IconData iconFor(PuzzlePower power) => switch (power) {
    PuzzlePower.moonflowerLeap => Icons.filter_vintage_rounded,
    PuzzlePower.lightSwap => Icons.swap_horiz_rounded,
    PuzzlePower.seal => Icons.lock_clock_rounded,
    PuzzlePower.wind => Icons.air_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final power in World2.boardPowers)
          if (stage?.contains(power) ?? true)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _PowerChip(
                  power: power,
                  label: powerDefinition(power)?.name.resolve(lang) ?? power.id,
                  hint: powerDefinition(power)?.description.resolve(lang) ?? '',
                  owned: owned.contains(power),
                  available:
                      enabled &&
                      owned.contains(power) &&
                      remaining.contains(power),
                  spent: owned.contains(power) && !remaining.contains(power),
                  armed: armed == power,
                  colors: colors,
                  onTap: () => onToggle(power),
                ),
              ),
            ),
      ],
    );
  }
}

class _PowerChip extends StatelessWidget {
  const _PowerChip({
    required this.power,
    required this.label,
    required this.hint,
    required this.owned,
    required this.available,
    required this.spent,
    required this.armed,
    required this.colors,
    required this.onTap,
  });
  final PuzzlePower power;
  final String label, hint;
  final bool owned, available, spent, armed;
  final GameColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = armed
        ? colors.surface
        : available
        ? colors.rewardInk
        : colors.secondaryText;
    final fill = armed
        ? colors.reward
        : colors.reward.withValues(alpha: available ? .14 : .05);
    return Semantics(
      button: true,
      selected: armed,
      enabled: available,
      label: label,
      hint: hint,
      child: Tooltip(
        message: hint,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: colors.reward.withValues(alpha: available ? .6 : .2),
            ),
          ),
          child: InkWell(
            key: ValueKey('power-${power.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: available ? onTap : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      owned ? PowerBar.iconFor(power) : Icons.lock_rounded,
                      size: 18,
                      color: ink,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GameTypography.label.copyWith(
                          fontSize: 12,
                          color: ink,
                          decoration: spent ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
