import 'dart:async';

import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';
import 'experience_dialogs.dart';
import 'intro_screen.dart';
import 'game_session.dart';
import '../story/spirit_album.dart';
import 'journey_panel.dart';
import 'play_context.dart';
import '../endless/endless_rules.dart';
import '../endless/endless_screen.dart';
import '../world/ending_screen.dart';
import '../world/world_catalog.dart';
import '../world/world_map.dart';
import '../world/world_text.dart';
import '../tutorial/world_tutorial.dart';
import '../trials/trial_catalog.dart';
import '../weekly/weekly_pool.dart';
import '../weekly/weekly_screen.dart';

enum _HomeMode { daily, weekly, voyage }

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
  Timer? _weeklyRefresh;
  final _modeRefresh = ValueNotifier(0);

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
      _scheduleWeeklyRefresh();
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
    if (state == AppLifecycleState.resumed && mounted) {
      _modeRefresh.value++;
      _scheduleWeeklyRefresh();
    }
  }

  void _scheduleWeeklyRefresh() {
    _weeklyRefresh?.cancel();
    final now = _session?.weekly.clock();
    if (now == null) return;
    _weeklyRefresh = Timer(nextWeeklyBoundary(now).difference(now), () {
      if (!mounted) return;
      _modeRefresh.value++;
      _scheduleWeeklyRefresh();
    });
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
    var nextId = levelId;
    var nextPlay = play;
    Object? result;
    try {
      // 다른 세계로 옮겨도 같은 플레이 흐름에서 테마와 보드를 새로 연다.
      while (mounted) {
        final id = nextId;
        final active = nextPlay;
        result = await Navigator.of(context).push<Object?>(
          PageRouteBuilder<Object?>(
            transitionDuration: transition,
            reverseTransitionDuration: transition,
            pageBuilder: (_, animation, secondaryAnimation) =>
                widget.gameBuilder(session, id, active),
            transitionsBuilder: (_, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
        if (!mounted || result is! OpenStage) break;
        final destination = _campaignContext(session, result.levelId);
        if (destination == null) break;
        nextId = result.levelId;
        nextPlay = destination;
        session.audio.setMusicTrack(
          session.saga?.world(destination.world).theme?.bgm,
        );
      }
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
    } else if (result is OpenEnding && mounted) {
      await showEnding(context, session, widget.settings);
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
    try {
      await showStarseaVoyage(context, session, widget.settings);
    } finally {
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
      final id = await showWorldMap(
        context,
        session,
        world,
        buildTrialGame: _buildTrialGame,
      );
      if (id != null && mounted) {
        await _open(id, play: PlayContext.world(world));
      }
    } finally {
      session.audio.setGameVisible(false);
      _choosing = false;
      if (mounted) setState(() {});
    }
  }

  Widget _buildTrialGame(TrialStage stage, Level board) =>
      widget.gameBuilder(_session!, board.id, PlayContext.trial(stage, board));

  Future<void> _journey() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showJourneyPanel(
        context,
        session,
        widget.settings,
        buildTrialGame: _buildTrialGame,
      );
      if (id != null && mounted) await _openLevel(id);
    } finally {
      _choosing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _openPlayModes(GameSession session) async {
    if (_opening || _choosing) return;
    _choosing = true;
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    _HomeMode? mode;
    try {
      mode = await showDialog<_HomeMode>(
        context: context,
        animationStyle: prefersReducedMotion(context, widget.settings)
            ? AnimationStyle.noAnimation
            : null,
        builder: (dialogContext) => ValueListenableBuilder(
          valueListenable: _modeRefresh,
          builder: (_, _, _) => AlertDialog(
            key: const ValueKey('play-modes'),
            title: Text(t.homePlayModes),
            scrollable: true,
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dailyTile(t, colors, session, () {
                    Navigator.pop(dialogContext, _HomeMode.daily);
                  }),
                  const SizedBox(height: GameSpacing.small),
                  _weeklyTile(t, colors, session, () {
                    Navigator.pop(dialogContext, _HomeMode.weekly);
                  }),
                  const SizedBox(height: GameSpacing.small),
                  _voyageTile(t, colors, session, () {
                    Navigator.pop(dialogContext, _HomeMode.voyage);
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('play-modes-close'),
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(t.close),
              ),
            ],
          ),
        ),
      );
    } finally {
      _choosing = false;
    }
    if (!mounted) return;
    await switch (mode) {
      _HomeMode.daily => _openDaily(session),
      _HomeMode.weekly => _openWeekly(session),
      _HomeMode.voyage => _openEndless(),
      null => Future<void>.value(),
    };
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
    _weeklyRefresh?.cancel();
    _modeRefresh.dispose();
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
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, .46, .82, 1],
              colors: [
                colors.background.withValues(alpha: .30),
                colors.background.withValues(alpha: .15),
                colors.background.withValues(alpha: .96),
                colors.background,
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
                  child: LayoutBuilder(
                    builder: (context, area) {
                      final target = session?.continueTarget;
                      final ready =
                          session != null && target != null && !_opening;
                      final scroll =
                          area.maxHeight < 480 ||
                          MediaQuery.textScalerOf(context).scale(10) > 14;
                      final hero = Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Image.asset(
                            StarArt.riq,
                            width: 138,
                            height: 138,
                            cacheWidth: 384,
                            fit: BoxFit.contain,
                            excludeFromSemantics: true,
                          ),
                        ),
                      );
                      final id = target?.levelId;
                      final column = Column(
                        mainAxisSize: scroll
                            ? MainAxisSize.min
                            : MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _homeHeader(t, session),
                          if (scroll)
                            SizedBox(height: 160, child: hero)
                          else
                            Expanded(child: hero),
                          if (session != null && target != null && id != null)
                            Text(
                              t.journeyStageLocation(
                                session.saga
                                        ?.world(target.world)
                                        .title
                                        .inLocale(t.localeName) ??
                                    t.journeyFirstWorld,
                                target.world == 1 ? id : Worlds.stageNumber(id),
                              ),
                              key: const ValueKey('home-destination'),
                              textAlign: TextAlign.center,
                              style: GameTypography.label.copyWith(
                                fontSize: 18,
                              ),
                            ),
                          if (session != null) ..._notices(t, session),
                          if (_failed) ...[
                            Text(t.loadError, textAlign: TextAlign.center),
                            TextButton.icon(
                              key: const ValueKey('retry-load'),
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: Text(t.retry),
                            ),
                          ],
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            key: const ValueKey('home-play'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(48, 54),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onPressed: ready ? () => _continue(target) : null,
                            icon: Icon(
                              target?.kind == ContinueKind.voyage
                                  ? Icons.sailing_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            label: Text(
                              switch (target?.kind) {
                                ContinueKind.polish => t.homeMoreStars,
                                ContinueKind.voyage =>
                                  EndlessText.title.resolve(t.localeName),
                                ContinueKind.replay => t.homeReplayStage,
                                ContinueKind.next || ContinueKind.newWorld =>
                                  WorldText.play.resolve(t.localeName),
                                null => t.preparingGame,
                              },
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 20),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Divider(color: colors.outline.withValues(alpha: .3)),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton(
                                  key: const ValueKey('home-journey'),
                                  onPressed: ready ? _journey : null,
                                  child: Text(
                                    t.journey,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                              Container(
                                height: 24,
                                width: 1,
                                color: colors.outline.withValues(alpha: .3),
                              ),
                              Expanded(
                                child: TextButton(
                                  key: const ValueKey('home-play-modes'),
                                  onPressed: ready
                                      ? () => _openPlayModes(session)
                                      : null,
                                  child: Text(
                                    t.homePlayModes,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colors.secondaryText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
                    session,
                    resumeGame: false,
                  ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
    ),
  );

  /// "이어가기"를 눌렀을 때: 고른 판을 지도 없이 바로 연다.
  Future<void> _continue(ContinueTarget target) {
    final id = target.levelId;
    return id == null ? _openEndless() : _openLevel(id);
  }

  /// 세계 1 목록에 있는 판은 id와 상관없이 세계 1 판이다.
  PlayContext? _campaignContext(GameSession session, int id) {
    if (session.levels.any((level) => level.id == id)) {
      return const PlayContext.campaign();
    }
    final world = Worlds.worldOf(id);
    if (world < 2 ||
        !session.worldUnlocked(world) ||
        session.worldAtlas(world)?.isUnlocked(id) != true) {
      return null;
    }
    return PlayContext.world(world);
  }

  Future<void> _openLevel(int id) async {
    final session = _session;
    if (session == null) return;
    final play = _campaignContext(session, id);
    if (play != null) await _open(id, play: play);
  }

  Future<void> _openDaily(GameSession session) => _open(
    session.daily.today.level.id,
    play: PlayContext.daily(session.daily.today),
  );

  Future<void> _openWeekly(GameSession session) async {
    if (_opening || _choosing) return;
    _choosing = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => WeeklyScreen(
            session: session,
            onPlay: (stage) =>
                _open(stage.level.id, play: PlayContext.weekly(stage)),
          ),
        ),
      );
    } finally {
      _choosing = false;
      if (mounted) setState(() {});
    }
  }

  Widget _dailyTile(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
    VoidCallback onTap,
  ) {
    final daily = session.daily;
    final challenge = daily.today;
    final done = daily.completed(challenge.date);
    final perfect =
        daily.bestMoves(challenge.date) == challenge.level.minimumMoves;
    return _modeTile(
      key: const ValueKey('daily-play'),
      icon: done ? Icons.stars_rounded : Icons.auto_awesome_rounded,
      color: colors.echo,
      ink: colors.echoInk,
      title: done ? t.dailyReplay : t.dailyPlay,
      detail: perfect
          ? t.dailyPerfect
          : WorldText.dailyGoal(challenge.level.minimumMoves)
                .resolve(t.localeName),
      onTap: onTap,
    );
  }

  Widget _weeklyTile(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
    VoidCallback onTap,
  ) {
    final count = session.weekly.cleared(session.weekly.currentKey);
    return _modeTile(
      key: const ValueKey('home-weekly'),
      icon: count == WeeklyPool.stageCount
          ? Icons.stars_rounded
          : Icons.auto_awesome_outlined,
      color: colors.reward,
      ink: colors.rewardInk,
      title: t.weeklyTitle,
      detail: t.weeklyProgress(count),
      onTap: onTap,
    );
  }

  /// 별바다 항해 입구. 최고 기록이나 이어서 할 항해를 함께 보여 준다.
  Widget _voyageTile(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
    VoidCallback onTap,
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
        : EndlessText.start.resolve(lang);
    return _modeTile(
      key: const ValueKey('home-voyage'),
      icon: unlocked ? Icons.sailing_rounded : Icons.lock_outline_rounded,
      color: colors.cyan,
      ink: unlocked ? colors.cyan : colors.secondaryText,
      title: EndlessText.title.resolve(lang),
      detail: detail,
      dim: !unlocked,
      onTap: onTap,
    );
  }

  /// 곁가지 플레이 입구 한 칸: 이름 한 줄, 지금 상태 한 줄.
  Widget _modeTile({
    required Key key,
    required IconData icon,
    required Color color,
    required Color ink,
    required String title,
    required String detail,
    required VoidCallback? onTap,
    bool dim = false,
  }) {
    final colors = GameTheme.colorsOf(context);
    return Material(
      color: color.withValues(alpha: dim ? .06 : .16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: dim ? .2 : .55)),
      ),
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        // 큰 글자에서는 칸이 글자만큼 높아진다.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Icon(icon, color: ink, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: GameTypography.label.copyWith(
                          fontSize: 15,
                          color: dim ? colors.secondaryText : colors.text,
                        ),
                      ),
                      Text(
                        detail,
                        style: GameTypography.body.copyWith(
                          fontSize: 12.5,
                          height: 1.15,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 저장과 이전에 관한 안내는 홈에서도 바로 확인할 수 있다.
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
    CollectionStorageNotice(session: session, onChanged: () => setState(() {})),
    if (session.progress.saveFailed || session.onboarding.saveFailed)
      Text(t.saveError, textAlign: TextAlign.center),
  ];
}
