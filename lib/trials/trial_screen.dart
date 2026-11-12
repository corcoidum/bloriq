import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import '../world/world_catalog.dart';
import 'trial_catalog.dart';

typedef TrialGameBuilder = Widget Function(TrialStage stage, Level board);

String trialConditionLabel(AppLocalizations t, TrialStage stage) =>
    switch (stage.condition) {
      TrialCondition.moveLimit => t.trialMoveLimit(stage.moveLimit!),
      TrialCondition.noUndo => t.trialNoUndo,
      TrialCondition.noPowers => t.trialNoPowers,
    };

Future<void> showTrials(
  BuildContext context,
  GameSession session,
  int world,
  TrialGameBuilder buildGame, {
  int? chapter,
}) async {
  if (!session.canPlayTrials(world, chapter: chapter)) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _TrialScreen(
        session: session,
        world: world,
        chapter: chapter,
        buildGame: buildGame,
      ),
    ),
  );
}

class _TrialScreen extends StatefulWidget {
  const _TrialScreen({
    required this.session,
    required this.world,
    required this.chapter,
    required this.buildGame,
  });

  final GameSession session;
  final int world;
  final int? chapter;
  final TrialGameBuilder buildGame;

  @override
  State<_TrialScreen> createState() => _TrialScreenState();
}

class _TrialScreenState extends State<_TrialScreen> {
  late final Future<TrialCatalog> _catalog = widget.session.trialCatalog;
  bool _opening = false;

  Future<void> _play(TrialStage stage) async {
    if (_opening) return;
    final session = widget.session;
    final sources = stage.world == 1
        ? session.levels
        : session.world(stage.world)!.levels;
    final Level board;
    try {
      board = stage.orient(
        sources.firstWhere((level) => level.id == stage.sourceId),
      );
    } on Object catch (error) {
      debugPrint('Trial ${stage.sourceId} unavailable: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.loadError)),
      );
      return;
    }
    setState(() => _opening = true);
    final audio = session.audio;
    final wasVisible = audio.gameVisible;
    audio.setMusicTrack(session.saga?.world(stage.world).theme?.bgm);
    audio.setGameVisible(true);
    audio.onUserInteraction();
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => widget.buildGame(stage, board)),
      );
    } finally {
      audio.setGameVisible(wasVisible);
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = widget.session;
    final world =
        session.saga?.world(widget.world).title.inLocale(t.localeName) ??
        t.journeyFirstWorld;
    final chapter = widget.chapter;
    final reward = trialRewards[widget.world]!;
    final rewarded =
        session.progression.ownedTitles.contains(reward.title.id) &&
        session.progression.ownedTrails.contains(reward.trail.id);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(
          chapter == null ? t.echoTrials : t.goldenTrials,
          style: GameTypography.reward.copyWith(color: colors.rewardInk),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<TrialCatalog>(
          future: _catalog,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text(t.loadError));
            final catalog = snapshot.data;
            if (catalog == null) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = catalog.forWorld(widget.world);
            return ListView(
              key: const ValueKey('trial-list'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Text(
                  world,
                  style: GameTypography.reward.copyWith(
                    fontSize: 20,
                    color: colors.goalInk,
                  ),
                ),
                Text(
                  t.trialProgress(
                    session.trialProgress.clearedCount(all),
                    all.length,
                  ),
                  style: GameTypography.label,
                ),
                if (chapter == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: ArcadeSurface(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rewarded
                                ? t.trialRewardUnlocked
                                : t.trialRewardGoal,
                            style: GameTypography.label.copyWith(
                              color: colors.rewardInk,
                            ),
                          ),
                          Text(
                            '${reward.title.name.resolve(t.localeName)} · ${reward.trail.name.resolve(t.localeName)}',
                            style: GameTypography.body,
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final (index, stage) in all.indexed)
                  if (chapter == null || stage.chapter == chapter)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _TrialTile(
                        stage: stage,
                        number: index + 1,
                        best: session.trialProgress.bestMoves(stage),
                        onTap: _opening ? null : () => _play(stage),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TrialTile extends StatelessWidget {
  const _TrialTile({
    required this.stage,
    required this.number,
    required this.best,
    required this.onTap,
  });
  final TrialStage stage;
  final int number;
  final int? best;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final icon = switch (stage.condition) {
      TrialCondition.moveLimit => Icons.timelapse_rounded,
      TrialCondition.noUndo => Icons.undo_rounded,
      TrialCondition.noPowers => Icons.pan_tool_outlined,
    };
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: ValueKey('trial-stage-${stage.sourceId}'),
        onTap: onTap,
        leading: Icon(
          best == null ? icon : Icons.check_circle_rounded,
          color: best == null ? colors.echoInk : colors.goalInk,
        ),
        title: Text(t.trialNumber(number), style: GameTypography.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              trialConditionLabel(t, stage),
              style: GameTypography.label.copyWith(color: colors.echoInk),
            ),
            Text(
              t.trialSource(
                Worlds.stageNumber(stage.sourceId),
                stage.minimumMoves,
              ),
            ),
            if (best case final moves?)
              Text(
                t.bestMoves(moves),
                style: GameTypography.label.copyWith(color: colors.goalInk),
              ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: colors.secondaryText,
        ),
      ),
    );
  }
}
