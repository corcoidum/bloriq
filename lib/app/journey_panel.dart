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
import '../story/spirit_album.dart';
import '../trials/trial_screen.dart';
import '../world/saga_map.dart';
import '../world/world_map.dart';
import '../world/world_text.dart';
import 'game_session.dart';
import 'journey_constellations.dart';
import 'level_picker.dart';

enum JourneyTab { status, constellations, companions, rewards }

/// 홈과 게임에서 같은 여정을 열고, 선택한 캠페인 스테이지 id를 돌려준다.
Future<int?> showJourneyPanel(
  BuildContext context,
  GameSession session,
  GameSettings settings, {
  JourneyTab initial = JourneyTab.status,
  int? initialWorld,
  int? initialLevelId,
  bool allowStageSelection = true,
  TrialGameBuilder? buildTrialGame,
}) => showDialog<int>(
  context: context,
  animationStyle: prefersReducedMotion(context, settings)
      ? AnimationStyle.noAnimation
      : null,
  builder: (_) => JourneyPanel(
    session: session,
    settings: settings,
    initial: initial,
    initialWorld: initialWorld,
    initialLevelId: initialLevelId,
    allowStageSelection: allowStageSelection,
    buildTrialGame: buildTrialGame,
  ),
);

class JourneyPanel extends StatefulWidget {
  const JourneyPanel({
    super.key,
    required this.session,
    required this.settings,
    this.initial = JourneyTab.status,
    this.initialWorld,
    this.initialLevelId,
    this.allowStageSelection = true,
    this.buildTrialGame,
  });

  final GameSession session;
  final GameSettings settings;
  final JourneyTab initial;
  final int? initialWorld, initialLevelId;
  final bool allowStageSelection;
  final TrialGameBuilder? buildTrialGame;

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
  late final _target = widget.session.continueTarget;
  late final int _world = widget.initialWorld ?? _target.world;
  late final int? _levelId =
      widget.initialLevelId ??
      (_world == _target.world ? _target.levelId : null);
  bool _choosingWorld = false;

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _chooseWorld(int world) async {
    if (_choosingWorld || !widget.session.worldUnlocked(world)) return;
    _choosingWorld = true;
    try {
      final id = world == 1
          ? await showLevelPicker(
              context,
              widget.session,
              widget.settings,
              currentLevelId: _world == 1 ? _levelId : null,
              buildTrialGame: widget.buildTrialGame,
            )
          : await showWorldMap(
              context,
              widget.session,
              world,
              buildTrialGame: widget.buildTrialGame,
            );
      if (mounted && id != null) Navigator.pop(context, id);
    } finally {
      _choosingWorld = false;
      _refresh();
    }
  }

  Future<void> _readLightroad() async {
    final world = await showSagaMap(
      context,
      widget.session,
      selectable: widget.allowStageSelection,
    );
    if (mounted && world != null) await _chooseWorld(world);
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
    final onPlay = widget.allowStageSelection
        ? (int id) => Navigator.pop(context, id)
        : null;
    Tab tab(JourneyTab type, String label) => Tab(
      key: ValueKey('journey-tab-${type.name}'),
      height: 46,
      child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      backgroundColor: colors.background,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outline.withValues(alpha: .4)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 52),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(t.journey, style: GameTypography.brand),
                      ),
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: IconButton(
                        key: const ValueKey('journey-close'),
                        tooltip: t.close,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabs,
                labelStyle: GameTypography.label.copyWith(fontSize: 16),
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                tabs: [
                  tab(JourneyTab.status, t.journeyStatus),
                  tab(JourneyTab.constellations, t.journeyConstellations),
                  tab(JourneyTab.companions, t.journeyCompanions),
                  tab(JourneyTab.rewards, t.journeyRewards),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _StatusTab(
                      session: widget.session,
                      focusWorld: _world,
                      playing: widget.initialLevelId != null,
                      onChooseWorld: widget.allowStageSelection
                          ? _chooseWorld
                          : null,
                      onReadLightroad: widget.session.saga == null
                          ? null
                          : _readLightroad,
                    ),
                    JourneyConstellations(
                      session: widget.session,
                      initialWorld: _world,
                      initialLevelId: _levelId,
                      onPlay: onPlay,
                    ),
                    SpiritAlbumShelf(
                      session: widget.session,
                      initialWorld: _world,
                      reduceMotion: prefersReducedMotion(
                        context,
                        widget.settings,
                      ),
                      showCampaignTotal: true,
                    ),
                    _RewardsTab(session: widget.session, onChanged: _refresh),
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

typedef _WorldProgress = ({
  int number,
  String title,
  int cleared,
  int total,
  int stars,
  bool unlocked,
});

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.session,
    required this.focusWorld,
    required this.playing,
    required this.onChooseWorld,
    required this.onReadLightroad,
  });

