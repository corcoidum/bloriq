import 'package:flutter/material.dart';

import '../constellation/star_sky.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../world/world_text.dart';
import 'game_session.dart';

abstract final class StarSkyText {
  static const overview = ProgressionText('하늘 전체 보기', 'See the whole sky');
  static const hint = ProgressionText(
    '별을 눌러 판을 골라요',
    'Tap a star to pick a stage',
  );
  static ProgressionText world(int number, String title) =>
      ProgressionText('세계 $number · $title', 'World $number · $title');
}

/// 일곱 세계의 별자리를 한 장의 별하늘로 보여 준다.
/// 별을 눌러 판을 고르고 아래 칸에서 플레이를 시작한다.
class JourneyConstellations extends StatefulWidget {
  const JourneyConstellations({
    super.key,
    required this.session,
    required this.initialWorld,
    required this.initialLevelId,
    required this.onPlay,
    this.reduceMotion = false,
  });

  final GameSession session;
  final int initialWorld;
  final int? initialLevelId;
  final ValueChanged<int>? onPlay;
  final bool reduceMotion;

  @override
  State<JourneyConstellations> createState() => _JourneyConstellationsState();
}

class _JourneyConstellationsState extends State<JourneyConstellations>
    with AutomaticKeepAliveClientMixin<JourneyConstellations> {
  final _sky = GlobalKey<StarSkyState>();
  late int? _levelId = widget.initialLevelId;

  /// 고른 별자리의 순서. null이면 고른 판이나 처음 세계에서 정한다.
  int? _focusIndex;

  @override
  bool get wantKeepAlive => true;

  SkyConstellation? _focus(StarSkyData data) =>
      (_focusIndex == null
          ? null
          : data.constellations
                .where((item) => item.index == _focusIndex)
                .firstOrNull) ??
      data.forLevel(_levelId) ??
      data.entryOf(widget.initialWorld) ??
      data.constellations.firstOrNull;

  void _visit(StarSkyData data, int world) {
    final entry = data.entryOf(world);
    if (entry == null) return;
    setState(() {
      _focusIndex = entry.index;
      _levelId = entry.next?.levelId;
    });
    // 같은 별자리를 다시 골라도 그쪽으로 돌아간다.
    _sky.currentState?.lookAt(entry.center);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final data = StarSkyData.of(widget.session, t, colors);
    final focus = _focus(data);
    final selected =
        focus?.stars
            .where((star) => star.unlocked && star.levelId == _levelId)
            .firstOrNull ??
        focus?.next;
    final onPlay = widget.onPlay;

    Widget worldChip(SkyWorld world, double width) {
      final here = world.number == focus?.world;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Semantics(
          selected: here,
          label: StarSkyText.world(world.number, world.title).resolve(lang),
          excludeSemantics: true,
          child: OutlinedButton(
            key: ValueKey('journey-sky-world-${world.number}'),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(width, 46),
              maximumSize: Size(width, 46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              backgroundColor: here
                  ? colors.reward.withValues(alpha: .14)
                  : colors.surface,
              foregroundColor: here
                  ? colors.rewardInk
                  : world.unlocked
                  ? colors.text
                  : colors.secondaryText,
              side: BorderSide(
                color: here
                    ? colors.reward
                    : colors.outline.withValues(alpha: .35),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(23),
              ),
            ),
            onPressed: () => _visit(data, world.number),
            // 큰 글자에서도 칸을 넘지 않게 줄여 넣는다.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!world.unlocked)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.lock_outline_rounded, size: 15),
                    ),
                  Text('${world.number}', style: GameTypography.label),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.journeyRestoredTotal(data.restored, data.total),
              key: const ValueKey('journey-constellation-total'),
              style: GameTypography.reward.copyWith(fontSize: 20),
            ),
          ),
          IconButton(
            key: const ValueKey('journey-sky-overview'),
            tooltip: StarSkyText.overview.resolve(lang),
            onPressed: () => _sky.currentState?.overview(),
            icon: const Icon(Icons.zoom_out_map_rounded),
          ),
        ],
      ),
    );

    // 일곱 세계가 한 줄에 다 보이게 너비를 나눈다. 아주 좁으면 옆으로 민다.
    final worlds = SizedBox(
      height: 46,
      child: LayoutBuilder(
        builder: (context, area) {
          const side = 12.0, gap = 4.0;
          final count = data.worlds.length;
          final shared = count == 0
              ? 44.0
              : (area.maxWidth - side * 2) / count - gap;
          final width = shared < 38 ? 44.0 : shared;
          return SingleChildScrollView(
            key: const ValueKey('journey-sky-worlds'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: side),
            child: Row(
              children: [
                for (final world in data.worlds) worldChip(world, width),
              ],
            ),
          );
        },
      ),
    );

    final sky = Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: StarSky(
        key: _sky,
        data: data,
        focus: focus,
        selectedLevelId: selected?.levelId,
        reduceMotion: widget.reduceMotion,
        starLabel: (star) => star.lit
            ? t.constellationLevelStars(star.number, star.stars)
            : t.constellationLevelDark(star.number),
        onStar: (star) => setState(() {
          _levelId = star.levelId;
          _focusIndex = data.forLevel(star.levelId)?.index;
        }),
      ),
    );

    final panel = focus == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Semantics(
              container: true,
              label: t.constellationSummary(
                focus.name,
                focus.litCount,
                focus.stars.length,
                focus.starCount,
                focus.stars.length * 3,
                focus.status,
              ),
              child: Column(
                key: const ValueKey('journey-sky-panel'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    focus.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GameTypography.reward.copyWith(
                      fontSize: 22,
                      color: focus.golden ? colors.rewardInk : colors.text,
                    ),
                  ),
                  Text(
                    '${focus.status} · ${t.journeyStarCount(focus.starCount, focus.stars.length * 3)}',
                    textAlign: TextAlign.center,
                    style: GameTypography.body.copyWith(
                      color: colors.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (selected != null && onPlay != null)
                    FilledButton(
                      key: const ValueKey('journey-play-stage'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(44, 50),
                      ),
                      onPressed: () => onPlay(selected.levelId),
                      child: Text(
                        selected.lit
                            ? t.journeyReplayStage(selected.number)
                            : t.journeyPlayStage(selected.number),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else if (!focus.unlocked)
                    KeepAllText(
                      WorldText.chapterLocked.resolve(lang),
                      textAlign: TextAlign.center,
                      style: GameTypography.body.copyWith(
                        color: colors.secondaryText,
                      ),
                    )
                  else
                    KeepAllText(
                      StarSkyText.hint.resolve(lang),
                      textAlign: TextAlign.center,
                      style: GameTypography.body.copyWith(
                        color: colors.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          );

    return LayoutBuilder(
      builder: (context, area) {
        // 아주 낮은 화면이나 큰 글자에서는 하늘 높이를 지키고 전체를 스크롤한다.
        final roomy =
            area.maxHeight >= 430 &&
            MediaQuery.textScalerOf(context).scale(10) <= 14;
        final content = roomy
            ? Column(
                children: [
                  header,
                  worlds,
                  Expanded(child: sky),
                  panel,
                ],
              )
            : ListView(
                key: const PageStorageKey('journey-constellation-list'),
                primary: false,
                // 하늘 안에서 끄는 손짓은 하늘을 움직이므로, 시작 버튼을 하늘 위에 둔다.
                children: [
                  header,
                  worlds,
                  panel,
                  SizedBox(height: 300, child: sky),
                ],
              );
        // 오른쪽에 있는 별이나 버튼에 초점이 가면(화면 읽기, 키보드) 바깥의 탭 화면이
        // 그 요소를 왼쪽 끝으로 끌어오려다 옆 탭으로 넘어간다. 움직이지 않는 가로
        // 스크롤로 감싸면 바깥은 이 칸 전체만 보이게 하므로 탭이 넘어가지 않는다.
        return SingleChildScrollView(
          key: const ValueKey('journey-sky-guard'),
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: SizedBox(
            width: area.maxWidth,
            height: area.maxHeight,
            child: content,
          ),
        );
      },
    );
  }
}
