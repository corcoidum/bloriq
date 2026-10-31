import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/arcade_components.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../constellation/constellation_catalog.dart';
import '../constellation/constellation_painter.dart';
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
    // 마지막 장면의 달꽃자리 실루엣. 읽지 못해도 별과 선은 그린다.
    if (!StarArt.portraits.containsKey(StarArt.lunabel)) {
      StarArt.loadPortrait(StarArt.lunabel)
          .then((_) => StarArt.revision.value++, onError: (_) {});
    }
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
                        t.lastEchoTitle,
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
///
/// 0.0 잠든 리크 → 0.7 깨어나 깡총 → 1.5 첫 이동과 Echo → 2.5 별문 도착
/// → 3.3 금빛 별이 하늘로 올라가 달꽃자리를 잇는다 → 4.0 종료.
class IntroBoardPainter extends CustomPainter {
  IntroBoardPainter({required this.progress, required this.colors})
    : super(repaint: progress);
  final Animation<double> progress;
  final GameColors colors;

  static const _sleepEnd = .55, _blink = .85, _blinkEnd = .94;
  static const _move1 = 1.55, _move1End = 1.85;
  static const _move2 = 2.50, _move2End = 2.80;
  static const _lookBack = 2.00, _lookBackEnd = 2.30;
  static const _starRise = 3.00, _starArrive = 3.40;
  static const _skyStart = 3.30;

  /// [start]~[end] 구간의 0..1 진행도.
  static double seg(
    double seconds,
    double start,
    double end, [
    Curve curve = Curves.linear,
  ]) => curve.transform(((seconds - start) / (end - start)).clamp(0.0, 1.0));

