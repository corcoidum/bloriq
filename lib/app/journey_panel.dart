import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import '../trials/trial_screen.dart';
import '../world/saga_map.dart';
import '../world/world_catalog.dart';
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
                  // 별하늘을 좌우로 움직여야 하므로 탭은 눌러서만 바꾼다.
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _StatusTab(
                      session: widget.session,
                      focusWorld: _world,
                      playing: widget.initialLevelId != null,
                      onChooseWorld: widget.allowStageSelection
                          ? _chooseWorld
                          : null,
                    ),
                    JourneyConstellations(
                      session: widget.session,
                      initialWorld: _world,
                      initialLevelId: _levelId,
                      onPlay: onPlay,
                      reduceMotion: prefersReducedMotion(
                        context,
                        widget.settings,
                      ),
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

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.session,
    required this.focusWorld,
    required this.playing,
    required this.onChooseWorld,
  });

  final GameSession session;
  final int focusWorld;
  final bool playing;
  final ValueChanged<int>? onChooseWorld;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final overall = session.overall;
    final numbers = [1, ...session.worlds.keys];
    final finished = numbers
        .where(
          (number) =>
              session.clearedInWorld(number) ==
              (number == 1 ? session.levels.length : Worlds.stageCount),
        )
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
                  t.journeyWorldsCleared(finished, numbers.length),
                  textAlign: TextAlign.end,
                  style: statsStyle.copyWith(color: colors.goalInk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 빛길 지도 화면을 따로 두지 않고 여기서 바로 보여 준다.
          if (session.saga != null)
            SagaRoad(
              session: session,
              onEnter: onChooseWorld,
              focusWorld: focusWorld,
              focusLabel: playing
                  ? t.journeyPlayingWorld
                  : t.journeyContinueWorld,
              tapCards: true,
            ),
          const SizedBox(height: 6),
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
          if (session.daily.streak > 0) ...[
            const SizedBox(height: 10),
            Text(t.journeyStreak(session.daily.streak)),
          ],
        ],
      ),
    );
  }
}
