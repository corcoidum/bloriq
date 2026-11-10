import 'dart:async';

import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'experience_dialogs.dart';
import 'intro_screen.dart';
import 'game_session.dart';
import '../story/companion_view.dart';
import '../story/spirit_album.dart';
import '../constellation/constellation_atlas.dart';
import 'journey_panel.dart';
import 'level_picker.dart';
import '../constellation/constellation_state.dart';
import 'play_context.dart';
import '../endless/endless_rules.dart';
import '../endless/endless_screen.dart';
import '../world/saga_map.dart';
import '../world/world_map.dart';
import '../world/world_text.dart';
import '../tutorial/world_tutorial.dart';
import '../daily/daily_panel.dart';

class AppEntry extends StatefulWidget {
  const AppEntry({
    super.key,
    required this.settings,
    required this.gameBuilder,
    this.loadLevels,
    this.clock,
    this.playtestMode = const bool.fromEnvironment('PLAYTEST_MODE'),
    this.firstRunIntro = true,
  });
  final GameSettings settings;
  final DateTime Function()? clock;
  final bool playtestMode;

  /// 처음 실행한 사용자에게만 인트로를 한 번 보여 준 뒤 튜토리얼로 잇는다.
  final bool firstRunIntro;
  final Future<List<Level>> Function()? loadLevels;
  final Widget Function(GameSession session, int levelId, PlayContext play)
  gameBuilder;

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> with WidgetsBindingObserver {
  bool _entryResolved = false;
  bool _startingTutorial = false;
  bool _introPlaying = false;
  bool _failed = false;
  bool _opening = false;
  bool _loading = false;
  bool _choosing = false;
  GameSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final session = await GameSession.load(
        loadLevels: widget.loadLevels,
        clock: widget.clock,
        onOnboardingReady: (onboarding) {
          if (mounted && !_entryResolved) {
            setState(() {
              _entryResolved = true;
              _startingTutorial = onboarding.pending;
              // 'unseen'만 해당한다. 튜토리얼을 열면 inProgress가 되어 다시 나오지 않는다.
              _introPlaying =
                  widget.firstRunIntro && onboarding.status == 'unseen';
            });
          }
        },
      );
      if (!mounted) {
        unawaited(session.dispose());
        return;
      }
      setState(() {
        _session = session;
        _loading = false;
      });
      if (!session.levels.any((level) => level.id == 1)) {
        _startingTutorial = false;
      }
      _startTutorial();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _introFinished() {
    if (!mounted || !_introPlaying) return;
    setState(() => _introPlaying = false);
    _startTutorial();
  }

  void _startTutorial() {
    final session = _session;
    // 인트로가 끝날 때 다시 호출되므로 그동안은 튜토리얼을 열지 않는다.
    if (_introPlaying ||
        session == null ||
        (widget.playtestMode && !session.analytics.consentKnown)) {
      return;
    }
    if (session.onboarding.pending &&
        session.levels.any((level) => level.id == 1)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _open(
            1,
            play: const PlayContext.campaign(guided: true),
            userInitiated: false,
          );
        }
      });
    }
  }

  Future<void> _consent(bool value) async {
    final session = _session;
    if (session == null) return;
    await session.analytics.setEnabled(value);
    if (mounted) {
      setState(() {});
      _startTutorial();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) setState(() {});
  }

  void _retry() {
    if (_loading) return;
    setState(() => _failed = false);
    _load();
  }

  Future<void> _open(
    int levelId, {
    PlayContext play = const PlayContext.campaign(),
    bool userInitiated = true,
  }) async {
    final session = _session;
    if (_opening || session == null) return;
    setState(() {
      _opening = true;
      _startingTutorial = false;
    });
    session.audio.setMusicTrack(session.saga?.world(play.world).theme?.bgm);
    session.audio.setGameVisible(true);
    if (userInitiated) session.audio.onUserInteraction();
    final transition =
        !userInitiated || prefersReducedMotion(context, widget.settings)
        ? Duration.zero
        : GameEffects.panelDuration;
    Object? result;
    try {
      result = await Navigator.of(context).push<Object?>(
        PageRouteBuilder<Object?>(
          transitionDuration: transition,
          reverseTransitionDuration: transition,
          pageBuilder: (_, animation, secondaryAnimation) =>
              widget.gameBuilder(session, levelId, play),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      session.audio.setGameVisible(false);
      if (mounted) setState(() => _opening = false);
    }
    // 세계를 막 마치고 "다음 세계로"를 눌렀으면 그 세계 지도를 바로 연다.
    // 스테이지 선택 화면에서 들어왔다면 그 흐름이 끝난 뒤에 열어야
    // 선택 중 잠금(_choosing)에 막히지 않는다.
    if (result case OpenWorld(:final world)) {
      unawaited(
        Future<void>(() async {
          if (mounted) await _openWorld(world);
        }),
      );
    }
  }

  /// 별바다 항해(끝없는 모드). 잠겨 있으면 여는 조건을 알려 준다.
  Future<void> _openEndless() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    final lang = AppLocalizations.of(context)!.localeName;
    if (!session.endlessUnlocked) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(EndlessText.locked.resolve(lang))));
      return;
    }
    setState(() => _opening = true);
    session.audio.setMusicTrack(null);
    session.audio.setGameVisible(true);
    session.audio.onUserInteraction();
    final transition = prefersReducedMotion(context, widget.settings)
        ? Duration.zero
        : GameEffects.panelDuration;
    try {
      await Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          transitionDuration: transition,
          reverseTransitionDuration: transition,
          pageBuilder: (_, animation, secondaryAnimation) =>
              EndlessScreen(session: session, settings: widget.settings),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } finally {
      session.audio.setGameVisible(false);
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openWorld(int world) async {
    final session = _session;
    if (session == null ||
        _opening ||
        _choosing ||
        world < 2 ||
        !session.worldUnlocked(world)) {
      return;
    }
    _choosing = true;
    session.audio.setMusicTrack(session.world(world)?.info.theme?.bgm);
    session.audio.setGameVisible(true);
    session.audio.onUserInteraction();
    try {
      final id = await showWorldMap(context, session, world);
      if (id != null && mounted) {
        await _open(id, play: PlayContext.world(world));
      }
    } finally {
      session.audio.setGameVisible(false);
      _choosing = false;
      if (mounted) setState(() {});
    }
  }

  /// 빛길 지도에서 고른 세계로 간다. 세계 1은 스테이지 선택을 연다.
  Future<void> _openSaga() async {
    final session = _session;
    if (session == null || session.saga == null || _opening || _choosing) {
      return;
    }
    _choosing = true;
    int? world;
    try {
      world = await showSagaMap(context, session);
    } finally {
      _choosing = false;
    }
    if (!mounted || world == null) {
      if (mounted) setState(() {});
      return;
    }
    if (world == 1) {
      await _chooseLevel();
    } else {
      await _openWorld(world);
    }
  }

  Future<void> _chooseLevel() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showLevelPicker(
        context,
        session,
        widget.settings,
        currentLevelId: session.nextLevelId,
      );
      if (id != null && mounted) await _open(id);
    } finally {
      _choosing = false;
    }
  }

  Future<void> _album() async {
    if (_session == null) return;
    await showSpiritAlbum(context, _session!, widget.settings);
    if (mounted) setState(() {});
  }

  Future<void> _atlas() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showConstellationAtlas(
        context,
        session,
        widget.settings,
      );
      if (id != null && mounted) await _open(id);
    } finally {
      _choosing = false;
    }
  }

  Future<void> _journey() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showJourneyPanel(context, session, widget.settings);
      if (mounted) setState(() {});
      if (id != null && mounted) await _open(id);
    } finally {
      _choosing = false;
    }
  }

  Future<void> _help() async {
    final session = _session;
    final replay = await showGameHelp(
      context,
      widget.settings,
      worldGuides: [
        for (final guide in WorldTutorial.values)
          if (session?.worldUnlocked(guide.world) ?? false) guide,
      ],
    );
    if (!mounted) return;
    if (replay?.worldGuide case final tutorial?) {
      await showWorldTutorial(context, widget.settings, tutorial);
    } else if (replay == GameHelpAction.echo && session != null) {
      await _open(
        1,
        play: PlayContext.tutorialReplay(
          session.levels.firstWhere((level) => level.id == 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_session?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_entryResolved) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (widget.playtestMode &&
        _session != null &&
        !_session!.analytics.consentKnown) {
      final t = AppLocalizations.of(context)!;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    t.playtestTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(t.playtestPrivacy),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const ValueKey('consent-accept'),
                    onPressed: () => _consent(true),
                    child: Text(t.playtestConsent),
                  ),
                  TextButton(
                    key: const ValueKey('consent-decline'),
                    onPressed: () => _consent(false),
                    child: Text(t.playWithoutRecording),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // 레벨과 기록은 인트로가 도는 동안 뒤에서 계속 불러온다.
    if (_introPlaying) {
      return IntroScreen(settings: widget.settings, onFinished: _introFinished);
    }
    if (_startingTutorial && !_failed) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final session = _session;
    return Scaffold(
      key: const ValueKey('home-screen'),
      body: ArcadeBackdrop(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  GameSpacing.page,
                  4,
                  GameSpacing.page,
                  GameSpacing.medium,
                ),
                child: LayoutBuilder(
                  builder: (context, area) {
                    // 보통 휴대폰에서는 한 화면에 고정하고, 아주 작은 화면이나 큰 글자에서만 스크롤한다.
                    final scroll =
                        area.maxHeight < 600 ||
                        area.maxHeight <
                            530 * MediaQuery.textScalerOf(context).scale(1) ||
                        MediaQuery.textScalerOf(context).scale(10) > 13;
                    final children = <Widget>[
                      _homeHeader(t, session),
                      const SizedBox(height: 6),
                      if (session != null) ...[
                        PlayerLevelCard(session: session),
                        const SizedBox(height: 6),
                        _playerStrip(t, colors, session),
                      ] else if (_failed)
                        Column(
                          children: [
                            Text(t.loadError),
                            TextButton.icon(
                              key: const ValueKey('retry-load'),
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(t.retry),
                            ),
                          ],
                        )
                      else
                        const LinearProgressIndicator(),
                      const SizedBox(height: GameSpacing.small),
                      if (scroll)
                        SizedBox(height: 320, child: _sky(t, colors, session))
                      else
                        Expanded(child: _sky(t, colors, session)),
                      if (session != null) ..._notices(t, session),
                      const SizedBox(height: GameSpacing.small),
                      FilledButton.icon(
                        key: const ValueKey('home-play'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 56),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onPressed: session == null || _opening
                            ? null
                            : () => _open(session.nextLevelId),
                        icon: const Icon(Icons.play_arrow_rounded, size: 27),
                        label: Text(
                          session == null
                              ? t.preparingGame
                              : t.playLevel(session.nextLevelId),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      if (session != null) ...[
                        const SizedBox(height: GameSpacing.small),
                        _voyageButton(t, colors, session),
                      ],
                      const SizedBox(height: GameSpacing.small),
                      _menuGrid(t, colors, session),
                      if (session != null) ...[
                        const SizedBox(height: GameSpacing.small),
                        DailyPanel(
                          compact: !scroll,
                          daily: session.daily,
                          onPlay: _opening
                              ? null
                              : () => _open(
                                  session.daily.today.level.id,
                                  play: PlayContext.daily(session.daily.today),
                                ),
                        ),
                      ],
                    ];
                    final column = Column(
                      mainAxisSize: scroll
                          ? MainAxisSize.min
                          : MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: children,
                    );
                    return scroll
                        ? SingleChildScrollView(child: column)
                        : column;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 가운데 BLORIQ, 왼쪽 도움말, 오른쪽 설정.
  Widget _homeHeader(AppLocalizations t, GameSession? session) => SizedBox(
    height: 52,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 52),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: GameWordmark(size: 34),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: t.help,
            onPressed: _help,
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: t.settings,
            onPressed: session == null
                ? null
                : () => showExperienceSettings(
                    context,
                    widget.settings,
                    session.audio,
                    resumeGame: false,
                    analytics: session.analytics,
                  ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    ),
  );

  /// 별바다 항해 입구. 최고 기록이나 이어서 할 항해를 함께 보여 준다.
  Widget _voyageButton(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
  ) {
    final lang = t.localeName;
    final unlocked = session.endlessUnlocked;
    final saved = session.endless.savedRun;
    final detail = !unlocked
        ? EndlessText.locked.resolve(lang)
        : saved != null
        ? '${EndlessText.resume.resolve(lang)} · '
              '${EndlessText.depth(saved.depth).resolve(lang)}'
        : session.endless.voyages > 0
        ? EndlessText.bestLine(
            session.endless.bestScore,
            session.endless.bestDepth,
          ).resolve(lang)
        : EndlessText.tagline.resolve(lang);
    return Material(
      color: colors.cyan.withValues(alpha: unlocked ? .16 : .06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: colors.cyan.withValues(alpha: unlocked ? .55 : .2),
        ),
      ),
      child: InkWell(
        key: const ValueKey('home-voyage'),
        borderRadius: BorderRadius.circular(18),
        onTap: _opening ? null : _openEndless,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Icon(
                unlocked ? Icons.sailing_rounded : Icons.lock_outline_rounded,
                color: unlocked ? colors.cyan : colors.secondaryText,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      EndlessText.title.resolve(lang),
                      style: GameTypography.label.copyWith(
                        fontSize: 17,
                        color: unlocked ? colors.text : colors.secondaryText,
                      ),
                    ),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GameTypography.body.copyWith(
                        fontSize: 14,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (unlocked)
                Icon(Icons.chevron_right_rounded, color: colors.cyan),
            ],
          ),
        ),
      ),
    );
  }

  /// 지금 갈 확장 세계 입구와 빛길 지도 버튼.
  Widget _worldRow(AppLocalizations t, GameSession session) {
    final current = session.currentExpansionWorld;
    final saga = session.saga!;
    final sagaButton = current == null
        ? FilledButton.tonalIcon(
            key: const ValueKey('saga-map'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 44)),
            onPressed: _opening ? null : _openSaga,
            icon: const Icon(Icons.timeline_rounded),
            label: Text(WorldText.sagaMap.resolve(t.localeName)),
          )
        : IconButton.filledTonal(
            key: const ValueKey('saga-map'),
            tooltip: WorldText.sagaMap.resolve(t.localeName),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 44),
            onPressed: _opening ? null : _openSaga,
            icon: const Icon(Icons.timeline_rounded),
          );
    if (current == null) return Center(child: sagaButton);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: FilledButton.tonalIcon(
            key: const ValueKey('world-entry'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 44)),
            onPressed: _opening ? null : () => _openWorld(current),
            icon: const Icon(Icons.light_rounded),
            label: Text(
              WorldText.enter(saga.world(current).title).resolve(t.localeName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 6),
        sagaButton,
      ],
    );
  }

  /// 진행 요약 한 줄: 완료 스테이지, 모은 별, 친구.
  Widget _playerStrip(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
  ) {
    Widget pill(IconData icon, String label, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: GameTypography.label.copyWith(
                    color: color,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      label: t.homeProgress,
      child: Row(
        children: [
          pill(
            Icons.flag_rounded,
            t.completedLevels(session.completedCount, session.levels.length),
            colors.goalInk,
          ),
          const SizedBox(width: 6),
          pill(
            Icons.star_rounded,
            t.collectedStars(session.totalStars),
            colors.rewardInk,
          ),
          const SizedBox(width: 6),
          pill(
            Icons.pets_rounded,
            t.journeyFriends(
              session.collection.owned.length,
              session.story.released.length,
            ),
            colors.echoInk,
          ),
        ],
      ),
    );
  }

  /// 지금 찾아가는 장의 별자리 하늘과 리크·동행 정령.
  Widget _sky(AppLocalizations t, GameColors colors, GameSession? session) {
    final chapterNumber = session?.recommendedChapter.number ?? 1;
    final atlas = session == null
        ? null
        : ConstellationAtlas.derive(session.levels, session.progress);
    final chapter = atlas == null || atlas.chapters.length < chapterNumber
        ? null
        : atlas.chapters[chapterNumber - 1];
    return Material(
      color: colors.surface.withValues(alpha: .55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.reward.withValues(alpha: .35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: session == null || _opening ? null : _atlas,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              if (session != null) ...[
                Text(
                  session.recommendedChapter.name.inLocale(t.localeName),
                  textAlign: TextAlign.center,
                  style: GameTypography.reward.copyWith(
                    fontSize: 20,
                    color: colors.rewardInk,
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value:
                          session.completedInChapter(
                            session.recommendedChapter.number,
                          ) /
                          5,
                      color: colors.goal,
                      backgroundColor: colors.outline.withValues(alpha: .25),
                    ),
                  ),
                ),
              ],
              Expanded(
                child: chapter == null
                    ? const SizedBox.expand()
                    : ConstellationArt(
                        chapter: chapter,
                        guardianAsset: guardianAssetFor(session!, chapter),
                      ),
              ),
              JourneyCompanions(
                companion: session?.collection.companion,
                reduceMotion: prefersReducedMotion(context, widget.settings),
                inline: true,
                compact: true,
                onAlbum: session == null ? null : _album,
              ),
              if (session != null && session.collection.owned.length == 25)
                Text(t.seasonComplete, textAlign: TextAlign.center),
              // 다섯 별자리를 모두 완성하면 예고 문구 대신 진짜 입구가 열린다.
              // 빛길 지도는 늘 곁에 두어 "다음엔 뭐가 있지?"에 답한다.
              if (session != null && session.saga != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _worldRow(t, session),
                )
              else if (session != null &&
                  session.progression.completedChapters.length >= 5)
                KeepAllText(
                  t.nextWorldTeaser,
                  textAlign: TextAlign.center,
                  style: GameTypography.body.copyWith(
                    fontSize: 13.5,
                    color: colors.goalInk,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 저장 문제나 새 기억처럼 알릴 것이 있을 때만 한 줄씩 보인다.
  List<Widget> _notices(AppLocalizations t, GameSession session) => [
    if (session.collection.backfillPending)
      Row(
        children: [
          Expanded(
            child: Text(
              t.backfillUpdated,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            key: const ValueKey('dismiss-backfill'),
            onPressed: () async {
              await session.collection.acknowledgeBackfill();
              if (mounted) setState(() {});
            },
            child: Text(t.backfillDismiss),
          ),
        ],
      ),
    if (session.collection.pendingIds.isNotEmpty)
      TextButton(
        onPressed: _album,
        child: Text(t.pendingMemories(session.collection.pendingIds.length)),
      ),
    CollectionStorageNotice(session: session, onChanged: () => setState(() {})),
    if (session.progress.saveFailed || session.onboarding.saveFailed)
      Text(t.saveError, textAlign: TextAlign.center),
  ];

  /// 여정·스테이지·별자리·앨범 메뉴 네 칸.
  Widget _menuGrid(
    AppLocalizations t,
    GameColors colors,
    GameSession? session,
  ) {
    Widget tile(
      Key key,
      IconData icon,
      String label,
      Color color,
      VoidCallback? onTap,
    ) => Expanded(
      child: Material(
        color: color.withValues(alpha: .12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: color.withValues(alpha: .35)),
        ),
        child: InkWell(
          key: key,
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 54,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: GameTypography.label.copyWith(color: colors.text),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final ready = session != null && !_opening;
    return Column(
      children: [
        Row(
          children: [
            tile(
              const ValueKey('home-journey'),
              Icons.menu_book_rounded,
              t.journey,
              colors.goalInk,
              ready ? _journey : null,
            ),
            const SizedBox(width: GameSpacing.small),
            tile(
              const ValueKey('home-levels'),
              Icons.route_rounded,
              t.journeyMap,
              colors.primaryInk,
              ready ? _chooseLevel : null,
            ),
          ],
        ),
        const SizedBox(height: GameSpacing.small),
        Row(
          children: [
            tile(
              const ValueKey('home-atlas'),
              Icons.auto_awesome,
              t.constellationAtlas,
              colors.rewardInk,
              ready ? _atlas : null,
            ),
            const SizedBox(width: GameSpacing.small),
            tile(
              const ValueKey('home-album'),
              Icons.auto_stories_outlined,
              t.album,
              colors.echoInk,
              session == null ? null : _album,
            ),
          ],
        ),
      ],
    );
  }
}
