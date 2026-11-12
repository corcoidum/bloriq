import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../settings/game_settings.dart';
import '../world/world_catalog.dart';
import '../world/world_progress.dart';
import '../world/world_shelf.dart';
import '../world/world_text.dart';
import 'constellation_painter.dart';
import 'constellation_state.dart';

/// 별자리 한 장. 완성된 별자리에는 별점과 수호 정령의 초상을 나란히 보여 준다.
class ConstellationArt extends StatefulWidget {
  const ConstellationArt({
    super.key,
    required this.chapter,
    required this.guardianAsset,
    this.pendingNode,
    this.highlightNode,
    this.nodeReveal = 1,
    this.spark,
    this.lineReveal = 1,
    this.portraitReveal = 1,
    this.golden,
    this.lit,
  });

  final ChapterConstellation chapter;
  final String? guardianAsset;
  final int? pendingNode;
  final int? highlightNode;
  final double nodeReveal;
  final double? spark;
  final double lineReveal;
  final double portraitReveal;

  /// 연출 중에는 저장된 상태 대신 보여 줄 값을 덮어쓴다.
  final double? golden;
  final List<bool>? lit;

  @override
  State<ConstellationArt> createState() => _ConstellationArtState();
}

class _ConstellationArtState extends State<ConstellationArt> {
  @override
  void initState() {
    super.initState();
    _loadPortrait();
  }

  @override
  void didUpdateWidget(covariant ConstellationArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guardianAsset != widget.guardianAsset) _loadPortrait();
  }

  void _loadPortrait() {
    final asset = widget.guardianAsset;
    if (asset == null || StarArt.portraits.containsKey(asset)) return;
    // 초상을 못 읽어도 별과 선은 그린다.
    StarArt.loadPortrait(asset).then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final lit = widget.lit ?? chapter.litMask;
    final complete = lit.every((value) => value);
    final colors = GameTheme.colorsOf(context);
    final portrait = complete ? StarArt.portraits[widget.guardianAsset] : null;
    final goldenGlow = widget.golden ?? (chapter.golden ? 1.0 : 0.0);
    final chart = CustomPaint(
      painter: ConstellationPainter(
        definition: chapter.definition,
        lit: lit,
        colors: colors,
        golden: goldenGlow,
        pendingNode: widget.pendingNode,
        highlightNode: widget.highlightNode,
        nodeReveal: widget.nodeReveal,
        spark: widget.spark,
        lineReveal: widget.lineReveal,
      ),
      child: const SizedBox.expand(),
    );
    return RepaintBoundary(
      child: portrait == null
          ? chart
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 56,
                  child: Opacity(
                    opacity: widget.portraitReveal.clamp(0.0, 1.0),
                    child: DecoratedBox(
                      // 황금 별자리의 수호 정령은 금빛 후광을 두른다.
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: goldenGlow > 0
                              ? [
                                  colors.reward.withValues(
                                    alpha: .6 * goldenGlow,
                                  ),
                                  colors.reward.withValues(
                                    alpha: .2 * goldenGlow,
                                  ),
                                  colors.reward.withValues(alpha: 0),
                                ]
                              : [
                                  colors.primary.withValues(alpha: .14),
                                  colors.primary.withValues(alpha: 0),
                                ],
                        ),
                      ),
                      child: RawImage(
                        key: const ValueKey('constellation-guardian-portrait'),
                        image: portrait,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 44,
                  child: Center(
                    child: AspectRatio(aspectRatio: 1.1, child: chart),
                  ),
                ),
              ],
            ),
    );
  }
}

String? guardianAssetFor(GameSession session, ChapterConstellation chapter) =>
    session.story.forLevel(chapter.levels.last.id)?.asset;

String constellationStatus(AppLocalizations t, ChapterConstellation chapter) =>
    chapter.golden
    ? t.constellationGolden
    : chapter.complete
    ? t.constellationRestored
    : t.constellationDormant;

String constellationSummary(AppLocalizations t, ChapterConstellation chapter) =>
    t.constellationSummary(
      chapter.definition.name(t),
      chapter.litCount,
      chapter.levels.length,
      chapter.stars,
      chapter.maxStars,
      constellationStatus(t, chapter),
    );

