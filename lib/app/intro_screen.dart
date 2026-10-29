import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../game/block_art.dart';
import '../l10n/app_localizations.dart';
import '../settings/game_settings.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({
    super.key,
    required this.settings,
    required this.onFinished,
  });
  final GameSettings settings;
  final VoidCallback onFinished;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _timeline;
  Timer? _fallback;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_accessibilityChanged);
    _timeline =
        AnimationController(vsync: this, duration: GameEffects.introDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish();
          })
          ..forward();
    // TickerMode나 렌더러가 멈춰도 시작 화면에 갇히지 않는다.
    _fallback = Timer(
      GameEffects.introDuration + const Duration(milliseconds: 200),
      _finish,
    );
  }

  void _finish() {
    if (_finished || !mounted) return;
    _finished = true;
    _fallback?.cancel();
    _timeline.stop();
    widget.onFinished();
  }

  void _accessibilityChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAccessibilityFeatures() => _accessibilityChanged();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finish();
  }

  @override
  void dispose() {
    _fallback?.cancel();
    widget.settings.removeListener(_accessibilityChanged);
    WidgetsBinding.instance.removeObserver(this);
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    if (prefersReducedMotion(context, widget.settings)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    }
    return Scaffold(
      key: const ValueKey('intro-screen'),
      body: ArcadeBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.all(GameSpacing.page),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: FadeTransition(
                              opacity: _timeline.drive(
                                CurveTween(curve: const Interval(.825, 1)),
                              ),
                              child: const Align(
                                alignment: Alignment.centerLeft,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: BrandMark(),
                                ),
                              ),
                            ),
                          ),
                          Flexible(
                            child: TextButton(
                              key: const ValueKey('skip-intro'),
                              onPressed: _finish,
                              child: Text(t.skipIntro),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: (constraints.maxHeight * .50).clamp(160, 480),
                        child: Center(child: IntroScene(progress: _timeline)),
                      ),
                      Text(
                        t.storyTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontFamily: GameTypography.canvasFontFamily,
                          color: GameTheme.colorsOf(context).rewardInk,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(t.homeSubtitle, textAlign: TextAlign.center),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IntroScene extends StatelessWidget {
  const IntroScene({
    super.key,
    this.progress = const AlwaysStoppedAnimation(.375),
  });
  final Animation<double> progress;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: AppLocalizations.of(context)!.introLabel,
    child: RepaintBoundary(
      child: AspectRatio(
        aspectRatio: 1.15,
        child: ValueListenableBuilder<int>(
          valueListenable: StarArt.revision,
          builder: (context, _, child) => CustomPaint(
            painter: IntroBoardPainter(
              progress: progress,
              colors: GameTheme.colorsOf(context),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 순수한 표시 타임라인. PuzzleController와 기록 저장에는 접근하지 않는다.
class IntroBoardPainter extends CustomPainter {
  IntroBoardPainter({required this.progress, required this.colors})
    : super(repaint: progress);
  final Animation<double> progress;
  final GameColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = progress.value.clamp(0.0, 1.0) * 4;
    final reveal = Curves.easeOutCubic.transform(
      (seconds / .6).clamp(0.0, 1.0),
    );
    final cell = math.min(size.width / 3.6, size.height / 3.5);
    final origin = Offset(
      (size.width - cell * 3) / 2,
      (size.height - cell * 3) / 2,
    );
    Offset center(double x, double y) =>
        origin + Offset((x + .5) * cell, (y + .5) * cell);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(.88 + .12 * reveal);
    canvas.translate(-size.width / 2, -size.height / 2);
    final paint = Paint();
    final rect = origin & Size(cell * 3, cell * 3);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(const Offset(0, 8)),
        Radius.circular(cell * .24),
      ),
      paint..color = colors.blockSymbol.withValues(alpha: .07),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(cell * .24)),
      paint..color = colors.boardSurface,
    );
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 3; x++) {
        final tile = Rect.fromLTWH(
          origin.dx + x * cell + 3,
          origin.dy + y * cell + 3,
          cell - 6,
          cell - 6,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(tile, Radius.circular(cell * .17)),
          paint
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.tileTop, colors.tileBottom],
            ).createShader(tile),
        );
        paint.shader = null;
      }
    }
    BlockArt.exit(canvas, center(2, 1), cell, colors);
    BlockArt.block(canvas, center(1, 0), cell, colors, goal: false);
    final first = Curves.easeOutCubic.transform(
      ((seconds - .6) / .65).clamp(0.0, 1.0),
    );
    final second = Curves.easeOutCubic.transform(
      ((seconds - 1.6) / .65).clamp(0.0, 1.0),
    );
    if (seconds >= .6 && seconds < 1.6) {
      BlockArt.echo(canvas, center(0, 1), cell, colors, opacity: first);
    } else if (seconds >= 1.6) {
      // 새 이동이 끝날 때까지만 이전 잔상이 남는다.
      if (second < 1) {
        BlockArt.echo(canvas, center(0, 1), cell, colors, opacity: 1 - second);
      }
      BlockArt.echo(canvas, center(1, 1), cell, colors, opacity: second);
    }
    if (seconds < 2.6) {
      BlockArt.block(
        canvas,
        center(first + second, 1),
        cell,
        colors,
        opacity: reveal,
      );
    }
    if (seconds >= 2.6 && seconds < 3.3) {
      final burst = (seconds - 2.6) / .7;
      final exit = center(2, 1);
      for (var i = 0; i < 12; i++) {
        final angle = i * math.pi / 6;
        final at =
            exit +
            Offset(math.cos(angle), math.sin(angle)) * cell * (.3 + burst * .7);
        canvas.drawCircle(
          at,
          cell * .035,
          paint
            ..color = (i.isEven ? colors.echo : colors.goal).withValues(
              alpha: 1 - burst,
            ),
        );
      }
      canvas.drawCircle(
        exit,
        cell * (.35 + .6 * burst),
        paint
          ..color = colors.reward.withValues(alpha: (1 - burst) * .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant IntroBoardPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.progress != progress;
}
