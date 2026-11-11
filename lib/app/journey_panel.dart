import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constellation/constellation_atlas.dart';
import '../constellation/constellation_state.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../game/bloriq_game.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../settings/game_settings.dart';
import '../story/companion_view.dart';
import '../story/story_catalog.dart';
import '../world/world_text.dart';
import 'game_session.dart';

enum JourneyTab { status, constellations, companions, rewards }

/// 여정 메뉴. 고른 스테이지 id를 돌려준다. 닫으면 null.
/// 좌우로 탭을 전환하고, 각 탭의 내용은 세로로 탐색한다.
Future<int?> showJourneyPanel(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  JourneyTab initial = JourneyTab.status,
  WidgetBuilder? rewards,
}) => showDialog<int>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) =>
      JourneyPanel(session: session, initial: initial, rewards: rewards),
);

class JourneyPanel extends StatefulWidget {
  const JourneyPanel({
    super.key,
    required this.session,
    this.initial = JourneyTab.status,
    this.rewards,
  });
  final GameSession session;
  final JourneyTab initial;

  /// 보상 탭 내용. 성장 정보가 없으면 별자리 권능 대신 안내만 보여 준다.
  final WidgetBuilder? rewards;

  @override
  State<JourneyPanel> createState() => _JourneyPanelState();
}

