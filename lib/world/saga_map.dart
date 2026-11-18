import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../l10n/app_localizations.dart';
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SagaRoad(
            session: session,
            onEnter: selectable
                ? (world) => Navigator.of(context).pop(world)
                : null,
          ),
        ),
      ),
    );
  }
}

/// 빛길 지도의 본문: 사가 제목과 줄거리, 켜진 등대 수, 세계를 잇는 줄.
/// 여정의 현황 탭과 [SagaMap] 화면이 같이 쓴다.
class SagaRoad extends StatelessWidget {
  const SagaRoad({
    super.key,
    required this.session,
    this.onEnter,
    this.focusWorld,
    this.focusLabel,
    this.tapCards = false,
  });

  final GameSession session;

  /// 들어가기를 눌렀을 때. null이면 들어가기 버튼을 그리지 않는다.
  final ValueChanged<int>? onEnter;

  /// 강조할 세계(이어서 할 곳)와 그 옆에 붙일 말.
  final int? focusWorld;
  final String? focusLabel;

  /// 카드 전체를 눌러도 들어가게 한다. 여정의 현황 탭에서 쓴다.
  final bool tapCards;

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

    int starsIn(int number) => number == 1
        ? session.totalStars
        : session
                  .worldAtlas(number)
                  ?.stages
                  .fold<int>(0, (sum, stage) => sum + stage.stars) ??
              0;

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
            stars: starsIn(world.number),
            focusLabel: world.number == focusWorld ? focusLabel : null,
            tapCard: tapCards,
            onEnter:
                onEnter != null &&
                    (stateOf(world) == _WorldState.open ||
                        stateOf(world) == _WorldState.restored)
                ? () => onEnter!(world.number)
                : null,
            lang: lang,
          ),
      ],
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
    required this.stars,
    required this.focusLabel,
    required this.tapCard,
    required this.onEnter,
    required this.lang,
  });
  final SagaWorld world;
  final _WorldState state;
  final bool revealed, last, tapCard;
  final int progress, stars;
  final String? focusLabel;
  final VoidCallback? onEnter;
  final String lang;

  /// 세계 카드의 껍데기. 여정에서는 카드 전체를 눌러 들어갈 수 있다.
  Widget _card(
    GameColors colors, {
    required bool focused,
    required Color accent,
    required Widget child,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(
        color: focused ? colors.reward : accent.withValues(alpha: .45),
        width: focused ? 1.5 : 1,
      ),
    );
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      child: child,
    );
    return Material(
      key: ValueKey('saga-world-${world.number}'),
      color: focused
          ? colors.reward.withValues(alpha: .1)
          : state == _WorldState.open
          ? colors.goal.withValues(alpha: .1)
          : colors.surface.withValues(alpha: .6),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: tapCard
          ? InkWell(
              key: ValueKey('journey-world-${world.number}'),
              onTap: onEnter,
              child: body,
            )
          : body,
    );
  }

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
      _WorldState.restored =>
        world.lighthouse != null
            ? world.theme?.palette?.accent ?? colors.reward
            : colors.reward,
      _WorldState.open => colors.goal,
      _ => colors.outline,
    };
    final t = AppLocalizations.of(context)!;
    // 들어가 본 세계에만 모은 별 수를 붙인다.
    final starText = state == _WorldState.restored || state == _WorldState.open
        ? t.journeyStarCount(stars, Worlds.stageCount * 3)
        : null;
    final status = switch (state) {
      _WorldState.restored => WorldText.restored.resolve(lang),
      _WorldState.open => WorldText.progress(
        progress,
        Worlds.stageCount,
      ).resolve(lang),
      _WorldState.locked => WorldText.lockedWorld.resolve(lang),
      _WorldState.planned => WorldText.comingSoon.resolve(lang),
    };
    final focused = focusLabel != null;
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
                      color: restored ? accent : accent.withValues(alpha: .14),
                      border: Border.all(color: accent, width: 2),
                      boxShadow: [
                        if (restored && world.lighthouse != null)
                          BoxShadow(
                            color: accent.withValues(alpha: .35),
                            blurRadius: 12,
                          ),
                      ],
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
                child: _card(
                  colors,
                  focused: focused,
                  accent: accent,
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
                                    fontSize: 13,
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
                      // 큰 글자에서는 다음 줄로 내려간다.
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          Text(
                            status,
                            style: GameTypography.label.copyWith(
                              fontSize: 13,
                              color: state == _WorldState.locked
                                  ? colors.secondaryText
                                  : colors.goalInk,
                            ),
                          ),
                          if (starText != null)
                            Text(
                              starText,
                              key: ValueKey('saga-stars-${world.number}'),
                              style: GameTypography.label.copyWith(
                                fontSize: 13,
                                color: colors.rewardInk,
                              ),
                            ),
                          if (focusLabel case final label?)
                            Text(
                              label,
                              key: ValueKey('saga-focus-${world.number}'),
                              style: GameTypography.label.copyWith(
                                fontSize: 13,
                                color: colors.rewardInk,
                              ),
                            ),
                        ],
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
