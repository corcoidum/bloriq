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
import 'app/play_context.dart';
import 'tutorial/echo_tutorial.dart';
import 'analytics/local_analytics.dart';

void main() => runApp(const BloriqApp());

class BloriqApp extends StatefulWidget {
  const BloriqApp({
    super.key,
    this.loadLevels,
    this.settings,
    this.clock,
    this.playtestMode = const bool.fromEnvironment('PLAYTEST_MODE'),
  });

  /// 테스트에서 이전 스테이지 구성과 기기 설정을 주입할 수 있다.
  final Future<List<Level>> Function()? loadLevels;
  final GameSettings? settings;
  final DateTime Function()? clock;
  final bool playtestMode;

  @override
  State<BloriqApp> createState() => _BloriqAppState();
}

class _BloriqAppState extends State<BloriqApp> {
  GameSettings? _settings;

  @override
  void initState() {
    super.initState();
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
  bool _allowPop = false;
  bool _leaving = false;
  EchoTutorial? _tutorial;
  AttemptRecorder? _attempt;
  bool _modalOpen = false;
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
    // 저장과 별 평가는 애니메이션 타이머/Canvas 성공 여부에 의존하지 않는다.
    unawaited(_recordCompletion(controller));
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
      GameEffects.celebrationDuration + const Duration(milliseconds: 200),
      () {
        if (mounted && identical(_game, game)) _skipCelebration();
      },
    );
  }

  void _select(int index) {
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
    if (!mounted ||
        !identical(_controller, controller) ||
        !identical(controller.state, state)) {
      return;
    }
    setState(() => _completion = result);
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

  Position? _cell(Offset offset, double width, double height) {
    final level = _controller!.state.level;
    if (offset.dx < 0 ||
        offset.dy < 0 ||
        offset.dx >= width ||
        offset.dy >= height) {
      return null;
    }
    return Position(
      (offset.dx / width * level.boardWidth).floor(),
      (offset.dy / height * level.boardHeight).floor(),
    );
  }

  void _start(DragStartDetails details, double width, double height) {
    final controller = _controller!;
    if (controller.state.isComplete || _replaying) return;
    final cell = _cell(details.localPosition, width, height);
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
    }
  }

  void _cancelDrag() {
    _game?.setDrag(null);
    _dragBlock = null;
    _dragStart = null;
    _dragEnd = null;
  }

  void _end(double width) {
    final controller = _controller!;
    if (_dragBlock != null && _dragStart != null && _dragEnd != null) {
      final delta = _dragEnd! - _dragStart!;
      final threshold =
          width /
          controller.state.level.boardWidth *
          GameEffects.dragThresholdFraction;
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
    _skipCelebration();
    setState(() {
      controller.undo();
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
        result: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t.completeDetail(state.moves)),
            if (_bestMoves case final best?) Text(t.bestMoves(best)),
            if (_completion?.saved == false) Text(t.saveError),
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
                final width = math.max(
                  1.0,
                  math.min(
                    constraints.maxWidth - GameSpacing.page * 2,
                    math.min(
                      GameSpacing.maxBoardWidth,
                      math.max(
                        controller.state.level.boardWidth * 48.0,
                        constraints.maxHeight *
                            .46 *
                            controller.state.level.boardWidth /
                            controller.state.level.boardHeight,
                      ),
                    ),
                  ),
                );
                final height =
                    width *
                    controller.state.level.boardHeight /
                    controller.state.level.boardWidth;
                return Center(
                  child: SingleChildScrollView(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      padding: const EdgeInsets.symmetric(
                        horizontal: GameSpacing.page,
                        vertical: GameSpacing.medium,
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
                              const Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: BrandMark(),
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
                          if (_tutorial != null)
                            TextButton(
                              key: const ValueKey('skip-tutorial'),
                              onPressed: _skipTutorial,
                              child: Text(t.skipTutorial),
                            ),
                          const SizedBox(height: GameSpacing.medium),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              StatPill(
                                icon: Icons.layers_outlined,
                                label: widget.play.mode == PlayMode.daily
                                    ? t.dailyEcho
                                    : t.level(_loaded[_index].id),
                                color: colors.primaryInk,
                              ),
                              StatPill(
                                icon: Icons.swipe_rounded,
                                label: t.moves(controller.state.moves),
                                color: colors.echoInk,
                              ),
                            ],
                          ),
                          const SizedBox(height: GameSpacing.large),
                          ArcadeSurface(
                            padding: EdgeInsets.zero,
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
                                    onHorizontalDragStart: (d) =>
                                        _start(d, width, height),
                                    onHorizontalDragUpdate: _update,
                                    onHorizontalDragEnd: (_) => _end(width),
                                    onHorizontalDragCancel: _cancelDrag,
                                    onVerticalDragStart: (d) =>
                                        _start(d, width, height),
                                    onVerticalDragUpdate: _update,
                                    onVerticalDragEnd: (_) => _end(width),
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
                          const SizedBox(height: GameSpacing.large),
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
                                OutlinedButton.icon(
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
