import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import 'bloriq_game.dart';
import 'device_art.dart';

/// 이번 판의 장치 칩. 긴 규칙 문장 대신 그림을 보여 주고, 누르면 한 줄 설명이 나온다.
class DeviceLegend extends StatelessWidget {
  const DeviceLegend({
    super.key,
    required this.level,
    required this.selected,
    required this.onSelect,
  });
  final Level level;
  final DeviceKind? selected;
  final ValueChanged<DeviceKind> onSelect;

  static String name(AppLocalizations t, DeviceKind kind) => switch (kind) {
    DeviceKind.gate => t.deviceGate,
    DeviceKind.moonbloom => t.deviceMoonbloom,
    DeviceKind.eraser => t.deviceEraser,
    DeviceKind.hold => t.deviceHold,
    DeviceKind.oneWay => t.deviceOneWay,
    DeviceKind.goalOnly => t.deviceGoalOnly,
    DeviceKind.wall => '',
  };

  static String rule(AppLocalizations t, DeviceKind kind) => switch (kind) {
    DeviceKind.gate || DeviceKind.moonbloom => t.gateInstruction,
    DeviceKind.eraser => t.eraserRule,
    DeviceKind.hold => t.holdRule,
    DeviceKind.oneWay => t.oneWayRule,
    DeviceKind.goalOnly => t.goalOnlyRule,
    DeviceKind.wall => '',
  };

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final kinds = deviceTiles(level).map((tile) => tile.$2).toSet().toList();
    if (kinds.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: GameSpacing.small),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: GameSpacing.small,
        runSpacing: GameSpacing.small,
        children: [
          for (final kind in kinds)
            Semantics(
              button: true,
              selected: selected == kind,
              label: '${name(t, kind)}. ${rule(t, kind)}',
              excludeSemantics: true,
              child: InkWell(
                key: ValueKey('device-${kind.name}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelect(kind),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: GameSpacing.small,
                    vertical: GameSpacing.tiny,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(
                      alpha: selected == kind ? .95 : .55,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected == kind
                          ? colors.reward
                          : colors.outline.withValues(alpha: .4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DeviceIcon(kind: kind),
                      // 장치가 많으면 아이콘만 두어 보드 아래를 한 줄로 유지한다.
                      if (kinds.length <= 2) ...[
                        const SizedBox(width: GameSpacing.tiny),
                        Flexible(
                          child: Text(
                            name(t, kind),
                            style: GameTypography.label.copyWith(fontSize: 13),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
