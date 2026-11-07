import 'dart:ui' as ui;
import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/game_audio.dart';
import 'domain/puzzle.dart';
import 'design/game_theme.dart';
import 'game/bloriq_game.dart';
import 'game/mechanic_legend.dart';
import 'design/keep_all_text.dart';
import 'game/board_geometry.dart';
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
import 'game/power_bar.dart';
import 'world2/world2_progress.dart';
import 'world2/world2_text.dart';
import 'world2/world2_catalog.dart';
import 'world2/world2_map.dart';

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
    theme: GameTheme.light,
    darkTheme: GameTheme.dark,
    themeMode: _settings?.themeMode ?? ThemeMode.system,
    // Flutter 위젯과 Flame 보드가 같은 프레임에 같은 팔레트로 바뀐다.
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

class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.session,
    required this.initialLevelId,
    this.play = const PlayContext.campaign(),
    required this.settings,
  });

  final GameSession session;
  final PlayContext play;
  final int initialLevelId;
  final GameSettings settings;

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
  bool _scrollLayout = false;
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
  bool _starlightFreeUsed = false;

  /// 월드 2: 권능 막대에서 고른 권능. 다음 밀기가 이 권능으로 움직인다.
  PuzzlePower? _armedPower;

  /// 월드 2 별자리를 저장 전에 떠 둔다.
  World2Atlas? _world2Before;

  bool get _world2 => widget.play.world == 2;

  /// 월드 2에서 쓸 수 있는 권능(성장 기록 기준). 월드 1은 늘 비어 있다.
  Set<PuzzlePower> get _ownedPowers => _world2
      ? ownedBoardPowers(widget.session.progression.hasPower)
      : const {};

  /// 이 스테이지에서 실제로 쓸 수 있는 권능: 가진 권능 중 스테이지가 여는 것.
  Set<PuzzlePower> _stagePowers(Level level) => level.world == 2
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
        : _world2
        ? widget.session.world2Levels
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
  }

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
    _world2Before = _world2 ? widget.session.world2Atlas : null;
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
  }

  void _stopReplay() {
    _replaying = false;
    _game?.skipReplay();
  }

  @override
  void dispose() {
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
    final previousStars = _progress!
        .forLevel(state.level.id, revision: state.level.revision)
        ?.bestStars;
    final usedStarlight = _starlightUsed;
    final usedPower = controller.usedPower;
    final world2Before = _world2Before;
    final result = await _progress!.recordCompletion(
      levelId: state.level.id,
      revision: state.level.revision,
      moves: state.moves,
      minimumMoves: state.level.minimumMoves,
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
    final world2After = world2Before == null
        ? null
        : widget.session.world2Atlas;
    final world2Event = world2Before == null || world2After == null
        ? null
        : World2Atlas.diff(world2Before, world2After, state.level.id);
    final reward = await widget.session.progression.recordClear(
      levelKey: '${state.level.id}:${state.level.revision}',
      stars: starRating(
        moves: state.moves,
        minimumMoves: state.level.minimumMoves,
      ),
      previousBestStars: previousStars,
      usedStarlightPath: usedStarlight,
      companionId: companion?.id,
      companionFamily: companion?.family,
      constellationCompletedChapter: world2Event != null
          ? world2Event.completed
          : event?.chapterCompleted == true
          ? chapter?.definition.chapter
          : null,
      constellationGoldenChapter: world2Event != null
          ? world2Event.golden
          : event?.becameGolden == true
          ? chapter?.definition.chapter
          : null,
      bareHandedClear: state.level.world == 2
          ? isWorld2BareHanded(
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
    setState(() => _reward = reward);
  }

  void _resetAssist() {
    _reward = null;
    _armedPower = null;
    _starlightUsed = false;
    _starlightFreeUsed = false;
    _game?.hintMove = null;
  }

  /// 별빛 길: 지금 상태에서 가장 짧은 다음 한 수를 보드에 비춘다.
  Future<void> _useStarlight(AppLocalizations t) async {
    final controller = _controller!;
    if (controller.state.isComplete || _replaying || _modalOpen) return;
    final messenger = ScaffoldMessenger.of(context);
    final solution = const PuzzleSolver().solveFromState(controller.state);
    if (solution == null || solution.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(t.starlightNoMove)));
      return;
    }
    final companion = widget.session.collection.companion;
    final quote = await widget.session.progression.useStarlightPath(
      freeUsedThisAttempt: _starlightFreeUsed,
      companionId: companion?.id,
      companionFamily: companion?.family,
    );
    if (!mounted || !identical(_controller, controller)) return;
    if (quote == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.starlightShort)));
      return;
    }
    final move = solution.first;
    final from = controller.state.blocks
        .firstWhere((block) => block.id == move.blockId)
        .position;
    if (move.power case final power?) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(World2Text.hintPower(power).resolve(t.localeName)),
        ),
      );
    }
    setState(() {
      if (quote.source == StarlightPathSource.free) _starlightFreeUsed = true;
      if (!_starlightUsed) {
        messenger.showSnackBar(SnackBar(content: Text(t.starlightCapped)));
      }
      _starlightUsed = true;
      _game!.hintMove = (from: from, to: move.target);
    });
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
      _game!.setDrag(_dragBlock, aligned);
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
          _game!.animateMove(block.id, from, previousEcho);
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
      final replay = await showGameHelp(context, widget.settings);
      if (replay == true && mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => GameScreen(
              session: widget.session,
              initialLevelId: 1,
              settings: widget.settings,
              play: PlayContext.tutorialReplay(
                widget.session.levels.firstWhere((level) => level.id == 1),
              ),
            ),
          ),
        );
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
      () => _world2
          ? showWorld2Map(context, widget.session, widget.settings)
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

  /// 화면에 보이는 스테이지 번호. 월드 2는 1..25로 센다.
  int _displayNumber(Level level) =>
      level.world == 2 ? level.id - World2.firstLevelId + 1 : level.id;

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
    final stars = capAssistedStars(
      starRating(moves: state.moves, minimumMoves: state.level.minimumMoves),
      usedStarlightPath: _starlightUsed,
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
              Text(t.completeDetail(state.moves)),
              if (_bestMoves case final best?) Text(t.bestMoves(best)),
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
              if (widget.play.mode == PlayMode.campaign &&
                  widget.session.collection.owned.length ==
                      widget.session.story.released.length &&
                  widget.session.story.released.length == 25)
                Text(t.seasonComplete),
              const SizedBox(height: GameSpacing.tiny),
              Text(
                state.moves == state.level.minimumMoves
                    ? t.optimalComplete
                    : t.improveComplete(state.level.minimumMoves),
                style: TextStyle(color: colors.secondaryText, fontSize: 14),
              ),
            ],
          ),
        ),
        actions: _victoryActions(t, controller),
      ),
    );
  }

  /// 결과 팝업 아래쪽 버튼. 다음 스테이지가 가장 크고 나머지는 작은 버튼으로 둔다.
  Widget _victoryActions(AppLocalizations t, PuzzleController controller) {
    final small = OutlinedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: GameTypography.label.copyWith(fontSize: 13.5),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
          onPressed: () => widget.play.mode != PlayMode.campaign
              ? Navigator.pop(context)
              : _select(_index + 1 < _loaded.length ? _index + 1 : 0),
          icon: const Icon(Icons.arrow_forward),
          label: Text(
            widget.play.mode != PlayMode.campaign
                ? t.close
                : _index + 1 < _loaded.length
                ? t.next
                : t.firstLevel,
          ),
        ),
        const SizedBox(height: GameSpacing.small),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              style: small,
              onPressed: _replaying ? null : () => _select(_index),
              icon: const Icon(Icons.replay, size: 18),
              label: Text(t.tryAgain),
            ),
            OutlinedButton.icon(
              style: small,
              onPressed: _celebrating ? null : _watchReplay,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: Text(t.watchReplay),
            ),
            OutlinedButton.icon(
              style: small,
              onPressed: _replaying ? null : () => _showPostcard(t, controller),
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(t.postcard),
            ),
            if (_discovery case final friend?) ...[
              OutlinedButton.icon(
                key: const ValueKey('result-album'),
                style: small,
                onPressed: _openAlbum,
                icon: const Icon(Icons.auto_stories_outlined, size: 18),
                label: Text(t.album),
              ),
              OutlinedButton.icon(
                key: const ValueKey('result-discovery-share'),
                style: small,
                onPressed: () => _withModal<void>(
                  () => showStoryCard(
                    context,
                    [friend],
                    chapter: widget.session.story.chapter(friend.chapter),
                    reduceMotion: _reduceMotion,
                  ),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 18),
                label: Text(t.discoveryCard),
              ),
            ],
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
      return [note(World2Text.armed(power).resolve(t.localeName))];
    }
    final gate = state.level.echoGate == null
        ? null
        : _gateBlocked
        ? t.gateClosed
        : state.isGateOpen
        ? t.gateOpen
        : state.blocks.any((block) => block.position == state.level.echoGate)
        ? t.gateOccupied
        : t.gateInstruction;
    final mechanics = [
      if (state.level.echoErasers.isNotEmpty)
        LegendItem(LegendKind.eraser, t.eraserRule),
      if (state.level.echoHolds.isNotEmpty)
        LegendItem(LegendKind.hold, t.holdRule),
      if (state.level.oneWays.isNotEmpty)
        LegendItem(LegendKind.oneWay, t.oneWayRule),
      if (state.level.goalOnlyTiles.isNotEmpty)
        LegendItem(LegendKind.goalOnly, t.goalOnlyRule),
      if (gate != null) LegendItem(LegendKind.gate, gate),
    ];
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
    _game!.configureAppearance(colors: colors, reduceMotion: _reduceMotion);
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
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 스크롤 없이 한 화면에 고정한다. 보드는 남은 높이를 모두 쓴다.
                    final compact = constraints.maxHeight < 700;
                    final complete = controller.state.isComplete;
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
                    // 보드 칸이 48px보다 작아지는 아주 작은 화면이나 가로 화면에서만 스크롤한다.
                    final layoutKey = (
                      constraints.biggest,
                      _loaded[_index].id,
                      MediaQuery.textScalerOf(context).scale(1),
                    );
                    if (_layoutKey != layoutKey) {
                      _layoutKey = layoutKey;
                      _scrollLayout = false;
                    }
                    final rows = controller.state.level.boardHeight;
                    final minBoard =
                        rows * _minCell + BoardGeometry.defaultFrameInset * 2;
                    if (!complete &&
                        _widthCell(
                              constraints.maxWidth - GameSpacing.page * 2,
                              controller.state.level.boardWidth,
                            ) >=
                            _minCell &&
                        constraints.maxHeight -
                                _chromeEstimate(
                                  constraints,
                                  hint,
                                  _hasNoMoves(controller),
                                ) <
                            minBoard) {
                      // 첫 프레임부터 넘치지 않도록 보드 외 높이를 넉넉히 추정한다.
                      _scrollLayout = true;
                    }
                    final scroll = _scrollLayout;
                    final boardHeight = math.max(
                      minBoard,
                      constraints.maxHeight * .55,
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
                                Semantics(
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
                                          Text(
                                            widget.play.mode == PlayMode.daily
                                                ? t.dailyEcho
                                                : t.level(
                                                    _displayNumber(
                                                      _loaded[_index],
                                                    ),
                                                  ),
                                            style: labelStyle,
                                          ),
                                          if (widget.session.world2Story
                                                  ?.forLevel(_loaded[_index].id)
                                              case final spirit? when _world2)
                                            Flexible(
                                              child: Text(
                                                ' · ${spirit.levelTitle.inLocale(t.localeName)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: labelStyle.copyWith(
                                                  color: colors.rewardInk,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                          if (story?.released == true)
                                            Flexible(
                                              child: Text(
                                                ' · ${story!.levelTitle.inLocale(t.localeName)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: labelStyle.copyWith(
                                                  color: colors.rewardInk,
                                                  decoration:
                                                      TextDecoration.none,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: compact ? 4 : 8),
                                // 정수 높이로 고정해 아래 보드가 픽셀 경계에 놓이게 한다.
                                SizedBox(
                                  height: math
                                      .max(
                                        50.0,
                                        24 +
                                            MediaQuery.textScalerOf(context)
                                                    .scale(15) *
                                                1.6,
                                      )
                                      .ceilToDouble(),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      ...[
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
                                      ],
                                      Flexible(
                                        flex: 2,
                                        child: StatPill(
                                          icon: Icons.swipe_rounded,
                                          label: _abilities.showMinimumMoves
                                              ? '${t.moves(controller.state.moves)} · '
                                                    '${t.minimumMovesChip(controller.state.level.minimumMoves)}'
                                              : t.moves(controller.state.moves),
                                          color: colors.echoInk,
                                        ),
                                      ),
                                      if (_tutorial == null &&
                                          widget.play.mode !=
                                              PlayMode.tutorialReplay) ...[
                                        const SizedBox(width: 6),
                                        _starlightButton(t, colors, controller),
                                      ],
                                    ],
                                  ),
                                ),
                                SizedBox(height: compact ? 4 : 8),
                                if (_world2 && _ownedPowers.isNotEmpty) ...[
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
                                    vertical: compact ? 6 : 10,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: _reduceMotion || _tutorial != null
                                        ? Duration.zero
                                        : GameEffects.panelDuration,
                                    layoutBuilder: (current, previous) => Stack(
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
                                        MechanicLegend(items: legend),
                                        if (_hasNoMoves(controller)) ...[
                                          const SizedBox(height: 8),
                                          FilledButton.icon(
                                            onPressed: () => _undo(controller),
                                            icon: const Icon(Icons.undo),
                                            label: Text(t.undoLastMove),
                                          ),
                                        ],
                                      ],
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
                                        flex: compact ? 4 : 11,
                                        child: FilledButton(
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(48, 48),
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
                                        flex: compact ? 4 : 9,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size(48, 48),
                                          ),
                                          onPressed: _replaying || _celebrating
                                              ? null
                                              : () => setState(() {
                                                  _skipCelebration();
                                                  _attempt?.restart();
                                                  _attempt?.finish(
                                                    'level_end',
                                                    controller.state.moves,
                                                    reason: 'restart',
                                                  );
                                                  _acknowledgeDiscovery();
                                                  _discovery = null;
                                                  _storyHidden = false;
                                                  _narrative.react(
                                                    CompanionReaction.idle,
                                                  );
                                                  controller.restart();
                                                  _resetAssist();
                                                  _attempt = null;
                                                  _startAttempt();
                                                  _game!.clearEffects();
                                                  _gateBlocked = false;
                                                  _completion = null;
                                                }),
                                          child: _buttonLabel(
                                            Icons.refresh_rounded,
                                            t.restart,
                                          ),
                                        ),
                                      ),
                                      if (compact) ...[
                                        const SizedBox(width: 4),
                                        Expanded(
                                          flex: 3,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              minimumSize: const Size(48, 48),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                  ),
                                            ),
                                            onPressed:
                                                widget.play.mode ==
                                                    PlayMode.campaign
                                                ? _pickLevel
                                                : null,
                                            child: _buttonLabel(
                                              Icons.grid_view_rounded,
                                              t.levels,
                                            ),
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
          ? padding.bottom + (compact ? 6 : 12) + 48
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
  Widget _starlightButton(
    AppLocalizations t,
    GameColors colors,
    PuzzleController controller,
  ) {
    final companion = widget.session.collection.companion;
    final quote = widget.session.progression.quoteStarlightPath(
      freeUsedThisAttempt: _starlightFreeUsed,
      companionId: companion?.id,
      companionFamily: companion?.family,
    );
    final price = switch (quote.source) {
      StarlightPathSource.free => t.starlightFree,
      StarlightPathSource.charge => t.starlightPass,
      StarlightPathSource.stardust => '${quote.cost}',
    };
    final enabled =
        !controller.state.isComplete && !_replaying && !_celebrating;
    return Tooltip(
      message: t.starlightPath,
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
  }

  /// 결과 팝업의 성장 보상: 경험치 막대, 별가루, 레벨 업, 권능, 유대, 맨손 별.
  Widget? _rewardView(AppLocalizations t) {
    final reward = _reward;
    if (reward == null || (!reward.saved && reward.xpGained == 0)) return null;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    final standing = reward.standing;
    final badges = <(IconData, String, Color)>[
      for (final up in reward.levelsGained)
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
                    fontSize: 15,
                    color: colors.goalInk,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    minHeight: 9,
                    value: standing.progress,
                    color: colors.goal,
                    backgroundColor: colors.outline.withValues(alpha: .25),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                t.rewardXp(reward.xpGained),
                style: GameTypography.label.copyWith(
                  fontSize: 13,
                  color: colors.goalInk,
                ),
              ),
            ],
          ),
          if (reward.stardustGained > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '✦ ${t.rewardStardust(reward.stardustGained)}',
                style: GameTypography.label.copyWith(
                  fontSize: 13.5,
                  color: colors.rewardInk,
                ),
              ),
            ),
          for (final (icon, label, color) in badges)
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
                        fontSize: 14.5,
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

  /// 보드를 제외한 머리글·동료·안내·버튼 높이의 보수적 추정치.
  double _chromeEstimate(
    BoxConstraints constraints,
    String hint,
    bool noMoves,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final width = math.min(constraints.maxWidth, 560.0) - GameSpacing.page * 2;
    final hintLines = hint
        .split('\n')
        .fold<int>(
          0,
          (lines, line) =>
              lines +
              math.max(1, (line.length * 16 * scale * .8 / width).ceil()),
        );
    return 48 +
        24 * scale +
        math.max(50.0, 34 * scale) +
        hintLines * math.max(38.0, 24 * scale) +
        (noMoves ? 56 : 0) +
        (_tutorial == null
            ? math.max(48.0, 22 * scale + 26)
            : 22 * scale + 24) +
        56;
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
      if (!_scrollLayout &&
          !(controller.state.isComplete && !_replaying) &&
          geometry.cellSize < _minCell &&
          _widthCell(area.maxWidth, controller.state.level.boardWidth) >=
              _minCell) {
        // 높이가 부족해 칸이 터치 기준보다 작아지면 다음 프레임에 스크롤 배치로 바꾼다.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_scrollLayout) setState(() => _scrollLayout = true);
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
