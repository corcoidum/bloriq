import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/game_session.dart';
import '../design/game_theme.dart';
import '../l10n/app_localizations.dart';
import '../world/world_catalog.dart';
import '../world/world_shelf.dart';
import 'constellation_atlas.dart';
import 'constellation_catalog.dart';
import 'constellation_state.dart';

/// 별하늘의 별 하나. 캠페인 판 하나와 짝을 이룬다.
class SkyStar {
  const SkyStar({
    required this.levelId,
    required this.number,
    required this.stars,
    required this.lit,
    required this.unlocked,
    required this.position,
  });

  final int levelId;

  /// 세계 안에서 센 판 번호(1..25).
  final int number;
  final int stars;
  final bool lit, unlocked;

  /// 별하늘 좌표.
  final Offset position;
}

/// 별하늘의 별자리 하나. 장 하나와 짝을 이룬다.
class SkyConstellation {
  const SkyConstellation({
    required this.index,
    required this.world,
    required this.name,
    required this.status,
    required this.definition,
    required this.box,
    required this.stars,
    required this.dust,
    required this.worldUnlocked,
  });

  /// 빛길을 따라 센 순서(0부터).
  final int index;
  final int world;
  final String name, status;
  final ConstellationDefinition definition;
  final Rect box;
  final List<SkyStar> stars;

  /// 모양을 달리 보이게 하는 흐린 장식 별. 판과는 무관하다.
  final List<Offset> dust;
  final bool worldUnlocked;

  int get litCount => stars.where((star) => star.lit).length;
  bool get complete => litCount == stars.length;
  bool get golden => stars.every((star) => star.stars == 3);
  bool get unlocked => worldUnlocked && stars.any((star) => star.unlocked);
  int get starCount => stars.fold(0, (total, star) => total + star.stars);
  Offset get center => box.center;

  /// 이어서 할 별: 열려 있고 아직 켜지 않은 첫 별, 없으면 열린 첫 별.
  SkyStar? get next => !worldUnlocked
      ? null
      : stars.where((star) => star.unlocked && !star.lit).firstOrNull ??
            stars.where((star) => star.unlocked).firstOrNull;
}

class SkyWorld {
  const SkyWorld({
    required this.number,
    required this.title,
    required this.unlocked,
    required this.band,
    required this.tint,
    required this.constellations,
  });

  final int number;
  final String title;
  final bool unlocked;
  final Rect band;
  final Color tint;
  final List<SkyConstellation> constellations;
}

/// 일곱 세계의 별자리를 한 장에 놓은 지도. 저장하지 않고 기록에서 매번 계산한다.
///
/// 세계 1이 맨 아래에 있고 빛길을 따라 위로 올라가 첫 별에 닿는다.
class StarSkyData {
  StarSkyData._(this.worlds, this.size, this.firstStar);

  static const width = 900.0;
  static const bandHeight = 540.0;
  static const _top = 280.0;
  static const _bottom = 110.0;
  static const _box = Size(232, 192);

  // 한 세계 안의 다섯 자리. 아래 줄 셋, 윗줄 둘로 빛길이 굽이친다.
  static const _slots = [
    Offset(.19, .76),
    Offset(.50, .82),
    Offset(.81, .72),
    Offset(.67, .30),
    Offset(.33, .24),
  ];

