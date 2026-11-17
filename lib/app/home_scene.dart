import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constellation/constellation_catalog.dart';
import '../constellation/constellation_painter.dart';
import '../constellation/constellation_state.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../l10n/app_localizations.dart';
import '../world/world_theme.dart';
import 'ability_spirits.dart';
import 'game_session.dart';

/// 홈 장면에 그릴 것. 저장하지 않고 기록에서 매번 계산한다.
class HomeSceneData {
  const HomeSceneData({
    required this.world,
    this.palette,
    this.hasLighthouse = false,
    this.firstStar = false,
    this.litLighthouses = 0,
    this.glow = 0,
    this.chapterName,
    this.constellation,
    this.lit = const [],
    this.pendingNode,
    this.golden = false,
    this.companions = const [],
  });

  /// "이어하기"가 갈 판을 기준으로 지금 서 있는 곳을 고른다.
  factory HomeSceneData.of(
    GameSession session,
    ContinueTarget target,
    AppLocalizations t,
  ) {
    final world = target.world;
    final id = target.levelId;
    final saga = session.saga;
    final info = saga?.world(world);
    // 함께 다니는 것은 능력을 가진 정령뿐이다. 합류한 순서(장 순서)대로 선다.
    final companions = [
      for (final entry in abilitySpirits(session.story))
        if (session.progression.hasPower(entry.power.id))
          if (entry.spirit.asset case final asset? when asset.isNotEmpty) asset,
    ];
    final before =
        saga?.worlds
            .where((other) => other.lighthouse != null && other.number < world)
            .length ??
        0;
    if (world == 1) {
      final atlas = ConstellationAtlas.derive(session.levels, session.progress);
      final chapter = id == null
          ? atlas.chapters.lastOrNull
          : atlas.forLevel(id);
      final index = chapter?.levels.indexWhere((level) => level.id == id) ?? -1;
      return HomeSceneData(
        world: world,
        glow: session.levels.isEmpty
            ? 0
            : session.completedCount / session.levels.length,
        chapterName: chapter?.definition.name(t),
        constellation: chapter?.definition,
        lit: chapter?.litMask ?? const [],
        pendingNode: index < 0 ? null : index,
        golden: chapter?.golden ?? false,
        companions: companions,
      );
    }
    final atlas = session.worldAtlas(world);
    final chapter = id == null
        ? atlas?.chapters.lastOrNull
        : atlas?.forLevel(id);
    final index =
        chapter?.stages.indexWhere((stage) => stage.level.id == id) ?? -1;
    final total = atlas?.stages.length ?? 0;
    return HomeSceneData(
      world: world,
      palette: info?.theme?.palette,
      hasLighthouse: info?.lighthouse != null,
      firstStar: info != null && info.lighthouse == null,
      litLighthouses: before,
      glow: total == 0 ? 0 : atlas!.cleared / total,
      chapterName: chapter?.chapter.constellation.inLocale(t.localeName),
      constellation: chapter?.definition,
      lit: chapter?.lit ?? const [],
      pendingNode: index < 0 ? null : index,
      golden: chapter?.golden ?? false,
      companions: companions,
    );
  }

  final int world;
  final WorldPalette? palette;

  /// 이 세계의 등대를 그릴지. 서막과 종장에는 등대가 없다.
  final bool hasLighthouse;

  /// 종장: 등대 대신 첫 별이 뜬다.
  final bool firstStar;

  /// 앞 세계에서 이미 켠 등대 수. 지평선에 작게 켜 둔다.
  final int litLighthouses;

  /// 이 세계를 깬 만큼(0~1) 등대나 첫 별의 빛이 차오른다.
  final double glow;

  final String? chapterName;
  final ConstellationDefinition? constellation;
  final List<bool> lit;

  /// 다음에 켤 별.
  final int? pendingNode;
  final bool golden;

  /// 합류한 능력 정령의 그림. 리크 곁에 함께 선다.
  final List<String> companions;