class _JourneyPanelState extends State<JourneyPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: JourneyTab.values.length,
    vsync: this,
    initialIndex: widget.initial.index,
  );

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);
    Tab tab(IconData icon, String label) => Tab(
      icon: Icon(icon),
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      backgroundColor: colors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colors.reward.withValues(alpha: .45)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: size.height * .9),
        child: SizedBox(
          height: size.height * .9,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          t.journey,
                          maxLines: 1,
                          style: GameTypography.brand.copyWith(
                            color: colors.rewardInk,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('journey-close'),
                      tooltip: t.close,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                labelStyle: GameTypography.label.copyWith(fontSize: 13.5),
                labelPadding: EdgeInsets.zero,
                tabs: [
                  tab(Icons.insights_rounded, t.journeyStatus),
                  tab(Icons.auto_awesome, t.journeyConstellations),
                  tab(Icons.pets_rounded, t.journeyCompanions),
                  tab(Icons.card_giftcard_rounded, t.journeyRewards),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _StatusTab(session: widget.session),
                    _ConstellationTab(session: widget.session),
                    _CompanionTab(session: widget.session, onChanged: _refresh),
                    widget.rewards?.call(context) ??
                        _RewardsTab(
                          session: widget.session,
                          onChanged: _refresh,
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _JourneyWorldProgress = ({
  int number,
  String title,
  int cleared,
  int total,
  int stars,
  bool unlocked,
});

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final expansions = session.worlds.values.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    // 달빛 숲과 확장 세계 모두 현재 판 리비전의 진행 기록을 집계한다.
    final worlds = <_JourneyWorldProgress>[
      (
        number: 1,
        title:
            session.saga?.world(1).title.inLocale(t.localeName) ??
            t.journeyFirstWorld,
        cleared: session.completedCount,
        total: session.levels.length,
        stars: session.totalStars,
        unlocked: true,
      ),
      for (final world in expansions)
        if (session.worldAtlas(world.number) case final atlas?)
          (
            number: world.number,
            title: world.info.title.inLocale(t.localeName),
            cleared: atlas.cleared,
            total: world.levels.length,
            stars: atlas.stages.fold(0, (sum, stage) => sum + stage.stars),
            unlocked: session.worldUnlocked(world.number),
          ),
    ];
    final total = worlds.fold(0, (sum, world) => sum + world.total);
    final cleared = worlds.fold(0, (sum, world) => sum + world.cleared);
    final stars = worlds.fold(0, (sum, world) => sum + world.stars);
    Widget stat(IconData icon, String label, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GameTypography.label.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
    return ListView(
      key: const PageStorageKey('journey-status-list'),
      primary: false,
      padding: const EdgeInsets.all(16),
      children: [
        PlayerLevelCard(session: session),
        const SizedBox(height: 8),
        Row(
          children: [
            stat(
              Icons.flag_rounded,
              t.journeyCleared(cleared, total),
              colors.goalInk,
            ),
            const SizedBox(width: 8),
            stat(
              Icons.star_rounded,
              t.journeyStarCount(stars, total * 3),
              colors.rewardInk,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            stat(
              Icons.pets_rounded,
              t.journeyFriends(
                session.collection.owned.length,
                session.story.released.length,
              ),
              colors.echoInk,
            ),
            const SizedBox(width: 8),
            stat(
              Icons.local_fire_department_rounded,
              t.journeyStreak(session.daily.streak),
              colors.primaryInk,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          t.journeyWorldProgress,
          style: GameTypography.reward.copyWith(
            fontSize: 19,
            color: colors.rewardInk,
          ),
        ),
        for (final world in worlds) ...[
          const SizedBox(height: 8),
          _WorldProgressCard(world: world),
        ],
      ],
    );
  }
}

class _WorldProgressCard extends StatelessWidget {
  const _WorldProgressCard({required this.world});
  final _JourneyWorldProgress world;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final (status, statusColor) = !world.unlocked
        ? (t.journeyWorldLocked, colors.secondaryText)
        : world.cleared == world.total
        ? (t.journeyWorldComplete, colors.goalInk)
        : (t.journeyWorldActive, colors.echoInk);
    final cleared = t.journeyCleared(world.cleared, world.total);
    return ArcadeSurface(
      key: ValueKey('journey-world-${world.number}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  t.journeyWorldName(world.number, world.title),
                  style: GameTypography.label.copyWith(
                    fontSize: 16,
                    color: colors.text,
                  ),
                ),
                Text(
                  status,
                  style: GameTypography.label.copyWith(
                    fontSize: 13,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                cleared,
                style: GameTypography.label.copyWith(color: colors.goalInk),
              ),
              Text(
                t.journeyStarCount(world.stars, world.total * 3),
                style: GameTypography.label.copyWith(color: colors.rewardInk),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: world.cleared / world.total,
              color: colors.goal,
              backgroundColor: colors.outline.withValues(alpha: .25),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConstellationTab extends StatefulWidget {
  const _ConstellationTab({required this.session});
  final GameSession session;

  @override
  State<_ConstellationTab> createState() => _ConstellationTabState();
}

class _ConstellationTabState extends State<_ConstellationTab>
    with AutomaticKeepAliveClientMixin<_ConstellationTab> {
  late final List<ChapterConstellation> _chapters;
  late final PageController _pages;
  late int _page;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    _chapters = ConstellationAtlas.derive(
      session.levels,
      session.progress,
    ).chapters;
    _page = math.max(0, _chapters.indexWhere((chapter) => !chapter.complete));
    _pages = PageController(initialPage: _page);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_chapters.isEmpty) return const SizedBox.shrink();
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    Widget label(String text, TextStyle style) => FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, style: style),
    );
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            key: const ValueKey('journey-constellation-pages'),
            controller: _pages,
            scrollDirection: Axis.vertical,
            allowImplicitScrolling: true,
            itemCount: _chapters.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final chapter = _chapters[index];
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    label(
                      chapter.definition.name(t),
                      GameTypography.reward.copyWith(
                        color: colors.rewardInk,
                        fontSize: 22,
                      ),
                    ),
                    label(
                      constellationStatus(t, chapter),
                      GameTypography.body.copyWith(
                        color: colors.secondaryText,
                        fontSize: 14,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: ConstellationArt(
                          chapter: chapter,
                          guardianAsset: guardianAssetFor(
                            widget.session,
                            chapter,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final (slot, level) in chapter.levels.indexed) ...[
                          if (slot > 0) const SizedBox(width: 6),
                          Expanded(
                            child: _LevelChip(
                              id: level.id,
                              stars: chapter.bestStars[level.id] ?? 0,
                              lit: chapter.isLit(level.id),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (_chapters.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${_page + 1} / ${_chapters.length} · ${t.journeyPageHint}',
                key: const ValueKey('journey-constellation-page-count'),
                maxLines: 1,
                style: GameTypography.label.copyWith(
                  fontSize: 12,
                  color: colors.secondaryText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.id, required this.stars, required this.lit});
  final int id, stars;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final textScaler = MediaQuery.textScalerOf(context);
    return Material(
      color: lit ? colors.reward.withValues(alpha: .14) : colors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: lit
              ? colors.reward.withValues(alpha: .6)
              : colors.outline.withValues(alpha: .4),
        ),
      ),
      child: InkWell(
        key: ValueKey('journey-play-$id'),
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pop(context, id),
        child: SizedBox(
          height: math.max(54.0, textScaler.scale(36) + 12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              children: [
                Expanded(
                  flex: 3,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$id',
                      style: GameTypography.reward.copyWith(
                        fontSize: 18,
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '${'★' * stars}${'☆' * (3 - stars)}',
                      style: TextStyle(fontSize: 11, color: colors.rewardInk),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionTab extends StatelessWidget {
  const _CompanionTab({required this.session, required this.onChanged});
  final GameSession session;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final spirits = session.story.released;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Text(
            t.journeyCompanionCollection(
              session.collection.owned.length,
              spirits.length,
            ),
            style: GameTypography.label.copyWith(color: colors.rewardInk),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, area) {
              const padding = EdgeInsets.fromLTRB(12, 6, 12, 16);
              const spacing = 8.0;
              final width = (area.maxWidth - padding.horizontal - spacing) / 2;
              final textScaler = MediaQuery.textScalerOf(context);
              final extraTextHeight = math.max(0.0, textScaler.scale(48) - 48);
              return GridView.builder(
                key: const PageStorageKey('journey-companion-grid'),
                primary: false,
                padding: padding,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  mainAxisExtent: math.max(160.0, width) + extraTextHeight,
                ),
                itemCount: spirits.length,
                itemBuilder: (context, index) => _CompanionCard(
                  key: ValueKey('journey-companion-${spirits[index].id}'),
                  session: session,
                  spirit: spirits[index],
                  onChanged: onChanged,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CompanionCard extends StatelessWidget {
  const _CompanionCard({
    super.key,
    required this.session,
    required this.spirit,
    required this.onChanged,
  });
  final GameSession session;
  final SpiritDefinition spirit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final owned = session.collection.owns(spirit.id);
    final equipped = session.collection.companion?.id == spirit.id;
    final textScaler = MediaQuery.textScalerOf(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: equipped
            ? colors.goal.withValues(alpha: .14)
            : colors.background.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: equipped ? colors.goal : colors.outline.withValues(alpha: .3),
          width: equipped ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, area) => SpiritPortrait(
                spirit: spirit,
                size: area.biggest.shortestSide,
                hidden: !owned,
              ),
            ),
          ),
          Text(
            owned ? spirit.name.inLocale(t.localeName) : '???',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GameTypography.body.copyWith(
              fontSize: 14,
              color: colors.text,
            ),
          ),
          if (owned)
            Text(
              t.bondLevel(session.progression.bondLevel(spirit.id)),
              style: GameTypography.label.copyWith(
                fontSize: 11.5,
                color: colors.echoInk,
              ),
            ),
          SizedBox(
            height: math.max(44.0, textScaler.scale(16) + 12),
            child: !owned
                ? null
                : equipped
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        t.companionEquipped,
                        style: GameTypography.label.copyWith(
                          fontSize: 12,
                          color: colors.goalInk,
                        ),
                      ),
                    ),
                  )
                : TextButton(
                    key: ValueKey('journey-equip-${spirit.id}'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () async {
                      await session.collection.equip(spirit.id);
                      onChanged();
                    },
                    child: FittedBox(child: Text(t.companionEquip)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 별지기 레벨·경험치·별가루·칭호 한 줄 카드. 홈과 여정 현황에서 쓴다.
class PlayerLevelCard extends StatelessWidget {
  const PlayerLevelCard({super.key, required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final progression = session.progression;
    final standing = progression.standing;
    final title = titleById(progression.title)?.name.resolve(t.localeName);
    return Container(
      key: const ValueKey('player-level'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.goal.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.goal.withValues(alpha: .2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              t.playerLevel(standing.level),
              style: GameTypography.reward.copyWith(
                fontSize: 16,
                color: colors.goalInk,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title ?? t.xpToNext(standing.xpRemaining),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GameTypography.body.copyWith(
                    fontSize: 12.5,
                    color: colors.secondaryText,
                  ),
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 7,
                    value: standing.progress,
                    color: colors.goal,
                    backgroundColor: colors.outline.withValues(alpha: .25),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.auto_awesome, size: 16, color: colors.rewardInk),
          const SizedBox(width: 3),
          Text(
            '${progression.stardust}',
            style: GameTypography.label.copyWith(color: colors.rewardInk),
          ),
        ],
      ),
    );
  }
}

/// 보상 탭은 모든 보상과 공방을 한 목록에서 이어서 보여 준다.
class _RewardsTab extends StatelessWidget {
  const _RewardsTab({required this.session, required this.onChanged});
  final GameSession session;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final progression = session.progression;
    final atlas = ConstellationAtlas.derive(session.levels, session.progress);
    final levelLabelWidth = math.max(
      56.0,
      MediaQuery.textScalerOf(context).scale(48),
    );

    Widget heading(String id, String title) => Padding(
      key: ValueKey('journey-rewards-$id'),
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: GameTypography.reward.copyWith(
          fontSize: 19,
          color: colors.rewardInk,
        ),
      ),
    );

    String rewardLabel(TrackReward reward) => switch (reward) {
      StardustBundle(:final amount) => t.rewardStardust(amount),
      TrailUnlock(:final trailId) => t.rewardTrail(
        trailById(trailId)?.name.resolve(lang) ?? trailId,
      ),
      TitleUnlock(:final titleId) => t.rewardTitle(
        titleById(titleId)?.name.resolve(lang) ?? titleId,
      ),
      StarlightCharge(:final charges) => t.rewardCharge(charges),
    };

    Iterable<Widget> achievementSection(
      String id,
      String title,
      Iterable<Achievement> items,
    ) sync* {
      yield heading(id, title);
      for (final achievement in items) {
        yield _AchievementRow(
          achievement: achievement,
          progress: progression.achievementProgress(achievement),
          claimed: progression.claimedAchievements.contains(achievement.id),
          rewards: achievement.rewards.map(rewardLabel).join(' · '),
        );
      }
    }

    return ListView(
      key: const PageStorageKey('journey-rewards-list'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        heading('powers', t.rewardsPowers),
        for (final power in powerCatalog)
          _PowerCard(
            power: power,
            unlocked: progression.hasPower(power.id),
            constellation: atlas.chapters
                .where((chapter) => chapter.definition.chapter == power.chapter)
                .firstOrNull
                ?.definition
                .name(t),
          ),
        if (progression.completedChapters.length >= 5)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: KeepAllText(
              session.worldUnlocked(2) && session.saga != null
                  ? WorldText.opened(session.saga!.world(2).title).resolve(lang)
                  : t.nextWorldTeaser,
              textAlign: TextAlign.center,
              style: GameTypography.body.copyWith(color: colors.goalInk),
            ),
          ),
        heading('track', t.rewardsTrack),
        for (final entry in rewardTrack)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: levelLabelWidth,
                  child: Text(
                    t.playerLevel(entry.level),
                    style: GameTypography.label.copyWith(
                      color: progression.level >= entry.level
                          ? colors.goalInk
                          : colors.secondaryText,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    rewardLabel(entry.reward),
                    style: GameTypography.body.copyWith(
                      fontSize: 15,
                      color: progression.level >= entry.level
                          ? colors.text
                          : colors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  progression.level >= entry.level
                      ? Icons.check_circle_rounded
                      : Icons.lock_outline_rounded,
                  size: 18,
                  color: progression.level >= entry.level
                      ? colors.goalInk
                      : colors.outline,
                ),
              ],
            ),
          ),
        ...achievementSection(
          'stars',
          AchievementText.stars.resolve(lang),
          achievements.where(
            (achievement) => achievement.kind == AchievementKind.worldStars,
          ),
        ),
        ...achievementSection(
          'golden',
          AchievementText.golden.resolve(lang),
          achievements.where(
            (achievement) =>
                achievement.kind == AchievementKind.worldGolden ||
                achievement.kind == AchievementKind.goldenConstellations,
          ),
        ),
        ...achievementSection(
          'bare-handed',
          AchievementText.bareHanded.resolve(lang),
          achievements.where(
            (achievement) =>
                achievement.kind == AchievementKind.bareHandedStars,
          ),
        ),
        heading('shop', ShopText.heading.resolve(lang)),
        Row(
          children: [
            Expanded(
              child: KeepAllText(
                ShopText.intro.resolve(lang),
                style: GameTypography.body.copyWith(
                  fontSize: 15,
                  color: colors.secondaryText,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.auto_awesome, size: 16, color: colors.rewardInk),
            const SizedBox(width: 4),
            Text(
              '${progression.stardust}',
              key: const ValueKey('shop-balance'),
              style: GameTypography.label.copyWith(color: colors.rewardInk),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in trailShop)
          _ShopRow(
            item: item,
            owned: progression.ownedTrails.contains(item.trailId),
            affordable: progression.stardust >= item.price,
            onBuy: () async {
              await progression.buyTrail(item.trailId);
              onChanged();
            },
          ),
        heading('trails', t.rewardsTrails),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final trail in trails)
              if (shopItemFor(trail.id) == null ||
                  progression.ownedTrails.contains(trail.id))
                ChoiceChip(
                  key: ValueKey('trail-${trail.id}'),
                  label: Text(trail.name.resolve(lang)),
                  selected: progression.equippedTrail == trail.id,
                  onSelected: progression.ownedTrails.contains(trail.id)
                      ? (_) async {
                          await progression.equipTrail(trail.id);
                          onChanged();
                        }
                      : null,
                ),
          ],
        ),
        heading('titles', t.rewardsTitles),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final title in titles)
              ChoiceChip(
                key: ValueKey('journey-title-${title.id}'),
                label: Text(title.name.resolve(lang)),
                selected: progression.title == title.id,
                onSelected: progression.ownedTitles.contains(title.id)
                    ? (_) async {
                        await progression.setTitle(title.id);
                        onChanged();
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

class _PowerCard extends StatelessWidget {
  const _PowerCard({
    required this.power,
    required this.unlocked,
    required this.constellation,
  });
  final PowerDefinition power;
  final bool unlocked;
  final String? constellation;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final status = !unlocked
        ? t.powerLocked(constellation ?? '')
        : power.activeInWorld1
        ? t.powerActive
        : t.powerWorld2;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: unlocked
            ? colors.reward.withValues(alpha: .12)
            : colors.background.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: unlocked
              ? colors.reward.withValues(alpha: .6)
              : colors.outline.withValues(alpha: .3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            unlocked ? Icons.auto_awesome : Icons.lock_outline_rounded,
            color: unlocked ? colors.rewardInk : colors.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  power.name.resolve(lang),
                  style: GameTypography.reward.copyWith(
                    fontSize: 16,
                    color: unlocked ? colors.rewardInk : colors.secondaryText,
                  ),
                ),
                KeepAllText(
                  '${power.description.resolve(lang)} · $status',
                  style: GameTypography.body.copyWith(
                    fontSize: 15,
                    color: colors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 별 모으기 업적 한 줄: 이름, 진행 막대, 보상.
class _AchievementRow extends StatelessWidget {
  const _AchievementRow({
    required this.achievement,
    required this.progress,
    required this.claimed,
    required this.rewards,
  });
  final Achievement achievement;
  final int progress;
  final bool claimed;
  final String rewards;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final value = progress.clamp(0, achievement.target);
    final name = achievement.name.resolve(lang);
    final count = '$value / ${achievement.target}';
    final largeLabels = MediaQuery.textScalerOf(context).scale(14) > 21;
    final title = Text(
      name,
      style: GameTypography.label.copyWith(
        height: 1.2,
        color: claimed ? colors.rewardInk : colors.text,
      ),
    );
    final counter = Text(
      count,
      textAlign: TextAlign.end,
      style: GameTypography.label.copyWith(
        fontSize: 14,
        color: colors.secondaryText,
      ),
    );
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '$name, $count. $rewards',
      child: Padding(
        key: ValueKey('achievement-${achievement.id}'),
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              claimed ? Icons.emoji_events_rounded : Icons.star_outline_rounded,
              size: 22,
              color: claimed ? colors.reward : colors.outline,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (largeLabels) ...[
                    title,
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: counter,
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        counter,
                      ],
                    ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: value / achievement.target,
                      color: claimed ? colors.reward : colors.goal,
                      backgroundColor: colors.outline.withValues(alpha: .2),
                    ),
                  ),
                  const SizedBox(height: 5),
                  KeepAllText(
                    rewards,
                    style: GameTypography.body.copyWith(
                      fontSize: 15,
                      color: colors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 별빛 공방의 한 줄: 색 견본, 이름, 값, 사기 버튼.
class _ShopRow extends StatelessWidget {
  const _ShopRow({
    required this.item,
    required this.owned,
    required this.affordable,
    required this.onBuy,
  });
  final ShopItem item;
  final bool owned, affordable;
  final Future<void> Function() onBuy;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final name = trailById(item.trailId)?.name.resolve(lang) ?? item.trailId;
    final swatch = BloriqGame.trailPalette[item.trailId] ?? colors.primary;
    return ConstrainedBox(
      key: ValueKey('shop-${item.trailId}'),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: swatch,
              border: Border.all(color: colors.outline.withValues(alpha: .5)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: GameTypography.label.copyWith(color: colors.text),
            ),
          ),
          const SizedBox(width: 8),
          if (owned)
            Text(
              ShopText.owned.resolve(lang),
              style: GameTypography.label.copyWith(color: colors.goalInk),
            )
          else
            FilledButton.tonalIcon(
              key: ValueKey('shop-buy-${item.trailId}'),
              onPressed: affordable ? onBuy : null,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text('${item.price}'),
            ),
        ],
      ),
    );
  }
}