  factory StarSkyData.of(
    GameSession session,
    AppLocalizations t,
    GameColors colors,
  ) {
    final numbers = [1, ...session.worlds.keys.toList()..sort()];
    final height = _top + numbers.length * bandHeight + _bottom;
    final lang = t.localeName;
    final worlds = <SkyWorld>[];
    var index = 0;

    Rect bandOf(int order) => Rect.fromLTWH(
      0,
      _top + (numbers.length - 1 - order) * bandHeight,
      width,
      bandHeight,
    );

    SkyConstellation place({
      required int world,
      required int slot,
      required Rect band,
      required String name,
      required String status,
      required ConstellationDefinition definition,
      required bool worldUnlocked,
      required List<({int id, int number, int stars, bool lit, bool unlocked})>
      stages,
    }) {
      final random = math.Random(index * 7919 + 13);
      // 짝수 세계는 좌우를 뒤집어 길이 지그재그로 오른다.
      final at = _slots[slot % _slots.length];
      final x = world.isEven ? 1 - at.dx : at.dx;
      final scale = .9 + random.nextDouble() * .18;
      final box = Rect.fromCenter(
        center: Offset(
          band.left + band.width * x,
          band.top + band.height * at.dy,
        ),
        width: _box.width * scale,
        height: _box.height * scale,
      );
      Offset node(Offset unit) =>
          box.topLeft + Offset(unit.dx * box.width, unit.dy * box.height);
      final nodes = [for (final unit in definition.nodes) node(unit)];
      final dust = <Offset>[];
      for (var tries = 0; tries < 40 && dust.length < 8; tries++) {
        final point = Offset(
          box.left - 18 + random.nextDouble() * (box.width + 36),
          box.top - 18 + random.nextDouble() * (box.height + 36),
        );
        if (nodes.every((other) => (other - point).distance > 26)) {
          dust.add(point);
        }
      }
      return SkyConstellation(
        index: index++,
        world: world,
        name: name,
        status: status,
        definition: definition,
        box: box,
        dust: List.unmodifiable(dust),
        worldUnlocked: worldUnlocked,
        stars: [
          for (final (slot, stage) in stages.indexed)
            SkyStar(
              levelId: stage.id,
              number: stage.number,
              stars: stage.stars,
              lit: stage.lit,
              unlocked: worldUnlocked && stage.unlocked,
              position: nodes[slot],
            ),
        ],
      );
    }

    for (final (order, number) in numbers.indexed) {
      final band = bandOf(order);
      final info = session.saga?.world(number);
      final unlocked = number == 1 || session.worldUnlocked(number);
      final tint = info?.theme?.palette?.accent ?? colors.primary;
      final List<SkyConstellation> constellations;
      if (number == 1) {
        final atlas = ConstellationAtlas.derive(
          session.levels,
          session.progress,
        );
        constellations = [
          for (final (slot, chapter) in atlas.chapters.indexed)
            place(
              world: 1,
              slot: slot,
              band: band,
              name: chapter.definition.name(t),
              status: constellationStatus(t, chapter),
              definition: chapter.definition,
              worldUnlocked: true,
              stages: [
                for (final level in chapter.levels)
                  (
                    id: level.id,
                    number: level.id,
                    stars: chapter.bestStars[level.id] ?? 0,
                    lit: chapter.isLit(level.id),
                    unlocked: true,
                  ),
              ],
            ),
        ];
      } else {
        constellations = [
          for (final (slot, chapter)
              in (session.worldAtlas(number)?.chapters ?? const []).indexed)
            place(
              world: number,
              slot: slot,
              band: band,
              name: chapter.chapter.constellation.inLocale(lang),
              status: unlocked && chapter.unlocked
                  ? worldChapterStatus(t, chapter)
                  : t.journeyWorldLocked,
              definition: chapter.definition,
              worldUnlocked: unlocked,
              stages: [
                for (final stage in chapter.stages)
                  (
                    id: stage.level.id,
                    number: Worlds.stageNumber(stage.level.id),
                    stars: stage.stars,
                    lit: stage.cleared,
                    unlocked: stage.unlocked,
                  ),
              ],
            ),
        ];
      }
      worlds.add(
        SkyWorld(
          number: number,
          title:
              info?.title.inLocale(lang) ??
              (number == 1 ? t.journeyFirstWorld : '$number'),
          unlocked: unlocked,
          band: band,
          tint: tint,
          constellations: List.unmodifiable(constellations),
        ),
      );
    }
    return StarSkyData._(
      List.unmodifiable(worlds),
      Size(width, height),
      const Offset(width / 2, 136),
    );
  }

  final List<SkyWorld> worlds;
  final Size size;

  /// 빛길 끝에서 기다리는 첫 별의 자리.
  final Offset firstStar;

  Iterable<SkyConstellation> get constellations =>
      worlds.expand((world) => world.constellations);
  int get total => constellations.length;
  int get restored => constellations.where((item) => item.complete).length;

