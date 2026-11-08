import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import 'saga.dart';
import 'world_catalog.dart';
import 'world_text.dart';

/// 빛길 지도: 모든 세계를 한 줄로 잇는 사가 진행판.
/// 들어갈 세계 번호를 돌려준다(닫거나 [selectable]이 false면 null).
Future<int?> showSagaMap(
  BuildContext context,
  GameSession session, {
  bool selectable = true,
}) => Navigator.of(context).push<int>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => SagaMap(session: session, selectable: selectable),
  ),
);

enum _WorldState { restored, open, locked, planned }

class SagaMap extends StatelessWidget {
  const SagaMap({super.key, required this.session, this.selectable = true});
  final GameSession session;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final saga = session.saga!;
    final completed = session.progression.completedChapters;
    _WorldState stateOf(SagaWorld world) {
      if (!world.playable) return _WorldState.planned;
      if (Worlds.isComplete(world.number, completed)) {
        return _WorldState.restored;
      }
      return session.worldUnlocked(world.number)
          ? _WorldState.open
          : _WorldState.locked;
    }

    // 아직 마치지 못한 첫 세계. 예고와 새 규칙은 여기까지와 바로 다음 세계만
    // 보여 주고, 더 먼 세계는 이름만 남겨 궁금증을 아낀다.
    final frontier =
        saga.worlds
            .where((world) => !Worlds.isComplete(world.number, completed))
            .firstOrNull
            ?.number ??
        saga.worlds.length;
    final lit = saga.worlds
        .where(
          (world) =>
              world.lighthouse != null &&
              Worlds.isComplete(world.number, completed),
        )
        .length;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        title: Text(
          WorldText.sagaMap.resolve(lang),
          style: GameTypography.reward.copyWith(color: colors.rewardInk),
        ),
        leading: IconButton(
          key: const ValueKey('saga-close'),
          tooltip: WorldText.close.resolve(lang),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              saga.title.inLocale(lang),
              textAlign: TextAlign.center,
              style: GameTypography.reward.copyWith(
                fontSize: 22,
                color: colors.rewardInk,
              ),
            ),
            const SizedBox(height: 4),
            KeepAllText(
              saga.premise.inLocale(lang),
              textAlign: TextAlign.center,
              style: GameTypography.body.copyWith(
                fontSize: 14,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Container(
                key: const ValueKey('saga-lit'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colors.reward.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  WorldText.litCount(lit).resolve(lang),
                  style: GameTypography.label.copyWith(color: colors.rewardInk),
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final world in saga.worlds)
              _WorldNode(
                world: world,
                state: stateOf(world),
                revealed: world.number <= frontier + 1,
                last: world.number == saga.worlds.length,
                progress: session.clearedInWorld(world.number),
                onEnter:
                    selectable &&
                        (stateOf(world) == _WorldState.open ||
                            stateOf(world) == _WorldState.restored)
                    ? () => Navigator.of(context).pop(world.number)
                    : null,
                lang: lang,
              ),
          ],
        ),
      ),
    );
  }
}

class _WorldNode extends StatelessWidget {
  const _WorldNode({
    required this.world,
    required this.state,
    required this.revealed,
    required this.last,
    required this.progress,
    required this.onEnter,
    required this.lang,
  });
  final SagaWorld world;
  final _WorldState state;
  final bool revealed, last;
  final int progress;
  final VoidCallback? onEnter;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final restored = state == _WorldState.restored;
    final icon = world.number == 1
        ? Icons.forest_rounded
        : world.lighthouse != null
        ? Icons.light_rounded
        : Icons.auto_awesome_rounded;
    final accent = switch (state) {
      _WorldState.restored => colors.reward,
      _WorldState.open => colors.goal,
      _ => colors.outline,
    };
    final status = switch (state) {
      _WorldState.restored => WorldText.restored.resolve(lang),
      _WorldState.open => WorldText.progress(
        progress,
        Worlds.stageCount,
      ).resolve(lang),
      _WorldState.locked => WorldText.lockedWorld.resolve(lang),
      _WorldState.planned => WorldText.comingSoon.resolve(lang),
    };
    final details = <Widget>[
      // 지나온 세계는 풀린 수수께끼, 앞으로 갈 세계는 예고를 보여 준다.
      if (restored)
        KeepAllText(
          world.reveal.inLocale(lang),
          style: GameTypography.body.copyWith(fontSize: 13.5),
        )
      else if (revealed) ...[
        KeepAllText(
          world.teaser.inLocale(lang),
          style: GameTypography.body.copyWith(fontSize: 13.5),
        ),
        if (state == _WorldState.planned)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: KeepAllText(
              '${WorldText.newRule.resolve(lang)} · '
              '${world.mechanic.inLocale(lang)}',
              style: GameTypography.body.copyWith(
                fontSize: 13,
                color: colors.goalInk,
              ),
            ),
          ),
      ],
    ];
    return Semantics(
      container: true,
      label: '${world.title.inLocale(lang)}, $status',
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: restored
                          ? colors.reward
                          : accent.withValues(alpha: .14),
                      border: Border.all(color: accent, width: 2),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: restored ? colors.background : accent,
                    ),
                  ),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 3,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: restored
                            ? colors.reward.withValues(alpha: .7)
                            : colors.outline.withValues(alpha: .35),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  key: ValueKey('saga-world-${world.number}'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                  decoration: BoxDecoration(
                    color: state == _WorldState.open
                        ? colors.goal.withValues(alpha: .1)
                        : colors.surface.withValues(alpha: .6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent.withValues(alpha: .45)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  world.title.inLocale(lang),
                                  style: GameTypography.reward.copyWith(
                                    fontSize: 18,
                                    color: colors.rewardInk,
                                  ),
                                ),
                                Text(
                                  revealed
                                      ? world.subtitle.inLocale(lang)
                                      : WorldText.mystery.resolve(lang),
                                  style: GameTypography.label.copyWith(
                                    fontSize: 12.5,
                                    color: colors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (onEnter != null)
                            FilledButton.tonal(
                              key: ValueKey('saga-enter-${world.number}'),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(48, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                              ),
                              onPressed: onEnter,
                              child: Text(WorldText.enterWorld.resolve(lang)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        status,
                        style: GameTypography.label.copyWith(
                          fontSize: 13,
                          color: state == _WorldState.locked
                              ? colors.secondaryText
                              : colors.goalInk,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        ...details,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
