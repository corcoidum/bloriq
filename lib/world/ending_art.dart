import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../constellation/constellation_catalog.dart';
import '../constellation/constellation_painter.dart';
import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../story/story_catalog.dart';
import 'saga.dart';

const endingNight = Color(0xFF0A1026);
const _starlight = Color(0xFFFFE6AD);

class EndingSky extends CustomPainter {
  const EndingSky();

  @override
  void paint(Canvas canvas, Size size) {
    final area = Offset.zero & size;
    canvas.drawRect(
      area,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [endingNight, Color(0xFF172549), endingNight],
        ).createShader(area),
    );
    final random = math.Random(35);
    final paint = Paint();
    for (var i = 0; i < 92; i++) {
      final center = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawCircle(
        center,
        .45 + random.nextDouble() * .95,
        paint
          ..color = Colors.white.withValues(
            alpha: .10 + random.nextDouble() * .28,
          ),
      );
    }
  }

  @override
  bool shouldRepaint(EndingSky oldDelegate) => false;
}

class EndingLightroad extends CustomPainter {
  EndingLightroad({required Saga saga, required this.progress})
    : lighthouses = saga.worlds
          .where((world) => world.lighthouse != null)
          .toList();

  final List<SagaWorld> lighthouses;
  final double progress;

  static const _points = [
    Offset(.47, .93),
    Offset(.26, .79),
    Offset(.71, .65),
    Offset(.31, .51),
    Offset(.74, .37),
    Offset(.39, .23),
    Offset(.63, .08),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      for (final point in _points)
        Offset(point.dx * size.width, point.dy * size.height),
    ];
    final route = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final start = points[i - 1], end = points[i];
      final middle = (start.dy + end.dy) / 2;
      route.cubicTo(start.dx, middle, end.dx, middle, end.dx, end.dy);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFF647AA3).withValues(alpha: .55);
    canvas.drawPath(route, paint);
    final light = route.computeMetrics().single;
    final litDistance = light.length * (progress * .88);
    canvas.drawPath(
      light.extractPath(0, litDistance),
      paint
        ..color = _starlight.withValues(alpha: .68)
        ..strokeWidth = 2.2,
    );
    _star(
      canvas,
      points.last,
      13,
      _starlight.withValues(alpha: .25),
      outline: true,
    );
    _star(canvas, points.first, 7, _starlight);

    for (final (index, world) in lighthouses.indexed) {
      final position = points[index + 1];
      final strength = ((progress - .08 - index * .165) / .14).clamp(0.0, 1.0);
      final color = world.theme?.palette?.accent ?? _starlight;
      _lighthouse(canvas, position, color, strength);
    }
  }

  void _lighthouse(Canvas canvas, Offset base, Color color, double light) {
    const stone = Color(0xFF28385F);
    final ink = Color.lerp(stone, color, .22 + light * .78)!;
    final lantern = base - const Offset(0, 22);
    _halo(canvas, lantern, 66, color, .40 * light);
    final paint = Paint();
    for (var i = 0; i < 3; i++) {
      canvas.drawOval(
        Rect.fromCenter(center: base, width: 35 + i * 14, height: 10 + i * 7),
        paint
          ..style = PaintingStyle.stroke
          ..color = ink.withValues(alpha: .40 - i * .10),
      );
    }
    paint.style = PaintingStyle.fill;
    if (light > 0) {
      final beam = Path()
        ..moveTo(lantern.dx, lantern.dy)
        ..lineTo(lantern.dx + 70, lantern.dy - 14)
        ..lineTo(lantern.dx + 70, lantern.dy + 1)
        ..close();
      canvas.drawPath(
        beam,
        paint..color = color.withValues(alpha: light * .15),
      );
    }
    final tower = Path()
      ..moveTo(base.dx - 9, base.dy)
      ..lineTo(base.dx - 5, lantern.dy + 3)
      ..lineTo(base.dx + 5, lantern.dy + 3)
      ..lineTo(base.dx + 9, base.dy)
      ..close();
    canvas.drawPath(tower, paint..color = ink);
    canvas.drawPath(
      Path()
        ..moveTo(lantern.dx - 8, lantern.dy - 3)
        ..lineTo(lantern.dx, lantern.dy - 12)
        ..lineTo(lantern.dx + 8, lantern.dy - 3)
        ..close(),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: lantern, width: 11, height: 8),
        const Radius.circular(2),
      ),
      paint..color = Color.lerp(stone, Colors.white, light)!,
    );
  }

  @override
  bool shouldRepaint(EndingLightroad oldDelegate) =>
      oldDelegate.progress != progress;
}