  /// 예비동작 → 도약 → 낙하 → 착지 찌그러짐 → 복원. (dy 셀 비율, sx, sy)
  static (double, double, double) hop(
    double seconds,
    double start,
    double height,
  ) {
    final t = seconds - start;
    if (t <= 0 || t >= .52) return (0, 1, 1);
    if (t < .10) {
      final k = Curves.easeOut.transform(t / .10);
      return (0, 1 + .08 * k, 1 - .08 * k);
    }
    if (t < .21) {
      final k = Curves.easeOutCubic.transform((t - .10) / .11);
      return (-height * k, 1.08 - .14 * k, .92 + .16 * k);
    }
    if (t < .29) {
      final k = Curves.easeInQuad.transform((t - .21) / .08);
      return (-height * (1 - k), .94 + .06 * k, 1.08 - .08 * k);
    }
    if (t < .37) {
      final k = Curves.easeOut.transform((t - .29) / .08);
      return (0, 1 + .06 * k, 1 - .06 * k);
    }
    final k = Curves.easeOutBack.transform((t - .37) / .15);
    return (0, 1.06 - .06 * k, .94 + .06 * k);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = progress.value.clamp(0.0, 1.0) * 4;
    final reveal = seg(seconds, 0, .6, Curves.easeOutCubic);
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
    final exit = center(2, 1);
    BlockArt.exit(canvas, exit, cell, colors);
    BlockArt.block(canvas, center(1, 0), cell, colors, goal: false);

    // Scene 1: 별문 위의 작은 반짝임이 잠든 리크를 부른다.
    final twinkle = math.sin(seg(seconds, .20, .62) * math.pi);
    if (twinkle > 0) {
      _sparkle(
        canvas,
        exit + Offset(cell * .26, -cell * .26),
        cell * .09 * twinkle,
        colors.reward.withValues(alpha: .9 * twinkle),
      );
    }

    // Echo는 실제 규칙처럼 한 번에 하나만 남고 다음 이동이 끝나면 바뀐다.
    final firstEcho = seg(seconds, _move1 + .05, _move1End);
    final swap = seg(seconds, _move2, _move2End);
    final pulse = 1 + .25 * math.sin(seg(seconds, 2.05, 2.35) * math.pi);
    if (firstEcho > 0 && swap < 1) {
      BlockArt.echo(
        canvas,
        center(0, 1),
        cell,
        colors,
        opacity: (firstEcho * (1 - swap) * pulse).clamp(0.0, 1 / .72),
      );
    }
    if (swap > 0) {
      BlockArt.echo(canvas, center(1, 1), cell, colors, opacity: swap);
    }

    _drawRiq(canvas, seconds, cell, center, reveal);

    // Scene 4: 별문에 닿은 순간의 작은 별빛 8개.
    if (seconds >= _move2End && seconds < 3.30) {
      final burst = seg(seconds, _move2End, 3.30, Curves.easeOutCubic);
      for (var i = 0; i < 8; i++) {
        final angle = i * math.pi / 4 + .2;
        final at =
            exit +
            Offset(math.cos(angle), math.sin(angle)) * cell * (.3 + burst * .6);
        canvas.drawCircle(
          at,
          cell * (i.isEven ? .035 : .025),
          paint
            ..color = (i.isEven ? colors.reward : colors.goal).withValues(
              alpha: 1 - burst,
            ),
        );
      }
    }

    // Scene 5: 하늘을 올려다보듯 판이 어두워지고 별자리가 이어진다.
    final sky = seg(seconds, _skyStart, 3.60, Curves.easeOut);
    if (sky > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(4), Radius.circular(cell * .26)),
        Paint()..color = colors.background.withValues(alpha: .72 * sky),
      );
    }
    final constellation = ConstellationCatalog.forChapter(1)!;
    final skyArea = Offset.zero & size;
    if (seconds >= _skyStart) {
      // 금빛 별(4번 노드)이 먼저 도착하고 나머지 별이 60ms 간격으로 깨어난다.
      final order = [4, 0, 1, 2, 3];
      final lit = List.filled(5, false);
      for (var i = 0; i < order.length; i++) {
        final appear = i == 0 ? _starArrive : _skyStart + .06 * i;
        if (seconds >= appear) lit[order[i]] = true;
      }
      final sketch = ConstellationPainter(
        definition: constellation,
        lit: lit,
        colors: colors,
        guides: false,
        lineReveal: seg(seconds, 3.45, 3.80, Curves.easeInOutCubic),
        silhouette: StarArt.portraits[StarArt.lunabel],
        silhouetteOpacity: .14 * seg(seconds, 3.60, 3.90),
      );
      canvas.save();
      canvas.clipRect(skyArea);
      sketch.paint(canvas, size);
      canvas.restore();
    }

    // 별문에서 금빛 별 하나가 하늘의 첫 노드로 올라간다.
    final rise = seg(seconds, _starRise, _starArrive, Curves.easeInOutCubic);
    if (rise > 0 && rise < 1) {
      final target = _nodeCenter(constellation, 4, size);
      final at =
          Offset.lerp(exit, target, rise)! +
          Offset(-math.sin(rise * math.pi) * cell * .35, 0);
      _sparkle(canvas, at, cell * (.18 - .07 * rise), colors.reward);
    }
    canvas.restore();
  }

  /// [ConstellationPainter]와 같은 배치 계산으로 노드 위치를 얻는다.
  static Offset _nodeCenter(ConstellationDefinition c, int index, Size size) {
    final radius = (math.min(size.width, size.height) * .045).clamp(3.0, 9.0);
    final area = (Offset.zero & size).deflate(radius * 2.4);
    final node = c.nodes[index];
    return area.topLeft + Offset(node.dx * area.width, node.dy * area.height);
  }

  void _drawRiq(
    Canvas canvas,
    double seconds,
    double cell,
    Offset Function(double, double) center,
    double reveal,
  ) {
    final move1 = seg(seconds, _move1, _move1End, Curves.easeOutCubic);
    final move2 = seg(seconds, _move2, _move2End, Curves.easeOutCubic);
    if (seconds >= _skyStart + .30) return;
    var at = center(move1 + move2, 1);

    // 숨쉬기와 눈 뜨기
    var sx = 1.0, sy = 1.0, dy = 0.0, rotation = 0.0;
    if (seconds < _sleepEnd) {
      final breath = math.sin(seconds / 1.2 * math.pi * 2);
      sy = 1 + .03 * breath;
      sx = 1 - .015 * breath;
    }
    final wake = math.sin(seg(seconds, _sleepEnd, .70) * math.pi);
    sx *= 1 - .03 * wake;
    sy *= 1 - .03 * wake;

    // Scene 2: 깡총 뛰고 별 쪽으로 고개를 갸웃한다.
    final (hopY, hopX, hopSy) = hop(seconds, .95, .12);
    // Scene 4: 별문에 닿자 기뻐서 한 번 더 뛴다.
    final (joyY, joyX, joySy) = hop(seconds, _move2End, .10);
    sx *= hopX * joyX;
    sy *= hopSy * joySy;
    dy += (hopY + joyY) * cell;
    rotation +=
        -8 *
        math.pi /
        180 *
        seg(seconds, 1.30, 1.50, Curves.easeInOutSine) *
        (1 - seg(seconds, _move1, 1.70));

    // 이동 중 기울기는 게임판과 같다.
    rotation +=
        .07 * math.sin(move1 * math.pi) + .07 * math.sin(move2 * math.pi);
    final land = math.sin(seg(seconds, _move1End, 1.95) * math.pi);
    sx *= 1 + .05 * land;
    sy *= 1 - .05 * land;

    // Scene 3: 남긴 Echo를 돌아본다. 회전이 조금 늦게 따라온다.
    final glance = math.sin(seg(seconds, _lookBack, _lookBackEnd) * math.pi);
    final follow = math.sin(
      seg(seconds, _lookBack + .04, _lookBackEnd + .04) * math.pi,
    );
    at += Offset(-.04 * cell * glance, 0);
    rotation += 6 * math.pi / 180 * follow;

    final sleeping =
        seconds < _sleepEnd || (seconds >= _blink && seconds < _blinkEnd);
    final face = sleeping
        ? StarArt.riqSleepImage
        : seconds >= _move2
        ? StarArt.riqHappyImage
        : seconds >= _lookBack && seconds < _lookBackEnd
        ? StarArt.riqSurprisedImage
        : null;

    final fade = 1 - seg(seconds, _skyStart, _skyStart + .30);
    // 발끝을 기준으로 찌그러뜨려 바닥에 붙어 있는 느낌을 준다.
    final foot = at + Offset(0, cell * .36);
    canvas.save();
    canvas.translate(foot.dx, foot.dy + dy);
    canvas.rotate(rotation);
    canvas.scale(sx, sy);
    canvas.translate(-foot.dx, -foot.dy);
    BlockArt.block(
      canvas,
      at,
      cell,
      colors,
      opacity: reveal * fade,
      face: face,
    );
    if (sleeping && StarArt.riqSleepImage == null && StarArt.riqImage != null) {
      _closedEyes(canvas, BlockArt.goalSpriteRect(at, cell), reveal * fade);
    }
    canvas.restore();
  }

  /// 잠든 얼굴 그림이 없을 때 기본 얼굴 위에 감은 눈을 그린다.
  void _closedEyes(Canvas canvas, Rect sprite, double opacity) {
    final lid = Paint()
      ..color = const Color(0xFFF8ECD7).withValues(alpha: opacity);
    final line = Paint()
      ..color = const Color(0xFF15233F).withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, sprite.width * .016);
    for (final eye in StarArt.riqEyes) {
      final at =
          sprite.topLeft +
          Offset(eye.dx * sprite.width, eye.dy * sprite.height);
      final r = Size(
        StarArt.riqEyeRadius.width * sprite.width,
        StarArt.riqEyeRadius.height * sprite.height,
      );
      canvas.drawOval(
        Rect.fromCenter(center: at, width: r.width * 2, height: r.height * 2),
        lid,
      );
      canvas.drawArc(
        Rect.fromCenter(
          center: at - Offset(0, r.height * .25),
          width: r.width * 1.6,
          height: r.height * 1.2,
        ),
        math.pi * .15,
        math.pi * .7,
        false,
        line,
      );
    }
  }

  static void _sparkle(Canvas canvas, Offset at, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + i * math.pi / 4;
      final r = i.isEven ? radius : radius * .34;
      final point = at + Offset(math.cos(angle), math.sin(angle)) * r;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant IntroBoardPainter oldDelegate) =>
      oldDelegate.colors != colors || oldDelegate.progress != progress;
}