  int get litCount => lit.where((value) => value).length;

  /// 홈 하늘 색. 어두운 테마는 세계의 밤하늘, 밝은 테마는 옅게 물든 하늘이다.
  List<Color>? sky(GameColors colors, {required bool dark}) {
    final palette = this.palette;
    if (palette == null) return null;
    return dark
        ? [
            Color.lerp(palette.background, palette.board, .28)!,
            palette.background,
            colors.background,
          ]
        : [
            Color.lerp(colors.background, palette.accent, .3)!,
            Color.lerp(colors.background, palette.accent, .12)!,
            colors.background,
          ];
  }
}

/// 리크가 지금 서 있는 곳: 지금 장의 별자리, 이 세계의 등대, 리크와 echo.
class HomeScene extends StatefulWidget {
  const HomeScene({
    super.key,
    required this.data,
    required this.reduceMotion,
    this.onSky,
  });

  final HomeSceneData data;
  final bool reduceMotion;

  /// 하늘의 별자리를 누르면 별하늘을 연다.
  final VoidCallback? onSky;

  @override
  State<HomeScene> createState() => _HomeSceneState();
}

class _HomeSceneState extends State<HomeScene>
    with SingleTickerProviderStateMixin {
  static const _moods = [
    StarArt.riq,
    StarArt.riqHappy,
    StarArt.riqSurprised,
    StarArt.riqThinking,
  ];

  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  int _mood = 0;

  /// 한 번에 이어지는 숨 횟수(약 30초).
  static const _breaths = 8;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(HomeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.reduceMotion) {
      _breath
        ..stop()
        ..value = 0;
    } else if (!_breath.isAnimating) {
      // 홈에 돌아오거나 리크를 누르면 다시 숨 쉰다. 계속 켜 두면 배터리를 쓴다.
      _breath.repeat(count: _breaths);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  double _bob(double delay) =>
      math.sin((_breath.value - delay) * 2 * math.pi) * 3;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final colors = GameTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final data = widget.data;
    return LayoutBuilder(
      builder: (context, area) {
        final width = area.maxWidth, height = area.maxHeight;
        final riq = (height * .34).clamp(72.0, 128.0);
        final floor = height * .05;
        Widget standing({
          required double left,
          required double size,
          required double delay,
          required Widget child,
        }) => AnimatedBuilder(
          animation: _breath,
          builder: (_, child) => Positioned(
            left: left,
            bottom: floor + _bob(delay),
            width: size,
            height: size,
            child: child!,
          ),
          child: child,
        );
        final riqLeft = width * .5 - riq / 2;
        final friend = riq * .36;
        // 오른쪽에 셋, 나머지는 리크의 echo 왼쪽에 선다.
        double companionLeft(int index) => index < 3
            ? width * .5 + riq * .44 + friend * .64 * index
            : riqLeft - riq * .4 - friend * (.7 + .64 * (index - 3));
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  key: const ValueKey('home-scene-sky'),
                  painter: HomeScenePainter(
                    data: data,
                    colors: colors,
                    dark: dark,
                    breath: _breath,
                  ),
                ),
              ),
            ),
            if (data.constellation case final definition?)
              Positioned(
                left: width * .08,
                right: width * .08,
                top: 0,
                height: height * .5,
                child: Semantics(
                  key: const ValueKey('home-constellation'),
                  button: widget.onSky != null,
                  label: data.chapterName,
                  value: '${data.litCount} / ${data.lit.length}',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onSky,
                    child: CustomPaint(
                      painter: ConstellationPainter(
                        definition: definition,
                        lit: data.lit,
                        colors: colors,
                        golden: data.golden ? 1 : 0,
                        pendingNode: data.pendingNode,
                      ),
                    ),
                  ),
                ),
              ),
            for (final (index, asset) in data.companions.indexed)
              standing(
                left: companionLeft(index),
                size: friend,
                delay: .3 + .12 * index,
                child: ExcludeSemantics(
                  child: Image.asset(
                    asset,
                    key: ValueKey('home-companion-$index'),
                    cacheWidth: 256,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            // echo: 리크의 그림자가 반 박자 늦게 따라 움직인다.
            standing(
              left: riqLeft - riq * .4,
              size: riq,
              delay: .18,
              child: ExcludeSemantics(
                child: Image.asset(
                  StarArt.riq,
                  key: const ValueKey('home-echo'),
                  cacheWidth: 384,
                  fit: BoxFit.contain,
                  color: colors.echo.withValues(alpha: .4),
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
            ),
            standing(
              left: riqLeft,
              size: riq,
              delay: 0,
              child: Semantics(
                button: true,
                label: t.homeRiq,
                child: GestureDetector(
                  key: const ValueKey('home-riq'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _mood = (_mood + 1) % _moods.length);
                    _sync();
                  },
                  child: Image.asset(
                    _moods[_mood],
                    cacheWidth: 384,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 하늘의 잔별, 지평선의 켜진 등대들, 이 세계의 등대(또는 첫 별), 발밑의 땅.
class HomeScenePainter extends CustomPainter {
  HomeScenePainter({
    required this.data,
    required this.colors,
    required this.dark,
    required Animation<double> breath,
  }) : _breath = breath,
       super(repaint: breath);

  final HomeSceneData data;
  final GameColors colors;
  final bool dark;
  final Animation<double> _breath;

  static const _stars = [
    Offset(.06, .12),
    Offset(.2, .34),
    Offset(.33, .06),
    Offset(.52, .44),
    Offset(.68, .1),
    Offset(.8, .3),
    Offset(.93, .16),
    Offset(.12, .52),
    Offset(.9, .5),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final pulse = .5 + .5 * math.sin(_breath.value * 2 * math.pi);
    final palette = data.palette;
    final ground = h * .95;
    final paint = Paint()..isAntiAlias = true;

    final starColor = dark ? (palette?.border ?? colors.text) : colors.primary;
    for (final (index, star) in _stars.indexed) {
      final twinkle = index.isEven ? pulse : 1 - pulse;
      canvas.drawCircle(
        Offset(star.dx * w, star.dy * h),
        index % 3 == 0 ? 1.6 : 1.1,
        paint..color = starColor.withValues(alpha: .28 + .3 * twinkle),
      );
    }

    final tower = dark
        ? (palette?.border ?? colors.text)
        : Color.lerp(
            palette?.background ?? colors.text,
            colors.background,
            .3,
          )!;
    final band = palette?.accent ?? colors.primary;

    for (var index = 0; index < data.litLighthouses; index++) {
      _lighthouse(
        canvas,
        Offset(w * (.035 + index * .05), ground - h * .025),
        h * .085,
        glow: 1,
        tower: tower.withValues(alpha: .7),
        band: band.withValues(alpha: .7),
        pulse: pulse,
        beam: false,
      );
    }

    if (data.hasLighthouse) {
      _lighthouse(
        canvas,
        Offset(w * .9, ground - h * .01),
        h * .42,
        glow: data.glow.clamp(0, 1).toDouble(),
        tower: tower,
        band: band,
        pulse: pulse,
        beam: true,
      );
    } else if (data.firstStar) {
      _firstStar(canvas, Offset(w * .84, h * .2), h * .07, pulse);
    }

    final earth = palette == null
        ? colors.primary.withValues(alpha: dark ? .2 : .16)
        : dark
        ? Color.lerp(palette.board, palette.background, .45)!
        : Color.lerp(palette.board, colors.background, .55)!;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * .5, h * 1.05),
        width: w * 1.7,
        height: h * .26,
      ),
      paint
        ..shader = null
        ..style = PaintingStyle.fill
        ..color = earth,
    );
  }

  void _lighthouse(
    Canvas canvas,
    Offset base,
    double height, {
    required double glow,
    required Color tower,
    required Color band,
    required double pulse,
    required bool beam,
  }) {
    final paint = Paint()..isAntiAlias = true;
    final bodyTop = base.dy - height * .7;
    final lamp = Rect.fromCenter(
      center: Offset(base.dx, bodyTop - height * .1),
      width: height * .15,
      height: height * .14,
    );
    final light = colors.reward;
    if (glow > 0) {
      final strength = glow * (.82 + .18 * pulse);
      if (beam) {
        final far = Offset(
          base.dx - height * 1.9,
          lamp.center.dy - height * .34,
        );
        canvas.drawPath(
          Path()
            ..moveTo(lamp.center.dx, lamp.center.dy)
            ..lineTo(far.dx, far.dy - height * .2)
            ..lineTo(far.dx, far.dy + height * .26)
            ..close(),
          paint
            ..shader = LinearGradient(
              colors: [
                light.withValues(alpha: .1 + .3 * strength),
                light.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromPoints(lamp.center, far)),
        );
      }
      canvas.drawCircle(
        lamp.center,
        height * (.16 + .16 * strength),
        paint
          ..shader =
              RadialGradient(
                colors: [
                  light.withValues(alpha: .5 * strength),
                  light.withValues(alpha: 0),
                ],
              ).createShader(
                Rect.fromCircle(
                  center: lamp.center,
                  radius: height * (.16 + .16 * strength),
                ),
              ),
      );
    }
    paint.shader = null;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - height * .15, base.dy)
        ..lineTo(base.dx - height * .09, bodyTop)
        ..lineTo(base.dx + height * .09, bodyTop)
        ..lineTo(base.dx + height * .15, base.dy)
        ..close(),
      paint..color = tower,
    );
    final stripe = base.dy - height * .36;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx - height * .122, stripe)
        ..lineTo(base.dx - height * .108, stripe - height * .11)
        ..lineTo(base.dx + height * .108, stripe - height * .11)
        ..lineTo(base.dx + height * .122, stripe)
        ..close(),
      paint..color = band,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(base.dx, bodyTop - height * .015),
          width: height * .26,
          height: height * .035,
        ),
        Radius.circular(height * .01),
      ),
      paint..color = band,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(lamp, Radius.circular(height * .02)),
      paint
        ..color = Color.lerp(
          colors.outline,
          light,
          glow > 0 ? .55 + .45 * glow : 0,
        )!,
    );
    canvas.drawPath(
      Path()
        ..moveTo(lamp.left - height * .025, lamp.top)
        ..lineTo(base.dx, lamp.top - height * .1)
        ..lineTo(lamp.right + height * .025, lamp.top)
        ..close(),
      paint..color = band,
    );
  }

  void _firstStar(Canvas canvas, Offset center, double radius, double pulse) {
    final glow = data.glow.clamp(0, 1).toDouble();
    final light = Color.lerp(colors.outline, colors.reward, .35 + .65 * glow)!;
    final reach = radius * (1.1 + .7 * glow) * (.94 + .06 * pulse);
    final paint = Paint()..isAntiAlias = true;
    canvas.drawCircle(
      center,
      reach * 2.4,
      paint
        ..shader = RadialGradient(
          colors: [
            light.withValues(alpha: .12 + .34 * glow),
            light.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: reach * 2.4)),
    );
    final path = Path();
    for (var point = 0; point < 16; point++) {
      final long = point.isEven && point % 4 == 0;
      final length = point.isOdd
          ? reach * .2
          : long
          ? reach
          : reach * .5;
      final angle = point * math.pi / 8 - math.pi / 2;
      final at = center + Offset(math.cos(angle), math.sin(angle)) * length;
      point == 0 ? path.moveTo(at.dx, at.dy) : path.lineTo(at.dx, at.dy);
    }
    canvas.drawPath(
      path..close(),
      paint
        ..shader = null
        ..color = light,
    );
  }

  @override
  bool shouldRepaint(HomeScenePainter oldDelegate) =>
      oldDelegate.data != data ||
      oldDelegate.colors != colors ||
      oldDelegate.dark != dark;
}
