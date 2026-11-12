import 'package:flutter/material.dart';

import '../constellation/constellation_atlas.dart';
import '../constellation/constellation_catalog.dart';
import '../constellation/constellation_painter.dart';
import '../constellation/constellation_state.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../world/world_catalog.dart';
import '../world/world_shelf.dart';
import '../world/world_text.dart';
import 'game_session.dart';

typedef _Stage = ({int id, int number, int stars, bool lit, bool unlocked});

class _Chapter {
  const _Chapter(this.definition, this.name, this.status, this.stages);

  final ConstellationDefinition definition;
  final String name, status;
  final List<_Stage> stages;

  bool get complete => stages.every((stage) => stage.lit);
  bool get golden => stages.every((stage) => stage.stars == 3);
  bool get unlocked => stages.any((stage) => stage.unlocked);
  int get stars => stages.fold(0, (total, stage) => total + stage.stars);
}

/// 한 세계 안에서는 장을 바로 고르고, 판을 고른 뒤 플레이를 시작한다.
class JourneyConstellations extends StatefulWidget {
  const JourneyConstellations({
    super.key,
    required this.session,
    required this.initialWorld,
    required this.initialLevelId,
    required this.onPlay,
  });

  final GameSession session;
  final int initialWorld;
  final int? initialLevelId;
  final ValueChanged<int>? onPlay;

  @override
  State<JourneyConstellations> createState() => _JourneyConstellationsState();
}