class EndingAscent extends CustomPainter {
  EndingAscent({required this.progress}) : super(repaint: StarArt.revision);

  final double progress;
  static const _path = [
    Offset(.16, .88),
    Offset(.30, .88),
    Offset(.44, .88),
    Offset(.44, .77),
    Offset(.58, .77),
    Offset(.72, .77),
    Offset(.72, .66),
    Offset(.72, .55),
    Offset(.58, .55),
    Offset(.44, .55),
    Offset(.44, .44),
    Offset(.44, .33),
    Offset(.58, .33),
    Offset(.72, .33),
    Offset(.72, .22),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final points = [
      for (final point in _path)
        Offset(point.dx * size.width, point.dy * size.height),
    ];
    final steps = points.length - 1;
    final walk = ((progress - .14) / .78).clamp(0.0, 1.0) * steps;
    final index = walk.floor();
    final fraction = walk - index;
    final tile = math.min(size.width * .105, size.height * .085);
    final paint = Paint()..strokeWidth = 2;
    final drawn = math.min(
      points.length,
      1 + (progress * 9 * points.length).floor(),
    );
    for (var i = 0; i < drawn; i++) {
      final point = points[i];
      if (i > 0) {
        canvas.drawLine(
          points[i - 1],
          point,
          paint..color = _starlight.withValues(alpha: i <= index ? .62 : .23),
        );
      }
      final cell = RRect.fromRectAndRadius(
        Rect.fromCenter(center: point, width: tile, height: tile * .82),
        Radius.circular(tile * .21),
      );
      canvas.drawRRect(
        cell,
        paint
          ..style = PaintingStyle.fill
          ..color = i <= index
              ? const Color(0xFF596487)
              : const Color(0xFF293759),
      );
      canvas.drawRRect(
        cell,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _starlight.withValues(alpha: i <= index ? .53 : .23),
      );
      paint.style = PaintingStyle.fill;
    }
    final star = points.last;
    _halo(canvas, star, tile * 2.1, _starlight, .26);
    _star(canvas, star, tile * .75, _starlight, outline: true);
    if (index > 0) {
      // 현재 이동의 출발 칸에만 잔상이 있다. 다음 이동이 끝나면 교체된다.
      _riq(
        canvas,
        points[index - 1],
        tile,
        opacity: .64 - .42 * fraction,
        echo: true,
      );
    }
    final next = points[math.min(index + 1, steps)];
    final position = Offset.lerp(points[index], next, fraction)!;
    _riq(canvas, position, tile);
  }

  void _riq(
    Canvas canvas,
    Offset position,
    double tile, {
    double opacity = 1,
    bool echo = false,
  }) {
    final color = echo ? const Color(0xFFC2AAFF) : _starlight;
    final center = position - Offset(0, tile * .23);
    final image = StarArt.riqImage;
    if (image == null) {
      _star(canvas, center, tile * .42, color.withValues(alpha: opacity));
      return;
    }
    StarArt.draw(
      canvas,
      image,
      Rect.fromCenter(center: center, width: tile * 1.32, height: tile * 1.32),
      opacity: opacity,
      tint: echo ? color : null,
    );
  }

  @override
  bool shouldRepaint(EndingAscent oldDelegate) =>
      oldDelegate.progress != progress;
}

class EndingStar extends CustomPainter {
  const EndingStar({required this.ignition, this.brightSky = false});

  final double ignition;
  final bool brightSky;