  /// 모든 별 가운데 켠 비율(0~1). 첫 별의 빛이 이만큼 차오른다.
  double get glow {
    final stars = constellations.expand((item) => item.stars);
    final count = stars.length;
    return count == 0 ? 0 : stars.where((star) => star.lit).length / count;
  }

  SkyConstellation? forLevel(int? levelId) => levelId == null
      ? null
      : constellations
            .where((item) => item.stars.any((star) => star.levelId == levelId))
            .firstOrNull;

  SkyWorld? world(int number) =>
      worlds.where((world) => world.number == number).firstOrNull;

  /// 세계에 들어갔을 때 먼저 볼 별자리: 하다 만 것, 없으면 첫 별자리.
  SkyConstellation? entryOf(int number) {
    final items = world(number)?.constellations ?? const <SkyConstellation>[];
    return items.where((item) => item.unlocked && !item.complete).firstOrNull ??
        items.firstOrNull;
  }
}

/// 별하늘 한 장을 그린다. [time]은 초 단위로 흐르고, [intro]는 열 때 한 번 0에서 1로 간다.
class StarSkyPainter extends CustomPainter {
  StarSkyPainter({
    required this.data,
    required this.colors,
    required this.labels,
    required this.time,
    required this.intro,
    required this.selectedLevelId,
    required this.focus,
    required this.viewport,
    required this.reduceMotion,
    super.repaint,
  });

  final StarSkyData data;
  final GameColors colors;

  /// 미리 배치해 둔 글자. 세계는 `w<번호>`, 별자리는 `c<순서>`로 찾는다.
  final Map<String, TextPainter> labels;
  final ValueGetter<double> time;
  final ValueGetter<double> intro;
  final int? selectedLevelId;
  final SkyConstellation? focus;

  /// 지금 화면에 보이는 영역(별하늘 좌표). 별똥별을 이 안에 떨어뜨린다.
  final ValueGetter<Rect> viewport;
  final bool reduceMotion;

  static const _gold = Color(0xffffd36b);

  @override
  void paint(Canvas canvas, Size size) {
    final now = reduceMotion ? 0.0 : time();
    final enter = reduceMotion ? 1.0 : Curves.easeOutCubic.transform(intro());
    final seen = viewport().inflate(120);
    _backdrop(canvas, size);
    _dust(canvas, size, now, seen);
    _road(canvas, now, enter);
    _firstStar(canvas, now);
    for (final world in data.worlds) {
      if (!world.band.inflate(80).overlaps(seen)) continue;
      labels['w${world.number}']?.paint(
        canvas,
        Offset(28, world.band.top + 22),
      );
      for (final item in world.constellations) {
        if (item.box.inflate(60).overlaps(seen)) {
          _constellation(canvas, world, item, now, enter);
        }
      }
    }
    if (!reduceMotion) _meteor(canvas, now);
  }

