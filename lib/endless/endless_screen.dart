import 'dart:async';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/game_session.dart';
import '../audio/game_audio.dart';
import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/keep_all_text.dart';
import '../design/star_art.dart';
import '../domain/puzzle.dart';
import '../game/bloriq_game.dart';
import '../game/board_geometry.dart';
import '../game/mechanic_legend.dart';
import '../l10n/app_localizations.dart';
import '../progression/progression_repository.dart';
import '../progression/progression_rules.dart';
import '../settings/game_settings.dart';
import 'endless_pool.dart';
import 'endless_repository.dart';
import 'endless_rules.dart';
import 'endless_run.dart';

enum _Phase { loading, harbor, sailing, over }

/// 별바다 항해: 판이 끝없이 이어지고, 등불이 꺼지면 끝나는 모드.
class EndlessScreen extends StatefulWidget {
  const EndlessScreen({
    super.key,
    required this.session,
    required this.settings,
    this.seed,
  });

  final GameSession session;
  final GameSettings settings;

  /// 테스트용 고정 항해 씨앗. 없으면 시각으로 정한다.
  final int? seed;

  @override
  State<EndlessScreen> createState() => _EndlessScreenState();
}

class _EndlessScreenState extends State<EndlessScreen> {
  _Phase _phase = _Phase.loading;
  bool _loadFailed = false;
  EndlessPool? _pool;
  VoyageRun? _run;
  PuzzleController? _controller;
  BloriqGame? _game;
  BoardGeometry? _geometry;
  BoardResult? _flash;
  Timer? _flashTimer, _overTimer;
  VoyageSummary? _summary;
  ClearReward? _reward;
  bool _finishing = false;

  /// 아주 작은 화면이나 큰 글자에서 보드 칸이 너무 작아지면 스크롤 배치로 바꾼다.
  bool _scrollLayout = false;
  bool _compactLegend = false;
  static const _minCell = 40.0;
  String? _dragBlock;
  Offset? _dragStart, _dragEnd;

