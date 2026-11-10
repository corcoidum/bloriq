import 'package:flutter/material.dart';

import '../constellation/constellation_atlas.dart';
import '../constellation/constellation_state.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../game/bloriq_game.dart';
import '../l10n/app_localizations.dart';
import '../progress/chapter_progress.dart';
import '../settings/game_settings.dart';
import '../story/companion_view.dart';
import '../story/story_catalog.dart';
import '../progression/progression_rules.dart';
import 'game_session.dart';
import '../world/world_text.dart';

enum JourneyTab { status, constellations, companions, rewards }

/// 여정 메뉴. 고른 스테이지 id를 돌려준다. 닫으면 null.
/// 탭마다 한 화면에 들어가도록 세로 스크롤 대신 옆으로 넘긴다.
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      backgroundColor: colors.surface,
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
                      child: Text(
                        t.journey,
                        style: GameTypography.brand.copyWith(
                          color: colors.rewardInk,
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
                  Tab(
                    icon: const Icon(Icons.insights_rounded),
                    text: t.journeyStatus,
                  ),
                  Tab(
                    icon: const Icon(Icons.auto_awesome),
                    text: t.journeyConstellations,
                  ),
                  Tab(
                    icon: const Icon(Icons.pets_rounded),
                    text: t.journeyCompanions,
                  ),
                  Tab(
                    icon: const Icon(Icons.card_giftcard_rounded),
                    text: t.journeyRewards,
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _StatusTab(session: widget.session),
                    _ConstellationTab(session: widget.session),
                    _CompanionTab(
                      session: widget.session,
                      onChanged: () => setState(() {}),
                    ),
                    widget.rewards?.call(context) ??
                        _RewardsTab(
                          session: widget.session,
                          onChanged: () => setState(() {}),
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

/// 옆으로 넘기는 페이지와 아래 점 표시.
class PagedPanel extends StatefulWidget {
  const PagedPanel({super.key, required this.pages, this.initialPage = 0});
  final List<Widget> pages;
  final int initialPage;

  @override
  State<PagedPanel> createState() => _PagedPanelState();
}

class _PagedPanelState extends State<PagedPanel> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
  );
  late int _page = widget.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return Column(
      children: [
        Expanded(
          child: PageView(
            controller: _controller,
            onPageChanged: (page) => setState(() => _page = page),
            children: widget.pages,
          ),
        ),
        if (widget.pages.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, top: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.pages.length; i++)
                  GestureDetector(
                    onTap: () => _controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? colors.reward
                            : colors.outline.withValues(alpha: .5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final chapters = ChapterProgress.group(session.levels, session.progress);
    final total = session.levels.length;
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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: GameTypography.label.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          PlayerLevelCard(session: session),
          const SizedBox(height: 8),
          Row(
            children: [
              stat(
                Icons.flag_rounded,
                t.journeyCleared(session.completedCount, total),
                colors.goalInk,
              ),
              const SizedBox(width: 8),
              stat(
                Icons.star_rounded,
                t.journeyStarCount(session.totalStars, total * 3),
                colors.rewardInk,
              ),
              const SizedBox(width: 8),
              stat(
                Icons.pets_rounded,
                t.journeyFriends(
                  session.collection.owned.length,
                  session.story.released.length,
                ),
                colors.echoInk,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              stat(
                Icons.local_fire_department_rounded,
                t.journeyStreak(session.daily.streak),
                colors.primaryInk,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final chapter in chapters)
                  Row(
                    children: [
                      SizedBox(
                        width: 112,
                        child: Text(
                          session.story
                              .chapter(chapter.number)
                              .name
                              .inLocale(t.localeName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GameTypography.body.copyWith(fontSize: 14),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            minHeight: 10,
                            value: chapter.completed / chapter.levels.length,
                            color: colors.goal,
                            backgroundColor: colors.outline.withValues(
                              alpha: .2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '★${chapter.stars}',
                        style: GameTypography.label.copyWith(
                          color: colors.rewardInk,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConstellationTab extends StatelessWidget {
  const _ConstellationTab({required this.session});
  final GameSession session;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final atlas = ConstellationAtlas.derive(session.levels, session.progress);
    final current = atlas.chapters.indexWhere((chapter) => !chapter.complete);
    return PagedPanel(
      initialPage: current < 0 ? 0 : current,
      pages: [
        for (final chapter in atlas.chapters)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              children: [
                Text(
                  chapter.definition.name(t),
                  style: GameTypography.reward.copyWith(
                    color: colors.rewardInk,
                    fontSize: 22,
                  ),
                ),
                Text(
                  constellationStatus(t, chapter),
                  style: GameTypography.body.copyWith(
                    color: colors.secondaryText,
                    fontSize: 14,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: ConstellationArt(
                      chapter: chapter,
                      guardianAsset: guardianAssetFor(session, chapter),
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final level in chapter.levels)
                      _LevelChip(
                        id: level.id,
                        stars: chapter.bestStars[level.id] ?? 0,
                        lit: chapter.isLit(level.id),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
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
          width: 58,
          height: 54,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$id',
                style: GameTypography.reward.copyWith(
                  fontSize: 18,
                  color: colors.text,
                ),
              ),
              Text(
                '${'★' * stars}${'☆' * (3 - stars)}',
                style: TextStyle(fontSize: 11, color: colors.rewardInk),
              ),
            ],
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
    final spirits = session.story.released;
    final companion = session.collection.companion;
    final pages = <List<SpiritDefinition>>[
      for (var i = 0; i < spirits.length; i += 6)
        spirits.skip(i).take(6).toList(),
    ];
    final current = companion == null ? 0 : spirits.indexOf(companion) ~/ 6;
    return PagedPanel(
      initialPage: current < 0 ? 0 : current,
      pages: [
        for (final page in pages)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: LayoutBuilder(
              builder: (context, area) {
                const spacing = 8.0;
                final width = (area.maxWidth - spacing) / 2;
                final height = (area.maxHeight - spacing * 2) / 3;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final spirit in page)
                      SizedBox(
                        width: width,
                        height: height,
                        child: _CompanionCard(
                          session: session,
                          spirit: spirit,
                          onChanged: onChanged,
                        ),
                      ),
                  ],
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
            height: 30,
            child: !owned
                ? null
                : equipped
                ? Center(
                    child: Text(
                      t.companionEquipped,
                      style: GameTypography.label.copyWith(
                        fontSize: 12,
                        color: colors.goalInk,
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

/// 보상 탭: 별자리 권능, 레벨 보상 트랙, 이동 잔영과 칭호.
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
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: GameTypography.reward.copyWith(
          fontSize: 19,
          color: colors.rewardInk,
        ),
      ),
    );
    final powers = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          heading(t.rewardsPowers),
          for (final power in powerCatalog)
            Expanded(
              child: _PowerCard(
                power: power,
                unlocked: progression.hasPower(power.id),
                constellation: atlas.chapters
                    .where((c) => c.definition.chapter == power.chapter)
                    .firstOrNull
                    ?.definition
                    .name(t),
              ),
            ),
          if (progression.completedChapters.length >= 5)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: KeepAllText(
                session.worldUnlocked(2) && session.saga != null
                    ? WorldText.opened(session.saga!.world(2).title)
                          .resolve(lang)
                    : t.nextWorldTeaser,
                textAlign: TextAlign.center,
                style: GameTypography.body.copyWith(color: colors.goalInk),
              ),
            ),
        ],
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
    Widget trackPage(Iterable<TrackEntry> entries) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          heading(t.rewardsTrack),
          for (final entry in entries)
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GameTypography.body.copyWith(
                        fontSize: 14,
                        color: progression.level >= entry.level
                            ? colors.text
                            : colors.secondaryText,
                      ),
                    ),
                  ),
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
        ],
      ),
    );
    String rewardsText(List<TrackReward> rewards) =>
        rewards.map(rewardLabel).join(' · ');
    Widget achievementPage(String title, Iterable<Achievement> items) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              heading(title),
              for (final achievement in items)
                Expanded(
                  child: _AchievementRow(
                    achievement: achievement,
                    progress: progression.achievementProgress(achievement),
                    claimed: progression.claimedAchievements.contains(
                      achievement.id,
                    ),
                    rewards: rewardsText(achievement.rewards),
                  ),
                ),
            ],
          ),
        );
    final style = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading(t.rewardsTrails),
          // 공방 잔영은 산 것만 보여 준다(살 수 있는 것은 공방 페이지에 있다).
          // 잔영이 많아져 작은 화면에서 넘치면 이 칸만 스크롤한다.
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
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
            ),
          ),
        ],
      ),
    );
    final shop = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading(ShopText.heading.resolve(lang)),
          Row(
            children: [
              Expanded(
                child: KeepAllText(
                  ShopText.intro.resolve(lang),
                  style: GameTypography.body.copyWith(
                    fontSize: 13.5,
                    color: colors.secondaryText,
                  ),
                ),
              ),
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
            Expanded(
              child: _ShopRow(
                item: item,
                owned: progression.ownedTrails.contains(item.trailId),
                affordable: progression.stardust >= item.price,
                onBuy: () async {
                  final bought = await progression.buyTrail(item.trailId);
                  if (!context.mounted) return;
                  onChanged();
                  if (bought ||
                      progression.ownedTrails.contains(item.trailId)) {
                    return;
                  }
                  await showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: Text(
                        progression.stardust < item.price
                            ? ShopText.short.resolve(lang)
                            : ShopText.saveFailed.resolve(lang),
                        style: GameTypography.body.copyWith(color: colors.text),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: Text(t.close),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
    final titlePage = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading(t.rewardsTitles),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final title in titles)
                ChoiceChip(
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
      ),
    );
    return PagedPanel(
      pages: [
        powers,
        trackPage(rewardTrack.where((entry) => entry.level <= 11)),
        trackPage(rewardTrack.where((entry) => entry.level > 11)),
        achievementPage(
          AchievementText.stars.resolve(lang),
          achievements.where((a) => a.kind == AchievementKind.worldStars),
        ),
        achievementPage(
          AchievementText.golden.resolve(lang),
          achievements.where(
            (a) =>
                a.kind == AchievementKind.worldGolden ||
                a.kind == AchievementKind.goldenConstellations,
          ),
        ),
        achievementPage(
          AchievementText.bareHanded.resolve(lang),
          achievements.where((a) => a.kind == AchievementKind.bareHandedStars),
        ),
        shop,
        style,
        titlePage,
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
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  power.name.resolve(lang),
                  style: GameTypography.reward.copyWith(
                    fontSize: 16,
                    color: unlocked ? colors.rewardInk : colors.secondaryText,
                  ),
                ),
                Flexible(
                  child: KeepAllText(
                    '${power.description.resolve(lang)} · $status',
                    maxLines: 2,
                    style: GameTypography.body.copyWith(
                      fontSize: 12.5,
                      color: colors.secondaryText,
                    ),
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
    return Semantics(
      container: true,
      label:
          '${achievement.name.resolve(lang)}, $value / ${achievement.target}',
      child: Row(
        key: ValueKey('achievement-${achievement.id}'),
        children: [
          Icon(
            claimed ? Icons.emoji_events_rounded : Icons.star_outline_rounded,
            size: 22,
            color: claimed ? colors.reward : colors.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        achievement.name.resolve(lang),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GameTypography.label.copyWith(
                          color: claimed ? colors.rewardInk : colors.text,
                        ),
                      ),
                    ),
                    Text(
                      '$value / ${achievement.target}',
                      style: GameTypography.label.copyWith(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: value / achievement.target,
                    color: claimed ? colors.reward : colors.goal,
                    backgroundColor: colors.outline.withValues(alpha: .2),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  rewards,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GameTypography.body.copyWith(
                    fontSize: 12.5,
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
    return Row(
      key: ValueKey('shop-${item.trailId}'),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GameTypography.label.copyWith(color: colors.text),
          ),
        ),
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
    );
  }
}