  @override
  void paint(Canvas canvas, Size size) {
    final point = Offset(size.width / 2, size.height * .47);
    final radius = size.shortestSide * (.12 + .12 * ignition);
    final ring = brightSky ? const Color(0xFF895B2E) : _starlight;
    _halo(canvas, point, radius * 3.4, _starlight, .44 * ignition);
    final paint = Paint()..style = PaintingStyle.stroke;
    for (final scale in [1.04, 1.42, 1.84]) {
      canvas.drawCircle(
        point,
        radius * scale,
        paint..color = ring.withValues(alpha: .19 * ignition),
      );
    }
    _star(
      canvas,
      point,
      radius,
      _starlight.withValues(alpha: .20 + ignition * .8),
    );
    _star(
      canvas,
      point,
      radius * .69,
      Colors.white.withValues(alpha: ignition),
    );
    if (brightSky) {
      _star(canvas, point, radius, ring.withValues(alpha: .8), outline: true);
    }
  }

  @override
  bool shouldRepaint(EndingStar oldDelegate) =>
      oldDelegate.ignition != ignition || oldDelegate.brightSky != brightSky;
}

class EndingGuardians extends StatelessWidget {
  const EndingGuardians({
    super.key,
    required this.session,
    required this.progress,
  });

  final GameSession session;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final lang = Localizations.localeOf(context).languageCode;
    final aster = session.story.spirits.last;
    final guardians = <(ConstellationDefinition, StoryText, String?, Color)>[
      for (final info in session.saga!.worlds)
        if (info.lighthouse != null)
          if (session.world(info.number) case final world?)
            (
              world.story.chapters.last.stars,
              world.story.spirits.last.name,
              world.story.spirits.last.asset,
              info.theme?.palette?.accent ?? colors.reward,
            ),
      (ConstellationCatalog.all.last, aster.name, aster.asset, colors.reward),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = (guardians.length / 2).ceil();
        final artHeight = (constraints.maxHeight / rows - 26).clamp(
          70.0,
          148.0,
        );
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var start = 0; start < guardians.length; start += 2)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var i = start;
                        i < math.min(start + 2, guardians.length);
                        i++
                      )
                        Expanded(
                          child: _guardian(
                            guardians[i],
                            lang,
                            colors,
                            i,
                            artHeight,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _guardian(
    (ConstellationDefinition, StoryText, String?, Color) guardian,
    String lang,
    GameColors colors,
    int index,
    double artHeight,
  ) {
    final (definition, name, asset, accent) = guardian;
    final reveal = (progress * 1.85 - index * .16).clamp(0.0, 1.0);
    final star = Icon(
      Icons.star_rounded,
      size: 32,
      color: accent.withValues(alpha: .72),
    );
    return Opacity(
      opacity: reveal,
      child: Transform.translate(
        offset: Offset(0, (1 - reveal) * 24),
        child: Column(
          children: [
            SizedBox(
              height: artHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: asset == null
                          ? star
                          : Padding(
                              padding: const EdgeInsets.all(9),
                              child: Image.asset(
                                asset,
                                width: 62,
                                height: 62,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) => star,
                              ),
                            ),
                    ),
                    CustomPaint(
                      painter: ConstellationPainter(
                        definition: definition,
                        lit: List.filled(definition.nodes.length, true),
                        colors: colors,
                        golden: .64,
                        lineReveal: reveal,
                        guides: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Text(
              name.inLocale(lang),
              textAlign: TextAlign.center,
              style: GameTypography.label.copyWith(color: accent),
            ),
          ],
        ),
      ),
    );
  }
}

void _halo(
  Canvas canvas,
  Offset center,
  double radius,
  Color color,
  double opacity,
) {
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
}

void _star(
  Canvas canvas,
  Offset center,
  double radius,
  Color color, {
  bool outline = false,
}) {
  final path = Path();
  for (var i = 0; i < 8; i++) {
    final angle = i * math.pi / 4 - math.pi / 2;
    final length = i.isEven ? radius : radius * .24;
    final point =
        center +
        Offset(math.cos(angle) * length * .78, math.sin(angle) * length);
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  canvas.drawPath(
    path..close(),
    Paint()
      ..color = color
      ..style = outline ? PaintingStyle.stroke : PaintingStyle.fill
      ..strokeWidth = 1.5,
  );
}
