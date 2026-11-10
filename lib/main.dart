import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/game_audio.dart';
import 'domain/puzzle.dart';
import 'domain/mechanics/clock_arrow.dart';
import 'domain/mechanics/mirror_pair.dart';
import 'design/game_theme.dart';
import 'game/bloriq_game.dart';
import 'game/mechanic_legend.dart';
import 'design/keep_all_text.dart';
import 'game/board_geometry.dart';
import 'game/hint_search.dart';
import 'game/victory_panel.dart';
import 'l10n/app_localizations.dart';
import 'postcard/echo_postcard.dart';
import 'progress/progress_repository.dart';
import 'settings/game_settings.dart';
import 'app/app_entry.dart';
import 'app/game_session.dart';
import 'app/experience_dialogs.dart';
import 'app/journey_panel.dart';
import 'progression/progression_repository.dart';
import 'progression/progression_rules.dart';
import 'app/level_picker.dart';
import 'design/arcade_components.dart';
import 'design/star_art.dart';
import 'app/play_context.dart';
import 'tutorial/echo_tutorial.dart';
import 'tutorial/world_tutorial.dart';
import 'analytics/local_analytics.dart';
import 'story/narrative_controller.dart';
import 'story/companion_view.dart';
import 'story/story_catalog.dart';
import 'story/spirit_album.dart';
import 'story/discovery_panel.dart';
import 'story/story_share.dart';
import 'constellation/constellation_atlas.dart';
import 'constellation/constellation_state.dart';
import 'constellation/victory_constellation.dart';
import 'game/assist.dart';
import 'game/power_bar.dart';
import 'world/saga.dart';
import 'world/saga_map.dart';
import 'world/world_catalog.dart';
import 'world/world_map.dart';
import 'world/world_progress.dart';
import 'world/world_text.dart';
import 'world/world_theme.dart';

void main() => runApp(const BloriqApp());

class BloriqApp extends StatefulWidget {
  const BloriqApp({
    super.key,
    this.loadLevels,
    this.settings,
    this.clock,
    this.playtestMode = const bool.fromEnvironment('PLAYTEST_MODE'),
    this.firstRunIntro = true,
  });

  /// 테스트에서 이전 스테이지 구성과 기기 설정을 주입할 수 있다.
  final Future<List<Level>> Function()? loadLevels;
  final GameSettings? settings;
  final DateTime Function()? clock;
  final bool playtestMode;
  final bool firstRunIntro;

  @override
  State<BloriqApp> createState() => _BloriqAppState();
}

class _BloriqAppState extends State<BloriqApp> {
  GameSettings? _settings;

  @override
  void initState() {
    super.initState();
    unawaited(StarArt.load());
    if (widget.settings case final settings?) {
      _settings = settings..addListener(_settingsChanged);
    } else {
      _loadSettings();
    }
  }

  Future<void> _loadSettings() async {
    final settings = await GameSettings.load();
    if (!mounted) {
      settings.dispose();
      return;
    }
    setState(() => _settings = settings..addListener(_settingsChanged));
  }

  void _settingsChanged() => setState(() {});

  @override
  void dispose() {
    _settings?.removeListener(_settingsChanged);
    if (widget.settings == null) _settings?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BLORIQ',
    debugShowCheckedModeBanner: false,
    // 밤하늘 게임이라 늘 다크 테마만 쓴다(기기 설정이 라이트여도 같다).
    theme: GameTheme.dark,
    darkTheme: GameTheme.dark,
    themeMode: ThemeMode.dark,
    themeAnimationDuration: Duration.zero,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeResolutionCallback: (locale, supported) =>
        locale?.languageCode == 'ko' ? const Locale('ko') : const Locale('en'),
    home: _settings == null
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : AppEntry(
            loadLevels: widget.loadLevels,
            clock: widget.clock,
            playtestMode: widget.playtestMode,
            firstRunIntro: widget.firstRunIntro,
            settings: _settings!,
            gameBuilder: (session, levelId, play) => GameScreen(
              session: session,
              play: play,
              initialLevelId: levelId,
              settings: _settings!,
            ),
          ),
  );
}

