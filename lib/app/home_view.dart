import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constellation/constellation_atlas.dart';
import '../constellation/constellation_state.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../progress/player_repository.dart';
import '../story/companion_view.dart';
import '../story/spirit_album.dart';
import 'game_session.dart';

/// 앱을 켤 때마다 도착하는 메인 화면. 일반 휴대폰에서는 스크롤 없이 한 화면에
/// 들어가고, 작은 화면이나 큰 글꼴에서만 스크롤한다.
class HomeView extends StatelessWidget {
  const HomeView({
    super.key,
    required this.session,
    required this.failed,
    required this.opening,
    required this.reduceMotion,
    required this.onPlay,
    required this.onLevels,
    required this.onAlbum,
    required this.onAtlas,
    required this.onDaily,
    required this.onHelp,
    required this.onSettings,
    required this.onRetry,
    required this.onChanged,
  });

  final GameSession? session;
  final bool failed, opening, reduceMotion;
  final VoidCallback onPlay, onLevels, onAlbum, onAtlas, onDaily;
  final VoidCallback onHelp, onSettings, onRetry, onChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('home-screen'),
    body: ArcadeBackdrop(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              // 폭을 먼저 정해야 IntrinsicHeight가 글줄 수를 바르게 계산한다.
              width: math.min(box.maxWidth, 560),
              child: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.all(GameSpacing.page),
                      child: _content(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = this.session;
    final tutorial =
        session != null &&
        session.onboarding.pending &&
        session.levels.any((level) => level.id == 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: session == null
                  ? const Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: BrandMark(),
                      ),
                    )
                  : _PlayerBadge(level: session.player.level),
            ),
            IconButton(
              tooltip: t.help,
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline_rounded),
            ),
            IconButton(
              tooltip: t.settings,
              onPressed: session == null ? null : onSettings,
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ),
        const SizedBox(height: GameSpacing.small),
        Text(
          t.lastEchoTitle,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 34,
            fontFamily: GameTypography.canvasFontFamily,
            height: 1.15,
            color: colors.rewardInk,
          ),
        ),
        const Spacer(),
        if (session != null) _hero(context, session),
        if (session == null && failed) ...[
          Text(t.loadError, textAlign: TextAlign.center),
          TextButton.icon(
            key: const ValueKey('retry-load'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t.retry),
          ),
        ] else if (session == null)
          const LinearProgressIndicator(),
        const Spacer(),
        FilledButton.icon(
          key: const ValueKey('home-play'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 66),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: GameSpacing.page,
            ),
          ),
          onPressed: session == null || opening ? null : onPlay,
          icon: const Icon(Icons.play_arrow_rounded, size: 28),
          label: Text(
            session == null
                ? t.preparingGame
                : tutorial
                ? t.startGame
                : t.playLevel(session.nextLevelId),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21),
          ),
        ),
        const SizedBox(height: GameSpacing.large),
        if (session != null) ...[
          _menu(context, session),
          CollectionStorageNotice(session: session, onChanged: onChanged),
          if (session.progress.saveFailed || session.onboarding.saveFailed)
            Padding(
              padding: const EdgeInsets.only(top: GameSpacing.small),
              child: Text(t.saveError, textAlign: TextAlign.center),
            ),
        ],
      ],
    );
  }

  Widget _hero(BuildContext context, GameSession session) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final chapter = session.recommendedChapter;
    final constellation = ConstellationAtlas.derive(
      session.levels,
      session.progress,
    ).forChapter(chapter.number);
    return Column(
      children: [
        Semantics(
          button: true,
          label: t.constellationAtlas,
          child: InkWell(
            key: const ValueKey('home-hero'),
            borderRadius: BorderRadius.circular(GameSpacing.radius),
            onTap: opening ? null : onAtlas,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (constellation != null)
                  SizedBox(
                    width: 230,
                    height: 112,
                    child: ExcludeSemantics(
                      child: ConstellationArt(
                        chapter: constellation,
                        guardianAsset: guardianAssetFor(session, constellation),
                      ),
                    ),
                  ),
                JourneyCompanions(
                  companion: session.collection.companion,
                  reduceMotion: reduceMotion,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: GameSpacing.small),
        Text(
          chapter.name.inLocale(t.localeName),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: GameSpacing.tiny),
        Semantics(
          label: t.homeProgress,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: GameSpacing.page,
            runSpacing: GameSpacing.tiny,
            children: [
              if (constellation != null)
                Text(
                  t.constellationLit(
                    constellation.litCount,
                    constellation.levels.length,
                  ),
                  style: TextStyle(color: colors.secondaryText),
                ),
              Text(
                t.completedLevels(
                  session.completedCount,
                  session.levels.length,
                ),
                style: TextStyle(color: colors.secondaryText),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 18, color: colors.rewardInk),
                  const SizedBox(width: GameSpacing.tiny),
                  Text(
                    t.collectedStars(session.totalStars),
                    style: TextStyle(color: colors.rewardInk),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (session.collection.owned.length == 25)
          Text(t.seasonComplete, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _menu(BuildContext context, GameSession session) {
    final t = AppLocalizations.of(context)!;
    final collection = session.collection;
    return Row(
      children: [
        _MenuTile(
          id: 'home-levels',
          icon: Icons.route_rounded,
          label: t.menuMap,
          onTap: opening ? null : onLevels,
        ),
        _MenuTile(
          id: 'home-album',
          icon: Icons.auto_stories_outlined,
          label: t.menuAlbum,
          badge: collection.pendingIds.isNotEmpty || collection.backfillPending,
          onTap: onAlbum,
        ),
        _MenuTile(
          id: 'home-atlas',
          icon: Icons.auto_awesome,
          label: t.menuAtlas,
          onTap: opening ? null : onAtlas,
        ),
        _MenuTile(
          id: 'home-daily',
          icon: Icons.today_rounded,
          label: t.menuDaily,
          badge: !session.daily.completed(session.daily.today.date),
          onTap: opening ? null : onDaily,
        ),
      ],
    );
  }
}

class _PlayerBadge extends StatelessWidget {
  const _PlayerBadge({required this.level});
  final PlayerLevel level;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    return Semantics(
      label:
          '${level.title(t)}. ${t.playerProgress(level.level, level.into, level.needed)}',
      excludeSemantics: true,
      child: Column(
        key: const ValueKey('home-player'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${t.playerLevel(level.level)}  ${level.title(t)}',
              style: GameTypography.label.copyWith(color: colors.rewardInk),
            ),
          ),
          const SizedBox(height: GameSpacing.tiny),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: level.fraction,
              color: colors.goal,
              backgroundColor: colors.goal.withValues(alpha: .15),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = false,
  });
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GameSpacing.tiny),
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey(id),
            borderRadius: BorderRadius.circular(GameSpacing.radius),
            onTap: onTap,
            child: ArcadeSurface(
              padding: const EdgeInsets.symmetric(
                vertical: GameSpacing.medium,
                horizontal: GameSpacing.tiny,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(icon, size: 26, color: colors.rewardInk),
                      if (badge)
                        Positioned(
                          right: -4,
                          top: -2,
                          child: Container(
                            key: ValueKey('$id-badge'),
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colors.goal,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: colors.surface,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: GameSpacing.tiny),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label, style: GameTypography.label),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
