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
import '../story/story_catalog.dart';
import '../constellation/constellation_atlas.dart';
import 'journey_panel.dart';
import 'level_picker.dart';
import '../constellation/constellation_painter.dart';
import '../constellation/constellation_state.dart';
import 'play_context.dart';
import '../endless/endless_rules.dart';
import '../endless/endless_screen.dart';
import '../world/ending_screen.dart';
import '../world/saga_map.dart';
import '../world/world_catalog.dart';
import '../world/world_map.dart';
import '../world/world_text.dart';
import '../tutorial/world_tutorial.dart';
import '../trials/trial_catalog.dart';
import '../daily/daily_panel.dart';
import '../weekly/weekly_pool.dart';
import '../weekly/weekly_screen.dart';

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
      setState(() {});
      _scheduleWeeklyRefresh();
    }
  }

  void _scheduleWeeklyRefresh() {
    _weeklyRefresh?.cancel();
    final now = _session?.weekly.clock();
    if (now == null) return;
    _weeklyRefresh = Timer(nextWeeklyBoundary(now).difference(now), () {
      if (!mounted) return;
      setState(() {});
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
        buildTrialGame: _buildTrialGame,
      );
      if (id != null && mounted) await _open(id);
    } finally {
      _choosing = false;
    }
  }

  Widget _buildTrialGame(TrialStage stage, Level board) =>
      widget.gameBuilder(_session!, board.id, PlayContext.trial(stage, board));

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
        allWorlds: true,
      );
      if (id != null && mounted) await _openLevel(id);
    } finally {
      _choosing = false;
    }
  }

  Future<void> _journey() async {
    final session = _session;
    if (session == null || _opening || _choosing) return;
    _choosing = true;
    try {
      final id = await showJourneyPanel(
        context,
        session,
        widget.settings,
        allWorlds: true,
      );
      if (mounted) setState(() {});
      if (id != null && mounted) await _openLevel(id);
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
    _weeklyRefresh?.cancel();
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
                    final target = session?.continueTarget;
                    final here = _here(t, colors, session, target);
                    final children = <Widget>[
                      _homeHeader(t, session),
                      const SizedBox(height: 6),
                      if (session != null)
                        PlayerLevelCard(session: session)
                      else if (_failed)
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
                        SizedBox(height: 320, child: here)
                      else
                        Expanded(child: here),
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
                        onPressed: session == null || target == null || _opening
                            ? null
                            : () => _continue(target),
                        icon: Icon(
                          target?.kind == ContinueKind.voyage
                              ? Icons.sailing_rounded
                              : Icons.play_arrow_rounded,
                          size: 27,
                        ),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            session == null || target == null
                                ? t.preparingGame
                                : _continueLabel(t, session, target),
                            maxLines: 1,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      ),
                      if (session != null) ...[
                        const SizedBox(height: 6),
                        _playerStrip(t, colors, session),
                        const SizedBox(height: GameSpacing.small),
                        if (!scroll) ...[
                          IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _dailyTile(t, colors, session)),
                                const SizedBox(width: GameSpacing.small),
                                Expanded(
                                  child: _weeklyTile(t, colors, session),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: GameSpacing.small),
                        ],
                        _voyageTile(t, colors, session),
                      ],
                      const SizedBox(height: GameSpacing.small),
                      _menuGrid(t, colors, session, target),
                      if (session != null && scroll) ...[
                        const SizedBox(height: GameSpacing.small),
                        DailyPanel(
                          daily: session.daily,
                          onPlay: _opening ? null : () => _openDaily(session),
                        ),
                        const SizedBox(height: GameSpacing.small),
                        _weeklyTile(t, colors, session),
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

  /// 판 id로 그 세계의 캠페인 판을 연다(세계 2부터는 101, 201 …).
  /// 세계 1 목록에 있는 판은 id와 상관없이 세계 1 판이다.
  Future<void> _openLevel(int id) async {
    final session = _session;
    if (session == null) return;
    final world = session.levels.any((level) => level.id == id)
        ? 1
        : Worlds.worldOf(id);
    if (world > 1 && !session.worldUnlocked(world)) return;
    await _open(
      id,
      play: world == 1
          ? const PlayContext.campaign()
          : PlayContext.world(world),
    );
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

  /// "이어가기" 문구. 버튼이 여는 판과 항상 같은 세계·번호를 말한다.
  String _continueLabel(
    AppLocalizations t,
    GameSession session,
    ContinueTarget target,
  ) {
    final lang = t.localeName;
    final id = target.levelId;
    if (id == null) return EndlessText.title.resolve(lang);
    final title = session.saga?.world(target.world).title;
    final stage = Worlds.stageNumber(id);
    // 아직 세계 1만 아는 플레이어에게는 세계 이름 없이 별문 번호만 보여 준다.
    final prelude = target.world == 1 && session.currentExpansionWorld == null;
    return switch (target.kind) {
      _ when title == null => t.playLevel(id),
      ContinueKind.polish => WorldText.polish(title, stage).resolve(lang),
      ContinueKind.newWorld => WorldText.newWorld(title, stage).resolve(lang),
      ContinueKind.next when !prelude => WorldText.continueIn(
        title,
        stage,
      ).resolve(lang),
      _ => t.playLevel(id),
    };
  }

  /// 오늘의 Echo 반 칸. 목표 수나 달성 여부를 함께 보여 준다.
  Widget _dailyTile(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
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
      onTap: _opening ? null : () => _openDaily(session),
    );
  }

  Widget _weeklyTile(
    AppLocalizations t,
    GameColors colors,
    GameSession session,
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
      onTap: _opening ? null : () => _openWeekly(session),
    );
  }

  /// 별바다 항해 입구. 최고 기록이나 이어서 할 항해를 함께 보여 준다.
  Widget _voyageTile(
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
        : EndlessText.start.resolve(lang);
    return _modeTile(
      key: const ValueKey('home-voyage'),
      icon: unlocked ? Icons.sailing_rounded : Icons.lock_outline_rounded,
      color: colors.cyan,
      ink: unlocked ? colors.cyan : colors.secondaryText,
      title: EndlessText.title.resolve(lang),
      detail: detail,
      dim: !unlocked,
      onTap: _opening ? null : _openEndless,
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
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          title,
                          maxLines: 1,
                          style: GameTypography.label.copyWith(
                            fontSize: 15,
                            color: dim ? colors.secondaryText : colors.text,
                          ),
                        ),
                      ),
                      Text(
                        detail,
                        // 반 칸에서는 두 줄까지 써서 글이 잘리지 않게 한다.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  /// 모든 세계를 합친 진행 요약 한 줄: 깬 판, 모은 별, 친구.
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
    final overall = session.overall;
    return Semantics(
      label: t.homeProgress,
      child: Row(
        children: [
          pill(
            Icons.flag_rounded,
            t.completedLevels(overall.cleared, overall.total),
            colors.goalInk,
          ),
          const SizedBox(width: 6),
          pill(
            Icons.star_rounded,
            t.collectedStars(overall.stars),
            colors.rewardInk,
          ),
          const SizedBox(width: 6),
          pill(
            Icons.pets_rounded,
            t.journeyFriends(overall.friends, overall.friendTotal),
            colors.echoInk,
          ),
        ],
      ),
    );
  }

  /// 빛길 위의 현재 위치: 지나온 세계는 금빛, 지금 세계는 민트.
  Widget _lightroad(GameColors colors, GameSession session, int here) {
    final saga = session.saga!;
    final done = session.progression.completedChapters;
    final lang = AppLocalizations.of(context)!.localeName;
    return Semantics(
      label:
          '${WorldText.sagaMap.resolve(lang)} · '
          '${WorldText.worldOf(here, saga.worlds.length).resolve(lang)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 2, 28, 4),
          child: SizedBox(
            height: 14,
            child: Row(
              children: [
                for (final world in saga.worlds) ...[
                  if (world.number > 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: world.number <= here
                            ? colors.reward.withValues(alpha: .8)
                            : colors.outline.withValues(alpha: .35),
                      ),
                    ),
                  Builder(
                    builder: (_) {
                      final now = world.number == here;
                      final lit = Worlds.isComplete(world.number, done);
                      final color = now
                          ? colors.goal
                          : lit
                          ? colors.reward
                          : colors.outline.withValues(alpha: .6);
                      return Container(
                        width: now ? 14 : 10,
                        height: now ? 14 : 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: now || lit ? color : null,
                          border: Border.all(color: color, width: 2),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "지금 여기" 카드: 빛길 위의 위치, 지금 세계와 장, 그 장의 별자리.
  /// 누르면 그 세계의 판 고르기가 열린다.
  Widget _here(
    AppLocalizations t,
    GameColors colors,
    GameSession? session,
    ContinueTarget? target,
  ) {
    final lang = t.localeName;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(color: colors.reward.withValues(alpha: .35)),
    );
    final surface = colors.surface.withValues(alpha: .55);
    if (session == null || target == null) {
      return Material(
        color: surface,
        shape: shape,
        child: const SizedBox.expand(),
      );
    }
    final world = target.world;
    final worldAtlas = world == 1 ? null : session.worldAtlas(world);
    final StoryText chapterName;
    final int chapterNumber, chapterCleared, chapterTotal, cleared, total;
    final Widget art;
    if (worldAtlas == null) {
      final chapter = session.story.chapterForLevel(
        world == 1 && target.levelId != null
            ? target.levelId!
            : session.levels.last.id,
      );
      final atlas = ConstellationAtlas.derive(session.levels, session.progress);
      final view = atlas.chapters.length < chapter.number
          ? null
          : atlas.chapters[chapter.number - 1];
      chapterName = chapter.name;
      chapterNumber = chapter.number;
      chapterCleared = session.completedInChapter(chapter.number);
      chapterTotal = view?.levels.length ?? Worlds.stagesPerChapter;
      cleared = session.completedCount;
      total = session.levels.length;
      art = view == null
          ? const SizedBox.expand()
          : ConstellationArt(
              chapter: view,
              guardianAsset: guardianAssetFor(session, view),
            );
    } else {
      final view = worldAtlas.forLevel(
        target.levelId ?? worldAtlas.stages.last.level.id,
      )!;
      chapterName = view.chapter.name;
      chapterNumber = view.chapter.number;
      chapterCleared = view.cleared;
      chapterTotal = view.stages.length;
      cleared = worldAtlas.cleared;
      total = worldAtlas.stages.length;
      art = Semantics(
        label: view.chapter.constellation.inLocale(lang),
        value: '${view.cleared} / ${view.stages.length}',
        child: CustomPaint(
          size: Size.infinite,
          painter: ConstellationPainter(
            definition: view.definition,
            lit: view.lit,
            colors: colors,
            golden: view.golden ? 1 : 0,
          ),
        ),
      );
    }
    final saga = session.saga;
    final expansion = worldAtlas != null;
    return Material(
      color: surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey(expansion ? 'world-entry' : 'home-levels'),
        onTap: _opening
            ? null
            : expansion
            ? () => _openWorld(world)
            : _chooseLevel,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Column(
            children: [
              if (saga != null) _lightroad(colors, session, world),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  saga?.world(world).title.inLocale(lang) ??
                      chapterName.inLocale(lang),
                  maxLines: 1,
                  style: GameTypography.reward.copyWith(
                    fontSize: 20,
                    color: colors.rewardInk,
                  ),
                ),
              ),
              if (saga != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    WorldText.chapterLine(
                      chapterNumber,
                      chapterName,
                    ).resolve(lang),
                    maxLines: 1,
                    style: GameTypography.body.copyWith(
                      fontSize: 13.5,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              Expanded(child: art),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: total == 0 ? 0 : cleared / total,
                    color: colors.goal,
                    backgroundColor: colors.outline.withValues(alpha: .25),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  WorldText.hereProgress(
                    cleared,
                    total,
                    chapterCleared,
                    chapterTotal,
                  ).resolve(lang),
                  maxLines: 1,
                  style: GameTypography.body.copyWith(
                    fontSize: 12.5,
                    color: colors.secondaryText,
                  ),
                ),
              ),
              JourneyCompanions(
                companion: session.collection.companion,
                reduceMotion: prefersReducedMotion(context, widget.settings),
                inline: true,
                compact: true,
                onAlbum: _album,
              ),
              if (saga == null &&
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

  /// 살펴보기 메뉴 네 칸. 이름 아래에 그 메뉴의 지금 상태를 한 줄로 보여 준다.
  Widget _menuGrid(
    AppLocalizations t,
    GameColors colors,
    GameSession? session,
    ContinueTarget? target,
  ) {
    Widget tile(
      Key key,
      IconData icon,
      String label,
      String? detail,
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
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: GameTypography.label.copyWith(
                                color: colors.text,
                              ),
                            ),
                          ),
                        ),
                        if (detail != null)
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                detail,
                                maxLines: 1,
                                style: GameTypography.body.copyWith(
                                  fontSize: 12.5,
                                  color: colors.secondaryText,
                                ),
                              ),
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
      ),
    );
    final lang = t.localeName;
    final ready = session != null && !_opening;
    final saga = session?.saga;
    final streak = session?.daily.streak ?? 0;
    final pending = session?.collection.pendingIds.length ?? 0;
    return Column(
      children: [
        Row(
          children: [
            if (saga != null)
              tile(
                const ValueKey('saga-map'),
                Icons.timeline_rounded,
                WorldText.sagaMap.resolve(lang),
                target == null
                    ? null
                    : WorldText.worldOf(
                        target.world,
                        saga.worlds.length,
                      ).resolve(lang),
                colors.primaryInk,
                ready ? _openSaga : null,
              )
            else
              tile(
                const ValueKey('home-map'),
                Icons.route_rounded,
                t.journeyMap,
                null,
                colors.primaryInk,
                ready ? _chooseLevel : null,
              ),
            const SizedBox(width: GameSpacing.small),
            tile(
              const ValueKey('home-journey'),
              Icons.menu_book_rounded,
              t.journey,
              streak > 0 ? t.journeyStreak(streak) : null,
              colors.goalInk,
              ready ? _journey : null,
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
              session == null
                  ? null
                  : WorldText.constellations(
                      session.progression.completedChapters.length,
                      (1 + session.worlds.length) * Worlds.chapterCount,
                    ).resolve(lang),
              colors.rewardInk,
              ready ? _atlas : null,
            ),
            const SizedBox(width: GameSpacing.small),
            tile(
              const ValueKey('home-album'),
              Icons.auto_stories_outlined,
              t.album,
              pending > 0
                  ? WorldText.newMemories(pending).resolve(lang)
                  : session?.collection.companion?.name.inLocale(lang),
              colors.echoInk,
              session == null ? null : _album,
            ),
          ],
        ),
      ],
    );
  }
}
