import 'dart:convert';
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import 'domain/puzzle.dart';
import 'game/bloriq_game.dart';
import 'l10n/app_localizations.dart';

void main() => runApp(const BloriqApp());

class BloriqApp extends StatelessWidget {
  const BloriqApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BLORIQ',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF60A5FA)),
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
  Offset? _pathPointer;
  bool _drawing = false;
  bool _showingComplete = false;

  Future<List<Level>> _loadLevels() async {
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
    setState(() {
      _index = index;
      _controller = PuzzleController(_loaded[index]);
      _game = BloriqGame(_controller!);
      _dragBlock = null;
      _drawing = false;
      _showingComplete = false;
    });
  }

  Position? _cell(Offset offset, double width) {
    final level = _controller!.state.level;
    if (offset.dx < 0 ||
        offset.dy < 0 ||
        offset.dx >= width ||
        offset.dy >= width) {
      return null;
    }
    return Position(
      (offset.dx / width * level.boardWidth).floor(),
      (offset.dy / width * level.boardHeight).floor(),
    );
  }

  void _start(DragStartDetails details, double width) {
    final controller = _controller!;
    if (controller.state.isComplete) return;
    final cell = _cell(details.localPosition, width);
    if (cell == null) return;
    _dragStart = details.localPosition;
    _dragBlock = null;
    _drawing = cell == controller.state.level.startPosition;
    _pathPointer = details.localPosition;
    if (_drawing) {
      controller.clearPath();
      controller.appendPath(cell);
      setState(() {});
      return;
    }
    for (final block in controller.state.blocks) {
      if (block.position == cell) _dragBlock = block.id;
    }
  }

  void _update(DragUpdateDetails details, double width) {
    if (!_drawing) return;
    final controller = _controller!;
    final previous = _pathPointer ?? details.localPosition;
    final distance = (details.localPosition - previous).distance;
    final cellSize = width / controller.state.level.boardWidth;
    final samples = math.max(1, (distance / (cellSize / 5)).ceil());
    // 포인터 이벤트 사이를 보간해 빠른 드래그의 누락을 줄인다.
    for (var i = 1; i <= samples; i++) {
      final point = Offset.lerp(previous, details.localPosition, i / samples)!;
      final target = _cell(point, width);
      if (target == null || controller.state.path.isEmpty) break;
      final last = controller.state.path.last;
      if (last == target) continue;
      if (!controller.appendPath(target)) break;
      if (controller.state.isComplete) break;
    }
    _pathPointer = details.localPosition;
    setState(() {});
    if (controller.state.isComplete && !_showingComplete) {
      _showingComplete = true;
      _drawing = false;
      _complete();
    }
  }

  void _end(DragEndDetails details, double width, Offset? end) {
    final controller = _controller!;
    if (_dragBlock != null && _dragStart != null && end != null) {
      final delta = end - _dragStart!;
      final threshold = width / controller.state.level.boardWidth * .25;
      if (delta.distance >= threshold) {
        final block = controller.state.blocks.firstWhere(
          (item) => item.id == _dragBlock,
        );
        final dx = delta.dx.abs() > delta.dy.abs() ? delta.dx.sign.toInt() : 0;
        final dy = dx == 0 ? delta.dy.sign.toInt() : 0;
        controller.move(
          block.id,
          Position(block.position.x + dx, block.position.y + dy),
        );
      }
    }
    _dragBlock = null;
    _drawing = false;
    _dragStart = null;
    setState(() {});
  }

  Future<void> _complete() async {
    final t = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(t.complete),
        content: Text(t.completeDetail(_controller!.state.moves)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t.close),
          ),
          if (_index + 1 < _loaded.length)
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _select(_index + 1);
              },
              child: Text(t.next),
            ),
        ],
      ),
    );
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
            return LayoutBuilder(
              builder: (context, constraints) {
                final width = math.min(
                  constraints.maxWidth - 32,
                  math.min(480.0, constraints.maxHeight * .54),
                );
                return Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'BLORIQ',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              fontSize: 30,
                              color: Color(0xFF334155),
                            ),
                          ),
                          Text(t.tagline, textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t.level(_index + 1),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(t.moves(controller.state.moves)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: width,
                            height: width,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              dragStartBehavior: DragStartBehavior.down,
                              onPanStart: (d) {
                                _dragEnd = d.localPosition;
                                _start(d, width);
                              },
                              onPanUpdate: (d) {
                                _dragEnd = d.localPosition;
                                _update(d, width);
                              },
                              onPanEnd: (d) => _end(d, width, _dragEnd),
                              onPanCancel: () {
                                _dragBlock = null;
                                _drawing = false;
                              },
                              child: GameWidget(game: _game!),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(t.instruction, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: controller.canUndo
                                    ? () => setState(() {
                                        controller.undo();
                                        _showingComplete = false;
                                      })
                                    : null,
                                icon: const Icon(Icons.undo),
                                label: Text(t.undo),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => setState(() {
                                  controller.restart();
                                  _showingComplete = false;
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
                                      child: Text(t.level(i + 1)),
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
