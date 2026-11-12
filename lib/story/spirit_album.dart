import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../settings/game_settings.dart';
import '../design/arcade_components.dart';
import '../world/world_catalog.dart';
import '../world/world_progress.dart';
import '../world/world_shelf.dart';
import '../world/world_spirit_album.dart';
import '../world/world_text.dart';
import 'companion_view.dart';
import 'story_catalog.dart';
import 'story_share.dart';

Future<void> showSpiritAlbum(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  int? initialWorld,
}) => showDialog<void>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => SpiritAlbum(
    session: session,
    reduceMotion: prefersReducedMotion(context, settings),
    initialWorld: initialWorld,
  ),
);

class SpiritAlbum extends StatelessWidget {
  const SpiritAlbum({
    super.key,
    required this.session,
    this.reduceMotion = false,
    this.initialWorld,
  });
  final GameSession session;
  final bool reduceMotion;

  /// 처음 보여 줄 세계. 게임 화면에서는 지금 플레이 중인 세계를 넘긴다.
  /// 비우면 홈 "이어가기"가 가리키는 세계부터 연다.
  final int? initialWorld;
  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      t.album,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: t.close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SpiritAlbumShelf(
                session: session,
                initialWorld: initialWorld,
                reduceMotion: reduceMotion,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 여정과 발견 화면에서 같은 해금 규칙과 정령 상세를 사용한다.
class SpiritAlbumShelf extends StatefulWidget {
  const SpiritAlbumShelf({
    super.key,
    required this.session,
    this.initialWorld,
    this.reduceMotion = false,
    this.showCampaignTotal = false,
  });

  final GameSession session;
  final int? initialWorld;
  final bool reduceMotion;
  final bool showCampaignTotal;

  @override
  State<SpiritAlbumShelf> createState() => _SpiritAlbumShelfState();
}

class _SpiritAlbumShelfState extends State<SpiritAlbumShelf>
    with AutomaticKeepAliveClientMixin<SpiritAlbumShelf> {
  @override
  bool get wantKeepAlive => true;

  bool _busy = false;

  /// 보고 있는 세계.
  late int _world = widget.initialWorld ?? widget.session.continueTarget.world;
  Future<void> _detail(SpiritDefinition friend) async {
    final session = widget.session;
    if (_busy || !session.collection.owns(friend.id)) return;
    _busy = true;
    await session.collection.acknowledge(friend.id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      animationStyle: widget.reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (_) => _SpiritDetail(
        session: session,
        friend: friend,
        reduceMotion: widget.reduceMotion,
      ),
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _share(StoryChapter chapter) async {
    if (_busy) return;
    setState(() => _busy = true);
    await showStoryCard(
      context,
      widget.session.collection.inChapter(chapter.number),
      chapter: chapter,
      collection: true,
      reduceMotion: widget.reduceMotion,
    );
    if (mounted) setState(() => _busy = false);
  }

  RoundedRectangleBorder _portraitShape(GameColors colors) =>
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.showCampaignTotal ? 12 : 18),
        side: widget.showCampaignTotal
            ? BorderSide(color: colors.outline.withValues(alpha: .3))
            : BorderSide.none,
      );

  Widget _chapterTile({
    required Key key,
    required int number,
    required String title,
    required int count,
    required bool expanded,
    required List<Widget> children,
  }) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final compact = widget.showCampaignTotal;
    return ExpansionTile(
      key: key,
      initiallyExpanded: expanded,
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      minTileHeight: compact ? 48 : null,
      title: compact
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    '${t.journeyChapter(number)} · $title',
                    style: GameTypography.label,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count / ${Worlds.stagesPerChapter}',
                  style: GameTypography.label.copyWith(color: colors.goalInk),
                ),
              ],
            )
          : Text(title, style: TextStyle(color: colors.rewardInk)),
      subtitle: compact ? null : Text(t.chapterFriends(count)),
      children: children,
    );
  }

  Widget _tile(SpiritDefinition friend, double width, double portrait) {
    final t = AppLocalizations.of(context)!,
        colors = GameTheme.colorsOf(context),
        repo = widget.session.collection;
    final owned = repo.owns(friend.id);
    return SizedBox(
      width: width,
      child: Material(
        color: repo.companion?.id == friend.id
            ? colors.echo.withValues(alpha: .13)
            : widget.showCampaignTotal
            ? colors.surface
            : colors.boardSurface.withValues(alpha: .4),
        shape: _portraitShape(colors),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('spirit-${friend.id}'),
          onTap: owned ? () => _detail(friend) : null,
          child: Semantics(
            label: owned
                ? friend.name.inLocale(t.localeName)
                : '${t.unknownSpirit}, ${t.level(friend.levelId)}',
            child: Padding(
              padding: EdgeInsets.all(widget.showCampaignTotal ? 7 : 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpiritPortrait(
                    spirit: friend,
                    size: portrait,
                    hidden: !owned,
                  ),
                  Text(
                    owned
                        ? friend.name.inLocale(t.localeName)
                        : t.unknownSpirit,
                    textAlign: TextAlign.center,
                    style: widget.showCampaignTotal
                        ? GameTypography.label
                        : null,
                  ),
                  if (!widget.showCampaignTotal) ...[
                    const SizedBox(height: 4),
                    Text(
                      t.level(friend.levelId),
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (repo.companion?.id == friend.id)
                    Icon(
                      Icons.favorite_rounded,
                      color: colors.echoInk,
                      size: 18,
                    ),
                  if (repo.pendingIds.contains(friend.id))
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.rewardInk,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 확장 세계의 친구들. 판을 깨면 그 판의 정령을 만난다.
  List<Widget> _worldShelf(WorldAtlas atlas) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final session = widget.session;
    final title = session.saga?.world(atlas.world).title.inLocale(lang);
    final total = atlas.stages.length;
    final target = session.continueTarget;
    final current =
        !widget.showCampaignTotal &&
            target.world == atlas.world &&
            target.levelId != null
        ? Worlds.chapterOf(target.levelId!)
        : 1;
    return [
      Text(
        widget.showCampaignTotal
            ? t.journeyWorldCollection(atlas.cleared, total)
            : '${title == null ? '' : '$title · '}${t.journeyFriends(atlas.cleared, total)}',
        key: const ValueKey('album-world-progress'),
        style: TextStyle(color: colors.secondaryText),
      ),
      if (!widget.showCampaignTotal) ...[
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: total == 0 ? 0 : atlas.cleared / total,
          color: colors.goal,
        ),
      ],
      const SizedBox(height: 8),
      for (final chapter in atlas.chapters)
        _chapterTile(
          key: ValueKey(
            'album-world-${atlas.world}-chapter-${chapter.chapter.number}',
          ),
          number: chapter.chapter.number,
          title: chapter.chapter.name.inLocale(lang),
          count: chapter.cleared,
          expanded: chapter.chapter.number == current,
          children: [
            _grid(
              (width, portrait) => [
                for (final stage in chapter.stages)
                  _worldTile(stage, chapter, width, portrait),
              ],
            ),
          ],
        ),
    ];
  }

  Widget _worldTile(
    WorldStageView stage,
    WorldChapterView chapter,
    double width,
    double portrait,
  ) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final spirit = stage.spirit;
    final met = stage.cleared;
    final number =
        '${WorldText.stage.resolve(lang)} '
        '${Worlds.stageNumber(stage.level.id)}';
    return SizedBox(
      width: width,
      child: Material(
        color: widget.showCampaignTotal
            ? colors.surface
            : colors.boardSurface.withValues(alpha: .4),
        shape: _portraitShape(colors),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('spirit-${spirit.id}'),
          onTap: met
              ? () => showDialog<void>(
                  context: context,
                  animationStyle: widget.reduceMotion
                      ? AnimationStyle.noAnimation
                      : null,
                  builder: (_) =>
                      _WorldSpiritDetail(stage: stage, chapter: chapter),
                )
              : null,
          child: Semantics(
            label: met
                ? spirit.name.inLocale(lang)
                : '${t.unknownSpirit}, $number',
            child: Padding(
              padding: EdgeInsets.all(widget.showCampaignTotal ? 7 : 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: portrait,
                    height: portrait,
                    child: met
                        ? WorldSpiritPortrait(
                            asset: chapter.portraitFor(stage),
                            size: portrait,
                          )
                        : Icon(
                            Icons.bedtime_outlined,
                            size: portrait * .5,
                            color: colors.outline,
                          ),
                  ),
                  Text(
                    met ? spirit.name.inLocale(lang) : t.unknownSpirit,
                    textAlign: TextAlign.center,
                    style: widget.showCampaignTotal
                        ? GameTypography.label
                        : null,
                  ),
                  if (!widget.showCampaignTotal) ...[
                    const SizedBox(height: 4),
                    Text(
                      number,
                      style: TextStyle(
                        color: colors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Widget> Function(double width, double portrait) tiles) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final compact = widget.showCampaignTotal;
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
          final columns = largeText || constraints.maxWidth < 180
              ? 1
              : compact && constraints.maxWidth >= 260
              ? 3
              : 2;
          final gap = compact ? 8.0 : 12.0;
          final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: tiles(width, math.min(width - 14, compact ? 58 : 96)),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = widget.session;
    final repo = session.collection;
    final inJourney = widget.showCampaignTotal;
    final initialChapter = inJourney
        ? 1
        : repo.companion?.chapter ?? session.recommendedChapter.number;
    final overall = inJourney ? session.overall : null;
    return SingleChildScrollView(
      key: inJourney ? const ValueKey('journey-companion-list') : null,
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overall != null) ...[
            Text(
              t.journeyCollectionTotal(overall.friends, overall.friendTotal),
              key: const ValueKey('journey-companion-total'),
              style: GameTypography.reward.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            WorldPicker(
              key: const ValueKey('journey-companion-world'),
              session: session,
              selected: _world,
              onSelected: (world) => setState(() => _world = world),
            ),
            const SizedBox(height: 8),
            if (_world != 1 && repo.pendingIds.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _world = 1),
                child: Text(t.pendingMemories(repo.pendingIds.length)),
              ),
          ] else
            WorldChips(
              session: session,
              selected: _world,
              onSelected: (world) => setState(() => _world = world),
            ),
          if (session.worldAtlas(_world) case final atlas? when _world > 1)
            ..._worldShelf(atlas)
          else ...[
            Text(
              inJourney
                  ? t.journeyWorldCollection(
                      repo.owned.length,
                      session.story.released.length,
                    )
                  : t.seasonProgress(repo.owned.length),
              key: const ValueKey('album-progress'),
              style: TextStyle(color: colors.secondaryText),
            ),
            if (!inJourney) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: repo.owned.length / session.story.spirits.length,
                color: colors.goal,
              ),
            ],
            const SizedBox(height: 8),
            CollectionStorageNotice(
              session: session,
              onChanged: () => setState(() {}),
            ),
            for (final chapter in session.story.chapters.where(
              (c) => c.released,
            ))
              _chapterTile(
                key: ValueKey('album-chapter-${chapter.number}'),
                number: chapter.number,
                title: chapter.name.inLocale(t.localeName),
                count: repo.inChapter(chapter.number).length,
                expanded: chapter.number == initialChapter,
                children: [
                  _grid(
                    (width, portrait) => [
                      for (final friend in session.story.inChapter(
                        chapter.number,
                      ))
                        _tile(friend, width, portrait),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: ValueKey(
                      chapter.number == 1
                          ? 'share-collection'
                          : 'share-chapter-${chapter.number}',
                    ),
                    onPressed: _busy || repo.inChapter(chapter.number).isEmpty
                        ? null
                        : () => _share(chapter),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(
                      t.chapterCard(chapter.name.inLocale(t.localeName)),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _WorldSpiritDetail extends StatelessWidget {
  const _WorldSpiritDetail({required this.stage, required this.chapter});
  final WorldStageView stage;
  final WorldChapterView chapter;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final spirit = stage.spirit;
    return AlertDialog(
      key: ValueKey('spirit-detail-${spirit.id}'),
      scrollable: true,
      title: Text(spirit.name.inLocale(lang), textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 수호 정령 원화는 별자리를 완성한 뒤에만 보인다.
          WorldSpiritPortrait(asset: chapter.portraitFor(stage), size: 120),
          Text(
            chapter.chapter.familyName.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.label.copyWith(color: colors.goalInk),
          ),
          const SizedBox(height: 8),
          KeepAllText(
            spirit.appearance.inLocale(lang),
            textAlign: TextAlign.center,
          ),
          KeepAllText(
            spirit.personality.inLocale(lang),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(t.recoveredMemory, style: GameTypography.label),
          KeepAllText(
            spirit.memory.inLocale(lang),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          KeepAllText(
            spirit.quote.inLocale(lang),
            textAlign: TextAlign.center,
            style: GameTypography.body.copyWith(color: colors.goalInk),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
      ],
    );
  }
}

class _SpiritDetail extends StatefulWidget {
  const _SpiritDetail({
    required this.session,
    required this.friend,
    required this.reduceMotion,
  });
  final GameSession session;
  final SpiritDefinition friend;
  final bool reduceMotion;
  @override
  State<_SpiritDetail> createState() => _SpiritDetailState();
}

class _SpiritDetailState extends State<_SpiritDetail> {
  bool _busy = false;

  Widget _companionBenefits(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final friend = widget.friend;
    final progression = widget.session.progression;
    final clears = progression.bondClears(friend.id);
    final level = bondLevelForClears(clears);
    final next = clearsToNextBond(clears);
    final family = SpiritFamily.tryParse(friend.family);
    final benefit = switch (family) {
      SpiritFamily.forest => t.companionForestBenefit(
        StardustRules.forestBonusPercent,
      ),
      SpiritFamily.starlight => t.companionStarlightBenefit(
        StarlightPathRules.starlightBondDiscount,
      ),
      SpiritFamily.letter => t.companionLetterBenefit(
        XpRules.letterBondFirstClear,
      ),
      SpiritFamily.cloud => t.companionCloudBenefit,
      SpiritFamily.memory => t.companionMemoryBenefit,
      null => null,
    };
    final body = GameTypography.body.copyWith(color: colors.secondaryText);
    return ArcadeSurface(
      key: const ValueKey('spirit-companion-benefits'),
      padding: const EdgeInsets.all(GameSpacing.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.companionBenefits} · ${t.bondLevel(level)}',
            style: GameTypography.label.copyWith(color: colors.echoInk),
          ),
          const SizedBox(height: GameSpacing.tiny),
          KeepAllText(
            t.companionFirstClearBenefit(companionFirstClearXp(family, level)),
            style: GameTypography.body,
          ),
          if (benefit != null)
            KeepAllText(
              t.companionBondBenefit(bondAbilityLevel, benefit),
              style: body,
            ),
          if (next != null) ...[
            KeepAllText(
              t.companionBondBenefit(
                bondMaxLevel,
                t.companionFirstClearBenefit(
                  companionFirstClearXp(family, bondMaxLevel),
                ),
              ),
              style: body,
            ),
            const SizedBox(height: GameSpacing.tiny),
            KeepAllText(t.companionNextBond(next), style: body),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!,
        f = widget.friend,
        repo = widget.session.collection;
    final chapter = widget.session.story.chapter(f.chapter);
    return AlertDialog(
      scrollable: true,
      title: Text(f.name.inLocale(t.localeName)),
      content: SizedBox(
        width: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: SpiritPortrait(spirit: f, size: 150)),
            Text(
              chapter.familyName.inLocale(t.localeName),
              style: TextStyle(color: GameTheme.colorsOf(context).goalInk),
            ),
            Text(f.personality.inLocale(t.localeName)),
            const SizedBox(height: 12),
            _companionBenefits(context),
            const SizedBox(height: 12),
            Text(t.recoveredMemory, style: GameTypography.label),
            Text(f.memory.inLocale(t.localeName)),
            if (f.guardian) ...[
              const SizedBox(height: 12),
              Text(
                chapter.endingTitle.inLocale(t.localeName),
                style: GameTypography.label,
              ),
              Text(chapter.ending.inLocale(t.localeName)),
            ],
            const SizedBox(height: 12),
            Text(t.foundAtStage(f.levelId)),
            Text(f.motion.inLocale(t.localeName)),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('equip-companion'),
              onPressed: repo.companion?.id == f.id
                  ? null
                  : () async {
                      await repo.equip(f.id);
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.favorite_rounded),
              label: Text(
                repo.companion?.id == f.id
                    ? t.equippedCompanion
                    : t.equipCompanion,
              ),
            ),
            CollectionStorageNotice(
              session: widget.session,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.close),
        ),
        OutlinedButton.icon(
          key: const ValueKey('share-spirit'),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await showStoryCard(
                    context,
                    [f],
                    chapter: chapter,
                    reduceMotion: widget.reduceMotion,
                  );
                  if (mounted) setState(() => _busy = false);
                },
          icon: const Icon(Icons.ios_share_rounded),
          label: Text(t.discoveryCard),
        ),
      ],
    );
  }
}

class CollectionStorageNotice extends StatefulWidget {
  const CollectionStorageNotice({
    super.key,
    required this.session,
    required this.onChanged,
  });
  final GameSession session;
  final VoidCallback onChanged;
  @override
  State<CollectionStorageNotice> createState() =>
      _CollectionStorageNoticeState();
}

class _CollectionStorageNoticeState extends State<CollectionStorageNotice> {
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final repo = widget.session.collection, t = AppLocalizations.of(context)!;
    if (!repo.saveFailed) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          repo.futureSchema
              ? t.collectionFuture
              : repo.corrupt
              ? t.collectionCorrupt
              : t.collectionError,
          style: TextStyle(color: GameTheme.colorsOf(context).error),
        ),
        if (!repo.futureSchema)
          TextButton(
            key: const ValueKey('retry-collection'),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    if (repo.corrupt) {
                      await repo.recover(
                        widget.session.progress.saveFailed
                            ? {}
                            : widget.session.progress.completedCampaignLevelIds,
                      );
                    } else {
                      await repo.retrySave();
                    }
                    if (mounted) {
                      setState(() => _busy = false);
                      widget.onChanged();
                    }
                  },
            child: Text(repo.corrupt ? t.restoreAlbum : t.retrySave),
          ),
      ],
    );
  }
}
