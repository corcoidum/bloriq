import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import 'world_progress.dart';

/// 도감 위쪽의 세계 고르기. 열린 세계만 보여 주고, 고른 세계를 알려 준다.
/// 세계가 하나뿐이거나 사가를 읽지 못했으면 아무것도 그리지 않는다.
class WorldChips extends StatefulWidget {
  const WorldChips({
    super.key,
    required this.session,
    required this.selected,
    required this.onSelected,
  });
  final GameSession session;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  State<WorldChips> createState() => _WorldChipsState();
}

class _WorldChipsState extends State<WorldChips> {
  final _selectedKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 뒤쪽 세계가 골라진 채 열리면 그 칩이 보이도록 옆으로 넘겨 둔다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chip = _selectedKey.currentContext;
      if (chip != null) Scrollable.ensureVisible(chip, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    final saga = widget.session.saga;
    final open = widget.session.openWorlds;
    if (saga == null || open.length < 2) return const SizedBox.shrink();
    final lang = AppLocalizations.of(context)!.localeName;
    final colors = GameTheme.colorsOf(context);
    return SingleChildScrollView(
      key: const ValueKey('world-chips'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          for (final world in open) ...[
            if (world != open.first) const SizedBox(width: 6),
            KeyedSubtree(
              key: world == widget.selected ? _selectedKey : null,
              child: ChoiceChip(
                key: ValueKey('world-chip-$world'),
                label: Text(saga.world(world).title.inLocale(lang)),
                selected: world == widget.selected,
                selectedColor: colors.reward.withValues(alpha: .25),
                onSelected: (_) => widget.onSelected(world),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 확장 세계 장의 별자리 상태 문구. 세계 1의 `constellationStatus`와 같은 말을 쓴다.
String worldChapterStatus(AppLocalizations t, WorldChapterView chapter) =>
    chapter.golden
    ? t.constellationGolden
    : chapter.complete
    ? t.constellationRestored
    : t.constellationDormant;

/// 장에서 모은 별 수.
int worldChapterStars(WorldChapterView chapter) =>
    chapter.stages.fold(0, (sum, stage) => sum + stage.stars);