/// 게임 화면 배치 단계. 위에서부터 공간이 모자랄 때마다 한 단계씩 줄인다.
/// [compactLegend]는 설명을 아이콘 한 줄로 접고, [tight]는 동료 줄까지 숨기며,
/// [minimal]은 설명을 한 줄로 줄인다.
enum _GameFit { full, compactLegend, tight, minimal, scroll }

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.session,
    required this.initialLevelId,
    this.play = const PlayContext.campaign(),
    required this.settings,
    this.hintSearch = const HintSearch(),
  });

  final GameSession session;
  final PlayContext play;
  final int initialLevelId;
  final GameSettings settings;
  final HintSearch hintSearch;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final List<Level> _loaded;
  final _narrative = NarrativeController();
  SpiritDefinition? _discovery;
  bool _storyHidden = false;
  bool _retryingSave = false;
  bool _allowPop = false;
  bool _leaving = false;
  EchoTutorial? _tutorial;
  AttemptRecorder? _attempt;
  bool _modalOpen = false;
  BoardGeometry? _geometry;

  /// 보드 칸의 최소 터치 크기. 고정 배치로 이를 지킬 수 없을 때만 스크롤한다.
  static const _minCell = 48.0;
  _GameFit _fitFloor = _GameFit.full;
  double _buttonHeight = 48;
  Object? _layoutKey;
  PuzzleController? _controller;
  BloriqGame? _game;
  int _index = 0;
  String? _dragBlock;
  Offset? _dragStart;
  Offset? _dragEnd;
  GameAudio? _audio;
  bool _gateBlocked = false;
  ProgressRepository? _progress;
  CompletionResult? _completion;
  bool _replaying = false;
  bool _reduceMotion = false;
  bool _isNewBest = false;

  /// 이번 클리어로 받은 경험치·별가루·권능·유대. 결과 팝업에 보여 준다.
  ClearReward? _reward;

  /// 이번 시도에서 별빛 길을 썼는지(2별 상한), 무료 사용을 이미 했는지.
  bool _starlightUsed = false;
  bool _hintBusy = false;
  PuzzleState? _guideState;
  List<PuzzleMove>? _guidePath;

  /// 이번 클리어로 지금 세계의 다섯 별자리가 모두 완성됐는지.
  bool _worldCleared = false;

  /// 풀이 따라 하기 중: 매 수마다 다음 최단 수를 비춘다. 깨면 별 1개.
  bool _guided = false;

  /// 막힘 도움을 권할 시각에 화면을 다시 그린다.
  Timer? _stuckTimer;
  bool _starlightFreeUsed = false;

  /// 이번 클리어를 기록할 때 정한 별 상한. 결과 팝업이 이 값을 쓴다
  /// (기록하면서 저장된 도움 상한이 지워지기 때문).
  int? _clearCap;

  /// 캠페인 판의 저장 키. 도움 상한은 이 키로 판마다 저장된다.
  String? get _assistKey {
    final level = _controller?.state.level;
    if (level == null || widget.play.mode != PlayMode.campaign) return null;
    return '${level.id}:${level.revision}';
  }

  /// 지금 깨면 받을 수 있는 최대 별: 이번 시도의 도움과, 다시 시작하거나
  /// 판을 나갔다 와도 남는 판별 도움 기록 중 낮은 쪽.
  int get _starCap {
    final attempt = assistedStarCap(
      followedSolution: _guided,
      usedHint: _starlightUsed,
    );
    final key = _assistKey;
    if (key == null) return attempt;
    return math.min(attempt, widget.session.progression.assistCap(key));
  }

  /// 확장 세계: 권능 막대에서 고른 권능. 다음 밀기가 이 권능으로 움직인다.
  PuzzlePower? _armedPower;

  /// 확장 세계 별자리를 저장 전에 떠 둔다.
  WorldAtlas? _worldBefore;

  /// 세계 2부터는 [LoadedWorld] 데이터와 권능 막대를 쓴다.
  bool get _expansion => widget.play.world >= 2;
  LoadedWorld? get _world => widget.session.world(widget.play.world);
  WorldBoardSkin? get _boardSkin => widget.session.boardSkin(widget.play.world);

  /// 확장 세계에서 쓸 수 있는 권능(성장 기록 기준). 세계 1은 늘 비어 있다.
  Set<PuzzlePower> get _ownedPowers => _expansion
      ? ownedBoardPowers(widget.session.progression.hasPower)
      : const {};

  /// 이 스테이지에서 실제로 쓸 수 있는 권능: 가진 권능 중 스테이지가 여는 것.
  Set<PuzzlePower> _stagePowers(Level level) => level.world >= 2
      ? _ownedPowers.intersection(level.availablePowers)
      : const {};

  PuzzleController _newController(Level level) =>
      PuzzleController(level, powers: _stagePowers(level));

  /// 저장 전 별자리. 저장이 성공한 뒤 [_atlasAfter]와 비교해 연출을 고른다.
  ConstellationAtlas? _atlasBefore, _atlasAfter;
  ConstellationEvent? _constellation;
  bool _constellationPending = false;
  Timer? _victoryFallback;
  late final AnimationController _victory = AnimationController(
    vsync: this,
    duration: GameEffects.celebrationDuration,
    value: 1,
  )..addListener(_updateVictory);

  bool get _celebrating =>
      _controller?.state.isComplete == true && _victory.value < 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loaded = widget.play.level != null
        ? [widget.play.level!]
        : _expansion
        ? _world!.levels
        : widget.session.levels;
    if (widget.play.guided) {
      _tutorial = EchoTutorial();
      if (widget.play.mode == PlayMode.campaign) {
        unawaited(widget.session.onboarding.mark('inProgress'));
      }
    }
    _index = _loaded.indexWhere((level) => level.id == widget.initialLevelId);
    if (_index < 0) _index = 0;
    _audio = widget.session.audio;
    _progress = widget.session.progress;
    _controller = _newController(_loaded[_index]);
    _game = BloriqGame(_controller!)
      ..trailStyle = widget.session.progression.equippedTrail;
    widget.session.analytics.addListener(_analyticsChanged);
    _startAttempt();
    _trackOpened();
    _maybeShowWorldGuide();
  }

  void _maybeShowWorldGuide() {
    final controller = _controller!;
    final level = controller.state.level;
    final tutorial = WorldTutorial.forWorld(widget.play.world);
    if (tutorial == null || level.id != Worlds.firstLevelId(tutorial.world)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_controller, controller) ||
          _modalOpen ||
          ModalRoute.of(context)?.isCurrent != true ||
          !widget.session.takeWorldGuide(level)) {
        return;
      }
      unawaited(
        _withModal<void>(
          () => showWorldTutorial(context, widget.settings, tutorial),
        ),
      );
    });
  }

  /// 캠페인 판을 열면 막힘 기록을 시작하고, 도움을 권할 시각에 다시 그린다.
  void _trackOpened() {
    _stuckTimer?.cancel();
    if (widget.play.mode != PlayMode.campaign || _tutorial != null) return;
    final struggle = widget.session.struggle;
    final id = _controller!.state.level.id;
    struggle.opened(id);
    final left = struggle.untilStuck(id);
    if (left != null && left > Duration.zero) {
      _stuckTimer = Timer(left, () {
        if (mounted) setState(() {});
      });
    }
  }

  bool _offerHelp(PuzzleController controller) =>
      widget.play.mode == PlayMode.campaign &&
      _tutorial == null &&
      !_guided &&
      !_replaying &&
      !controller.state.isComplete &&
      widget.session.struggle.isStuck(controller.state.level.id);

  Map<String, Object?> get _eventContext => {
    'mode': widget.play.mode.name,
    'levelId': _controller!.state.level.id,
    'revision': _controller!.state.level.revision,
    if (_attempt != null) 'runId': _attempt!.runId,
    if (widget.play.dailyDate != null) 'date': widget.play.dailyDate,
    if (widget.play.challenge != null)
      'poolVersion': widget.play.challenge!.poolVersion,
  };
  void _startAttempt() {
    if (!widget.session.analytics.enabled) return;
    _attempt = AttemptRecorder(widget.session.analytics, _eventContext);
    if (_modalOpen) _attempt?.pause();
    if (_tutorial != null) {
      widget.session.analytics.record('tutorial_start', {
        ..._eventContext,
        'replay': widget.play.mode == PlayMode.tutorialReplay,
        'reason': _tutorial!.step == 0 ? 'entry' : 'consent_midrun',
      });
    }
    if (widget.play.mode == PlayMode.daily) {
      widget.session.analytics.record('daily_open', _eventContext);
    }
  }

  void _analyticsChanged() {
    if (widget.session.analytics.enabled) {
      if (_attempt == null) _startAttempt();
    } else {
      _attempt = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _attempt?.foreground(state == AppLifecycleState.resumed);
  }

  @override
  void didChangeMetrics() {
    // 창/DPR 변경은 보드 크기가 같아도 진행 중 포인터의 기준을 무효화한다.
    _cancelDrag();
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
  }

  int? get _bestMoves {
    final level = _controller!.state.level;
    if (widget.play.mode == PlayMode.daily) {
      return widget.session.daily.bestMoves(widget.play.dailyDate!);
    }
    if (widget.play.mode == PlayMode.tutorialReplay) return null;
    return _progress!.forLevel(level.id, revision: level.revision)?.bestMoves;
  }

  void _updateVictory() {
    _game?.setCelebrationProgress(_victory.value, isNewBest: _isNewBest);
    if (_victory.value >= 1 && mounted) {
      _victoryFallback?.cancel();
      setState(() {});
    }
  }

  void _skipCelebration() {
    _victoryFallback?.cancel();
    _victory.value = 1;
  }

  void _beginCompletion(PuzzleController controller) {
    final state = controller.state;
    final previous = widget.play.mode == PlayMode.campaign
        ? _progress!.forLevel(state.level.id, revision: state.level.revision)
        : null;
    _isNewBest = widget.play.mode == PlayMode.daily
        ? (widget.session.daily.bestMoves(widget.play.dailyDate!) == null ||
              state.moves <
                  widget.session.daily.bestMoves(widget.play.dailyDate!)!)
        : widget.play.mode == PlayMode.campaign &&
              (previous == null || state.moves < previous.bestMoves);
    _attempt?.finish(
      widget.play.mode == PlayMode.daily ? 'daily_complete' : 'level_complete',
      state.moves,
    );
    if (_tutorial?.complete == true) {
      widget.session.analytics.record('tutorial_complete', {
        ..._eventContext,
        'replay': widget.play.mode == PlayMode.tutorialReplay,
      });
    }
    // 기록이 메모리에서 바뀌기 전에 별자리 상태를 떠 둔다.
    _constellation = null;
    _constellationPending = false;
    _atlasAfter = null;
    _atlasBefore = widget.play.mode == PlayMode.campaign
        ? ConstellationAtlas.derive(widget.session.levels, _progress!)
        : null;
    _worldBefore = _expansion
        ? widget.session.worldAtlas(widget.play.world)
        : null;
    _armedPower = null;
    final chapter = _atlasBefore?.forLevel(state.level.id);
    final lightsStar = chapter != null && !chapter.isLit(state.level.id);
    final completesChapter =
        lightsStar && chapter.litCount == chapter.levels.length - 1;
    // 저장과 별 평가는 애니메이션 타이머/Canvas 성공 여부에 의존하지 않는다.
    unawaited(_recordCompletion(controller));
    _narrative.react(CompanionReaction.complete);
    final friend = widget.session.story.forLevel(state.level.id);
    final newGuardian =
        friend?.released == true &&
        friend!.guardian &&
        widget.play.mode == PlayMode.campaign &&
        !widget.session.collection.owns(friend.id);
    _victory.duration = completesChapter || newGuardian
        ? GameEffects.constellationCompleteDuration
        : GameEffects.celebrationDuration;
    _victoryFallback?.cancel();
    if (_reduceMotion) {
      _victory.value = 1;
      _game!.setCelebrationProgress(1, isNewBest: _isNewBest);
      return;
    }
    _victory.forward(from: 0);
    final game = _game;
    // ticker나 Canvas가 멈춰도 결과 버튼은 독립 타이머로 복구한다.
    _victoryFallback = Timer(
      _victory.duration! + const Duration(milliseconds: 200),
      () {
        if (mounted && identical(_game, game)) _skipCelebration();
      },
    );
  }

  void _acknowledgeDiscovery() {
    if (_discovery case final friend?) {
      unawaited(widget.session.collection.acknowledge(friend.id));
    }
  }

  Future<void> _openAlbum() async {
    await _withModal<void>(
      () => showSpiritAlbum(context, widget.session, widget.settings),
    );
    if (mounted) setState(() {});
  }

  void _select(int index) {
    _acknowledgeDiscovery();
    _resetAssist();
    _discovery = null;
    _storyHidden = false;
    _constellation = null;
    _constellationPending = false;
    _atlasBefore = _atlasAfter = null;
    _narrative.react(CompanionReaction.idle);
    _attempt?.finish(
      'level_end',
      _controller!.state.moves,
      reason: 'stage_change',
    );
    _tutorial = null;
    _skipCelebration();
    _stopReplay();
    setState(() {
      _index = index;
      _controller = _newController(_loaded[index]);
      _game = BloriqGame(_controller!)
        ..trailStyle = widget.session.progression.equippedTrail;
      _dragBlock = null;
      _dragStart = null;
      _gateBlocked = false;
      _completion = null;
      _attempt = null;
      _startAttempt();
    });
    _trackOpened();
    _maybeShowWorldGuide();
  }

  /// 결과 화면 "다음"이 고를 판. 확장 세계는 아직 잠긴 판 대신
  /// 열려 있는 못 깬 판으로 간다(장 안에서는 순서가 자유롭다).
  int _nextIndex() {
    final next = _index + 1 < _loaded.length ? _index + 1 : 0;
    if (!_expansion) return next;
    final atlas = widget.session.worldAtlas(widget.play.world);
    if (atlas == null || atlas.isUnlocked(_loaded[next].id)) return next;
    final index = _loaded.indexWhere((level) => level.id == atlas.nextLevelId);
    return index < 0 ? next : index;
  }

  void _stopReplay() {
    _replaying = false;
    _game?.skipReplay();
  }

  @override
  void dispose() {
    _stuckTimer?.cancel();
    _attempt?.finish('level_end', _controller!.state.moves, reason: 'leave');
    _narrative.dispose();
    widget.session.analytics.removeListener(_analyticsChanged);
    _victoryFallback?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _victory.removeListener(_updateVictory);
    _victory.dispose();
    _stopReplay();
    super.dispose();
  }

  void _watchReplay() {
    if (_replaying || _celebrating) return;
    final game = _game!;
    setState(() => _replaying = true);
    final started = game.startReplay(
      onFinished: () {
        if (mounted && _replaying && identical(_game, game)) {
          setState(() => _replaying = false);
        }
      },
    );
    if (!started && mounted) setState(() => _replaying = false);
  }

  Future<void> _recordCompletion(PuzzleController controller) async {
    final state = controller.state;
    if (_tutorial?.complete == true) {
      _tutorial = null;
      if (widget.play.mode == PlayMode.campaign) {
        unawaited(widget.session.onboarding.mark('complete'));
      }
    }
    if (widget.play.mode == PlayMode.daily) {
      final result = await widget.session.daily.recordCompletion(
        widget.play.challenge!,
        state.moves,
      );
      final reward = result.saved
          ? await widget.session.progression.recordDailyClear(
              widget.session.daily.streak,
            )
          : null;
      if (mounted && identical(_controller, controller)) {
        setState(() {
          _completion = result;
          _reward = reward;
        });
      }
      return;
    }
    if (widget.play.mode != PlayMode.campaign) return;
    widget.session.struggle.cleared(state.level.id);
    _stuckTimer?.cancel();
    final previousStars = _progress!
        .forLevel(state.level.id, revision: state.level.revision)
        ?.bestStars;
    final guided = _guided;
    final starCap = _starCap;
    _clearCap = starCap;
    final usedStarlight = _starlightUsed || guided || starCap < 3;
    final usedPower = controller.usedPower;
    final worldBefore = _worldBefore;
    final worldWasComplete = Worlds.isComplete(
      widget.play.world,
      widget.session.progression.completedChapters,
    );
    final result = await _progress!.recordCompletion(
      levelId: state.level.id,
      revision: state.level.revision,
      moves: state.moves,
      minimumMoves: state.level.minimumMoves,
      maxStars: starCap,
    );
    final added = result.saved
        ? await widget.session.collection.reconcile(
            _progress!.completedCampaignLevelIds,
          )
        : <SpiritDefinition>[];
    if (!mounted ||
        !identical(_controller, controller) ||
        !identical(controller.state, state)) {
      return;
    }
    setState(() {
      _completion = result;
      _discovery = added.where((f) => f.levelId == state.level.id).firstOrNull;
      _updateConstellation(state.level.id, saved: result.saved);
    });
    if (!result.saved) return;
    final event = _constellation;
    final chapter = _atlasAfter?.forLevel(state.level.id);
    final companion = widget.session.collection.companion;
    final worldAfter = worldBefore == null
        ? null
        : widget.session.worldAtlas(worldBefore.world);
    final worldEvent = worldBefore == null || worldAfter == null
        ? null
        : WorldAtlas.diff(worldBefore, worldAfter, state.level.id);
    final reward = await widget.session.progression.recordClear(
      levelKey: '${state.level.id}:${state.level.revision}',
      stars: math.min(
        starRating(moves: state.moves, minimumMoves: state.level.minimumMoves),
        starCap,
      ),
      previousBestStars: previousStars,
      usedStarlightPath: usedStarlight,
      companionId: companion?.id,
      companionFamily: companion?.family,
      constellationCompletedChapter: worldEvent != null
          ? worldEvent.completed
          : event?.chapterCompleted == true
          ? chapter?.definition.chapter
          : null,
      constellationGoldenChapter: worldEvent != null
          ? worldEvent.golden
          : event?.becameGolden == true
          ? chapter?.definition.chapter
          : null,
      bareHandedClear: state.level.world >= 2
          ? isBareHandedClear(
              level: state.level,
              moves: state.moves,
              usedPower: usedPower,
              usedStarlightPath: usedStarlight,
            )
          : null,
    );
    if (!mounted ||
        !identical(_controller, controller) ||
        !identical(controller.state, state)) {
      return;
    }
    _game?.trailStyle = widget.session.progression.equippedTrail;
    setState(() {
      _reward = reward;
      _worldCleared =
          !worldWasComplete &&
          Worlds.isComplete(
            widget.play.world,
            widget.session.progression.completedChapters,
          );
    });
  }

  void _resetAssist() {
    _reward = null;
    _armedPower = null;
    _starlightUsed = false;
    _starlightFreeUsed = false;
    _clearCap = null;
    _guided = false;
    _guideState = null;
    _guidePath = null;
    _worldCleared = false;
    _game?.hintMove = null;
  }

  /// 판을 처음 상태로 되돌린다. [countStruggle]이면 막힘 기록에 다시 시작을 센다.
  void _restartBoard(PuzzleController controller, {bool countStruggle = true}) {
    _skipCelebration();
    _attempt?.restart();
    _attempt?.finish('level_end', controller.state.moves, reason: 'restart');
    _acknowledgeDiscovery();
    _discovery = null;
    _storyHidden = false;
    _narrative.react(CompanionReaction.idle);
    if (countStruggle && widget.play.mode == PlayMode.campaign) {
      widget.session.struggle.restarted(controller.state.level.id);
    }
    controller.restart();
    _resetAssist();
    _attempt = null;
    _startAttempt();
    _game!.clearEffects();
    _gateBlocked = false;
    _completion = null;
  }

  /// 풀이 따라 하기: 지금 상태의 다음 최단 수를 비추고, 권능 수면 권능을 골라 둔다.
  void _refreshGuide() {
    if (!_guided) return;
    final controller = _controller!;
    final state = controller.state;
    if (state.isComplete) {
      _showGuideMove(state, null);
      return;
    }
    if (!identical(_guideState, state)) {
      final last = controller.lastMove;
      final step = _guidePath?.firstOrNull;
      // 최단 풀이를 따라왔다면 남은 경로도 최단이다.
      _guidePath =
          last != null &&
              step != null &&
              identical(last.before, _guideState) &&
              last.blockId == step.blockId &&
              last.landing == step.target &&
              last.power == step.power
          ? _guidePath!.sublist(1)
          : widget.hintSearch.storedSolution(state);
      _guideState = state;
    }
    _showGuideMove(state, _guidePath?.firstOrNull);
    if (_guidePath == null && !_hintBusy) unawaited(_findGuidePath(state));
  }

  void _showGuideMove(PuzzleState state, PuzzleMove? move) {
    if (move == null) {
      _game?.hintMove = null;
      return;
    }
    _armedPower = move.power;
    _game?.hintMove = (from: state.positionOf(move.blockId)!, to: move.target);
  }

  Future<T?> _withHint<T>(Future<T> Function() action) async {
    if (_hintBusy) return null;
    setState(() => _hintBusy = true);
    try {
      return await action();
    } finally {
      if (mounted) setState(() => _hintBusy = false);
    }
  }

  void _hintSearchLimit(AppLocalizations t) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.starlightSearchLimit)));

  Future<void> _findGuidePath(PuzzleState state) async {
    final result = await _withHint(() => widget.hintSearch.solve(state));
    if (!mounted || !_guided || result == null) return;
    if (!identical(state, _controller!.state)) {
      setState(_refreshGuide);
      return;
    }
    setState(() {
      _guidePath = result.moves ?? const [];
      _showGuideMove(state, _guidePath!.firstOrNull);
    });
    if (result.limited) _hintSearchLimit(AppLocalizations.of(context)!);
  }

  /// 막혔을 때의 도움: 열쇠 한 줄(무료) → 별빛 길 → 풀이 따라 하기.
  Future<void> _openHelp(
    AppLocalizations t,
    PuzzleController controller,
  ) async {
    if (_hintBusy || _modalOpen) return;
    final level = controller.state.level;
    final initial = PuzzleState.initial(level, powers: _stagePowers(level));
    var solution = widget.hintSearch.storedSolution(initial);
    if (solution == null) {
      final result = await _withHint(() => widget.hintSearch.solve(initial));
      if (!mounted || !identical(controller, _controller) || result == null) {
        return;
      }
      if (result.limited) {
        _hintSearchLimit(t);
        return;
      }
      solution = result.moves ?? const [];
    }
    final clue = keyHint(level, solution).resolve(t.localeName);
    final lang = t.localeName;
    final choice = await _withModal<_HelpChoice>(
      () => showModalBottomSheet<_HelpChoice>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => _HelpSheet(keyHint: clue, lang: lang),
      ),
    );
    if (!mounted || !identical(controller, _controller)) return;
    switch (choice) {
      case _HelpChoice.starlight:
        await _useStarlight(t);
      case _HelpChoice.guide:
        if (_assistKey case final key?) {
          unawaited(widget.session.progression.markAssist(key, 1));
        }
        setState(() {
          _restartBoard(controller, countStruggle: false);
          _guided = true;
          _guideState = controller.state;
          _guidePath = solution;
          _refreshGuide();
        });
      case null:
        break;
    }
  }

  /// 별빛 길: 지금 상태에서 가장 짧은 다음 한 수를 보드에 비춘다.
  Future<void> _useStarlight(AppLocalizations t) async {
    final controller = _controller!;
    final state = controller.state;
    if (state.isComplete || _replaying || _modalOpen) return;
    bool current() => identical(state, _controller?.state);

    await _withHint(() async {
      final result = await widget.hintSearch.solve(state);
      if (!mounted || !current()) return;
      if (result.limited) {
        _hintSearchLimit(t);
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      final move = result.moves?.firstOrNull;
      if (move == null) {
        messenger.showSnackBar(SnackBar(content: Text(t.starlightNoMove)));
        return;
      }
      final companion = widget.session.collection.companion;
      final quote = await widget.session.progression.useStarlightPath(
        freeUsedThisAttempt: _starlightFreeUsed,
        levelKey: _assistKey,
        companionId: companion?.id,
        companionFamily: companion?.family,
        onUsed: (used) {
          if (move.power case final power?) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(WorldText.hintPower(power).resolve(t.localeName)),
              ),
            );
          }
          setState(() {
            if (used.source == StarlightPathSource.free) {
              _starlightFreeUsed = true;
            }
            if (!_starlightUsed) {
              messenger.showSnackBar(
                SnackBar(content: Text(t.starlightCapped)),
              );
            }
            _starlightUsed = true;
            _game!.hintMove = (
              from: state.positionOf(move.blockId)!,
              to: move.target,
            );
          });
        },
      );
      if (quote == null && mounted && current()) {
        messenger.showSnackBar(SnackBar(content: Text(t.starlightShort)));
      }
    });
    if (mounted && !current() && _guided) setState(_refreshGuide);
  }

  Future<void> _retryProgressSave() async {
    if (_retryingSave) return;
    setState(() => _retryingSave = true);
    final controller = _controller;
    final result = _completion;
    final saved = await _progress!.retrySave();
    final added = saved
        ? await widget.session.collection.reconcile(
            _progress!.completedCampaignLevelIds,
          )
        : <SpiritDefinition>[];
    if (!mounted) return;
    setState(() {
      _retryingSave = false;
      if (identical(controller, _controller) && result != null) {
        _completion = CompletionResult(
          progress: result.progress,
          stars: result.stars,
          isNewBest: result.isNewBest,
          saved: saved,
        );
        _discovery ??= added
            .where((f) => f.levelId == controller!.state.level.id)
            .firstOrNull;
        _updateConstellation(controller!.state.level.id, saved: saved);
      }
    });
  }

  /// 저장 결과로만 별을 켠다. 실패하면 점선 고리로 대기 상태를 보여 준다.
  void _updateConstellation(int levelId, {required bool saved}) {
    final before = _atlasBefore;
    if (before == null) return;
    if (!saved) {
      _constellationPending = before.forLevel(levelId)?.isLit(levelId) == false;
      return;
    }
    final after = ConstellationAtlas.derive(widget.session.levels, _progress!);
    _atlasAfter = after;
    _constellationPending = false;
    _constellation = ConstellationAtlas.diff(before, after, levelId);
  }

  Widget? _constellationView(PuzzleController controller) {
    final levelId = controller.state.level.id;
    final event = _constellation;
    final atlas = _constellationPending ? _atlasBefore : _atlasAfter;
    final chapter = atlas?.forLevel(levelId);
    if (chapter == null ||
        (!_constellationPending && (event == null || event.isEmpty))) {
      return null;
    }
    return VictoryConstellation(
      chapter: chapter,
      levelId: levelId,
      progress: _victory.value,
      reduceMotion: _reduceMotion,
      guardianAsset: guardianAssetFor(widget.session, chapter),
      event: _constellationPending ? null : event,
      pending: _constellationPending,
      onOpen: () => _openAtlas(chapter.chapter),
    );
  }

  Future<void> _openAtlas(int chapter) async {
    final id = await _withModal<int>(
      () => showConstellationAtlas(
        context,
        widget.session,
        widget.settings,
        initialChapter: chapter,
      ),
    );
    if (!mounted || id == null) return;
    final index = _loaded.indexWhere((level) => level.id == id);
    if (index >= 0) _select(index);
  }

  void _showPostcard(AppLocalizations t, PuzzleController controller) {
    widget.session.analytics.record('postcard_open', _eventContext);
    final state = controller.state;
    final best = _bestMoves ?? state.moves;
    showDialog<void>(
      context: context,
      animationStyle: _reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (_) => EchoPostcardDialog(
        data: EchoPostcardData(
          levelId: state.level.id,
          moves: state.moves,
          bestMoves: best,
          stars: starRating(
            moves: state.moves,
            minimumMoves: state.level.minimumMoves,
          ),
          levelText: widget.play.mode == PlayMode.daily
              ? '${t.dailyEcho} ${widget.play.dailyDate}'
              : t.level(_displayNumber(state.level)),
          movesText: t.moves(state.moves),
          bestText: t.bestMoves(best),
          mirrorSteps: [
            for (final move in controller.moveHistory)
              if (MirrorPair.recordedShift(move) case final shift?)
                (
                  pair: shift.pair,
                  dx: shift.to.x - shift.from.x,
                  dy: shift.to.y - shift.from.y,
                ),
          ],
        ),
        onShareTap: () => widget.session.analytics.record(
          'postcard_share_tap',
          _eventContext,
        ),
        title: t.postcard,
        shareLabel: t.shareImage,
        closeLabel: t.close,
        errorLabel: t.shareError,
      ),
    );
  }

  Position? _cell(Offset offset) => _geometry?.positionAt(offset);

  void _start(DragStartDetails details) {
    final controller = _controller!;
    if (controller.state.isComplete || _replaying) return;
    final cell = _cell(details.localPosition);
    _dragStart = details.localPosition;
    _dragEnd = details.localPosition;
    _dragBlock = null;
    for (final block in controller.state.blocks) {
      if (block.position == cell) {
        _dragBlock = block.id;
        _game!.setDrag(block.id);
        break;
      }
    }
  }

  void _update(DragUpdateDetails details) {
    _dragEnd = details.localPosition;
    if (_dragBlock != null && _dragStart != null) {
      final delta = details.localPosition - _dragStart!;
      // A block can move along only one axis per gesture.
      final aligned = delta.dx.abs() >= delta.dy.abs()
          ? Offset(delta.dx, 0)
          : Offset(0, delta.dy);
      _game!.setDrag(_dragBlock, aligned, _armedPower);
      _narrative.react(
        CompanionReaction.look,
        direction: aligned.dx.sign.toInt(),
      );
    }
  }

  void _cancelDrag() {
    _game?.setDrag(null);
    _dragBlock = null;
    _dragStart = null;
    _dragEnd = null;
  }

  void _end() {
    final controller = _controller!;
    if (_dragBlock != null && _dragStart != null && _dragEnd != null) {
      final delta = _dragEnd! - _dragStart!;
      final threshold = _geometry!.dragThreshold;
      if (math.max(delta.dx.abs(), delta.dy.abs()) >= threshold) {
        final block = controller.state.blocks.firstWhere(
          (item) => item.id == _dragBlock,
        );
        final from = block.position;
        final previousEcho = controller.state.echo;
        final gateWasOpen = controller.state.isGateOpen;
        final dx = delta.dx.abs() >= delta.dy.abs() ? delta.dx.sign.toInt() : 0;
        final dy = dx == 0 ? delta.dy.sign.toInt() : 0;
        final target = Position(from.x + dx, from.y + dy);
        if (_tutorial != null && !_tutorial!.accepts(block.id, target)) {
          _cancelDrag();
          setState(() {});
          return;
        }
        final before = controller.state;
        final power = _armedPower;
        // 권능을 고른 상태면 이번 밀기는 그 권능으로 움직인다(한 스테이지 한 번).
        final moved = power != null
            ? controller.usePower(power, block.id, Position(dx, dy))
            : controller.move(block.id, target);
        if (power == null) _tutorial?.observe(before, target, moved);
        if (moved && power != null) _armedPower = null;
        if (moved) {
          _attempt?.moved(echo: controller.state.echo != null);
          if (widget.play.mode == PlayMode.daily) {
            unawaited(widget.session.daily.markPlayed(widget.play.challenge!));
          }
          _gateBlocked = false;
          _narrative.react(
            !gateWasOpen && controller.state.isGateOpen
                ? CompanionReaction.gate
                : controller.state.echo == from
                ? CompanionReaction.echo
                : CompanionReaction.idle,
          );
          _game!.animateMove(controller.lastMove!);
          _refreshGuide();
          if (controller.state.isComplete) _beginCompletion(controller);
          final effect = controller.state.isComplete
              ? SoundEffect.complete
              : !gateWasOpen && controller.state.isGateOpen
              ? SoundEffect.gate
              : previousEcho != null
              ? SoundEffect.echo
              : SoundEffect.move;
          _audio?.play(effect);
          HapticFeedback.lightImpact();
        } else {
          _narrative.react(
            target == controller.state.echo
                ? CompanionReaction.blocked
                : CompanionReaction.look,
          );
          _audio?.play(SoundEffect.blocked);
          _gateBlocked =
              target == controller.state.level.echoGate &&
              !controller.state.isGateOpen;
          _game!.flashBlocked(target, blockId: block.id);
          HapticFeedback.mediumImpact();
        }
      }
    }
    _game!.setDrag(null);
    _dragBlock = null;
    _dragStart = null;
    _dragEnd = null;
    setState(() {});
  }

  bool _hasNoMoves(PuzzleController controller) {
    final state = controller.state;
    // 남은 권능으로 움직일 수 있으면 막힌 것이 아니다.
    return !state.isComplete &&
        controller.canUndo &&
        PuzzleSolver.successors(state).isEmpty;
  }

  void _togglePower(PuzzlePower power) {
    if (_replaying || _celebrating || _modalOpen) return;
    setState(() => _armedPower = _armedPower == power ? null : power);
  }

  void _undo(PuzzleController controller) {
    _acknowledgeDiscovery();
    _discovery = null;
    _storyHidden = false;
    _skipCelebration();
    setState(() {
      controller.undo();
      _armedPower = null;
      _narrative.react(CompanionReaction.idle);
      _attempt?.undo();
      _game!.clearEffects();
      _gateBlocked = false;
      _completion = null;
      _refreshGuide();
    });
  }

  Future<T?> _withModal<T>(Future<T?> Function() action) async {
    if (_modalOpen || !mounted) return null;
    _modalOpen = true;
    _cancelDrag();
    _attempt?.pause();
    try {
      return await action();
    } finally {
      _modalOpen = false;
      _attempt?.resume();
    }
  }

  Future<void> _showSettings() async {
    await _withModal<void>(
      () => showExperienceSettings(
        context,
        widget.settings,
        _audio!,
        resumeGame: true,
        analytics: widget.session.analytics,
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _showHelp(AppLocalizations t) async {
    await _withModal<void>(() async {
      final replay = await showGameHelp(
        context,
        widget.settings,
        showMirrorGuide: widget.play.world == 3,
        showClockGuide: widget.play.world == 4,
      );
      if (!mounted) return;
      if (replay?.worldGuide case final tutorial?) {
        await showWorldTutorial(context, widget.settings, tutorial);
      } else if (replay == GameHelpAction.echo) {
        final session = widget.session;
        final saga = session.saga;
        session.audio.setMusicTrack(saga?.world(1).theme?.bgm);
        try {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => GameScreen(
                session: session,
                initialLevelId: 1,
                settings: widget.settings,
                play: PlayContext.tutorialReplay(
                  session.levels.firstWhere((level) => level.id == 1),
                ),
              ),
            ),
          );
        } finally {
          if (mounted) {
            session.audio.setMusicTrack(
              saga?.world(widget.play.world).theme?.bgm,
            );
          }
        }
      }
    });
  }

  void _skipTutorial() {
    widget.session.analytics.record('tutorial_skip', {
      ..._eventContext,
      'replay': widget.play.mode == PlayMode.tutorialReplay,
    });
    if (widget.play.mode == PlayMode.campaign) {
      unawaited(widget.session.onboarding.mark('skipped'));
    }
    setState(() => _tutorial = null);
  }

  Future<void> _pickLevel() async {
    final id = await _withModal<int>(
      () => _expansion
          ? showWorldMap(context, widget.session, widget.play.world)
          : showLevelPicker(
              context,
              widget.session,
              widget.settings,
              currentLevelId: _loaded[_index].id,
            ),
    );
    final index = _loaded.indexWhere((level) => level.id == id);
    if (id != null && mounted && index >= 0) _select(index);
  }

  /// 화면에 보이는 스테이지 번호. 확장 세계는 세계 안에서 1..25로 센다.
  int _displayNumber(Level level) =>
      level.world >= 2 ? Worlds.stageNumber(level.id) : level.id;

  Future<void> _openJourney() async {
    final id = await _withModal<int>(
      () => showJourneyPanel(context, widget.session, widget.settings),
    );
    final index = _loaded.indexWhere((level) => level.id == id);
    if (id != null &&
        mounted &&
        widget.play.mode == PlayMode.campaign &&
        index >= 0) {
      _select(index);
    }
  }

  bool get _dirty =>
      _controller != null &&
      _controller!.state.moves > 0 &&
      !_controller!.state.isComplete;

  Future<void> _leaveGame() async {
    if (_leaving) return;
    _leaving = true;
    _cancelDrag();
    final t = AppLocalizations.of(context)!;
    final leave =
        !_dirty ||
        await showDialog<bool>(
              context: context,
              animationStyle: _reduceMotion ? AnimationStyle.noAnimation : null,
              builder: (dialogContext) => AlertDialog(
                title: Text(t.leaveGameTitle),
                content: Text(t.leaveGameBody),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(t.keepPlaying),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(t.leaveGame),
                  ),
                ],
              ),
            ) ==
            true;
    if (!mounted) return;
    if (leave) {
      _acknowledgeDiscovery();
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } else {
      _leaving = false;
    }
  }

  Widget _buildVictory(AppLocalizations t, PuzzleController controller) {
    final state = controller.state;
    final colors = GameTheme.colorsOf(context);
    final stars = math.min(
      starRating(moves: state.moves, minimumMoves: state.level.minimumMoves),
      _clearCap ?? _starCap,
    );
    return AnimatedBuilder(
      key: const ValueKey('complete'),
      animation: _victory,
      builder: (context, _) => VictoryPanel(
        progress: _victory.value,
        stars: stars,
        isNewBest: _isNewBest,
        reduceMotion: _reduceMotion,
        onSkip: _skipCelebration,
        discovery: _discovery != null && !_storyHidden
            ? DiscoveryPanel(
                spirit: _discovery!,
                chapter: widget.session.story.chapter(_discovery!.chapter),
                progress: _victory.value,
                reduceMotion: _reduceMotion,
                onSkip: () {
                  _skipCelebration();
                  _acknowledgeDiscovery();
                  setState(() => _storyHidden = true);
                },
              )
            : null,
        constellation: _constellationView(controller),
        reward: _rewardView(t),
        result: DefaultTextStyle.merge(
          style: GameTypography.body.copyWith(color: colors.text),
          textAlign: TextAlign.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _resultStats(t, colors, state),
              // 기록 갱신 배지가 뜨면 같은 칭찬을 두 번 하지 않는다.
              if (state.moves == state.level.minimumMoves && !_isNewBest)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    t.optimalComplete,
                    style: GameTypography.label.copyWith(
                      color: colors.goalInk,
                      fontSize: 15,
                    ),
                  ),
                ),
              if (_completion?.saved == false) ...[
                Text(t.saveError),
                if (widget.play.mode == PlayMode.campaign)
                  TextButton(
                    key: const ValueKey('retry-progress'),
                    onPressed: _retryingSave ? null : _retryProgressSave,
                    child: Text(t.retrySave),
                  ),
              ],
              if (widget.play.mode == PlayMode.campaign)
                CollectionStorageNotice(
                  session: widget.session,
                  onChanged: () => setState(() {}),
                ),
              if (_worldFinished case final finished?)
                _worldClearCard(t, colors, finished)
              else if (widget.play.mode == PlayMode.campaign &&
                  widget.session.collection.owned.length ==
                      widget.session.story.released.length &&
                  widget.session.story.released.length == 25)
                Text(t.seasonComplete),
            ],
          ),
        ),
        actions: _victoryActions(t, controller),
      ),
    );
  }

  /// 이번 이동 수·최고 기록·최소 이동 수를 큰 숫자 세 칸으로 보여 준다.
  Widget _resultStats(
    AppLocalizations t,
    GameColors colors,
    PuzzleState state,
  ) {
    Widget stat(String key, String label, int value, Color color) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            key: ValueKey(key),
            style: GameTypography.reward.copyWith(
              fontSize: 28,
              height: 1.1,
              color: color,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GameTypography.body.copyWith(
              fontSize: 15,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
    final best = _bestMoves;
    return Semantics(
      container: true,
      label: [
        t.completeDetail(state.moves),
        if (best != null) t.bestMoves(best),
        state.moves == state.level.minimumMoves
            ? t.optimalComplete
            : t.improveComplete(state.level.minimumMoves),
      ].join(' '),
      excludeSemantics: true,
      child: Row(
        children: [
          stat('result-moves', t.resultMoves, state.moves, colors.text),
          // 최고 기록이 이번 기록과 같으면 같은 숫자를 두 번 보이지 않는다.
          if (best != null && best != state.moves)
            stat('result-best', t.resultBest, best, colors.rewardInk),
          stat(
            'result-fewest',
            t.resultFewest,
            state.level.minimumMoves,
            colors.goalInk,
          ),
        ],
      ),
    );
  }

  /// 세계를 다 마친 결과인지. 이번 클리어로 마지막 별자리가 완성됐거나,
  /// 이미 마친 세계의 마지막 판을 깼을 때다. [next]는 바로 갈 수 있는 다음 세계
  /// (아직 준비 중이거나 데이터가 없으면 null).
  ({SagaWorld world, SagaWorld? next})? get _worldFinished {
    final saga = widget.session.saga;
    if (saga == null || widget.play.mode != PlayMode.campaign) return null;
    final number = widget.play.world;
    final complete = Worlds.isComplete(
      number,
      widget.session.progression.completedChapters,
    );
    if (!_worldCleared && !(complete && _index + 1 == _loaded.length)) {
      return null;
    }
    final next = saga.next(number);
    return (
      world: saga.world(number),
      next: next != null && widget.session.worldUnlocked(next.number)
          ? next
          : null,
    );
  }

  /// 결과 팝업 안의 "세계 완료" 카드: 다음에 어디로 가는지 분명히 알려 준다.
  Widget _worldClearCard(
    AppLocalizations t,
    GameColors colors,
    ({SagaWorld world, SagaWorld? next}) finished,
  ) {
    final lang = t.localeName;
    final upcoming = widget.session.saga?.next(finished.world.number);
    final detail = finished.next != null
        ? WorldText.gateOpened(finished.next!.title).resolve(lang)
        : upcoming != null
        ? '${WorldText.nextStory.resolve(lang)} · '
              '${upcoming.title.inLocale(lang)} · '
              '${WorldText.comingSoon.resolve(lang)}'
        : null;
    return Container(
      key: const ValueKey('world-clear'),
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.reward.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.reward.withValues(alpha: .6)),
      ),
      child: Column(
        children: [
          Text(
            WorldText.worldCleared(finished.world.title).resolve(lang),
            textAlign: TextAlign.center,
            style: GameTypography.reward.copyWith(
              fontSize: 19,
              color: colors.rewardInk,
            ),
          ),
          if (detail != null)
            KeepAllText(
              detail,
              textAlign: TextAlign.center,
              style: GameTypography.body.copyWith(fontSize: 15),
            ),
        ],
      ),
    );
  }

  /// 결과 화면을 닫고 홈에서 다음 세계 지도를 바로 연다.
  void _goToWorld(int world) {
    _acknowledgeDiscovery();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, OpenWorld(world));
    });
  }

  /// 결과 팝업 아래쪽 버튼. 다음 스테이지가 가장 크고 나머지는 작은 버튼으로 둔다.
  Widget _victoryActions(AppLocalizations t, PuzzleController controller) {
    final small = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 46),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: GameTypography.label.copyWith(fontSize: 15.5),
    );
    final friend = _discovery;
    // 세계를 다 마쳤으면 "첫 스테이지로" 대신 다음 세계(열렸으면 그 지도,
    // 아직 준비 중이면 빛길 지도의 예고)로 안내한다.
    final finished = _worldFinished;
    final worldFinished = finished != null;
    final nextWorld = finished?.next;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('result-next'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            textStyle: GameTypography.label.copyWith(fontSize: 18),
          ),
          onPressed: () => widget.play.mode != PlayMode.campaign
              ? Navigator.pop(context)
              : nextWorld != null
              ? _goToWorld(nextWorld.number)
              : worldFinished
              ? _withModal<int>(
                  () => showSagaMap(context, widget.session, selectable: false),
                )
              : _select(_nextIndex()),
          icon: Icon(
            nextWorld != null
                ? Icons.light_rounded
                : worldFinished
                ? Icons.auto_awesome_rounded
                : Icons.arrow_forward,
          ),
          label: Text(
            widget.play.mode != PlayMode.campaign
                ? t.close
                : nextWorld != null
                ? WorldText.enter(nextWorld.title).resolve(t.localeName)
                : worldFinished
                ? WorldText.nextStory.resolve(t.localeName)
                : _index + 1 < _loaded.length
                ? t.next
                : t.firstLevel,
          ),
        ),
        const SizedBox(height: GameSpacing.small),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: small,
                onPressed: _replaying ? null : () => _select(_index),
                child: _buttonLabel(Icons.replay, t.tryAgain),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton(
                style: small,
                onPressed: _celebrating ? null : _watchReplay,
                child: _buttonLabel(Icons.play_arrow, t.watchReplayShort),
              ),
            ),
            const SizedBox(width: 6),
            // 포스트카드·정령 도감·발견 카드는 더 보기 메뉴로 접어 둔다.
            PopupMenuButton<VoidCallback>(
              key: const ValueKey('result-more'),
              tooltip: t.moreActions,
              enabled: !_replaying,
              onSelected: (action) => action(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  key: const ValueKey('result-postcard'),
                  value: () => _showPostcard(t, controller),
                  child: ListTile(
                    leading: const Icon(Icons.image_outlined),
                    title: Text(t.postcard),
                  ),
                ),
                if (friend != null) ...[
                  PopupMenuItem(
                    key: const ValueKey('result-album'),
                    value: _openAlbum,
                    child: ListTile(
                      leading: const Icon(Icons.auto_stories_outlined),
                      title: Text(t.album),
                    ),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('result-discovery-share'),
                    value: () => _withModal<void>(
                      () => showStoryCard(
                        context,
                        [friend],
                        chapter: widget.session.story.chapter(friend.chapter),
                        reduceMotion: _reduceMotion,
                      ),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.ios_share_rounded),
                      title: Text(t.discoveryCard),
                    ),
                  ),
                ],
              ],
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(23),
                  border: Border.all(
                    color: GameTheme.colorsOf(context).outline,
                  ),
                ),
                child: const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 판 아래에 계속 보여 줄 설명. 기믹이 있으면 기믹마다 한 줄씩 나눈다.
  List<LegendItem> _legend(AppLocalizations t, PuzzleController controller) {
    final state = controller.state;
    LegendItem note(String text) => LegendItem(LegendKind.note, text);
    // This detects only states with no legal move, not every unsolvable state.
    if (_tutorial case final tutorial?) {
      return [
        note(switch (tutorial.step) {
          0 => t.tutorialMove,
          1 => t.tutorialBlock,
          _ => t.tutorialFinish,
        }),
      ];
    }
    if (_hasNoMoves(controller)) return [note(t.noMoves)];
    if (_armedPower case final power?) {
      return [note(WorldText.armed(power).resolve(t.localeName))];
    }
    final mechanics = MechanicLegend.itemsFor(
      state,
      t,
      gateBlocked: _gateBlocked,
    );
    if (mechanics.isNotEmpty) return mechanics;
    return [note(state.echo == null ? t.instruction : t.echoInstruction)];
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    _reduceMotion = prefersReducedMotion(context, widget.settings);
    if (_reduceMotion && _celebrating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _reduceMotion && _celebrating) _skipCelebration();
      });
    }
    _game!.configureAppearance(
      colors: colors,
      reduceMotion: _reduceMotion,
      skin: _boardSkin,
    );
    final controller = _controller!;
    final legend = _legend(t, controller);
    final hint = legend.map((item) => item.text).join('\n');
    _game!.tutorialTarget = _tutorial?.target;
    return PopScope<void>(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) unawaited(_leaveGame());
        if (didPop &&
            _tutorial != null &&
            widget.play.mode == PlayMode.campaign) {
          widget.session.analytics.record('tutorial_skip', {
            ..._eventContext,
            'reason': 'leave',
          });
          unawaited(widget.session.onboarding.mark('skipped'));
        }
      },
      child: Scaffold(
        body: ArcadeBackdrop(
          background: _boardSkin?.palette?.background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 스크롤 없이 한 화면에 고정한다. 보드는 남은 높이를 모두 쓴다.
                    final compact = constraints.maxHeight < 700;
                    final story = widget.play.mode == PlayMode.campaign
                        ? widget.session.story.forLevel(_loaded[_index].id)
                        : null;
                    final canPickLevel =
                        widget.play.mode == PlayMode.campaign &&
                        _tutorial == null;
                    final labelStyle = TextStyle(
                      color: colors.echoInk,
                      fontSize: 15,
                      decoration: canPickLevel
                          ? TextDecoration.underline
                          : null,
                    );
                    // 칸이 48px 아래로 내려가지 않는 가장 넉넉한 배치를 고른다.
                    final layoutKey = (
                      constraints.biggest,
                      _loaded[_index].id,
                      MediaQuery.textScalerOf(context).scale(1),
                    );
                    if (_layoutKey != layoutKey) {
                      _layoutKey = layoutKey;
                      _fitFloor = _GameFit.full;
                    }
                    final columns = controller.state.level.boardWidth;
                    final rows = controller.state.level.boardHeight;
                    final minBoard =
                        rows * _minCell + BoardGeometry.defaultFrameInset * 2;
                    final fit = _chooseFit(t, constraints, minBoard);
                    final tight = fit.index >= _GameFit.tight.index;
                    final scroll = fit == _GameFit.scroll;
                    final boardHeight = math.max(
                      minBoard,
                      constraints.maxHeight * .55,
                    );
                    // 보드는 너비에 막혀 더 커지지 않으므로 남는 높이는 아래 버튼을 키워 채운다.
                    final spare = fit != _GameFit.full
                        ? 0.0
                        : math.max(
                            0.0,
                            constraints.maxHeight -
                                _chromeHeight(t, constraints, fit) -
                                _widthCell(
                                      constraints.maxWidth -
                                          GameSpacing.page * 2,
                                      columns,
                                    ) *
                                    rows -
                                BoardGeometry.defaultFrameInset * 2,
                          );
                    final buttonHeight = 48.0 + math.min(8.0, spare * .1);
                    _buttonHeight = buttonHeight;
                    final rowHeight = _rowHeight(fit);
                    final movePill = StatPill(
                      icon: Icons.swipe_rounded,
                      label: _abilities.showMinimumMoves
                          ? '${t.moves(controller.state.moves)} · '
                                '${t.minimumMovesChip(controller.state.level.minimumMoves)}'
                          : t.moves(controller.state.moves),
                      color: colors.echoInk,
                    );
                    final starlight =
                        _tutorial == null &&
                            widget.play.mode != PlayMode.tutorialReplay
                        ? _starlightButton(t, colors, controller)
                        : null;
                    final levelLabel = Semantics(
                      label: t.levels,
                      button: true,
                      child: InkWell(
                        key: const ValueKey('game-levels'),
                        borderRadius: BorderRadius.circular(12),
                        onTap: canPickLevel ? _pickLevel : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.play.mode == PlayMode.daily
                                      ? t.dailyEcho
                                      : t.level(
                                          _displayNumber(_loaded[_index]),
                                        ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                              ),
                              if (_world?.story.forLevel(_loaded[_index].id)
                                  case final spirit? when !tight)
                                Flexible(
                                  child: Text(
                                    ' · ${spirit.levelTitle.inLocale(t.localeName)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: labelStyle.copyWith(
                                      color: colors.rewardInk,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              if (!tight && story?.released == true)
                                Flexible(
                                  child: Text(
                                    ' · ${story!.levelTitle.inLocale(t.localeName)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: labelStyle.copyWith(
                                      color: colors.rewardInk,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                    final clockPhase = _game!.clockPhase;
                    final boardHeading = clockPhase == null
                        ? levelLabel
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: levelLabel),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: ValueListenableBuilder<int>(
                                    valueListenable: clockPhase,
                                    builder: (_, phase, _) => Semantics(
                                      key: const ValueKey('clock-phase'),
                                      label: t.clockPhaseLabel(
                                        phase + 1,
                                        ClockArrow.phaseCount,
                                      ),
                                      excludeSemantics: true,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.schedule_rounded,
                                            size: 16,
                                            color: colors.rewardInk,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${phase + 1}/${ClockArrow.phaseCount}',
                                            style: GameTypography.label
                                                .copyWith(
                                                  color: colors.rewardInk,
                                                  fontSize: 13,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            GameSpacing.page,
                            compact ? 2 : 8,
                            GameSpacing.page,
                            compact ? 6 : 12,
                          ),
                          child: _scrollable(
                            scroll,
                            Column(
                              mainAxisSize: scroll
                                  ? MainAxisSize.min
                                  : MainAxisSize.max,
                              children: [
                                SizedBox(
                                  height: 48,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 92,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: GameWordmark(
                                            size: compact ? 28 : 32,
                                          ),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              key: const ValueKey('game-home'),
                                              tooltip: t.home,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: _leaveGame,
                                              icon: const Icon(
                                                Icons.home_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              key: const ValueKey(
                                                'game-journey',
                                              ),
                                              tooltip: t.journeyMenu,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: _tutorial == null
                                                  ? _openJourney
                                                  : null,
                                              icon: const Icon(
                                                Icons.menu_book_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              tooltip: t.help,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => _showHelp(t),
                                              icon: const Icon(
                                                Icons.help_outline_rounded,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: t.settings,
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: _showSettings,
                                              icon: const Icon(
                                                Icons.tune_rounded,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (tight) ...[
                                  // 좁은 화면: 스테이지 이름 옆으로 이동 수를 옮긴다.
                                  SizedBox(
                                    height: rowHeight,
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: boardHeading,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: movePill,
                                          ),
                                        ),
                                        if (starlight != null) ...[
                                          const SizedBox(width: 6),
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: starlight,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ] else ...[
                                  boardHeading,
                                  SizedBox(height: compact ? 4 : 8),
                                  // 정수 높이로 고정해 아래 보드가 픽셀 경계에 놓이게 한다.
                                  SizedBox(
                                    height: rowHeight,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: JourneyCompanions(
                                            companion: widget
                                                .session
                                                .collection
                                                .companion,
                                            narrative: _narrative,
                                            reduceMotion: _reduceMotion,
                                            compact: compact,
                                            inline: true,
                                            onAlbum: _openAlbum,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          flex: 2,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: movePill,
                                          ),
                                        ),
                                        if (starlight != null) ...[
                                          const SizedBox(width: 6),
                                          starlight,
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                                SizedBox(height: compact ? 4 : 8),
                                if (_expansion && _ownedPowers.isNotEmpty) ...[
                                  PowerBar(
                                    owned: _ownedPowers,
                                    stage:
                                        controller.state.level.availablePowers,
                                    remaining: controller.state.powers,
                                    armed: _armedPower,
                                    enabled:
                                        !controller.state.isComplete &&
                                        !_replaying &&
                                        !_celebrating,
                                    onToggle: _togglePower,
                                  ),
                                  SizedBox(height: compact ? 4 : 6),
                                ],
                                // 결과는 보드 위 팝업으로 띄우므로 판 크기는 끝까지 그대로다.
                                if (scroll)
                                  SizedBox(
                                    height: boardHeight,
                                    child: _buildBoard(t),
                                  )
                                else
                                  Expanded(child: _buildBoard(t)),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: fit == _GameFit.minimal
                                        ? 2
                                        : compact
                                        ? 6
                                        : 10,
                                  ),
                                  // 문구가 바뀌어도 보드가 움직이지 않도록 가장 긴 문구의 높이를 잡아 둔다.
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: _legendSlotHeight(
                                        t,
                                        constraints,
                                        fit,
                                      ),
                                    ),
                                    child: AnimatedSwitcher(
                                      duration:
                                          _reduceMotion || _tutorial != null
                                          ? Duration.zero
                                          : GameEffects.panelDuration,
                                      layoutBuilder: (current, previous) =>
                                          Stack(
                                            alignment: Alignment.topCenter,
                                            children: [
                                              for (final child in previous)
                                                IgnorePointer(
                                                  child: ExcludeSemantics(
                                                    child: child,
                                                  ),
                                                ),
                                              ?current,
                                            ],
                                          ),
                                      child: Column(
                                        key: ValueKey(hint),
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          MechanicLegend(
                                            items: legend,
                                            compact: fit != _GameFit.full,
                                            lines: fit == _GameFit.minimal
                                                ? 1
                                                : 2,
                                          ),
                                          if (_guided &&
                                              !controller.state.isComplete) ...[
                                            const SizedBox(height: 6),
                                            _guideBanner(t, colors),
                                          ] else if (_offerHelp(
                                            controller,
                                          )) ...[
                                            const SizedBox(height: 6),
                                            FilledButton.tonalIcon(
                                              key: const ValueKey('stuck-help'),
                                              onPressed: _hintBusy
                                                  ? null
                                                  : () => _openHelp(
                                                      t,
                                                      controller,
                                                    ),
                                              icon: _hintBusy
                                                  ? HintProgress(
                                                      t.starlightCalculating,
                                                    )
                                                  : const Icon(
                                                      Icons.lightbulb_rounded,
                                                    ),
                                              label: Text(
                                                AssistText.offer.resolve(
                                                  t.localeName,
                                                ),
                                              ),
                                            ),
                                          ],
                                          // 좁은 화면에서는 아래의 되돌리기 버튼으로 충분하다.
                                          if (fit == _GameFit.full &&
                                              _hasNoMoves(controller)) ...[
                                            const SizedBox(height: 8),
                                            FilledButton.icon(
                                              onPressed: () =>
                                                  _undo(controller),
                                              icon: const Icon(Icons.undo),
                                              label: Text(t.undoLastMove),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                if (_tutorial != null)
                                  TextButton(
                                    key: const ValueKey('skip-tutorial'),
                                    onPressed: _skipTutorial,
                                    child: Text(t.skipTutorial),
                                  ),
                                if (_tutorial == null)
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: compact ? 1 : 11,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            minimumSize: Size(48, buttonHeight),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          onPressed:
                                              controller.canUndo &&
                                                  !_replaying &&
                                                  !_celebrating
                                              ? () => _undo(controller)
                                              : null,
                                          child: _buttonLabel(
                                            Icons.undo_rounded,
                                            t.undo,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: compact ? 1 : 9,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: Size(48, buttonHeight),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                          ),
                                          onPressed: _replaying || _celebrating
                                              ? null
                                              : () => setState(
                                                  () =>
                                                      _restartBoard(controller),
                                                ),
                                          child: _buttonLabel(
                                            Icons.refresh_rounded,
                                            t.restart,
                                          ),
                                        ),
                                      ),
                                      if (compact) ...[
                                        const SizedBox(width: 4),
                                        IconButton(
                                          tooltip: t.levels,
                                          constraints: BoxConstraints(
                                            minWidth: 48,
                                            minHeight: buttonHeight,
                                          ),
                                          onPressed:
                                              widget.play.mode ==
                                                  PlayMode.campaign
                                              ? _pickLevel
                                              : null,
                                          icon: const Icon(
                                            Icons.grid_view_rounded,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (controller.state.isComplete && !_replaying)
                // 머리글(BLORIQ·홈·메뉴)과 아래 버튼은 그대로 두고 보드 영역만 덮는다.
                Positioned(
                  left: 0,
                  right: 0,
                  top: _overlayInsets.top,
                  bottom: _overlayInsets.bottom,
                  child: _victoryOverlay(t, controller),
                ),
              if (controller.state.isComplete && _replaying)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 0,
                  right: 0,
                  child: Center(child: _replayBanner(t)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 결과 팝업이 덮는 범위. 위 머리글과 아래 버튼 줄은 계속 누를 수 있다.
  EdgeInsets get _overlayInsets {
    final padding = MediaQuery.paddingOf(context);
    final compact = MediaQuery.sizeOf(context).height - padding.vertical < 700;
    return EdgeInsets.only(
      top: padding.top + (compact ? 2 : 8) + 48,
      bottom: _tutorial == null
          ? padding.bottom + (compact ? 6 : 12) + _buttonHeight
          : padding.bottom,
    );
  }

  /// 보드 위 결과 팝업. 뒤 화면은 반투명 남색과 약한 흐림으로 비친다.
  Widget _victoryOverlay(AppLocalizations t, PuzzleController controller) {
    final colors = GameTheme.colorsOf(context);
    return AnimatedBuilder(
      animation: _victory,
      builder: (context, child) {
        final dim = _reduceMotion || _discovery != null
            ? 1.0
            : ((_victory.value - .2) / .2).clamp(0.0, 1.0);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 팝업이 떠 있는 동안 보드를 누르지 못하게 막는다.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              onPanStart: (_) {},
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 3 * dim, sigmaY: 3 * dim),
                  child: ColoredBox(
                    color: colors.background.withValues(alpha: .5 * dim),
                  ),
                ),
              ),
            ),
            ?child,
          ],
        );
      },
      child: SafeArea(
        top: false,
        bottom: false,
        child: LayoutBuilder(
          builder: (context, area) => Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GameSpacing.page,
                vertical: GameSpacing.small,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  maxHeight: math.max(
                    1,
                    area.maxHeight - GameSpacing.small * 2,
                  ),
                ),
                // 내용이 길어도 스크롤 없이 화면 안에 맞춰 줄인다.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: math.min(400, area.maxWidth - GameSpacing.page * 2),
                    child: _buildVictory(t, controller),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 리플레이 중에는 팝업을 접고 위쪽에 작은 띠만 남긴다.
  Widget _replayBanner(AppLocalizations t) {
    final colors = GameTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.reward.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_circle_outline, size: 18, color: colors.rewardInk),
          const SizedBox(width: 6),
          Text(
            t.watchReplay,
            style: GameTypography.label.copyWith(fontSize: 14),
          ),
          TextButton.icon(
            onPressed: () {
              _stopReplay();
              setState(() {});
            },
            icon: const Icon(Icons.skip_next, size: 18),
            label: Text(t.skipReplay),
          ),
        ],
      ),
    );
  }

  FamilyAbilities get _abilities {
    final companion = widget.session.collection.companion;
    return widget.session.progression.abilitiesFor(
      companionId: companion?.id,
      companionFamily: companion?.family,
    );
  }

  /// 이동 수 옆의 별빛 길 버튼. 무료·사용권·별가루 비용을 함께 보여 준다.
  /// 풀이 따라 하기 중임을 알리는 띠. "직접 풀기"는 판을 처음부터 다시 연다.
  Widget _guideBanner(AppLocalizations t, GameColors colors) => Container(
    key: const ValueKey('guide-banner'),
    padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
    decoration: BoxDecoration(
      color: colors.reward.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        if (_hintBusy)
          HintProgress(
            t.starlightCalculating,
            size: 18,
            color: colors.rewardInk,
          )
        else
          Icon(Icons.auto_awesome_rounded, size: 18, color: colors.rewardInk),
        const SizedBox(width: 6),
        Expanded(
          child: KeepAllText(
            AssistText.guiding.resolve(t.localeName),
            style: GameTypography.body.copyWith(fontSize: 14),
          ),
        ),
        TextButton(
          key: const ValueKey('guide-stop'),
          onPressed: () =>
              setState(() => _restartBoard(_controller!, countStruggle: false)),
          child: Text(AssistText.stopGuide.resolve(t.localeName)),
        ),
      ],
    ),
  );

  Widget _starlightButton(
    AppLocalizations t,
    GameColors colors,
    PuzzleController controller,
  ) {
    final companion = widget.session.collection.companion;
    final quote = widget.session.progression.quoteStarlightPath(
      freeUsedThisAttempt: _starlightFreeUsed,
      levelKey: _assistKey,
      companionId: companion?.id,
      companionFamily: companion?.family,
    );
    final price = switch (quote.source) {
      StarlightPathSource.free => t.starlightFree,
      StarlightPathSource.charge => t.starlightPass,
      StarlightPathSource.stardust => '${quote.cost}',
    };
    final enabled =
        !controller.state.isComplete &&
        !_replaying &&
        !_celebrating &&
        !_hintBusy;
    final cap = _starCap;
    final button = Tooltip(
      message: cap < 3
          ? '${t.starlightPath} · ${AssistCapText.kept.resolve(t.localeName)}'
          : t.starlightPath,
      child: Material(
        color: colors.reward.withValues(alpha: .14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.reward.withValues(alpha: .5)),
        ),
        child: InkWell(
          key: const ValueKey('starlight-path'),
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? () => _useStarlight(t) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hintBusy)
                  HintProgress(t.starlightCalculating, color: colors.rewardInk)
                else
                  Icon(Icons.auto_awesome, size: 20, color: colors.rewardInk),
                Text(
                  price,
                  style: GameTypography.label.copyWith(
                    fontSize: 11,
                    color: colors.rewardInk,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (cap >= 3) return button;
    // 도움을 쓴 판: 다시 시작해도 상한이 남아 있음을 늘 보여 준다.
    return Badge(
      key: const ValueKey('assist-cap-badge'),
      backgroundColor: colors.reward,
      textColor: colors.rewardInk,
      label: Text(AssistCapText.badge(cap).resolve(t.localeName)),
      // 버튼 위 가운데에 붙여서 화면 오른쪽 끝을 넘지 않게 한다.
      alignment: Alignment.topCenter,
      offset: const Offset(-26, -10),
      child: button,
    );
  }

  /// 결과 팝업의 성장 보상: 경험치 막대, 별가루, 레벨 업, 권능, 유대, 맨손 별.
  Widget? _rewardView(AppLocalizations t) {
    final reward = _reward;
    if (reward == null || (!reward.saved && reward.xpGained == 0)) return null;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final standing = reward.standing;
    final badges = <(IconData, String, Color)>[
      // 별 모으기 업적이 가장 큰 소식이라 맨 앞에 둔다.
      for (final achievement in reward.achievements)
        (
          Icons.emoji_events_rounded,
          achievementReached(achievement.name).resolve(lang),
          colors.rewardInk,
        ),
      // 한 번에 여러 레벨이 올라도 마지막 레벨 한 줄만 보여 준다.
      if (reward.levelsGained.lastOrNull case final up?)
        (
          Icons.keyboard_double_arrow_up_rounded,
          t.rewardLevelUp(up.level),
          colors.goalInk,
        ),
      if (reward.newPower case final power?)
        (
          Icons.auto_awesome,
          t.rewardPower(power.name.resolve(lang)),
          colors.rewardInk,
        ),
      for (final trail in reward.newTrails)
        if (trailById(trail) case final definition?)
          (
            Icons.blur_on_rounded,
            t.rewardTrail(definition.name.resolve(lang)),
            colors.echoInk,
          ),
      for (final title in reward.newTitles)
        if (titleById(title) case final definition?)
          (
            Icons.workspace_premium_rounded,
            t.rewardTitle(definition.name.resolve(lang)),
            colors.rewardInk,
          ),
      if (reward.newStarlightCharges > 0)
        (
          Icons.confirmation_number_outlined,
          t.rewardCharge(reward.newStarlightCharges),
          colors.rewardInk,
        ),
      if (reward.bondLevelUp case final level?)
        if (widget.session.collection.companion case final friend?)
          (
            Icons.favorite_rounded,
            t.rewardBond(friend.name.inLocale(lang), level),
            colors.echoInk,
          ),
      if (reward.newBareHanded)
        (Icons.back_hand_rounded, t.rewardBareHanded, colors.goalInk),
    ];
    final bondLine = reward.bondLevelUp == 2
        ? widget.session.collection.companion?.bondLine?.inLocale(lang)
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: GameSpacing.small),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.reward.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.goal.withValues(alpha: .2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  t.playerLevel(standing.level),
                  style: GameTypography.reward.copyWith(
                    fontSize: 16,
                    color: colors.goalInk,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 10,
                    value: standing.progress,
                    color: colors.goal,
                    backgroundColor: colors.outline.withValues(alpha: .25),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            children: [
              Text(
                t.rewardXp(reward.xpGained),
                style: GameTypography.label.copyWith(
                  fontSize: 16,
                  color: colors.goalInk,
                ),
              ),
              if (reward.stardustGained > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 14,
                      color: colors.rewardInk,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        t.rewardStardust(reward.stardustGained),
                        style: GameTypography.label.copyWith(
                          fontSize: 16,
                          color: colors.rewardInk,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          // 특별 보상은 가장 중요한 두 개만 보여 준다(레벨 업·권능이 먼저).
          for (final (icon, label, color) in badges.take(2))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Flexible(
                    child: KeepAllText(
                      label,
                      style: GameTypography.body.copyWith(
                        fontSize: 15.5,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (bondLine != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: KeepAllText(
                '“$bondLine”',
                textAlign: TextAlign.center,
                style: GameTypography.body.copyWith(
                  fontSize: 14,
                  color: colors.secondaryText,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 큰 글자에서도 넘치지 않도록 버튼 글자는 말줄임으로 줄인다.
  Widget _buttonLabel(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  );

  double _widthCell(double width, int columns) =>
      (math.min(
            width,
            GameSpacing.maxBoardWidth + BoardGeometry.defaultFrameInset * 2,
          ) -
          BoardGeometry.defaultFrameInset * 2) /
      columns;

  double get _textScale => MediaQuery.textScalerOf(context).scale(16) / 16;

  /// 동료·이동 수 줄의 높이. 정수로 고정해 아래 보드가 픽셀 경계에 놓이게 한다.
  double _rowHeight(_GameFit fit) => fit == _GameFit.minimal
      ? 48
      : math.max(50.0, 24 + 24 * _textScale).ceilToDouble();

  /// 칸이 48px 아래로 내려가지 않는 가장 넉넉한 배치를 고른다.
  /// 스크롤은 줄여도 들어가지 않을 때(가로 화면, 아주 큰 글자)만 쓴다.
  _GameFit _chooseFit(
    AppLocalizations t,
    BoxConstraints constraints,
    double minBoard,
  ) {
    final room = constraints.maxHeight - minBoard;
    var fit = _GameFit.values.firstWhere(
      (fit) =>
          fit == _GameFit.scroll || room >= _chromeHeight(t, constraints, fit),
    );
    if (fit.index < _fitFloor.index) fit = _fitFloor;
    // 너비 때문에 칸이 작은 화면은 스크롤해도 칸이 커지지 않는다.
    if (fit == _GameFit.scroll &&
        _widthCell(
              constraints.maxWidth - GameSpacing.page * 2,
              _controller!.state.level.boardWidth,
            ) <
            _minCell) {
      fit = _GameFit.minimal;
    }
    return fit;
  }

  /// 보드를 제외한 머리글·동료·권능·안내·버튼 높이의 보수적 추정치.
  double _chromeHeight(
    AppLocalizations t,
    BoxConstraints constraints,
    _GameFit fit,
  ) {
    final controller = _controller!;
    final compact = constraints.maxHeight < 700;
    final gap = compact ? 4.0 : 8.0;
    final row = _rowHeight(fit);
    return (compact ? 8.0 : 20.0) +
        48 +
        (fit.index >= _GameFit.tight.index
            ? row + gap
            : 26 * _textScale + 8 + gap + row + gap) +
        (_expansion && _ownedPowers.isNotEmpty
            ? math.max(44.0, 17 * _textScale + 8) + (compact ? 4 : 6)
            : 0) +
        (fit == _GameFit.minimal
            ? 4.0
            : compact
            ? 12.0
            : 20.0) +
        _legendSlotHeight(t, constraints, fit) +
        (_guided || _offerHelp(controller)
            ? 6 + math.max(48.0, 42 * _textScale + 4)
            : 0) +
        (fit == _GameFit.full && _hasNoMoves(controller) ? 56 : 0) +
        (_tutorial == null
            ? math.max(48.0, 22 * _textScale + 18)
            : 22 * _textScale + 24);
  }

  /// 이번 판에 나올 수 있는 가장 긴 설명까지 들어가는 칸의 높이.
  double _legendSlotHeight(
    AppLocalizations t,
    BoxConstraints constraints,
    _GameFit fit,
  ) {
    final level = _controller!.state.level;
    return MechanicLegend.slotHeight(
      context,
      width: math.min(constraints.maxWidth, 560.0) - GameSpacing.page * 2,
      compact: fit != _GameFit.full,
      lines: fit == _GameFit.minimal ? 1 : 2,
      notes: _tutorial != null
          ? [t.tutorialMove, t.tutorialBlock, t.tutorialFinish]
          : [
              t.noMoves,
              t.instruction,
              t.echoInstruction,
              for (final power in _ownedPowers)
                WorldText.armed(power).resolve(t.localeName),
            ],
      mechanics: _tutorial != null
          ? const []
          : MechanicLegend.possibleTexts(level, t),
    );
  }

  Widget _scrollable(bool scroll, Widget child) =>
      scroll ? SingleChildScrollView(child: child) : child;

  /// 남은 공간에 맞춰 보드 크기를 정한다. Flame과 터치가 같은 좌표계를 쓴다.
  Widget _buildBoard(AppLocalizations t) => LayoutBuilder(
    builder: (context, area) {
      final controller = _controller!;
      final geometry = BoardGeometry.fit(
        available: Size(
          math.max(
            1.0,
            math.min(
              area.maxWidth,
              GameSpacing.maxBoardWidth + BoardGeometry.defaultFrameInset * 2,
            ),
          ),
          math.max(1.0, area.maxHeight),
        ),
        columns: controller.state.level.boardWidth,
        rows: controller.state.level.boardHeight,
        devicePixelRatio: View.of(context).devicePixelRatio,
      );
      if (_fitFloor != _GameFit.scroll &&
          geometry.cellSize < _minCell &&
          _widthCell(area.maxWidth, controller.state.level.boardWidth) >=
              _minCell) {
        // 추정보다 칸이 작아지면 다음 프레임에 한 단계 더 줄인다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _fitFloor != _GameFit.scroll) {
            setState(() => _fitFloor = _GameFit.values[_fitFloor.index + 1]);
          }
        });
      }
      if (_geometry != null && !_geometry!.sameLayout(geometry)) {
        _cancelDrag();
      }
      _geometry = geometry;
      _game!.configureGeometry(geometry);
      // 정수 좌표에 두어 보드 영역과 Flame 좌표가 정확히 일치하게 한다.
      final outer = geometry.outerSize;
      return Padding(
        padding: EdgeInsets.only(
          left: math
              .max(0.0, (area.maxWidth - outer.width) / 2)
              .floorToDouble(),
          top: math
              .max(0.0, (area.maxHeight - outer.height) / 2)
              .floorToDouble(),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: StarBoardFrame(
            geometry: geometry,
            skin: _boardSkin,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(GameSpacing.radius),
              child: SizedBox(
                width: geometry.canvasSize.width,
                height: geometry.canvasSize.height,
                child: Semantics(
                  label: t.boardLabel,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: (d) => _start(d),
                    onHorizontalDragUpdate: _update,
                    onHorizontalDragEnd: (_) => _end(),
                    onHorizontalDragCancel: _cancelDrag,
                    onVerticalDragStart: (d) => _start(d),
                    onVerticalDragUpdate: _update,
                    onVerticalDragEnd: (_) => _end(),
                    onVerticalDragCancel: _cancelDrag,
                    child: Listener(
                      onPointerDown: (_) => _audio?.onUserInteraction(),
                      onPointerCancel: (_) => _cancelDrag(),
                      child: GameWidget(game: _game!),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

enum _HelpChoice { starlight, guide }

/// 막혔을 때 여는 도움 시트. 열쇠 한 줄은 바로 보여 주고,
/// 별빛 길과 풀이 따라 하기는 고른 쪽을 돌려준다.
class _HelpSheet extends StatelessWidget {
  const _HelpSheet({required this.keyHint, required this.lang});
  final String keyHint;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AssistText.title.resolve(lang),
              textAlign: TextAlign.center,
              style: GameTypography.reward.copyWith(
                fontSize: 22,
                color: colors.rewardInk,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('help-key'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.reward.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.reward.withValues(alpha: .4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.key_rounded,
                        size: 20,
                        color: colors.rewardInk,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        AssistText.keyTitle.resolve(lang),
                        style: GameTypography.label.copyWith(
                          color: colors.rewardInk,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  KeepAllText(
                    keyHint,
                    style: GameTypography.body.copyWith(fontSize: 16),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            KeepAllText(
              AssistText.selfNote.resolve(lang),
              textAlign: TextAlign.center,
              style: GameTypography.body.copyWith(
                fontSize: 13.5,
                color: colors.secondaryText,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('help-starlight'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context, _HelpChoice.starlight),
              icon: const Icon(Icons.flare_rounded),
              label: Text(AssistText.starlight.resolve(lang)),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('help-guide'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () => Navigator.pop(context, _HelpChoice.guide),
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(AssistText.guide.resolve(lang)),
            ),
            const SizedBox(height: 4),
            KeepAllText(
              AssistText.guideNote.resolve(lang),
              textAlign: TextAlign.center,
              style: GameTypography.body.copyWith(
                fontSize: 13,
                color: colors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
