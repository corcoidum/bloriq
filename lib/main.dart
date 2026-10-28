import 'dart:async';
import 'dart:convert';
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
import 'settings/settings_dialog.dart';

void main() => runApp(const BloriqApp());

class BloriqApp extends StatefulWidget {
  const BloriqApp({super.key, this.loadLevels, this.settings});

  /// 테스트에서 이전 스테이지 구성과 기기 설정을 주입할 수 있다.
  final Future<List<Level>> Function()? loadLevels;
  final GameSettings? settings;

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
        : GameScreen(loadLevels: widget.loadLevels, settings: _settings!),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.loadLevels, required this.settings});

  final Future<List<Level>> Function()? loadLevels;
  final GameSettings settings;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Future<List<Level>> _levels = _loadLevels();
  List<Level> _loaded = [];
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
  }

  @override
  void didChangeAccessibilityFeatures() {
    if (mounted) setState(() {});
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
    final previous = _progress!.forLevel(state.level.id);
    _isNewBest = previous == null || state.moves < previous.bestMoves;
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

  Future<List<Level>> _loadLevels() async {
    _progress = await ProgressRepository.load();
    final audio = await GameAudio.load();
    if (mounted) {
      _audio = audio;
      WidgetsBinding.instance.addObserver(audio);
    } else {
      audio.dispose();
    }
    final injected = widget.loadLevels;
    if (injected != null) {
      final levels = await injected();
      if (levels.isEmpty) throw const FormatException('No levels');
      return levels;
    }
    final json = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List<dynamic>;
    final levels = json
        .map((item) => Level.fromJson(item as Map<String, dynamic>))
        .toList();
    if (levels.isEmpty) throw const FormatException('No levels');
    return levels;
  }

  void _select(int index) {
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
    });
  }

  void _stopReplay() {
    _replaying = false;
    _game?.skipReplay();
  }

  @override
  void dispose() {
    _victoryFallback?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _victory.removeListener(_updateVictory);
    _victory.dispose();
    _stopReplay();
    _audio?.dispose();
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
    final result = await _progress!.recordCompletion(
      levelId: state.level.id,
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
    final state = controller.state;
    final best = _progress!.forLevel(state.level.id)?.bestMoves ?? state.moves;
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
          levelText: t.level(state.level.id),
          movesText: t.moves(state.moves),
          bestText: t.bestMoves(best),
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
      final threshold = width / controller.state.level.boardWidth * .24;
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
        if (controller.move(block.id, target)) {
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
      _game!.clearEffects();
      _gateBlocked = false;
      _completion = null;
    });
  }

  Future<void> _showSettings() async {
    _cancelDrag();
    await showDialog<void>(
      context: context,
      animationStyle: _reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (_) => SettingsDialog(settings: widget.settings, audio: _audio!),
    );
    if (mounted) setState(() {});
  }

  void _showHelp(AppLocalizations t) {
    showDialog<void>(
      context: context,
      animationStyle: _reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (context) => AlertDialog(
        title: Text(t.help),
        content: SingleChildScrollView(child: Text(t.helpBody)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.close),
          ),
        ],
      ),
    );
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
            if (_progress!.forLevel(state.level.id) case final best?)
              Text(t.bestMoves(best.bestMoves)),
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
              onPressed: () =>
                  _select(_index + 1 < _loaded.length ? _index + 1 : 0),
              icon: const Icon(Icons.arrow_forward),
              label: Text(_index + 1 < _loaded.length ? t.next : t.firstLevel),
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
    _reduceMotion =
        widget.settings.reduceMotion ||
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    if (_reduceMotion && _celebrating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _reduceMotion && _celebrating) _skipCelebration();
      });
    }
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<List<Level>>(
          future: _levels,
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text(t.loadError));
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_controller == null) {
              _loaded = snapshot.data!;
              _controller = PuzzleController(_loaded[_index]);
              _game = BloriqGame(_controller!);
            }
            _game!.configureAppearance(
              colors: colors,
              reduceMotion: _reduceMotion,
            );
            final controller = _controller!;
            final hint = _hint(t, controller);
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = math.max(
                  1.0,
                  math.min(
                    constraints.maxWidth - GameSpacing.page * 2,
                    math.min(
                      GameSpacing.maxBoardWidth,
                      constraints.maxHeight *
                          .46 *
                          controller.state.level.boardWidth /
                          controller.state.level.boardHeight,
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
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: GameSpacing.small,
                            children: [
                              Text(
                                'BLORIQ',
                                style: GameTypography.brand.copyWith(
                                  color: colors.text,
                                ),
                              ),
                              Wrap(
                                children: [
                                  IconButton(
                                    tooltip: t.settings,
                                    onPressed: _showSettings,
                                    icon: const Icon(Icons.tune_rounded),
                                  ),
                                  IconButton(
                                    tooltip: t.help,
                                    onPressed: () => _showHelp(t),
                                    icon: const Icon(Icons.help_outline),
                                  ),
                                  IconButton(
                                    tooltip: _audio!.effectsEnabled
                                        ? t.soundOn
                                        : t.soundOff,
                                    onPressed: () => setState(() {
                                      _audio!.onUserInteraction();
                                      _audio!.setEffectsEnabled(
                                        !_audio!.effectsEnabled,
                                      );
                                    }),
                                    icon: Icon(
                                      _audio!.effectsEnabled
                                          ? Icons.volume_up_outlined
                                          : Icons.volume_off_outlined,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _audio!.musicEnabled
                                        ? t.musicOn
                                        : t.musicOff,
                                    onPressed: () => setState(
                                      () => _audio!.setMusicEnabled(
                                        !_audio!.musicEnabled,
                                      ),
                                    ),
                                    icon: Icon(
                                      _audio!.musicEnabled
                                          ? Icons.music_note
                                          : Icons.music_off,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            spacing: GameSpacing.large,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                t.level(_index + 1),
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(t.moves(controller.state.moves)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: width,
                            height: height,
                            child: Semantics(
                              label: t.boardLabel,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                dragStartBehavior: DragStartBehavior.down,
                                // 축별 recognizer가 바깥 스크롤보다 보드 드래그를 우선한다.
                                // 작은 화면에서도 위/아래 이동이 페이지 스크롤로 바뀌지 않는다.
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
                                // Pointer 취소가 pan 종료로 전달되더라도 이동을 확정하지 않는다.
                                child: Listener(
                                  onPointerDown: (_) =>
                                      _audio?.onUserInteraction(),
                                  onPointerCancel: (_) => _cancelDrag(),
                                  child: GameWidget(game: _game!),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: _reduceMotion
                                ? Duration.zero
                                : GameEffects.panelDuration,
                            // 사라지는 결과 패널의 버튼이 연속 터치를 받지 않게 한다.
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
                                            .bodyLarge,
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
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed:
                                    controller.canUndo &&
                                        !_replaying &&
                                        !_celebrating
                                    ? () => _undo(controller)
                                    : null,
                                icon: const Icon(Icons.undo),
                                label: Text(t.undo),
                              ),
                              OutlinedButton.icon(
                                onPressed: _replaying || _celebrating
                                    ? null
                                    : () => setState(() {
                                        _skipCelebration();
                                        controller.restart();
                                        _game!.clearEffects();
                                        _gateBlocked = false;
                                        _completion = null;
                                      }),
                                icon: const Icon(Icons.refresh),
                                label: Text(t.restart),
                              ),
                              PopupMenuButton<int>(
                                popUpAnimationStyle: _reduceMotion
                                    ? AnimationStyle.noAnimation
                                    : null,
                                tooltip: t.levels,
                                onSelected: _select,
                                itemBuilder: (_) => [
                                  for (var i = 0; i < _loaded.length; i++)
                                    PopupMenuItem(
                                      value: i,
                                      child: Wrap(
                                        alignment: WrapAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: GameSpacing.small,
                                        children: [
                                          Text(t.level(i + 1)),
                                          if (_progress!.forLevel(_loaded[i].id)
                                              case final best?)
                                            Text(
                                              '★' * best.bestStars,
                                              style: TextStyle(
                                                color: colors.rewardInk,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(t.levels),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
