import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import '../trials/trial_screen.dart';
import '../world/saga_map.dart';
import '../world/world_map.dart';
import '../world/world_text.dart';
import 'ability_spirits.dart';
import 'game_session.dart';
import 'journey_constellations.dart';
import 'level_picker.dart';

enum JourneyTab { status, constellations, spirits }

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
                  tab(
                    JourneyTab.spirits,
                    AbilitySpiritText.tab.resolve(t.localeName),
                  ),
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
                    AbilitySpiritsTab(session: widget.session),
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
            ],
          ),
          const SizedBox(height: 10),
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
                          fontSize: 13,
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
                        fontSize: 13,
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