  void _backdrop(Canvas canvas, Size size) {
    final deep = Color.lerp(colors.background, Colors.black, .35)!;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [deep, colors.background, deep],
          stops: const [0, .55, 1],
        ).createShader(Offset.zero & size),
    );
    // 세계마다 제 빛깔의 성운을 깐다. 잠긴 세계는 거의 보이지 않는다.
    for (final world in data.worlds) {
      final strength = world.unlocked ? .2 : .05;
      for (final (order, at) in const [
        Offset(.28, .62),
        Offset(.74, .34),
      ].indexed) {
        final center = Offset(
          world.band.left +
              world.band.width * (world.number.isEven ? 1 - at.dx : at.dx),
          world.band.top + world.band.height * at.dy,
        );
        final radius = 300.0 - order * 60;
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                world.tint.withValues(alpha: strength),
                world.tint.withValues(alpha: 0),
              ],
            ).createShader(Rect.fromCircle(center: center, radius: radius)),
        );
      }
    }
  }

  /// 배경의 잔별. 자리와 박자는 고정이고 밝기만 흔들린다.
  void _dust(Canvas canvas, Size size, double now, Rect seen) {
    final random = math.Random(20261117);
    final paint = Paint();
    final count = (size.height / 7).round();
    for (var i = 0; i < count; i++) {
      final point = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      final radius = .6 + random.nextDouble() * 1.3;
      final phase = random.nextDouble() * math.pi * 2;
      final speed = .5 + random.nextDouble() * 1.4;
      if (!seen.contains(point)) continue;
      final twinkle = .55 + .45 * math.sin(now * speed + phase);
      paint.color = Colors.white.withValues(
        alpha: .12 + .5 * twinkle * radius / 1.9,
      );
      canvas.drawCircle(point, radius, paint);
    }
  }

  /// 별자리를 차례로 잇는 빛길. 완성한 데까지는 밝게 흐른다.
  void _road(Canvas canvas, double now, double enter) {
    final stops = [for (final item in data.constellations) item];
    if (stops.isEmpty) return;
    final points = [for (final item in stops) item.center, data.firstStar];
    for (var i = 0; i < points.length - 1; i++) {
      final from = points[i], to = points[i + 1];
      final done = stops[i].complete;
      final bend = Offset(
        (from.dx + to.dx) / 2 + (i.isEven ? 26 : -26),
        (from.dy + to.dy) / 2,
      );
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
      if (!done) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = colors.outline.withValues(alpha: .16),
        );
        continue;
      }
      final metric = path.computeMetrics().first;
      final shown = metric.extractPath(0, metric.length * enter);
      canvas.drawPath(
        shown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6)
          ..color = colors.reward.withValues(alpha: .16),
      );
      canvas.drawPath(
        shown,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..color = colors.reward.withValues(alpha: .5),
      );
      if (reduceMotion) continue;
      // 길 위를 흐르는 빛 알갱이.
      final flow = (now * .16 + i * .37) % 1;
      final spot = metric.getTangentForOffset(metric.length * flow)?.position;
      if (spot != null) {
        canvas.drawCircle(
          spot,
          2.6,
          Paint()
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
            ..color = Colors.white.withValues(
              alpha: .85 * math.sin(flow * math.pi),
            ),
        );
      }
    }
  }

  void _firstStar(Canvas canvas, double now) {
    final glow = data.glow;
    final center = data.firstStar;
    final breath = reduceMotion ? 1.0 : 1 + .05 * math.sin(now * .9);
    final radius = (34 + 46 * glow) * breath;
    canvas.drawCircle(
      center,
      radius * 2.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _gold.withValues(alpha: .1 + .32 * glow),
            _gold.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius * 2.6)),
    );
    final rays = Path();
    for (var i = 0; i < 16; i++) {
      final angle = i * math.pi / 8 - math.pi / 2;
      final reach = i.isEven ? radius * (i % 4 == 0 ? 1.5 : .9) : radius * .26;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * reach;
      i == 0
          ? rays.moveTo(point.dx, point.dy)
          : rays.lineTo(point.dx, point.dy);
    }
    rays.close();
    canvas.drawPath(
      rays,
      Paint()..color = Color.lerp(colors.outline, _gold, .25 + .75 * glow)!,
    );
  }

  void _constellation(
    Canvas canvas,
    SkyWorld world,
    SkyConstellation item,
    double now,
    double enter,
  ) {
    final focused = identical(item, focus) || item.index == focus?.index;
    final ink = item.golden
        ? _gold
        : Color.lerp(world.tint, Colors.white, .55)!;
    final open = item.unlocked;

    if (focused) {
      // 고른 별자리 뒤에 옅은 빛무리를 둔다.
      canvas.drawOval(
        item.box.inflate(34),
        Paint()
          ..shader = RadialGradient(
            colors: [ink.withValues(alpha: .14), ink.withValues(alpha: 0)],
          ).createShader(item.box.inflate(34)),
      );
    }

    final faint = Paint()
      ..color = Colors.white.withValues(alpha: open ? .34 : .14);
    for (final (order, point) in item.dust.indexed) {
      final pulse = reduceMotion
          ? 1.0
          : .7 + .3 * math.sin(now * 1.1 + item.index + order * 1.7);
      canvas.drawCircle(point, 1.1 * pulse, faint);
    }

    final stars = item.stars;
    final shimmer = reduceMotion
        ? 0.0
        : .5 + .5 * math.sin(now * 1.6 + item.index * .9);
    for (final (a, b) in item.definition.edges) {
      final from = stars[a].position, to = stars[b].position;
      if (stars[a].lit && stars[b].lit) {
        final end = Offset.lerp(from, to, enter)!;
        canvas.drawLine(
          from,
          end,
          Paint()
            ..strokeWidth = item.golden ? 6 : 5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
            ..color = ink.withValues(
              alpha: item.golden ? .3 + .2 * shimmer : .22,
            ),
        );
        canvas.drawLine(
          from,
          end,
          Paint()
            ..strokeWidth = 1.8
            ..strokeCap = StrokeCap.round
            ..color = ink.withValues(alpha: item.complete ? .95 : .7),
        );
      } else {
        _dotted(
          canvas,
          from,
          to,
          Paint()..color = Colors.white.withValues(alpha: open ? .2 : .08),
        );
      }
    }

    // 황금 별자리: 선을 따라 도는 반짝임.
    if (item.golden && !reduceMotion && item.definition.edges.isNotEmpty) {
      final edges = item.definition.edges;
      final travel = (now * .55 + item.index * .31) % edges.length;
      final (a, b) = edges[travel.floor()];
      final spot = Offset.lerp(
        stars[a].position,
        stars[b].position,
        travel - travel.floor(),
      )!;
      _sparkle(canvas, spot, 7, Colors.white.withValues(alpha: .95));
    }

    for (final star in stars) {
      final at = star.position;
      final chosen = star.levelId == selectedLevelId;
      if (star.lit) {
        final twinkle = reduceMotion
            ? 1.0
            : .88 + .12 * math.sin(now * 2.1 + star.levelId * 1.3);
        final core = (3.4 + star.stars * 1.25) * (.6 + .4 * enter) * twinkle;
        final color = star.stars == 3 ? _gold : ink;
        canvas.drawCircle(
          at,
          core * 3.4,
          Paint()
            ..shader = RadialGradient(
              colors: [color.withValues(alpha: .5), color.withValues(alpha: 0)],
            ).createShader(Rect.fromCircle(center: at, radius: core * 3.4)),
        );
        canvas.drawCircle(at, core, Paint()..color = Colors.white);
        canvas.drawCircle(
          at,
          core,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = color,
        );
        if (star.stars == 3) _sparkle(canvas, at, core * 2.3, color);
      } else {
        canvas.drawCircle(
          at,
          4.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = Colors.white.withValues(alpha: star.unlocked ? .55 : .2),
        );
      }
      if (chosen) {
        final pulse = reduceMotion ? 0.0 : (now * .8) % 1;
        canvas.drawCircle(
          at,
          17,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = colors.reward,
        );
        if (!reduceMotion) {
          canvas.drawCircle(
            at,
            17 + 12 * pulse,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = colors.reward.withValues(alpha: .7 * (1 - pulse)),
          );
        }
      }
    }

    final label = labels['c${item.index}'];
    if (label != null) {
      label.paint(
        canvas,
        Offset(item.center.dx - label.width / 2, item.box.bottom + 10),
      );
    }
  }

  void _dotted(Canvas canvas, Offset from, Offset to, Paint paint) {
    final length = (to - from).distance;
    if (length == 0) return;
    final step = (to - from) / length;
    for (var at = 6.0; at < length - 4; at += 9) {
      canvas.drawCircle(from + step * at, 1, paint);
    }
  }

  void _sparkle(Canvas canvas, Offset center, double reach, Color color) {
    final paint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas
      ..drawLine(center - Offset(reach, 0), center + Offset(reach, 0), paint)
      ..drawLine(center - Offset(0, reach), center + Offset(0, reach), paint);
  }

  /// 아홉 초에 한 번, 지금 보는 하늘을 가로지르는 별똥별.
  void _meteor(Canvas canvas, double now) {
    const period = 9.0, flight = 1.1;
    final cycle = (now / period).floor();
    final progress = (now % period) / flight;
    if (progress >= 1) return;
    final seen = viewport();
    if (seen.isEmpty) return;
    final random = math.Random(cycle * 92821 + 5);
    final start = Offset(
      seen.left + seen.width * (.25 + random.nextDouble() * .7),
      seen.top + seen.height * random.nextDouble() * .45,
    );
    final travel = Offset(-seen.width * .55, seen.width * .32);
    final head = start + travel * Curves.easeIn.transform(progress);
    final tail = head - travel * .22;
    final fade = math.sin(progress * math.pi);
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: .9 * fade),
          ],
        ).createShader(Rect.fromPoints(tail, head)),
    );
    canvas.drawCircle(
      head,
      2.2,
      Paint()..color = Colors.white.withValues(alpha: fade),
    );
  }

  @override
  bool shouldRepaint(covariant StarSkyPainter old) =>
      old.data != data ||
      old.colors != colors ||
      old.labels != labels ||
      old.selectedLevelId != selectedLevelId ||
      old.focus?.index != focus?.index ||
      old.reduceMotion != reduceMotion;
}