class _JourneyConstellationsState extends State<JourneyConstellations>
    with AutomaticKeepAliveClientMixin<JourneyConstellations> {
  late int _world = widget.initialWorld;
  late int? _levelId = widget.initialLevelId;
  int? _chapterIndex;

  @override
  bool get wantKeepAlive => true;

  List<_Chapter> _chapters(AppLocalizations t, ConstellationAtlas worldOne) {
    if (_world == 1) {
      return [
        for (final chapter in worldOne.chapters)
          _Chapter(
            chapter.definition,
            chapter.definition.name(t),
            constellationStatus(t, chapter),
            [
              for (final level in chapter.levels)
                (
                  id: level.id,
                  number: level.id,
                  stars: chapter.bestStars[level.id] ?? 0,
                  lit: chapter.isLit(level.id),
                  unlocked: true,
                ),
            ],
          ),
      ];
    }

    final atlas = widget.session.worldAtlas(_world);
    return [
      for (final chapter in atlas?.chapters ?? const [])
        _Chapter(
          chapter.definition,
          chapter.chapter.constellation.inLocale(t.localeName),
          chapter.unlocked
              ? worldChapterStatus(t, chapter)
              : t.journeyWorldLocked,
          [
            for (final stage in chapter.stages)
              (
                id: stage.level.id,
                number: Worlds.stageNumber(stage.level.id),
                stars: stage.stars,
                lit: stage.cleared,
                unlocked: stage.unlocked,
              ),
          ],
        ),
    ];
  }

  Widget _choices(List<Widget> choices) => LayoutBuilder(
    builder: (context, area) {
      final scaled = MediaQuery.textScalerOf(context).scale(32);
      const gap = 6.0;
      final minWidth = scaled < 44 ? 44.0 : scaled;
      final columns = ((area.maxWidth + gap) / (minWidth + gap)).floor().clamp(
        1,
        choices.length,
      );
      final width = (area.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final child in choices) SizedBox(width: width, child: child),
        ],
      );
    },
  );

  Widget _choice({
    required Key key,
    required bool selected,
    required Widget child,
    required VoidCallback? onPressed,
    String? label,
  }) {
    final colors = GameTheme.colorsOf(context);
    return Semantics(
      selected: selected,
      label: label,
      child: OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 46),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          backgroundColor: selected
              ? colors.reward.withValues(alpha: .12)
              : colors.surface,
          foregroundColor: selected ? colors.rewardInk : colors.text,
          side: BorderSide(
            color: selected
                ? colors.reward
                : colors.outline.withValues(alpha: .35),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: onPressed,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = widget.session;
    final worldOne = ConstellationAtlas.derive(
      session.levels,
      session.progress,
    );
    final chapters = _chapters(t, worldOne);
    final worldChapters = [
      for (final world in session.worlds.keys)
        ...?session.worldAtlas(world)?.chapters,
    ];
    final restored =
        worldOne.chapters.where((chapter) => chapter.complete).length +
        worldChapters.where((chapter) => chapter.complete).length;
    final total = worldOne.chapters.length + worldChapters.length;
    final preferred = chapters.indexWhere(
      (chapter) => chapter.stages.any((stage) => stage.id == _levelId),
    );
    final next = chapters.indexWhere(
      (chapter) => chapter.unlocked && !chapter.complete,
    );
    final index =
        _chapterIndex ??
        (preferred >= 0
            ? preferred
            : next >= 0
            ? next
            : 0);
    final chapter = chapters.isEmpty ? null : chapters[index];
    final stages = chapter?.stages ?? const <_Stage>[];
    final selected =
        stages
            .where((stage) => stage.unlocked && stage.id == _levelId)
            .firstOrNull ??
        stages.where((stage) => stage.unlocked && !stage.lit).firstOrNull ??
        stages.where((stage) => stage.unlocked).firstOrNull;
    final stageIndex = selected == null ? null : stages.indexOf(selected);
    final onPlay = widget.onPlay;

    return ListView(
      key: const PageStorageKey('journey-constellation-list'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      children: [
        Text(
          t.journeyRestoredTotal(restored, total),
          key: const ValueKey('journey-constellation-total'),
          style: GameTypography.reward.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 8),
        WorldPicker(
          key: const ValueKey('journey-constellation-world'),
          session: session,
          selected: _world,
          onSelected: (world) => setState(() {
            if (world == _world) return;
            _world = world;
            _chapterIndex = null;
            _levelId = null;
          }),
        ),
        if (chapter != null) ...[
          const SizedBox(height: 8),
          _choices([
            for (final (slot, item) in chapters.indexed)
              _choice(
                key: ValueKey('journey-chapter-${slot + 1}'),
                selected: slot == index,
                label: item.name,
                onPressed: () => setState(() {
                  _chapterIndex = slot;
                  _levelId = null;
                }),
                child: Text(
                  t.journeyChapter(slot + 1),
                  textAlign: TextAlign.center,
                ),
              ),
          ]),
          const SizedBox(height: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.outline.withValues(alpha: .35)),
              gradient: RadialGradient(
                center: const Alignment(0, .25),
                radius: .9,
                colors: [
                  Color.alphaBlend(
                    colors.primary.withValues(alpha: .13),
                    colors.surface,
                  ),
                  colors.background,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  Text(
                    chapter.name,
                    textAlign: TextAlign.center,
                    style: GameTypography.reward.copyWith(fontSize: 24),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${chapter.status} · ${t.journeyStarCount(chapter.stars, stages.length * 3)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.secondaryText),
                    ),
                  ),
                  Semantics(
                    image: true,
                    label: t.constellationSummary(
                      chapter.name,
                      stages.where((stage) => stage.lit).length,
                      stages.length,
                      chapter.stars,
                      stages.length * 3,
                      chapter.status,
                    ),
                    child: SizedBox(
                      height: 170,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: ConstellationPainter(
                          definition: chapter.definition,
                          lit: [for (final stage in stages) stage.lit],
                          colors: colors,
                          golden: chapter.golden ? 1 : 0,
                          highlightNode: stageIndex,
                          chart: true,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _choices([
            for (final stage in stages)
              _choice(
                key: ValueKey('journey-stage-${stage.id}'),
                selected: selected == stage,
                label: stage.lit
                    ? t.constellationLevelStars(stage.number, stage.stars)
                    : t.constellationLevelDark(stage.number),
                onPressed: stage.unlocked
                    ? () => setState(() => _levelId = stage.id)
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${stage.number}', style: GameTypography.label),
                    Text(
                      '${stage.stars} / 3',
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ]),
          if (!chapter.unlocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(WorldText.chapterLocked.resolve(t.localeName)),
            ),
          if (selected != null && onPlay != null) ...[
            const SizedBox(height: 10),
            FilledButton(
              key: const ValueKey('journey-play-stage'),
              style: FilledButton.styleFrom(minimumSize: const Size(44, 50)),
              onPressed: () => onPlay(selected.id),
              child: Text(
                selected.lit
                    ? t.journeyReplayStage(selected.number)
                    : t.journeyPlayStage(selected.number),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
