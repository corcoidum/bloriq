import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/game_audio.dart';
import 'domain/puzzle.dart';
import 'game/bloriq_game.dart';
import 'l10n/app_localizations.dart';
import 'postcard/echo_postcard.dart';
import 'progress/progress_repository.dart';

void main() => runApp(const BloriqApp());

class BloriqApp extends StatelessWidget {
  const BloriqApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BLORIQ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF5D78D6)),
      scaffoldBackgroundColor: const Color(0xFFF6F8FF),
      useMaterial3: true,
    ),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    localeResolutionCallback: (locale, supported) =>
        locale?.languageCode == 'ko' ? const Locale('ko') : const Locale('en'),
    home: const GameScreen(),
  );
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
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

  Future<List<Level>> _loadLevels() async {
    _progress = await ProgressRepository.load();
    final audio = await GameAudio.load();
    if (mounted) {
      _audio = audio;
      WidgetsBinding.instance.addObserver(audio);
    } else {
      audio.dispose();
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
    _stopReplay();
    _audio?.dispose();
    super.dispose();
  }

  void _watchReplay() {
    if (_replaying) return;
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
          if (controller.state.isComplete) _recordCompletion(controller);
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
    setState(() {
      controller.undo();
      _game!.clearEffects();
      _gateBlocked = false;
      _completion = null;
    });
  }

  void _showHelp(AppLocalizations t) {
    showDialog<void>(
      context: context,
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

  String _hint(AppLocalizations t, PuzzleController controller) {
    final state = controller.state;
    // This detects only states with no legal move, not every unsolvable state.
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
            final controller = _controller!;
            final hint = _hint(t, controller);
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = math.max(
                  1.0,
                  math.min(
                    constraints.maxWidth - 32,
                    math.min(
                      460.0,
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'BLORIQ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    fontSize: 23,
                                    color: Color(0xFF334155),
                                  ),
                                ),
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
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                onPanStart: (d) => _start(d, width, height),
                                onPanUpdate: _update,
                                onPanEnd: (_) => _end(width),
                                onPanCancel: _cancelDrag,
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
                            duration: const Duration(milliseconds: 250),
                            child: controller.state.isComplete
                                ? Column(
                                    key: const ValueKey('complete'),
                                    children: [
                                      Text(
                                        t.complete,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge
                                            ?.copyWith(
                                              color: const Color(0xFF15845F),
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      Text(
                                        t.completeDetail(
                                          controller.state.moves,
                                        ),
                                      ),
                                      Semantics(
                                        label: t.starsLabel(
                                          starRating(
                                            moves: controller.state.moves,
                                            minimumMoves: controller
                                                .state
                                                .level
                                                .minimumMoves,
                                          ),
                                        ),
                                        child: Text(
                                          '${'★' * starRating(moves: controller.state.moves, minimumMoves: controller.state.level.minimumMoves)}${'☆' * (3 - starRating(moves: controller.state.moves, minimumMoves: controller.state.level.minimumMoves))}',
                                          style: const TextStyle(
                                            fontSize: 28,
                                            color: Color(0xFFF2AC47),
                                          ),
                                        ),
                                      ),
                                      if (_progress!.forLevel(
                                            controller.state.level.id,
                                          )
                                          case final best?)
                                        Text(t.bestMoves(best.bestMoves)),
                                      if (_completion?.isNewBest == true)
                                        Text(
                                          t.newBest,
                                          style: const TextStyle(
                                            color: Color(0xFF15845F),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      if (_completion?.saved == false)
                                        Text(t.saveError),
                                      Text(
                                        controller.state.moves ==
                                                controller
                                                    .state
                                                    .level
                                                    .minimumMoves
                                            ? t.optimalComplete
                                            : t.improveComplete(
                                                controller
                                                    .state
                                                    .level
                                                    .minimumMoves,
                                              ),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF5271A4),
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        alignment: WrapAlignment.center,
                                        spacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            onPressed: _replaying
                                                ? () {
                                                    _stopReplay();
                                                    setState(() {});
                                                  }
                                                : _watchReplay,
                                            icon: Icon(
                                              _replaying
                                                  ? Icons.skip_next
                                                  : Icons.play_arrow,
                                            ),
                                            label: Text(
                                              _replaying
                                                  ? t.skipReplay
                                                  : t.watchReplay,
                                            ),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _replaying
                                                ? null
                                                : () => _select(_index),
                                            icon: const Icon(Icons.replay),
                                            label: Text(t.tryAgain),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _replaying
                                                ? null
                                                : () => _showPostcard(
                                                    t,
                                                    controller,
                                                  ),
                                            icon: const Icon(
                                              Icons.image_outlined,
                                            ),
                                            label: Text(t.postcard),
                                          ),
                                        ],
                                      ),
                                      if (_index + 1 < _loaded.length)
                                        FilledButton.icon(
                                          onPressed: () => _select(_index + 1),
                                          icon: const Icon(Icons.arrow_forward),
                                          label: Text(t.next),
                                        )
                                      else
                                        FilledButton.icon(
                                          onPressed: () => _select(0),
                                          icon: const Icon(Icons.replay),
                                          label: Text(t.firstLevel),
                                        ),
                                    ],
                                  )
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
                                onPressed: controller.canUndo && !_replaying
                                    ? () => _undo(controller)
                                    : null,
                                icon: const Icon(Icons.undo),
                                label: Text(t.undo),
                              ),
                              OutlinedButton.icon(
                                onPressed: _replaying
                                    ? null
                                    : () => setState(() {
                                        controller.restart();
                                        _game!.clearEffects();
                                        _gateBlocked = false;
                                        _completion = null;
                                      }),
                                icon: const Icon(Icons.refresh),
                                label: Text(t.restart),
                              ),
                              PopupMenuButton<int>(
                                tooltip: t.levels,
                                onSelected: _select,
                                itemBuilder: (_) => [
                                  for (var i = 0; i < _loaded.length; i++)
                                    PopupMenuItem(
                                      value: i,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(t.level(i + 1)),
                                          if (_progress!.forLevel(_loaded[i].id)
                                              case final best?)
                                            Text(
                                              '★' * best.bestStars,
                                              style: const TextStyle(
                                                color: Color(0xFFF2AC47),
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
