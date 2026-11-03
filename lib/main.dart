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
import 'endless/endless_repository.dart';
import 'game/board_geometry.dart';

import 'game/device_art.dart';
import 'game/device_legend.dart';
import 'game/victory_panel.dart';
import 'l10n/app_localizations.dart';
import 'postcard/echo_postcard.dart';
import 'progress/player_repository.dart';
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
    this.showIntro = true,
  });

  /// 테스트에서 이전 스테이지 구성과 기기 설정을 주입할 수 있다.
  final Future<List<Level>> Function()? loadLevels;
  final GameSettings? settings;
  final DateTime Function()? clock;
  final bool playtestMode;
  final bool showIntro;

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
    theme: GameTheme.dark,
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
            showIntro: widget.showIntro,
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

/// 게임 화면 배치 단계. full: 전부 표시, tight: 동행과 긴 안내를 줄임, scroll: 최후 수단.
enum _GameFit { full, tight, scroll }

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
  late List<Level> _loaded;

  final _narrative = NarrativeController();
  SpiritDefinition? _discovery;
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

  /// 저장 전 별자리. 저장이 성공한 뒤 [_atlasAfter]와 비교해 연출을 고른다.
  ConstellationAtlas? _atlasBefore, _atlasAfter;
  ConstellationEvent? _constellation;
  bool _constellationPending = false;
  DeviceKind? _legendSelected;
  String? _lastHint;
  bool _advancing = false;
  bool _endlessUnsaved = false;

  RunScore? _runScore;
  XpAward? _award;

  /// 저장이 성공하면 지급할 경험치. 지급 뒤에는 0이다.
  int _pendingXp = 0;
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
    _prepareEndlessRound();
  }

  bool get _isEndless => widget.play.mode == PlayMode.endless;

  /// 다음 판을 미리 만들고, 처음 만나는 장치는 설명을 켜 둔 채 시작한다.
  void _prepareEndlessRound() {
    if (!_isEndless) return;
    final endless = widget.session.endless;
    endless.prefetchNext();
    for (final (_, kind, _) in deviceTiles(_controller!.state.level)) {
      if (!endless.seenDevice(kind.name)) {
        endless.markDeviceSeen(kind.name);
        _legendSelected ??= kind;
      }
    }
  }

  Future<void> _nextEndless() async {
    if (_advancing) return;
    _advancing = true;
    final level = await widget.session.endless.nextPuzzle();
    _advancing = false;
    if (!mounted) return;
    _loaded = [level];
    _select(0);
    setState(_prepareEndlessRound);
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
    if (widget.play.mode == PlayMode.tutorialReplay || _isEndless) return null;

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
    _prepareReward(state, previous);
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

  /// 점수는 바로 정해지고, 경험치는 기록 저장이 성공한 뒤에 지급한다.
  void _prepareReward(PuzzleState state, LevelProgress? previous) {
    _award = null;
    _pendingXp = 0;
    _runScore = null;
    if (widget.play.mode == PlayMode.tutorialReplay) return;
    final stars = starRating(
      moves: state.moves,
      minimumMoves: state.level.minimumMoves,
    );
    final score = RunScore.of(
      minimumMoves: state.level.minimumMoves,
      stars: stars,
      combo: _isEndless ? widget.session.endless.combo : 1,
    );
    _runScore = score;
    if (_isEndless) {
      // 판이 매번 새로우니 경험치는 언제나 전부 준다.
      _pendingXp = score.total;
    } else if (widget.play.mode == PlayMode.daily) {
      // Daily 경험치는 그날 처음 완료했을 때만 준다.
      final done = widget.session.daily.completed(widget.play.dailyDate!);
      _pendingXp = done ? 0 : score.total;
    } else {
      final improved = previous == null || stars > previous.bestStars;
      _pendingXp = improved
          ? score.total
          : (score.total * PlayerRepository.replayRate).round();
    }
  }

  Future<XpAward?> _grantXp() async {
    final gained = _pendingXp;
    if (gained <= 0) return null;
    _pendingXp = 0;
    return widget.session.player.award(gained);
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
    _runScore = null;
    _award = null;
    _pendingXp = 0;
    _endlessUnsaved = false;
    _constellation = null;
    _constellationPending = false;
    _atlasBefore = _atlasAfter = null;
    _legendSelected = null;
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
      final award = result.saved ? await _grantXp() : null;
      if (mounted && identical(_controller, controller)) {
        setState(() {
          _completion = result;
          _award = award;
        });
      }
      return;
    }
    if (_isEndless) {
      final saved = await widget.session.endless.recordClear();
      final award = await _grantXp();
      if (mounted && identical(_controller, controller)) {
        setState(() {
          _endlessUnsaved = !saved;
          _award = award;
        });
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
    final award = result.saved ? await _grantXp() : null;
    if (!mounted ||
        !identical(_controller, controller) ||
        !identical(controller.state, state)) {
      return;
    }
    setState(() {
      _completion = result;
      _award = award;
      _discovery = added.where((f) => f.levelId == state.level.id).firstOrNull;
      _updateConstellation(state.level.id, saved: result.saved);
    });
  }

  Future<void> _retryProgressSave() async {
    if (_retryingSave) return;
    setState(() => _retryingSave = true);
    if (_isEndless) {
      final saved = await widget.session.endless.retrySave();
      final playerSaved = await widget.session.player.retrySave();
      if (mounted) {
        setState(() {
          _retryingSave = false;
          _endlessUnsaved = !saved;
          final old = _award;
          if (old != null && playerSaved) {
            _award = XpAward(
              gained: old.gained,
              before: old.before,
              after: old.after,
              saved: true,
            );
          }
        });
      }
      return;
    }
    final controller = _controller;
    final result = _completion;
    final saved = await _progress!.retrySave();
    final added = saved
        ? await widget.session.collection.reconcile(
            _progress!.completedCampaignLevelIds,
          )
        : <SpiritDefinition>[];
    var award = saved ? await _grantXp() : null;
    if (saved && _award?.saved == false) {
      final playerSaved = await widget.session.player.retrySave();
      if (playerSaved) {
        final old = _award!;
        award = XpAward(
          gained: old.gained,
          before: old.before,
          after: old.after,
          saved: true,
        );
      }
    }
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
        _award = award ?? _award;
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

  Widget? _constellationView(
    PuzzleController controller, {
    bool compact = false,
    void Function(int chapter)? onOpen,
  }) {
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
      compact: compact,
      onOpen: () => onOpen != null
          ? onOpen(chapter.chapter)
          : _openAtlas(chapter.chapter),
    );
  }

  Future<void> _openAtlas(int? chapter) async {
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
          levelText: _isEndless
              ? t.endlessRound(state.level.id - EndlessRepository.firstId + 1)
              : widget.play.mode == PlayMode.daily
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
    final stars = starRating(
      moves: state.moves,
      minimumMoves: state.level.minimumMoves,
    );
    final best = _bestMoves;
    final campaign = widget.play.mode == PlayMode.campaign;
    return AnimatedBuilder(
      key: const ValueKey('complete'),
      animation: _victory,
      builder: (context, _) => VictoryPanel(
        progress: _victory.value,
        stars: stars,
        isNewBest: _isNewBest,
        reduceMotion: _reduceMotion,
        onSkip: _skipCelebration,
        score: _runScore,
        award: _award,
        details: [
          best == null
              ? t.completeDetail(state.moves)
              : '${t.completeDetail(state.moves)} ${t.bestMoves(best)}',
          state.moves == state.level.minimumMoves
              ? t.optimalComplete
              : t.improveComplete(state.level.minimumMoves),
        ],
        reward: _rewardSlot(t, controller),
        notices: [
          if (_completion?.saved == false ||
              _award?.saved == false ||
              _endlessUnsaved) ...[
            Text(t.saveError, textAlign: TextAlign.center),
            if (campaign || _isEndless)
              TextButton(
                key: const ValueKey('retry-progress'),
                onPressed: _retryingSave ? null : _retryProgressSave,
                child: Text(t.retrySave),
              ),
          ],
          if (campaign)
            CollectionStorageNotice(
              session: widget.session,
              onChanged: () => setState(() {}),
            ),
          if (campaign &&
              widget.session.collection.owned.length ==
                  widget.session.story.released.length &&
              widget.session.story.released.length == 25)
            Text(t.seasonComplete, textAlign: TextAlign.center),
        ],
        next: FilledButton.icon(
          key: const ValueKey('result-next'),
          style: FilledButton.styleFrom(minimumSize: const Size(48, 60)),
          onPressed: () => _isEndless
              ? _nextEndless()
              : !campaign
              ? Navigator.pop(context)
              : _select(_index + 1 < _loaded.length ? _index + 1 : 0),
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(
            _isEndless
                ? t.next
                : !campaign
                ? t.close
                : _index + 1 < _loaded.length
                ? t.next
                : t.firstLevel,
            style: const TextStyle(fontSize: 19),
          ),
        ),
        actions: [
          IconButton.filledTonal(
            key: const ValueKey('result-home'),
            tooltip: t.home,
            iconSize: 26,
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            onPressed: _replaying ? null : _leaveGame,
            icon: const Icon(Icons.home_rounded),
          ),
          // 무한 모드는 같은 판으로 경험치를 다시 벌 수 없게 다시 도전을 두지 않는다.
          if (!_isEndless)
            _resultAction(
              Icons.replay_rounded,
              t.tryAgain,
              _replaying ? null : () => _select(_index),
            ),
          _resultAction(
            Icons.play_circle_outline_rounded,
            t.watchReplay,
            _celebrating ? null : _watchReplay,
          ),
          _resultAction(
            Icons.image_outlined,
            t.postcard,
            _replaying ? null : () => _showPostcard(t, controller),
          ),
          if (campaign)
            _resultAction(
              Icons.more_horiz_rounded,
              t.moreActions,
              () => _showMore(t),
            ),
        ],
      ),
    );
  }

  Widget _resultAction(IconData icon, String label, VoidCallback? onPressed) =>
      IconButton.filledTonal(
        tooltip: label,
        iconSize: 26,
        constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
        onPressed: onPressed,
        icon: Icon(icon),
      );

  /// 보상은 한 칸만 보여 준다. 새 친구가 있으면 친구, 없으면 별자리다.
  Widget? _rewardSlot(AppLocalizations t, PuzzleController controller) {
    if (_discovery case final friend?) {
      final chapter = _atlasAfter?.forLevel(controller.state.level.id);
      final caption = chapter == null
          ? null
          : VictoryConstellation.caption(t, chapter, event: _constellation);
      return RewardCard(
        leading: SpiritPortrait(spirit: friend, size: 64),
        title: friend.guardian
            ? t.newGuardian(friend.name.inLocale(t.localeName))
            : t.newFriend(friend.name.inLocale(t.localeName)),
        subtitle: caption ?? t.readMemory,
        // 첫 클리어마다 친구가 오므로 별이 켜지는 모습을 같은 칸에서 함께 보여 준다.
        trailing: _constellationView(controller, compact: true),
        onTap: () => _showStory(controller),
      );
    }
    return _constellationView(controller);
  }

  /// 기억과 결말의 긴 글은 결과 화면 대신 시트에서 읽는다.
  Future<void> _showStory(PuzzleController controller) async {
    final friend = _discovery;
    if (friend == null) return;
    int? atlasChapter;
    await _withModal<void>(
      () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(GameSpacing.medium),
            child: ArcadeSurface(
              accent: GameColors.dark.reward,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DiscoveryPanel(
                    spirit: friend,
                    chapter: widget.session.story.chapter(friend.chapter),
                    progress: 1,
                    reduceMotion: true,
                    onSkip: () => Navigator.pop(sheet),
                  ),
                  ?_constellationView(
                    controller,
                    onOpen: (chapter) {
                      atlasChapter = chapter;
                      Navigator.pop(sheet);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _acknowledgeDiscovery();
    if (atlasChapter != null && mounted) await _openAtlas(atlasChapter);
  }

  Future<void> _showMore(AppLocalizations t) async {
    final friend = _discovery;
    // 시트가 닫힌 뒤에 실행해야 다음 대화상자가 열린다.
    Future<void> Function()? after;
    await _withModal<void>(
      () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: GameColors.dark.surface,
        builder: (sheet) {
          Widget item(
            String key,
            IconData icon,
            String label,
            Future<void> Function() action,
          ) => ListTile(
            key: ValueKey(key),
            leading: Icon(icon),
            title: Text(label),
            onTap: () {
              after = action;
              Navigator.pop(sheet);
            },
          );
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                item(
                  'result-album',
                  Icons.auto_stories_outlined,
                  t.album,
                  _openAlbum,
                ),
                item(
                  'result-atlas',
                  Icons.auto_awesome,
                  t.constellationAtlas,
                  () => _openAtlas(
                    ConstellationAtlas.derive(
                      widget.session.levels,
                      _progress!,
                    ).forLevel(_controller!.state.level.id)?.chapter,
                  ),
                ),
                if (friend != null)
                  item(
                    'result-discovery-share',
                    Icons.ios_share_rounded,
                    t.discoveryCard,
                    () async {
                      await _withModal<void>(
                        () => showStoryCard(
                          context,
                          [friend],
                          chapter: widget.session.story.chapter(friend.chapter),
                          reduceMotion: _reduceMotion,
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (mounted) await after?.call();
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
    if (!controller.state.isComplete) _lastHint = hint;
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
        body: Stack(
          fit: StackFit.expand,
          children: [
            ArcadeBackdrop(
              child: SafeArea(
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
                    final tight = fit != _GameFit.full;
                    final scroll = fit == _GameFit.scroll;
                    final boardHeight = math.max(
                      minBoard,
                      constraints.maxHeight * .55,
                    );
                    // 보드는 너비에 막혀 더 커지지 않으므로 남는 높이는 아래 버튼을 키워 채운다.
                    final spare = tight
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
                                  _isEndless
                                      ? t.endlessRound(
                                          widget.session.endless.round -
                                              (complete ? 1 : 0),
                                        )
                                      : widget.play.mode == PlayMode.daily
                                      ? t.dailyEcho
                                      : t.level(_loaded[_index].id),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: labelStyle,
                                ),
                              ),
                              if (_isEndless &&
                                  widget.session.endless.streak > 0)
                                Flexible(
                                  child: Text(
                                    ' · ${t.comboLabel(widget.session.endless.combo.toStringAsFixed(1))}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: labelStyle.copyWith(
                                      color: colors.rewardInk,
                                      decoration: TextDecoration.none,
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
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
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
                                        child: IconButton(
                                          key: const ValueKey('game-home'),
                                          tooltip: t.home,
                                          onPressed: _leaveGame,
                                          icon: const Icon(Icons.home_outlined),
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
                                if (tight)
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Center(child: levelLabel),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        flex: 2,
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.swipe_rounded,
                                                size: 16,
                                                color: colors.echoInk,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                t.moves(controller.state.moves),
                                                style: GameTypography.label
                                                    .copyWith(
                                                      color: colors.echoInk,
                                                      fontSize: 13,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  levelLabel,
                                  SizedBox(height: compact ? 4 : 8),
                                  SizedBox(
                                    height: math.max(
                                      compact ? 38.0 : 46.0,
                                      46 * _textScale,
                                    ),
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
                                            child: StatPill(
                                              icon: Icons.swipe_rounded,
                                              label: t.moves(
                                                controller.state.moves,
                                              ),
                                              color: colors.echoInk,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                SizedBox(height: compact ? 4 : 8),
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
                                  // 안내 칸 높이를 고정해 문구가 바뀌거나 클리어해도 보드 크기가 유지된다.
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: _hintSlotHeight(
                                        t,
                                        constraints,
                                        fit,
                                      ),
                                      minWidth: double.infinity,
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
                                      child: complete
                                          ? Stack(
                                              key: const ValueKey(
                                                'complete-slot',
                                              ),
                                              alignment: Alignment.center,
                                              children: [
                                                // 보이지 않게 두어 클리어해도 칸 높이와 보드 위치가 그대로다.
                                                Visibility.maintain(
                                                  visible: false,
                                                  child: _hintPanel(
                                                    t,
                                                    controller,
                                                    _lastHint ?? hint,
                                                    fit,
                                                  ),
                                                ),
                                                if (_replaying)
                                                  FilledButton.icon(
                                                    key: const ValueKey(
                                                      'skip-replay',
                                                    ),
                                                    onPressed: () {
                                                      _stopReplay();
                                                      setState(() {});
                                                    },
                                                    icon: const Icon(
                                                      Icons.skip_next,
                                                    ),
                                                    label: Text(t.skipReplay),
                                                  ),
                                              ],
                                            )
                                          : KeyedSubtree(
                                              key: ValueKey(hint),
                                              child: _hintPanel(
                                                t,
                                                controller,
                                                hint,
                                                fit,
                                              ),
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
                                              : () => setState(() {
                                                  _skipCelebration();
                                                  if (_isEndless) {
                                                    widget.session.endless
                                                        .breakStreak();
                                                  }
                                                  _attempt?.restart();
                                                  _attempt?.finish(
                                                    'level_end',
                                                    controller.state.moves,
                                                    reason: 'restart',
                                                  );
                                                  _acknowledgeDiscovery();
                                                  _discovery = null;
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
            ),
            if (controller.state.isComplete && !_replaying)
              BlockSemantics(child: _buildVictory(t, controller)),
          ],
        ),
      ),
    );
  }

  /// 보드 아래 장치 칩과 안내 문구. 좁은 화면에서는 두 줄까지만 보여 준다.
  Widget _hintPanel(
    AppLocalizations t,
    PuzzleController controller,
    String hint,
    _GameFit fit,
  ) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_tutorial == null)
        DeviceLegend(
          level: controller.state.level,
          selected: _legendSelected,
          iconsOnly: fit != _GameFit.full,
          onSelect: (kind) => setState(
            () => _legendSelected = _legendSelected == kind ? null : kind,
          ),
        ),
      Text(
        _tutorial == null && _legendSelected != null
            ? '${DeviceLegend.name(t, _legendSelected!)} · '
                  '${DeviceLegend.rule(t, _legendSelected!)}'
            : hint,
        textAlign: TextAlign.center,
        maxLines: fit == _GameFit.full ? null : 2,
        overflow: fit == _GameFit.full ? null : TextOverflow.ellipsis,
        style: _hintStyle,
      ),
      // 좁은 화면에서는 아래의 되돌리기 버튼으로 충분하다.
      if (fit == _GameFit.full && _hasNoMoves(controller)) ...[
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _undo(controller),
          icon: const Icon(Icons.undo),
          label: Text(t.undoLastMove),
        ),
      ],
    ],
  );

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

  /// 칸이 48px 아래로 내려가지 않는 가장 넓은 배치를 고른다.
  /// 스크롤은 줄여도 들어가지 않을 때(가로 화면, 아주 큰 글자)만 쓴다.
  _GameFit _chooseFit(
    AppLocalizations t,
    BoxConstraints constraints,
    double minBoard,
  ) {
    final room = constraints.maxHeight - minBoard;
    var fit = room >= _chromeHeight(t, constraints, _GameFit.full)
        ? _GameFit.full
        : room >= _chromeHeight(t, constraints, _GameFit.tight)
        ? _GameFit.tight
        : _GameFit.scroll;
    if (fit.index < _fitFloor.index) fit = _fitFloor;
    // 너비 때문에 칸이 작은 화면은 스크롤해도 칸이 커지지 않는다.
    if (fit == _GameFit.scroll &&
        _widthCell(
              constraints.maxWidth - GameSpacing.page * 2,
              _controller!.state.level.boardWidth,
            ) <
            _minCell) {
      fit = _GameFit.tight;
    }
    return fit;
  }

  /// 보드를 제외한 머리글·동료·안내·버튼 높이의 보수적 추정치.
  double _chromeHeight(
    AppLocalizations t,
    BoxConstraints constraints,
    _GameFit fit,
  ) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final compact = constraints.maxHeight < 700;
    final gap = compact ? 4.0 : 8.0;
    return (compact ? 8.0 : 20.0) +
        48 +
        26 * scale +
        8 +
        gap +
        (fit == _GameFit.full
            ? gap + math.max(compact ? 38.0 : 46.0, 46 * _textScale)
            : 0) +
        (compact ? 12.0 : 20.0) +
        _hintSlotHeight(t, constraints, fit) +
        (_tutorial == null ? math.max(48.0, 22 * scale + 26) : 22 * scale + 24);
  }

  /// 장치 칩 한 줄의 높이. 장치가 없는 판이나 튜토리얼에서는 칩이 없다.
  double _legendHeight() =>
      _tutorial == null && deviceTiles(_controller!.state.level).isNotEmpty
      ? 48.0 + GameSpacing.small
      : 0;

  TextStyle? get _hintStyle =>
      Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.35);

  /// 이번 판에 나올 수 있는 가장 긴 안내까지 들어가는 칸.
  /// 문구가 바뀌어도 보드가 움직이지 않는다. 다시보기 건너뛰기 버튼도 들어간다.
  double _hintSlotHeight(
    AppLocalizations t,
    BoxConstraints constraints,
    _GameFit fit,
  ) {
    final level = _controller!.state.level;
    final texts = _tutorial != null
        ? [t.tutorialMove, t.tutorialBlock, t.tutorialFinish]
        : [
            t.noMoves,
            t.instruction,
            t.echoInstruction,
            if (level.echoGate != null) ...[
              t.gateClosed,
              t.gateOpen,
              t.gateOccupied,
              t.gateInstruction,
            ],
            for (final tile in deviceTiles(level))
              '${DeviceLegend.name(t, tile.$2)} · '
                  '${DeviceLegend.rule(t, tile.$2)}',
          ];
    final width = math.min(constraints.maxWidth, 560.0) - GameSpacing.page * 2;
    var tallest = 0.0;
    for (final text in texts) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _hintStyle),
        textAlign: TextAlign.center,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: fit == _GameFit.full ? null : 2,
        ellipsis: fit == _GameFit.full ? null : '…',
      )..layout(maxWidth: math.max(1.0, width));
      tallest = math.max(tallest, painter.height);
      painter.dispose();
    }
    return _legendHeight() + math.max(48.0, tallest.ceilToDouble());
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
