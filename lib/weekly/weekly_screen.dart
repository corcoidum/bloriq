import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../constellation/constellation_catalog.dart';
import '../constellation/constellation_painter.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_rules.dart';
import 'weekly_pool.dart';
import 'weekly_repository.dart';

String weeklyRewardLabel(AppLocalizations t, int rotation) =>
    switch (weeklyRewards[rotation]) {
      TrailUnlock(:final trailId) => t.weeklyRewardTrail(
        trailById(trailId)!.name.resolve(t.localeName),
      ),
      TitleUnlock(:final titleId) => t.weeklyRewardTitle(
        titleById(titleId)!.name.resolve(t.localeName),
      ),
      _ => throw StateError('Invalid weekly reward'),
    };

class WeeklyScreen extends StatefulWidget {
  const WeeklyScreen({super.key, required this.session, required this.onPlay});

  final GameSession session;
  final Future<void> Function(WeeklyStage stage) onPlay;

  @override
  State<WeeklyScreen> createState() => _WeeklyScreenState();
}

class _WeeklyScreenState extends State<WeeklyScreen> {
  late final String _week = widget.session.weekly.currentKey;
  late Future<WeeklyChallenge?> _challenge = widget.session.openWeekly(_week);
  bool _playing = false;

  Future<void> _play(WeeklyStage stage) async {
    if (_playing) return;
    setState(() => _playing = true);
    try {
      await widget.onPlay(stage);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return Scaffold(
      key: const ValueKey('weekly-screen'),
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(
          t.weeklyTitle,
          style: GameTypography.reward.copyWith(color: colors.rewardInk),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<WeeklyChallenge?>(
          future: _challenge,
          builder: (context, snapshot) {
            final challenge = snapshot.data;
            if (challenge != null) return _list(t, colors, challenge);
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      snapshot.hasError ? t.loadError : t.saveError,
                      textAlign: TextAlign.center,
                    ),
                    TextButton(
                      onPressed: () => setState(
                        () => _challenge = widget.session.openWeekly(_week),
                      ),
                      child: Text(t.retry),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _list(
    AppLocalizations t,
    GameColors colors,
    WeeklyChallenge challenge,
  ) {
    final repository = widget.session.weekly;
    final stages = [
      for (var index = 0; index < WeeklyPool.stageCount; index++)
        challenge.stage(index),
    ];
    final lit = [
      for (final stage in stages) repository.bestMoves(stage) != null,
    ];
    final cleared = repository.cleared(_week);
    final complete = cleared == WeeklyPool.stageCount;
    final patterns = ConstellationCatalog.all;
    return ListView(
      key: const ValueKey('weekly-stages'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          t.weeklyWeekStarting(_week),
          style: GameTypography.label,
          textAlign: TextAlign.center,
        ),
        SizedBox(
          height: 112,
          child: CustomPaint(
            painter: ConstellationPainter(
              definition: patterns[weeklyOrdinal(_week) % patterns.length],
              lit: lit,
              colors: colors,
              golden: complete ? 1 : 0,
            ),
          ),
        ),
        Text(
          complete ? t.weeklyComplete : t.weeklyProgress(cleared),
          key: const ValueKey('weekly-progress'),
          style: GameTypography.reward.copyWith(color: colors.goalInk),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        ArcadeSurface(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.weeklyReward,
                style: GameTypography.label.copyWith(color: colors.rewardInk),
              ),
              Text(
                weeklyRewardLabel(t, challenge.rotation),
                style: GameTypography.body,
              ),
            ],
          ),
        ),
        for (final stage in stages)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('weekly-stage-${stage.index + 1}'),
                enabled: !_playing,
                onTap: _playing ? null : () => _play(stage),
                leading: Icon(
                  lit[stage.index]
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  color: lit[stage.index]
                      ? colors.reward
                      : colors.secondaryText,
                ),
                title: Text(
                  t.weeklyStage(stage.index + 1),
                  style: GameTypography.label,
                ),
                subtitle: Text(switch (repository.bestMoves(stage)) {
                  final best? => t.bestMoves(best),
                  null => t.minimumMovesChip(stage.level.minimumMoves),
                }),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
      ],
    );
  }
}