  final GameSession session;
  final int focusWorld;
  final bool playing;
  final ValueChanged<int>? onChooseWorld;
  final VoidCallback? onReadLightroad;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final overall = session.overall;
    final saga = session.saga;
    final expansions = session.worlds.keys.toList()..sort();
    final worlds = <_WorldProgress>[
      (
        number: 1,
        title:
            saga?.world(1).title.inLocale(t.localeName) ?? t.journeyFirstWorld,
        cleared: session.completedCount,
        total: session.levels.length,
        stars: session.totalStars,
        unlocked: true,
      ),
      for (final world in expansions)
        if (session.worldAtlas(world) case final atlas?)
          (
            number: world,
            title: session.world(world)!.info.title.inLocale(t.localeName),
            cleared: atlas.cleared,
            total: atlas.stages.length,
            stars: atlas.stages.fold(0, (sum, stage) => sum + stage.stars),
            unlocked: session.worldUnlocked(world),
          ),
    ];
    final finished = worlds
        .where((world) => world.cleared == world.total)
        .length;
    final statsStyle = GameTypography.label.copyWith(fontSize: 14);
    return SingleChildScrollView(
      key: const PageStorageKey('journey-status-list'),
      primary: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  WorldText.sagaMap.resolve(t.localeName),
                  style: GameTypography.reward.copyWith(fontSize: 22),
                ),
              ),
              Flexible(
                child: Text(
                  t.journeyWorldsCleared(finished, worlds.length),
                  textAlign: TextAlign.end,
                  style: statsStyle.copyWith(color: colors.goalInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Stack(
            children: [
              PositionedDirectional(
                start: 23,
                top: 24,
                bottom: 24,
                child: Container(
                  width: 1,
                  color: colors.goal.withValues(alpha: .34),
                ),
              ),
              Column(
                children: [
                  for (final world in worlds)
                    _WorldRow(
                      world: world,
                      focus: world.number == focusWorld,
                      playing: playing,
                      onTap: world.unlocked && onChooseWorld != null
                          ? () => onChooseWorld!(world.number)
                          : null,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(t.journeyProgressSummary, style: GameTypography.label),
          const SizedBox(height: 4),
          Divider(color: colors.outline.withValues(alpha: .35)),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                t.journeyCleared(overall.cleared, overall.total),
                style: statsStyle.copyWith(color: colors.goalInk),
              ),
              Text(
                t.journeyStarCount(overall.stars, overall.total * 3),
                style: statsStyle.copyWith(color: colors.rewardInk),
              ),
              Text(
                t.journeySpiritCount(overall.friends, overall.friendTotal),
                style: statsStyle.copyWith(color: colors.echoInk),
              ),
            ],
          ),
          const SizedBox(height: 10),
          PlayerLevelCard(session: session),
          if (session.daily.streak > 0)
            Text(t.journeyStreak(session.daily.streak)),
          if (onReadLightroad != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('journey-lightroad-story'),
                onPressed: onReadLightroad,
                icon: const Icon(Icons.auto_stories_outlined, size: 18),
                label: Text(t.journeyLightroadStory),
              ),
            ),
        ],
      ),
    );
  }
}

class _WorldRow extends StatelessWidget {
  const _WorldRow({
    required this.world,
    required this.focus,
    required this.playing,
    this.onTap,
  });

  final _WorldProgress world;
  final bool focus, playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: focus
          ? BorderSide(color: colors.reward.withValues(alpha: .4))
          : BorderSide.none,
    );
    return Material(
      color: focus ? colors.reward.withValues(alpha: .1) : Colors.transparent,
      shape: shape,
      child: InkWell(
        key: ValueKey('journey-world-${world.number}'),
        customBorder: shape,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 49),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 27,
                  height: 27,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: focus ? colors.reward : colors.surface,
                    border: Border.all(
                      color: world.unlocked ? colors.goal : colors.outline,
                      width: .8,
                    ),
                  ),
                  child: world.unlocked
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${world.number}',
                            style: GameTypography.label.copyWith(
                              color: focus
                                  ? colors.blockSymbol
                                  : colors.goalInk,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: colors.secondaryText,
                        ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(world.title, style: GameTypography.label),
                      Text(
                        world.unlocked
                            ? '${t.journeyCleared(world.cleared, world.total)} · '
                                  '${t.journeyStarCount(world.stars, world.total * 3)}'
                            : t.journeyWorldLocked,
                        style: TextStyle(
                          color: colors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (focus)
                  Flexible(
                    child: Text(
                      playing ? t.journeyPlayingWorld : t.journeyContinueWorld,
                      textAlign: TextAlign.end,
                      style: GameTypography.label.copyWith(
                        color: colors.rewardInk,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (onTap != null)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: colors.secondaryText,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
            flex: 3,
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
          Flexible(
            flex: 2,
            child: Text(
              t.stardustCount(progression.stardust),
              textAlign: TextAlign.end,
              style: GameTypography.label.copyWith(color: colors.rewardInk),
            ),
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
      Iterable<Achievement> items, {
      Widget? summary,
    }) sync* {
      yield heading(id, title);
      if (summary != null) yield summary;
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
          summary: GoldenConstellationBenefit(session: session),
        ),
        ...achievementSection(
          'starflowers',
          AchievementText.starflowers.resolve(lang),
          achievements.where(
            (achievement) =>
                achievement.kind == AchievementKind.worldStarflowers,
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