/// 손가락으로 움직이고 확대할 수 있는 별하늘. 별을 누르면 그 판을 고른다.
class StarSky extends StatefulWidget {
  const StarSky({
    super.key,
    required this.data,
    required this.focus,
    required this.selectedLevelId,
    required this.reduceMotion,
    required this.onStar,
    required this.starLabel,
  });

  final StarSkyData data;

  /// 화면 가운데에 둘 별자리. 바뀌면 그쪽으로 옮겨 간다.
  final SkyConstellation? focus;
  final int? selectedLevelId;
  final bool reduceMotion;
  final ValueChanged<SkyStar> onStar;

  /// 화면 읽기 프로그램이 읽을 별의 설명.
  final String Function(SkyStar star) starLabel;

  @override
  State<StarSky> createState() => StarSkyState();
}

class StarSkyState extends State<StarSky> with TickerProviderStateMixin {
  static const _maxScale = 1.5;
  // 이웃 별자리가 함께 보이도록 조금 물러서서 시작한다.
  static const _startScale = .7;
  static const _starTarget = 48.0;

  late final _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 240),
  );
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  )..addListener(_glideTick);

  TransformationController? _camera;
  Matrix4Tween? _route;
  Size _view = Size.zero;
  final _labels = <String, TextPainter>{};
  Object? _labelKey;

  @override
  void initState() {
    super.initState();
    if (!widget.reduceMotion) {
      _clock.repeat();
      _intro.forward();
    } else {
      _intro.value = 1;
    }
  }

  @override
  void didUpdateWidget(StarSky oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      if (widget.reduceMotion) {
        _clock.stop();
        _intro.value = 1;
      } else {
        _clock.repeat();
      }
    }
    if (oldWidget.focus?.index != widget.focus?.index && widget.focus != null) {
      lookAt(widget.focus!.center);
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _intro.dispose();
    _glide.dispose();
    _camera?.dispose();
    for (final painter in _labels.values) {
      painter.dispose();
    }
    super.dispose();
  }

  double get _minScale => _view.isEmpty
      ? .3
      : math.min(_startScale, _view.width / widget.data.size.width);

  /// [center]가 화면 가운데에 오도록 하되 하늘 밖이 보이지 않게 막는다.
  Matrix4 _matrix(Offset center, double scale) {
    final size = widget.data.size;
    double fit(double wanted, double view, double extent) {
      final low = view - extent * scale;
      return low >= 0 ? low / 2 : wanted.clamp(low, 0.0);
    }

    return Matrix4.identity()
      ..translateByDouble(
        fit(_view.width / 2 - center.dx * scale, _view.width, size.width),
        fit(_view.height / 2 - center.dy * scale, _view.height, size.height),
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
  }

  double get _scale => _camera?.value.getMaxScaleOnAxis() ?? _startScale;

  /// 지금 화면에 보이는 영역(별하늘 좌표).
  Rect get _seen {
    final camera = _camera;
    if (camera == null || _view.isEmpty) return Rect.zero;
    final scale = _scale;
    final shift = camera.value.getTranslation();
    return Rect.fromLTWH(
      -shift.x / scale,
      -shift.y / scale,
      _view.width / scale,
      _view.height / scale,
    );
  }

  void _glideTick() {
    final route = _route;
    if (route != null) {
      _camera?.value = route.evaluate(
        CurvedAnimation(parent: _glide, curve: Curves.easeInOutCubic),
      );
    }
  }

  void _go(Matrix4 target) {
    final camera = _camera;
    if (camera == null) return;
    if (widget.reduceMotion) {
      camera.value = target;
      return;
    }
    _route = Matrix4Tween(begin: camera.value.clone(), end: target);
    _glide.forward(from: 0);
  }

  /// 하늘의 한 점으로 옮겨 간다. 너무 멀리 보고 있었으면 읽을 만큼 당긴다.
  void lookAt(Offset center) =>
      _go(_matrix(center, math.max(_scale, _startScale.clamp(_minScale, 1.0))));

  /// 하늘 전체가 가로로 다 보이게 물러난다.
  void overview() {
    final seen = _seen;
    _go(
      _matrix(
        seen.isEmpty ? widget.data.size.center(Offset.zero) : seen.center,
        _minScale,
      ),
    );
  }

  void _layoutLabels(BuildContext context, GameColors colors) {
    final scaler = MediaQuery.textScalerOf(context);
    final key = (widget.data, colors, scaler);
    if (_labelKey == key) return;
    _labelKey = key;
    for (final painter in _labels.values) {
      painter.dispose();
    }
    _labels.clear();
    TextPainter text(String value, TextStyle style, double width) =>
        TextPainter(
          text: TextSpan(text: value, style: style),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          maxLines: 1,
          ellipsis: '…',
          // 하늘이 줄어들어 보이므로 글자 확대는 조금만 반영한다.
          textScaler: TextScaler.linear(scaler.scale(1).clamp(1, 1.3)),
        )..layout(maxWidth: width);

    for (final world in widget.data.worlds) {
      _labels['w${world.number}'] = text(
        '${world.number} · ${world.title}',
        GameTypography.reward.copyWith(
          fontSize: 38,
          color: (world.unlocked ? colors.text : colors.secondaryText)
              .withValues(alpha: world.unlocked ? .9 : .45),
        ),
        StarSkyData.width - 56,
      );
      for (final item in world.constellations) {
        _labels['c${item.index}'] = text(
          item.name,
          GameTypography.label.copyWith(
            fontSize: 25,
            color: item.golden
                ? const Color(0xffffd36b)
                : item.complete
                ? colors.text
                : colors.secondaryText.withValues(
                    alpha: item.unlocked ? .8 : .4,
                  ),
          ),
          item.box.width + 60,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final data = widget.data;
    _layoutLabels(context, colors);
    return LayoutBuilder(
      builder: (context, area) {
        _view = area.biggest;
        final start = widget.focus?.center ?? data.size.center(Offset.zero);
        // 처음 크기를 안 순간에 한 번만 자리를 잡는다.
        final camera = _camera ??= TransformationController(
          _matrix(start, _startScale.clamp(_minScale, 1.0)),
        );
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: InteractiveViewer(
            key: const ValueKey('star-sky'),
            transformationController: camera,
            constrained: false,
            minScale: _minScale,
            maxScale: _maxScale,
            onInteractionStart: (_) => _glide.stop(),
            child: SizedBox.fromSize(
              size: data.size,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: StarSkyPainter(
                          data: data,
                          colors: colors,
                          labels: _labels,
                          time: () => _clock.value * 240,
                          intro: () => _intro.value,
                          selectedLevelId: widget.selectedLevelId,
                          focus: widget.focus,
                          viewport: () => _seen,
                          reduceMotion: widget.reduceMotion,
                          repaint: Listenable.merge([_clock, _intro, camera]),
                        ),
                      ),
                    ),
                  ),
                  for (final item in data.constellations)
                    for (final star in item.stars)
                      Positioned(
                        left: star.position.dx - _starTarget / 2,
                        top: star.position.dy - _starTarget / 2,
                        width: _starTarget,
                        height: _starTarget,
                        child: Semantics(
                          button: true,
                          enabled: star.unlocked,
                          selected: star.levelId == widget.selectedLevelId,
                          label: widget.starLabel(star),
                          child: GestureDetector(
                            key: ValueKey('journey-stage-${star.levelId}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: star.unlocked
                                ? () => widget.onStar(star)
                                : null,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
