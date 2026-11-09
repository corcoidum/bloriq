import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'constellation_painter.dart';
import 'constellation_state.dart';

/// 별자리 한 장. 완성된 별자리만 수호 정령의 흐린 실루엣을 드러낸다.
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
    this.silhouetteReveal = 1,
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
  final double silhouetteReveal;

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
    _loadSilhouette();
  }

  @override
  void didUpdateWidget(covariant ConstellationArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.guardianAsset != widget.guardianAsset) _loadSilhouette();
  }

  void _loadSilhouette() {
    final asset = widget.guardianAsset;
    if (asset == null || StarArt.portraits.containsKey(asset)) return;
    // 실루엣을 못 읽어도 별과 선은 그대로 그린다.
    StarArt.loadPortrait(asset).then((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.chapter;
    final lit = widget.lit ?? chapter.litMask;
    final complete = lit.every((value) => value);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: CustomPaint(
        painter: ConstellationPainter(
          definition: chapter.definition,
          lit: lit,
          colors: GameTheme.colorsOf(context),
          golden: widget.golden ?? (chapter.golden ? 1 : 0),
          pendingNode: widget.pendingNode,
          highlightNode: widget.highlightNode,
          nodeReveal: widget.nodeReveal,
          spark: widget.spark,
          lineReveal: widget.lineReveal,
          silhouette: complete ? StarArt.portraits[widget.guardianAsset] : null,
          silhouetteOpacity: (dark ? .14 : .10) * widget.silhouetteReveal,
        ),
        child: const SizedBox.expand(),
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
Future<int?> showConstellationAtlas(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  int? initialChapter,
}) => showDialog<int>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => ConstellationAtlasDialog(
    session: session,
    initialChapter: initialChapter,
  ),
);

class ConstellationAtlasDialog extends StatefulWidget {
  const ConstellationAtlasDialog({
    super.key,
    required this.session,
    this.initialChapter,
  });
  final GameSession session;
  final int? initialChapter;

  @override
  State<ConstellationAtlasDialog> createState() =>
      _ConstellationAtlasDialogState();
}

class _ConstellationAtlasDialogState extends State<ConstellationAtlasDialog> {
  late int? _selected = widget.initialChapter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = widget.session;
    final atlas = ConstellationAtlas.derive(session.levels, session.progress);
    final selected = _selected == null ? null : atlas.forChapter(_selected!);
    return AlertDialog(
      key: const ValueKey('constellation-atlas'),
      icon: Icon(Icons.auto_awesome, color: colors.rewardInk),
      title: Text(
        selected == null ? t.constellationAtlas : selected.definition.name(t),
      ),
      content: SizedBox(
        width: 460,
        height: MediaQuery.sizeOf(context).height * .6,
        child: selected == null
            ? _overview(context, atlas)
            : _detail(context, selected),
      ),
      actions: [
        if (selected != null)
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

  Widget _overview(BuildContext context, ConstellationAtlas atlas) {
    final t = AppLocalizations.of(context)!;
    return ListView.separated(
      key: const ValueKey('atlas-list'),
      itemCount: atlas.chapters.length,
      separatorBuilder: (_, _) => const SizedBox(height: GameSpacing.medium),
      itemBuilder: (context, index) {
        final chapter = atlas.chapters[index];
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