  EndlessRepository get _repo => widget.session.endless;
  GameAudio get _audio => widget.session.audio;
  int get _minimum => _controller!.state.level.minimumMoves;
  bool get _busy => _flash != null || _finishing || _phase != _Phase.sailing;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPool());
  }

  Future<void> _loadPool() async {
    try {
      final pool = await widget.session.endlessPool;
      if (!mounted) return;
      setState(() {
        _pool = pool;
        _phase = _Phase.harbor;
      });
    } on Object catch (error) {
      debugPrint('Endless pool unavailable: $error');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    _overTimer?.cancel();
    super.dispose();
  }

  // ---- 항해 흐름 -------------------------------------------------------------

  void _startNew() {
    final seed =
        widget.seed ?? DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    final run = VoyageRun.start(_pool!, seed: seed);
    unawaited(_repo.saveRun(run));
    _sail(run);
  }

  void _resume() {
    final run = _repo.savedRun;
    if (run == null) return _startNew();
    _sail(run);
  }

  void _sail(VoyageRun run) {
    setState(() {
      _run = run;
      _summary = null;
      _reward = null;
      _finishing = false;
      _flash = null;
      _phase = _Phase.sailing;
      _loadBoard();
    });
  }

  /// 지금 깊이의 판을 보드에 놓는다. 판 묶음이 바뀌어 판이 없으면 새로 고른다.
  void _loadBoard() {
    final run = _run!;
    var level = _pool!.level(run.board);
    if (level == null) {
      run.board = _pool!.pick(seed: run.seed, depth: run.depth, used: {});
      level = _pool!.level(run.board)!;
    }
    _controller = PuzzleController(level);
    _game = BloriqGame(_controller!)
      ..trailStyle = widget.session.progression.equippedTrail;
    _cancelDrag();
  }

  void _boardCleared() {
    final run = _run!;
    final result = run.clear(_minimum, _pool!);
    unawaited(_repo.saveRun(run));
    _flash = result;
    final reduce = prefersReducedMotion(context, widget.settings);
    _flashTimer = Timer(Duration(milliseconds: reduce ? 700 : 1300), () {
      if (!mounted) return;
      setState(() {
        _flash = null;
        _loadBoard();
      });
    });
  }

  Future<void> _lanternOut() async {
    _finishing = true;
    final run = _run!;
    final summary = await _repo.finish(run);
    final reward = await widget.session.progression.recordVoyage(
      xp: summary.xp,
      stardust: summary.stardust,
      rewards: [for (final m in summary.milestones) ...m.rewards],
    );
    if (!mounted) return;
    final reduce = prefersReducedMotion(context, widget.settings);
    _overTimer = Timer(Duration(milliseconds: reduce ? 0 : 700), () {
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _reward = reward;
        _phase = _Phase.over;
      });
    });
  }

  void _undo() {
    if (_busy || !_controller!.canUndo) return;
    setState(() {
      _controller!.undo();
      _game!.clearEffects();
      _game!.hintMove = null;
    });
  }

  void _restart() {
    if (_busy || _controller!.state.moves == 0) return;
    setState(() {
      _controller!.restart();
      _game!.clearEffects();
      _game!.hintMove = null;
    });
  }

  void _hint(AppLocalizations t) {
    if (_busy) return;
    final run = _run!;
    final messenger = ScaffoldMessenger.of(context);
    if (!run.canHint(_minimum)) {
      messenger.showSnackBar(
        SnackBar(content: Text(EndlessText.noHint.resolve(t.localeName))),
      );
      return;
    }
    final state = _controller!.state;
    final move = const PuzzleSolver().solveFromState(state)?.firstOrNull;
    if (move == null) {
      messenger.showSnackBar(SnackBar(content: Text(t.starlightNoMove)));
      return;
    }
    final from = state.blocks
        .firstWhere((block) => block.id == move.blockId)
        .position;
    setState(() {
      run.hinted();
      _game!.hintMove = (from: from, to: move.target);
    });
    unawaited(_repo.saveRun(run));
  }

  // ---- 입력 ----------------------------------------------------------------

  void _start(DragStartDetails details) {
    if (_busy) return;
    final cell = _geometry?.positionAt(details.localPosition);
    _dragStart = details.localPosition;
    _dragEnd = details.localPosition;
    _dragBlock = null;
    for (final block in _controller!.state.blocks) {
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
      _game!.setDrag(
        _dragBlock,
        delta.dx.abs() >= delta.dy.abs()
            ? Offset(delta.dx, 0)
            : Offset(0, delta.dy),
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
    if (!_busy &&
        _dragBlock != null &&
        _dragStart != null &&
        _dragEnd != null) {
      final delta = _dragEnd! - _dragStart!;
      if (math.max(delta.dx.abs(), delta.dy.abs()) >=
          _geometry!.dragThreshold) {
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
          _run!.pushed();
          _game!.animateMove(block.id, from, previousEcho);
          final complete = controller.state.isComplete;
          _audio.play(
            complete
                ? SoundEffect.complete
                : !gateWasOpen && controller.state.isGateOpen
                ? SoundEffect.gate
                : previousEcho != null
                ? SoundEffect.echo
                : SoundEffect.move,
          );
          HapticFeedback.lightImpact();
          if (complete) {
            _boardCleared();
          } else if (_run!.isOut(_minimum)) {
            unawaited(_lanternOut());
          } else {
            unawaited(_repo.saveRun(_run!));
          }
        } else {
          _audio.play(SoundEffect.blocked);
          _game!.flashBlocked(target, blockId: block.id);
          HapticFeedback.mediumImpact();
        }
      }
    }
    _cancelDrag();
    setState(() {});
  }

  // ---- 화면 ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final lang = t.localeName;
    return Scaffold(
      key: const ValueKey('endless-screen'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(t, colors),
                    Expanded(
                      child: switch (_phase) {
                        _Phase.loading => Center(
                          child: _loadFailed
                              ? Text(t.loadError)
                              : const CircularProgressIndicator(),
                        ),
                        _Phase.harbor => _harbor(lang, colors),
                        _Phase.sailing || _Phase.over => Stack(
                          fit: StackFit.expand,
                          children: [
                            _sailing(t, colors),
                            if (_flash case final flash?)
                              _flashCard(lang, colors, flash),
                            if (_phase == _Phase.over) _overCard(lang, colors),
                          ],
                        ),
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations t, GameColors colors) => SizedBox(
    height: 52,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 52),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              EndlessText.title.resolve(t.localeName),
              style: GameTypography.brand.copyWith(
                fontSize: 24,
                color: colors.cyan,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            key: const ValueKey('endless-home'),
            tooltip: t.home,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.home_rounded),
          ),
        ),
        if (_phase == _Phase.sailing)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              key: const ValueKey('endless-rules'),
              tooltip: EndlessText.rulesTitle.resolve(t.localeName),
              onPressed: () => _showRules(t.localeName),
              icon: const Icon(Icons.help_outline_rounded),
            ),
          ),
      ],
    ),
  );

  Widget _rulesList(String lang, GameColors colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (index, rule) in EndlessText.rules.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                const [
                  Icons.waves_rounded,
                  Icons.local_fire_department_rounded,
                  Icons.add_circle_outline_rounded,
                  Icons.bolt_rounded,
                  Icons.flare_rounded,
                ][index],
                size: 20,
                color: colors.rewardInk,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: KeepAllText(
                  rule.resolve(lang),
                  style: GameTypography.body.copyWith(fontSize: 15.5),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Future<void> _showRules(String lang) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final colors = GameTheme.colorsOf(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                EndlessText.rulesTitle.resolve(lang),
                textAlign: TextAlign.center,
                style: GameTypography.reward.copyWith(
                  fontSize: 22,
                  color: colors.rewardInk,
                ),
              ),
              const SizedBox(height: 12),
              _rulesList(lang, colors),
            ],
          ),
        ),
      );
    },
  );

  Widget _record(String label, String value, GameColors colors, Key key) =>
      Expanded(
        child: Container(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outline.withValues(alpha: .4)),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: GameTypography.label.copyWith(
                  fontSize: 13,
                  color: colors.secondaryText,
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: GameTypography.reward.copyWith(
                    fontSize: 22,
                    color: colors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  /// 출항 전 항구: 기록, 규칙, 출항 버튼.
  Widget _harbor(String lang, GameColors colors) {
    final saved = _repo.savedRun;
    return SingleChildScrollView(
      key: const ValueKey('endless-harbor'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Icon(Icons.sailing_rounded, size: 56, color: colors.cyan),
          KeepAllText(
            EndlessText.tagline.resolve(lang),
            textAlign: TextAlign.center,
            style: GameTypography.body.copyWith(
              fontSize: 17,
              color: colors.secondaryText,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _record(
                EndlessText.best.resolve(lang),
                '${_repo.bestScore}',
                colors,
                const ValueKey('endless-best'),
              ),
              const SizedBox(width: 8),
              _record(
                EndlessText.weekBest.resolve(lang),
                '${_repo.weekBest}',
                colors,
                const ValueKey('endless-week'),
              ),
              const SizedBox(width: 8),
              _record(
                EndlessText.bestDepth.resolve(lang),
                '${_repo.bestDepth}',
                colors,
                const ValueKey('endless-depth'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            EndlessText.rulesTitle.resolve(lang),
            style: GameTypography.label.copyWith(color: colors.rewardInk),
          ),
          const SizedBox(height: 6),
          _rulesList(lang, colors),
          const SizedBox(height: 12),
          if (saved != null) ...[
            FilledButton.icon(
              key: const ValueKey('endless-resume'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
              onPressed: _resume,
              icon: const Icon(Icons.play_arrow_rounded, size: 27),
              label: Text(
                '${EndlessText.resume.resolve(lang)} · '
                '${EndlessText.depth(saved.depth).resolve(lang)}',
                style: const TextStyle(fontSize: 19),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('endless-new'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () async {
                await _repo.discardRun();
                if (mounted) _startNew();
              },
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(EndlessText.newVoyage.resolve(lang)),
            ),
          ] else
            FilledButton.icon(
              key: const ValueKey('endless-start'),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 56)),
              onPressed: _startNew,
              icon: const Icon(Icons.sailing_rounded, size: 26),
              label: Text(
                EndlessText.start.resolve(lang),
                style: const TextStyle(fontSize: 20),
              ),
            ),
        ],
      ),
    );
  }

  /// 설명을 접어도 보드가 들어가지 않을 때만 스크롤 배치를 쓴다.
  Widget _sailing(AppLocalizations t, GameColors colors) => LayoutBuilder(
    builder: (context, area) {
      final level = _controller!.state.level;
      final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
      final room =
          area.maxHeight -
          level.boardHeight * _minCell -
          BoardGeometry.defaultFrameInset * 2 -
          (30 * scale +
              6 +
              math.max(24.0, 22 * scale) +
              4 +
              24 * scale +
              8 +
              math.max(48.0, 22 * scale + 26));
      double legendHeight(bool compact) => MechanicLegend.slotHeight(
        context,
        width: area.maxWidth,
        compact: compact,
        notes: [t.instruction, t.echoInstruction],
        mechanics: [
          if (level.echoErasers.isNotEmpty) [t.eraserRule],
          if (level.echoHolds.isNotEmpty) [t.holdRule],
          if (level.oneWays.isNotEmpty) [t.oneWayRule],
          if (level.goalOnlyTiles.isNotEmpty) [t.goalOnlyRule],
          if (level.echoGate != null)
            [t.gateOpen, t.gateOccupied, t.gateInstruction],
        ],
      );
      _compactLegend = room < legendHeight(false);
      if (!_scrollLayout && room < legendHeight(true)) _scrollLayout = true;
      return _sailingColumn(t, colors);
    },
  );

  Widget _sailingColumn(AppLocalizations t, GameColors colors) {
    final lang = t.localeName;
    final run = _run!;
    final controller = _controller!;
    final reduce = prefersReducedMotion(context, widget.settings);
    _game!.configureAppearance(colors: colors, reduceMotion: reduce);
    final minimum = _minimum;
    final lantern = _flash != null
        ? run.lanternAtStart
        : run.lanternFor(minimum);
    final multiplier = EndlessRules.multiplier(
      perfect: true,
      combo: run.combo + 1,
    );
    final lanternColor = lantern <= 3 ? colors.error : colors.reward;
    final legend = _legend(t, controller.state);
    final column = Column(
      mainAxisSize: _scrollLayout ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 큰 글자에서도 한 줄에 들도록 왼쪽(깊이·콤보)과 오른쪽(점수)을 줄여 맞춘다.
        Row(
          children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      EndlessText.depth(_flash?.depth ?? run.depth)
                          .resolve(lang),
                      key: const ValueKey('endless-depth-label'),
                      style: GameTypography.label.copyWith(color: colors.cyan),
                    ),
                    if (run.combo > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        key: const ValueKey('endless-combo'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.reward.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          EndlessText.nextCombo(multiplier).resolve(lang),
                          style: GameTypography.label.copyWith(
                            fontSize: 13,
                            color: colors.rewardInk,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${EndlessText.score.resolve(lang)} ${run.score}',
                    key: const ValueKey('endless-score'),
                    style: GameTypography.label.copyWith(color: colors.text),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label: '${EndlessText.lantern.resolve(lang)} $lantern',
          child: Row(
            key: const ValueKey('endless-lantern'),
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: lanternColor,
                size: 22,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: lantern / EndlessRules.maxLantern),
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 280),
                    builder: (context, value, _) => LinearProgressIndicator(
                      minHeight: 12,
                      value: value,
                      color: lanternColor,
                      backgroundColor: colors.outline.withValues(alpha: .25),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$lantern',
                style: GameTypography.reward.copyWith(
                  fontSize: 20,
                  color: lanternColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${t.moves(controller.state.moves)} · '
          '${t.minimumMovesChip(minimum)}',
          textAlign: TextAlign.center,
          style: GameTypography.body.copyWith(
            fontSize: 15,
            color: colors.secondaryText,
          ),
        ),
        if (_scrollLayout)
          LayoutBuilder(
            builder: (context, area) {
              final level = controller.state.level;
              final width = math.min(
                area.maxWidth,
                GameSpacing.maxBoardWidth + BoardGeometry.defaultFrameInset * 2,
              );
              final cell =
                  (width - BoardGeometry.defaultFrameInset * 2) /
                  level.boardWidth;
              return SizedBox(
                height:
                    cell * level.boardHeight +
                    BoardGeometry.defaultFrameInset * 2,
                child: _board(t),
              );
            },
          )
        else
          Expanded(child: _board(t)),
        MechanicLegend(items: legend, compact: _compactLegend),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('endless-undo'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: !_busy && controller.canUndo ? _undo : null,
                icon: const Icon(Icons.undo_rounded),
                label: FittedBox(child: Text(t.undo)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('endless-restart'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: !_busy && controller.state.moves > 0
                    ? _restart
                    : null,
                icon: const Icon(Icons.refresh_rounded),
                label: FittedBox(child: Text(t.restart)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('endless-hint'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: _busy ? null : () => _hint(t),
                icon: const Icon(Icons.flare_rounded),
                label: FittedBox(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(EndlessText.hint.resolve(lang)),
                      Text(
                        EndlessText.hintCostLabel(EndlessRules.hintCost)
                            .resolve(lang),
                        style: GameTypography.label.copyWith(
                          fontSize: 11,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return _scrollLayout ? SingleChildScrollView(child: column) : column;
  }

  List<LegendItem> _legend(AppLocalizations t, PuzzleState state) {
    final level = state.level;
    final gate = level.echoGate == null
        ? null
        : state.isGateOpen
        ? t.gateOpen
        : state.blocks.any((block) => block.position == level.echoGate)
        ? t.gateOccupied
        : t.gateInstruction;
    final items = [
      if (level.echoErasers.isNotEmpty)
        LegendItem(LegendKind.eraser, t.eraserRule),
      if (level.echoHolds.isNotEmpty) LegendItem(LegendKind.hold, t.holdRule),
      if (level.oneWays.isNotEmpty) LegendItem(LegendKind.oneWay, t.oneWayRule),
      if (level.goalOnlyTiles.isNotEmpty)
        LegendItem(LegendKind.goalOnly, t.goalOnlyRule),
      if (gate != null) LegendItem(LegendKind.gate, gate),
    ];
    return items.isNotEmpty
        ? items
        : [
            LegendItem(
              LegendKind.note,
              state.echo == null ? t.instruction : t.echoInstruction,
            ),
          ];
  }

  Widget _board(AppLocalizations t) => LayoutBuilder(
    builder: (context, area) {
      final level = _controller!.state.level;
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
        columns: level.boardWidth,
        rows: level.boardHeight,
        devicePixelRatio: View.of(context).devicePixelRatio,
      );
      if (_geometry != null && !_geometry!.sameLayout(geometry)) {
        _cancelDrag();
      }
      _geometry = geometry;
      _game!.configureGeometry(geometry);
      if (!_scrollLayout && geometry.cellSize < _minCell) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_scrollLayout) setState(() => _scrollLayout = true);
        });
      }
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
                    key: const ValueKey('endless-board'),
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onHorizontalDragStart: _start,
                    onHorizontalDragUpdate: _update,
                    onHorizontalDragEnd: (_) => _end(),
                    onHorizontalDragCancel: _cancelDrag,
                    onVerticalDragStart: _start,
                    onVerticalDragUpdate: _update,
                    onVerticalDragEnd: (_) => _end(),
                    onVerticalDragCancel: _cancelDrag,
                    child: Listener(
                      onPointerDown: (_) => _audio.onUserInteraction(),
                      child: GameWidget(key: ObjectKey(_game), game: _game!),
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

  /// 판을 건넜을 때 잠깐 뜨는 카드: 완벽 여부, 콤보, 점수, 채워진 등불.
  Widget _flashCard(String lang, GameColors colors, BoardResult flash) =>
      IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .7, end: 1),
            duration: prefersReducedMotion(context, widget.settings)
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              key: const ValueKey('endless-flash'),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: .94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: (flash.perfect ? colors.reward : colors.cyan)
                      .withValues(alpha: .7),
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (flash.perfect ? EndlessText.perfect : EndlessText.cleared)
                        .resolve(lang),
                    style: GameTypography.reward.copyWith(
                      fontSize: 30,
                      color: flash.perfect ? colors.rewardInk : colors.cyan,
                    ),
                  ),
                  if (flash.multiplier > 1)
                    Text(
                      EndlessText.combo(flash.multiplier).resolve(lang),
                      style: GameTypography.label.copyWith(
                        color: colors.rewardInk,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    '+${flash.points}  ·  '
                    '${EndlessText.lantern.resolve(lang)} +${flash.refill}',
                    style: GameTypography.label.copyWith(
                      fontSize: 17,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  /// 등불이 꺼졌을 때: 기록, 보상, 다시 출항.
  Widget _overCard(String lang, GameColors colors) {
    final summary = _summary!;
    final reward = _reward;
    final milestoneDust = summary.milestones
        .expand((m) => m.rewards)
        .whereType<StardustBundle>()
        .fold<int>(0, (total, bundle) => total + bundle.amount);
    final badges = <String>[
      if (summary.newBestScore || summary.newBestDepth)
        EndlessText.newRecord.resolve(lang),
      for (final milestone in summary.milestones)
        EndlessText.milestone(milestone.depth).resolve(lang),
      if (reward?.levelsGained.lastOrNull case final level?)
        EndlessText.levelBadge(level.level).resolve(lang),
      for (final trail in reward?.newTrails ?? const <String>[])
        if (trailById(trail) case final definition?)
          EndlessText.trailBadge(definition.name.resolve(lang)).resolve(lang),
      for (final milestone in summary.milestones)
        for (final r in milestone.rewards)
          if (r case TitleUnlock(:final titleId))
            if (titleById(titleId) case final title?) title.name.resolve(lang),
    ];
    return ColoredBox(
      color: colors.background.withValues(alpha: .72),
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            key: const ValueKey('endless-over'),
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: colors.cyan.withValues(alpha: .5)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.local_fire_department_outlined,
                  size: 44,
                  color: colors.secondaryText,
                ),
                Text(
                  EndlessText.lanternOut.resolve(lang),
                  textAlign: TextAlign.center,
                  style: GameTypography.reward.copyWith(
                    fontSize: 26,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 6),
                KeepAllText(
                  EndlessText.reached(
                    summary.boards,
                    summary.perfects,
                  ).resolve(lang),
                  textAlign: TextAlign.center,
                  style: GameTypography.body.copyWith(fontSize: 17),
                ),
                const SizedBox(height: 10),
                Text(
                  '${summary.score}',
                  key: const ValueKey('endless-final-score'),
                  textAlign: TextAlign.center,
                  style: GameTypography.reward.copyWith(
                    fontSize: 44,
                    color: colors.rewardInk,
                  ),
                ),
                Text(
                  EndlessText.bestLine(
                    _repo.bestScore,
                    _repo.bestDepth,
                  ).resolve(lang),
                  textAlign: TextAlign.center,
                  style: GameTypography.label.copyWith(
                    fontSize: 14,
                    color: colors.secondaryText,
                  ),
                ),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final badge in badges)
                        Chip(
                          avatar: Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: colors.rewardInk,
                          ),
                          label: Text(badge),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  EndlessText.rewards.resolve(lang),
                  textAlign: TextAlign.center,
                  style: GameTypography.label.copyWith(
                    fontSize: 14,
                    color: colors.secondaryText,
                  ),
                ),
                Row(
                  key: const ValueKey('endless-rewards'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 20, color: colors.rewardInk),
                    const SizedBox(width: 4),
                    Text(
                      '${(reward?.clearStardust ?? summary.stardust) + milestoneDust}',
                      style: GameTypography.label.copyWith(
                        fontSize: 18,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'XP +${reward?.xpGained ?? summary.xp}',
                      style: GameTypography.label.copyWith(
                        fontSize: 18,
                        color: colors.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('endless-again'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                  onPressed: _startNew,
                  icon: const Icon(Icons.sailing_rounded),
                  label: Text(EndlessText.again.resolve(lang)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('endless-leave'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.home_rounded),
                  label: Text(EndlessText.home.resolve(lang)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
