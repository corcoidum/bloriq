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
import 'game/board_geometry.dart';
import 'game/victory_panel.dart';
import 'l10n/app_localizations.dart';
import 'postcard/echo_postcard.dart';
import 'progress/progress_repository.dart';
import 'settings/game_settings.dart';
import 'app/app_entry.dart';
import 'app/game_session.dart';
import 'app/experience_dialogs.dart';
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
  final ScrollController _pageScroll = ScrollController();
  BoardGeometry? _geometry;
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
    _loaded = widget.play.level == null
        ? widget.session.levels
        : [widget.play.level!];
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
    _controller = PuzzleController(_loaded[_index]);
    _game = BloriqGame(_controller!);
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
    _discovery = null;
    _storyHidden = false;
    _constellation = null;
    _constellationPending = false;
    _atlasBefore = _atlasAfter = null;
    _narrative.react(CompanionReaction.idle);
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
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
      _controller = PuzzleController(_loaded[index]);
      _game = BloriqGame(_controller!);
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
    _pageScroll.dispose();
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
      if (mounted && identical(_controller, controller)) {
        setState(() => _completion = result);
      }
      return;
    }
    if (widget.play.mode != PlayMode.campaign) return;
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
              : t.level(state.level.id),
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
        final moved = controller.move(block.id, target);
        _tutorial?.observe(before, target, moved);
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
          HapticFeedback.selectionClick();
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
          _game!.flashBlocked(target);
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
    return !state.isComplete &&
        controller.canUndo &&
        !state.blocks.any(
          (block) => block.position.neighbors.any(
            (target) => MoveValidator.canMove(state, block.id, target),
          ),
        );
  }

  void _undo(PuzzleController controller) {
    _acknowledgeDiscovery();
    _discovery = null;
    _storyHidden = false;
    _skipCelebration();
    setState(() {
      controller.undo();
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
      () => showLevelPicker(
        context,
        widget.session,
        widget.settings,
        currentLevelId: _loaded[_index].id,
      ),
    );
    if (id != null && mounted) {
      _select(_loaded.indexWhere((level) => level.id == id));
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
    final stars = starRating(
      moves: state.moves,
      minimumMoves: state.level.minimumMoves,
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
        result: Column(
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
            const SizedBox(height: GameSpacing.small),
            Text(
              state.moves == state.level.minimumMoves
                  ? t.optimalComplete
                  : t.improveComplete(state.level.minimumMoves),
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.secondaryText),
            ),
            const SizedBox(height: GameSpacing.medium),
            FilledButton.icon(
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
              spacing: GameSpacing.small,
              runSpacing: GameSpacing.small,
              children: [
                if (_discovery case final friend?) ...[
                  OutlinedButton.icon(
                    key: const ValueKey('result-album'),
                    onPressed: _openAlbum,
                    icon: const Icon(Icons.auto_stories_outlined),
                    label: Text(t.album),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('result-discovery-share'),
                    onPressed: () => _withModal<void>(
                      () => showStoryCard(
                        context,
                        [friend],
                        chapter: widget.session.story.chapter(friend.chapter),
                        reduceMotion: _reduceMotion,
                      ),
                    ),
                    icon: const Icon(Icons.ios_share_rounded),
                    label: Text(t.discoveryCard),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: _replaying ? null : () => _select(_index),
                  icon: const Icon(Icons.replay),
                  label: Text(t.tryAgain),
                ),
                OutlinedButton.icon(
                  onPressed: _celebrating
                      ? null
                      : _replaying
                      ? () {
                          _stopReplay();
                          setState(() {});
                        }
                      : _watchReplay,
                  icon: Icon(_replaying ? Icons.skip_next : Icons.play_arrow),
                  label: Text(_replaying ? t.skipReplay : t.watchReplay),
                ),
                OutlinedButton.icon(
                  onPressed: _replaying
                      ? null
                      : () => _showPostcard(t, controller),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(t.postcard),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _hint(AppLocalizations t, PuzzleController controller) {
    final state = controller.state;
    // This detects only states with no legal move, not every unsolvable state.
    if (_tutorial case final tutorial?) {
      return switch (tutorial.step) {
        0 => t.tutorialMove,
        1 => t.tutorialBlock,
        _ => t.tutorialFinish,
      };
    }
    if (_hasNoMoves(controller)) return t.noMoves;
    final mechanics = <String>[
      if (state.level.echoErasers.isNotEmpty) t.eraserRule,
      if (state.level.echoHolds.isNotEmpty) t.holdRule,
      if (state.level.oneWays.isNotEmpty) t.oneWayRule,
      if (state.level.goalOnlyTiles.isNotEmpty) t.goalOnlyRule,
    ];
    if (mechanics.isNotEmpty) {
      // 팝업 없이 현재 스테이지의 규칙을 보드 아래에 계속 표시한다.
      if (state.level.echoGate != null) {
        final gateHint = _gateBlocked
            ? t.gateClosed
            : state.isGateOpen
            ? t.gateOpen
            : state.blocks.any(
                (block) => block.position == state.level.echoGate,
              )
            ? t.gateOccupied
            : t.gateInstruction;
        mechanics.add(gateHint);
      }
      return mechanics.join('\n');
    }
    if (state.level.echoGate == null) {
      return state.echo == null ? t.instruction : t.echoInstruction;
    }
    if (_gateBlocked) return t.gateClosed;
    if (state.isGateOpen) return t.gateOpen;
    if (state.blocks.any((block) => block.position == state.level.echoGate)) {
      return t.gateOccupied;
    }
    return t.gateInstruction;
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
    final hint = _hint(t, controller);
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
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 700;
                final boardRoom = math.max(
                  controller.state.level.boardHeight * 48.0,
                  constraints.maxHeight - (compact ? 310 : 350),
                );
                final availableWidth = math.max(
                  1.0,
                  math.min(
                    constraints.maxWidth - GameSpacing.page * 2,
                    GameSpacing.maxBoardWidth +
                        BoardGeometry.defaultFrameInset * 2,
                  ),
                );
                final targetWidth = controller.state.isComplete && !_replaying
                    ? math.min(availableWidth, compact ? 218.0 : 258.0)
                    : availableWidth;
                final geometry = BoardGeometry.fit(
                  available: Size(
                    targetWidth,
                    boardRoom + BoardGeometry.defaultFrameInset * 2,
                  ),
                  columns: controller.state.level.boardWidth,
                  rows: controller.state.level.boardHeight,
                  devicePixelRatio: View.of(context).devicePixelRatio,
                );
                if (_geometry != null && !_geometry!.sameLayout(geometry)) {
                  _cancelDrag();
                }
                _geometry = geometry;
                _game!.configureGeometry(geometry);
                final width = geometry.canvasSize.width;
                final height = geometry.canvasSize.height;
                return Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    controller: _pageScroll,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      padding: EdgeInsets.fromLTRB(
                        GameSpacing.page,
                        compact ? 12 : 28,
                        GameSpacing.page,
                        12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                key: const ValueKey('game-home'),
                                tooltip: t.home,
                                onPressed: _leaveGame,
                                icon: const Icon(Icons.home_outlined),
                              ),
                              Expanded(
                                child: Semantics(
                                  label: t.levels,
                                  button: true,
                                  child: InkWell(
                                    key: const ValueKey('game-levels'),
                                    borderRadius: BorderRadius.circular(12),
                                    onTap:
                                        widget.play.mode == PlayMode.campaign &&
                                            _tutorial == null
                                        ? _pickLevel
                                        : null,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 48,
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            t.lastEchoTitle,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 25,
                                              fontFamily: GameTypography
                                                  .canvasFontFamily,
                                              height: 1.15,
                                              color: colors.rewardInk,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            widget.play.mode == PlayMode.daily
                                                ? t.dailyEcho
                                                : t.level(_loaded[_index].id),
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: colors.echoInk,
                                              fontSize: 15,
                                              decoration:
                                                  widget.play.mode ==
                                                          PlayMode.campaign &&
                                                      _tutorial == null
                                                  ? TextDecoration.underline
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: t.help,
                                onPressed: () => _showHelp(t),
                                icon: const Icon(Icons.help_outline_rounded),
                              ),
                              IconButton(
                                tooltip: t.settings,
                                onPressed: _showSettings,
                                icon: const Icon(Icons.tune_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (!controller.state.isComplete)
                            JourneyCompanions(
                              companion: widget.session.collection.companion,
                              narrative: _narrative,
                              reduceMotion: _reduceMotion,
                              compact: compact,
                              onAlbum: _openAlbum,
                            ),
                          if (widget.play.mode == PlayMode.campaign &&
                              widget.session.story
                                      .forLevel(_loaded[_index].id)
                                      ?.released ==
                                  true)
                            Text(
                              widget.session.story
                                  .forLevel(_loaded[_index].id)!
                                  .levelTitle
                                  .inLocale(t.localeName),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.rewardInk),
                            ),
                          const SizedBox(height: 10),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              StatPill(
                                icon: Icons.swipe_rounded,
                                label: t.moves(controller.state.moves),
                                color: colors.echoInk,
                              ),
                              if (_tutorial != null)
                                TextButton(
                                  key: const ValueKey('skip-tutorial'),
                                  onPressed: _skipTutorial,
                                  child: Text(t.skipTutorial),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          StarBoardFrame(
                            geometry: geometry,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                GameSpacing.radius,
                              ),
                              child: SizedBox(
                                width: width,
                                height: height,
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
                                      onPointerDown: (_) =>
                                          _audio?.onUserInteraction(),
                                      onPointerCancel: (_) => _cancelDrag(),
                                      child: GameWidget(game: _game!),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          AnimatedSwitcher(
                            duration: _reduceMotion || _tutorial != null
                                ? Duration.zero
                                : GameEffects.panelDuration,
                            layoutBuilder: (current, previous) => Stack(
                              alignment: Alignment.topCenter,
                              children: [
                                for (final child in previous)
                                  IgnorePointer(
                                    child: ExcludeSemantics(child: child),
                                  ),
                                ?current,
                              ],
                            ),
                            child: controller.state.isComplete
                                ? _buildVictory(t, controller)
                                : Column(
                                    key: ValueKey(hint),
                                    children: [
                                      Text(
                                        hint,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(height: 1.5),
                                      ),
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
                          const SizedBox(height: GameSpacing.medium),
                          if (_tutorial == null)
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    minimumSize: Size(
                                      compact ? 48 : width * .55,
                                      48,
                                    ),
                                  ),
                                  onPressed:
                                      controller.canUndo &&
                                          !_replaying &&
                                          !_celebrating
                                      ? () => _undo(controller)
                                      : null,
                                  icon: const Icon(Icons.undo_rounded),
                                  label: Text(t.undo),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: Size(
                                      compact ? 48 : width * .42,
                                      48,
                                    ),
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
                                          _attempt = null;
                                          _startAttempt();
                                          _game!.clearEffects();
                                          _gateBlocked = false;
                                          _completion = null;
                                        }),
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: Text(t.restart),
                                ),
                                if (compact)
                                  TextButton.icon(
                                    onPressed:
                                        widget.play.mode == PlayMode.campaign
                                        ? _pickLevel
                                        : null,
                                    icon: const Icon(Icons.grid_view_rounded),
                                    label: Text(t.levels),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 8),
                          Text(
                            'BLORIQ',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 4,
                              color: colors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