/// 고른 별문의 id를 돌려준다. 닫으면 null.
/// [allWorlds]이면 열린 세계를 모두 다루고, 지금 진행 중인 세계부터 보여 준다.
/// 게임 화면처럼 한 세계 안에서 여는 곳은 세계 1 도감만 쓴다.
Future<int?> showConstellationAtlas(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  int? initialChapter,
  bool allWorlds = false,
}) => showDialog<int>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => ConstellationAtlasDialog(
    session: session,
    initialChapter: initialChapter,
    allWorlds: allWorlds,
  ),
);

class ConstellationAtlasDialog extends StatefulWidget {
  const ConstellationAtlasDialog({
    super.key,
    required this.session,
    this.initialChapter,
    this.allWorlds = false,
  });
  final GameSession session;
  final int? initialChapter;
  final bool allWorlds;

  @override
  State<ConstellationAtlasDialog> createState() =>
      _ConstellationAtlasDialogState();
}

class _ConstellationAtlasDialogState extends State<ConstellationAtlasDialog> {
  /// 고른 장. 세계 1은 장 번호(1..5), 확장 세계는 세계 안의 장 번호(1..5).
  late int? _selected = widget.initialChapter;
  late int _world = widget.allWorlds && widget.initialChapter == null
      ? widget.session.continueTarget.world
      : 1;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = widget.session;
    final worldAtlas = _world == 1 ? null : session.worldAtlas(_world);
    final String? title;
    final Widget body;
    if (worldAtlas == null) {
      final atlas = ConstellationAtlas.derive(session.levels, session.progress);
      final selected = _selected == null ? null : atlas.forChapter(_selected!);
      title = selected?.definition.name(t);
      body = selected == null
          ? _overview(context, atlas)
          : _detail(context, selected);
    } else {
      final selected = _selected == null
          ? null
          : worldAtlas.chapters[_selected! - 1];
      title = selected?.chapter.constellation.inLocale(t.localeName);
      body = selected == null
          ? _worldOverview(context, worldAtlas)
          : _worldDetail(context, selected);
    }
    return AlertDialog(
      key: const ValueKey('constellation-atlas'),
      icon: Icon(Icons.auto_awesome, color: colors.rewardInk),
      title: Text(title ?? t.constellationAtlas),
      content: SizedBox(
        width: 460,
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            if (widget.allWorlds && _selected == null)
              WorldChips(
                session: session,
                selected: _world,
                onSelected: (world) => setState(() => _world = world),
              ),
            Expanded(child: body),
          ],
        ),
      ),
      actions: [
        if (_selected != null)
          TextButton.icon(
            key: const ValueKey('atlas-back'),
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.arrow_back_rounded),
            label: Text(t.constellationBack),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    );
  }

  Widget _worldArt(BuildContext context, WorldChapterView chapter) =>
      CustomPaint(
        size: Size.infinite,
        painter: ConstellationPainter(
          definition: chapter.definition,
          lit: chapter.lit,
          colors: GameTheme.colorsOf(context),
          golden: chapter.golden ? 1 : 0,
        ),
      );

  Widget _worldStatus(BuildContext context, WorldChapterView chapter) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final (icon, color) = chapter.golden
        ? (Icons.workspace_premium_rounded, colors.rewardInk)
        : chapter.complete
        ? (Icons.auto_awesome, colors.goalInk)
        : (Icons.bedtime_outlined, colors.secondaryText);
    return StatPill(
      icon: icon,
      label: worldChapterStatus(t, chapter),
      color: color,
    );
  }

  /// 확장 세계의 다섯 별자리. 잠긴 장은 여는 조건만 보여 준다.
  Widget _worldOverview(BuildContext context, WorldAtlas atlas) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    return ListView.separated(
      key: ValueKey('atlas-list-world-${atlas.world}'),
      itemCount: atlas.chapters.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: GameSpacing.medium),
      itemBuilder: (context, index) {
        if (index == 0) {
          return GoldenConstellationBenefit(session: widget.session);
        }
        final chapter = atlas.chapters[index - 1];
        final info = chapter.chapter;
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.constellation.inLocale(lang),
              style: TextStyle(
                fontFamily: GameTypography.canvasFontFamily,
                fontSize: 20,
                color: colors.rewardInk,
              ),
            ),
            Text(
              info.name.inLocale(lang),
              style: TextStyle(color: colors.secondaryText),
            ),
            const SizedBox(height: GameSpacing.tiny),
            if (!chapter.unlocked)
              Text(WorldText.lockedStage.resolve(lang))
            else ...[
              Text(t.constellationLit(chapter.cleared, chapter.stages.length)),
              Text(
                t.constellationBestStars(
                  worldChapterStars(chapter),
                  chapter.stages.length * 3,
                ),
              ),
              const SizedBox(height: GameSpacing.tiny),
              _worldStatus(context, chapter),
            ],
          ],
        );
        final art = SizedBox(
          width: 104,
          height: 80,
          child: _worldArt(context, chapter),
        );
        return InkWell(
          key: ValueKey('atlas-chapter-${info.globalChapter}'),
          borderRadius: BorderRadius.circular(GameSpacing.radius),
          onTap: chapter.unlocked
              ? () => setState(() => _selected = info.number)
              : null,
          child: ArcadeSurface(
            padding: const EdgeInsets.all(GameSpacing.medium),
            accent: chapter.golden
                ? colors.reward
                : chapter.complete
                ? colors.goal
                : null,
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 300
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [art, text],
                    )
                  : Row(
                      children: [
                        art,
                        const SizedBox(width: GameSpacing.medium),
                        Expanded(child: text),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _worldDetail(BuildContext context, WorldChapterView chapter) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    return ListView(
      key: ValueKey('atlas-detail-${chapter.chapter.globalChapter}'),
      children: [
        AspectRatio(
          aspectRatio: 1.35,
          child: Semantics(
            image: true,
            label: chapter.chapter.constellation.inLocale(lang),
            value: '${chapter.cleared} / ${chapter.stages.length}',
            child: _worldArt(context, chapter),
          ),
        ),
        Center(child: _worldStatus(context, chapter)),
        const SizedBox(height: GameSpacing.small),
        Text(
          '${t.constellationLit(chapter.cleared, chapter.stages.length)} · '
          '${t.constellationBestStars(worldChapterStars(chapter), chapter.stages.length * 3)}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GameSpacing.medium),
        GoldenConstellationBenefit(session: widget.session),
        const SizedBox(height: GameSpacing.medium),
        for (final stage in chapter.stages)
          Padding(
            padding: const EdgeInsets.only(bottom: GameSpacing.small),
            child: Row(
              children: [
                Icon(
                  stage.cleared
                      ? Icons.star_rounded
                      : stage.unlocked
                      ? Icons.star_outline_rounded
                      : Icons.lock_rounded,
                  color: stage.cleared ? colors.rewardInk : colors.outline,
                ),
                const SizedBox(width: GameSpacing.small),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stage.cleared
                            ? t.constellationLevelStars(
                                Worlds.stageNumber(stage.level.id),
                                stage.stars,
                              )
                            : t.constellationLevelDark(
                                Worlds.stageNumber(stage.level.id),
                              ),
                      ),
                      if (stage.unlocked)
                        Text(
                          stage.cleared
                              ? '${stage.spirit.levelTitle.inLocale(lang)} · '
                                    '${stage.spirit.name.inLocale(lang)}'
                              : stage.spirit.levelTitle.inLocale(lang),
                          style: TextStyle(
                            color: colors.secondaryText,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  key: ValueKey('atlas-play-${stage.level.id}'),
                  onPressed: stage.unlocked
                      ? () => Navigator.pop(context, stage.level.id)
                      : null,
                  child: Text(t.constellationPlay),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _overview(BuildContext context, ConstellationAtlas atlas) {
    final t = AppLocalizations.of(context)!;
    return ListView.separated(
      key: const ValueKey('atlas-list'),
      itemCount: atlas.chapters.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: GameSpacing.medium),
      itemBuilder: (context, index) {
        if (index == 0) {
          return GoldenConstellationBenefit(session: widget.session);
        }
        final chapter = atlas.chapters[index - 1];
        return Semantics(
          button: true,
          label: constellationSummary(t, chapter),
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('atlas-chapter-${chapter.chapter}'),
            borderRadius: BorderRadius.circular(GameSpacing.radius),
            onTap: () => setState(() => _selected = chapter.chapter),
            child: ArcadeSurface(
              padding: const EdgeInsets.all(GameSpacing.medium),
              accent: chapter.golden
                  ? GameTheme.colorsOf(context).reward
                  : chapter.complete
                  ? GameTheme.colorsOf(context).goal
                  : null,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final art = SizedBox(
                    width: 104,
                    height: 80,
                    child: ConstellationArt(
                      chapter: chapter,
                      guardianAsset: guardianAssetFor(widget.session, chapter),
                    ),
                  );
                  final text = _cardText(context, chapter);
                  // 좁은 화면과 큰 글꼴에서는 그림과 글을 위아래로 쌓는다.
                  return constraints.maxWidth < 300
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [art, text],
                        )
                      : Row(
                          children: [
                            art,
                            const SizedBox(width: GameSpacing.medium),
                            Expanded(child: text),
                          ],
                        );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cardText(BuildContext context, ChapterConstellation chapter) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          chapter.definition.name(t),
          style: TextStyle(
            fontFamily: GameTypography.canvasFontFamily,
            fontSize: 20,
            color: colors.rewardInk,
          ),
        ),
        Text(
          widget.session.story
              .chapter(chapter.chapter)
              .name
              .inLocale(t.localeName),
          style: TextStyle(color: colors.secondaryText),
        ),
        const SizedBox(height: GameSpacing.tiny),
        Text(t.constellationLit(chapter.litCount, chapter.levels.length)),
        Text(t.constellationBestStars(chapter.stars, chapter.maxStars)),
        const SizedBox(height: GameSpacing.tiny),
        _StatusChip(chapter: chapter),
      ],
    );
  }

  Widget _detail(BuildContext context, ChapterConstellation chapter) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return ListView(
      key: ValueKey('atlas-detail-${chapter.chapter}'),
      children: [
        Semantics(
          image: true,
          label: constellationSummary(t, chapter),
          excludeSemantics: true,
          child: AspectRatio(
            aspectRatio: 1.35,
            child: ConstellationArt(
              chapter: chapter,
              guardianAsset: guardianAssetFor(widget.session, chapter),
            ),
          ),
        ),
        Center(child: _StatusChip(chapter: chapter)),
        const SizedBox(height: GameSpacing.small),
        Text(
          '${t.constellationLit(chapter.litCount, chapter.levels.length)} · '
          '${t.constellationBestStars(chapter.stars, chapter.maxStars)}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: GameSpacing.medium),
        GoldenConstellationBenefit(session: widget.session),
        const SizedBox(height: GameSpacing.medium),
        for (final level in chapter.levels)
          Padding(
            padding: const EdgeInsets.only(bottom: GameSpacing.small),
            child: Row(
              children: [
                Icon(
                  chapter.isLit(level.id)
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: chapter.isLit(level.id)
                      ? colors.rewardInk
                      : colors.outline,
                ),
                const SizedBox(width: GameSpacing.small),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chapter.isLit(level.id)
                            ? t.constellationLevelStars(
                                level.id,
                                chapter.bestStars[level.id] ?? 0,
                              )
                            : t.constellationLevelDark(level.id),
                      ),
                      if (chapter.needsNewVersion(level.id))
                        Text(
                          t.constellationNewVersion,
                          style: TextStyle(
                            color: colors.secondaryText,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  key: ValueKey('atlas-play-${level.id}'),
                  onPressed: () => Navigator.pop(context, level.id),
                  child: Text(t.constellationPlay),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class GoldenConstellationBenefit extends StatelessWidget {
  const GoldenConstellationBenefit({super.key, required this.session});

  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final discount = goldenStarlightDiscount(
      session.progression.goldenChapters.length,
    );
    return ArcadeSurface(
      key: const ValueKey('atlas-golden-benefit'),
      padding: const EdgeInsets.all(GameSpacing.small),
      accent: discount > 0 ? colors.reward : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t.goldenStarlightDiscount(discount),
            style: GameTypography.label.copyWith(color: colors.rewardInk),
          ),
          const SizedBox(height: GameSpacing.tiny),
          KeepAllText(
            t.goldenStarlightRule(
              StarlightPathRules.goldenDiscountPerConstellation,
              StarlightPathRules.goldenDiscountCap,
            ),
            style: GameTypography.body.copyWith(color: colors.secondaryText),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.chapter});
  final ChapterConstellation chapter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final (icon, color) = chapter.golden
        ? (Icons.workspace_premium_rounded, colors.rewardInk)
        : chapter.complete
        ? (Icons.auto_awesome, colors.goalInk)
        : (Icons.bedtime_outlined, colors.secondaryText);
    return StatPill(
      icon: icon,
      label: constellationStatus(t, chapter),
      color: color,
    );
  }
}
