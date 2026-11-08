import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/puzzle.dart';
import '../game/board_geometry.dart';
import 'game_theme.dart';
import 'star_art.dart';

/// 판·룬석·받침에 같은 광원과 돌의 두께를 적용한다. 그림과 입력은 분리된다.
class BoardMaterial {
  const BoardMaterial(this.colors);
  final GameColors colors;
  bool get dark => colors == GameColors.dark;
  Color get stone => dark ? const Color(0xff4b6180) : const Color(0xffb3bfce);
  Color get edge => dark ? const Color(0xff202e49) : const Color(0xff6c7f98);
  Color get well => dark ? const Color(0xff15263d) : const Color(0xffd0d6df);

  /// 달빛 숲 정원의 고목 판자 색. 판자 그림의 결만 쓰고 색은 여기서 입힌다.
  static const wood = Color(0xff7a5638);
  static const woodEdge = Color(0xff3b2817);
  static const moss = Color(0xff7fa865);

  void frame(Canvas canvas, BoardGeometry geometry) {
    final shape = geometry.frameShape;
    final depth = geometry.stoneDepth;
    final plank = StarArt.garden['plank'];
    canvas.drawRRect(
      shape.shift(Offset(0, depth + 1)),
      Paint()..color = Colors.black.withValues(alpha: dark ? .35 : .16),
    );
    canvas.drawRRect(
      shape.shift(Offset(0, depth)),
      Paint()..color = plank == null ? edge : woodEdge,
    );
    if (plank != null) {
      _woodFrame(canvas, geometry, shape, plank);
      return;
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(stone, colors.highlight, .24)!,
            stone,
            Color.lerp(stone, edge, .32)!,
          ],
        ).createShader(shape.outerRect),
    );
    canvas.drawRRect(
      shape.deflate(1),
      Paint()
        ..color = colors.highlight.withValues(alpha: .24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    final inner = RRect.fromRectAndRadius(
      geometry.framedBoardRect.inflate(3),
      Radius.circular(geometry.boardRadius + 3),
    );
    canvas.drawRRect(inner, Paint()..color = edge);
    canvas.drawRRect(
      inner.inflate(4),
      Paint()
        ..color = colors.rewardInk.withValues(alpha: dark ? .27 : .2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    // 각 모서리의 작은 각인은 보드 안쪽과 겹치지 않는다.
    final band = geometry.frameInset / 2;
    for (final p in [
      Offset(shape.left + band + 2, shape.top + band),
      Offset(shape.right - band - 2, shape.top + band),
      Offset(shape.left + band + 2, shape.bottom - band),
      Offset(shape.right - band - 2, shape.bottom - band),
    ]) {
      final path = Path();
      for (var i = 0; i < 8; i++) {
        final angle = -math.pi / 2 + i * math.pi / 4;
        final r = i.isEven ? 3.8 : 1.3;
        final at = p + Offset(math.cos(angle) * r, math.sin(angle) * r);
        if (i == 0) {
          path.moveTo(at.dx, at.dy);
        } else {
          path.lineTo(at.dx, at.dy);
        }
      }
      canvas.drawPath(
        path..close(),
        Paint()..color = colors.reward.withValues(alpha: .68),
      );
    }
  }

  /// 이끼 낀 고목 판자 테두리. 위아래는 가로 결, 좌우는 세로 결로 깐다.
  void _woodFrame(
    Canvas canvas,
    BoardGeometry geometry,
    RRect shape,
    ui.Image plank,
  ) {
    final inner = RRect.fromRectAndRadius(
      geometry.framedBoardRect.inflate(3),
      Radius.circular(geometry.boardRadius + 3),
    );
    final ring = Path.combine(
      PathOperation.difference,
      Path()..addRRect(shape),
      Path()..addRRect(inner),
    );
    final band = geometry.frameInset;
    final scale = band / plank.height * 1.4;
    Paint grain(bool vertical) => Paint()
      ..shader = ImageShader(
        plank,
        TileMode.repeated,
        TileMode.repeated,
        (Matrix4.identity()
              ..rotateZ(vertical ? math.pi / 2 : 0)
              ..scaleByDouble(scale, scale, 1, 1))
            .storage,
      )
      ..colorFilter = const ColorFilter.mode(wood, BlendMode.color);
    canvas.save();
    canvas.clipPath(ring);
    canvas.drawRect(shape.outerRect, grain(false));
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        shape.left,
        shape.top + band,
        shape.right,
        shape.bottom - band,
      ),
    );
    for (final side in [
      Rect.fromLTWH(shape.left, shape.top, band, shape.height),
      Rect.fromLTWH(shape.right - band, shape.top, band, shape.height),
    ]) {
      canvas.drawRect(side, grain(true));
    }
    canvas.restore();
    // 달빛이 좌상단에서 비치고 우하단은 그늘진다.
    canvas.drawRect(
      shape.outerRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.highlight.withValues(alpha: dark ? .10 : .22),
            Colors.transparent,
            Colors.black.withValues(alpha: dark ? .30 : .16),
          ],
        ).createShader(shape.outerRect),
    );
    // 판자 이음매와 위쪽 가장자리의 이끼.
    final seam = Paint()
      ..color = woodEdge.withValues(alpha: .55)
      ..strokeWidth = 1.2;
    for (final t in [.31, .68]) {
      final x = shape.left + shape.width * t;
      canvas.drawLine(Offset(x, shape.top), Offset(x, shape.top + band), seam);
      canvas.drawLine(
        Offset(x + 9, shape.bottom - band),
        Offset(x + 9, shape.bottom),
        seam,
      );
    }
    final random = math.Random(geometry.columns * 31 + geometry.rows);
    final tuft = Paint()..color = moss.withValues(alpha: dark ? .72 : .85);
    // 윗면에만 몇 군데 이끼가 뭉쳐 자란다.
    for (var i = 0; i < 5; i++) {
      final along = .12 + random.nextDouble() * .76;
      final base = Offset(shape.left + shape.width * along, shape.top + 2);
      for (var j = 0; j < 4; j++) {
        canvas.drawOval(
          Rect.fromCenter(
            center: base + Offset(j * 4.0 - 6, random.nextDouble() * 2),
            width: 5 + random.nextDouble() * 5,
            height: 3 + random.nextDouble() * 2,
          ),
          tuft,
        );
      }
    }
    canvas.restore();
    canvas.drawRRect(
      shape.deflate(1),
      Paint()
        ..color = colors.highlight.withValues(alpha: .16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawRRect(inner, Paint()..color = woodEdge);
    // 모서리에는 은은히 빛나는 버섯 세 송이.
    final glow = colors.reward;
    for (final corner in [
      Offset(shape.left + band * .55, shape.top + band * .55),
      Offset(shape.right - band * .55, shape.top + band * .55),
      Offset(shape.left + band * .55, shape.bottom - band * .55),
      Offset(shape.right - band * .55, shape.bottom - band * .55),
    ]) {
      canvas.drawCircle(
        corner,
        band * .62,
        Paint()
          ..shader = RadialGradient(
            colors: [glow.withValues(alpha: .38), glow.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: corner, radius: band * .62)),
      );
      for (final (dx, dy, r) in [
        (-.16, .06, .20),
        (.14, -.04, .16),
        (.02, .18, .12),
      ]) {
        final cap = corner + Offset(dx * band, dy * band);
        canvas.drawLine(
          cap,
          cap + Offset(0, band * r * 1.1),
          Paint()
            ..color = const Color(0xfff1e2bf)
            ..strokeWidth = math.max(1.2, band * r * .35),
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: cap,
            width: band * r * 2,
            height: band * r * 1.3,
          ),
          Paint()..color = Color.lerp(glow, const Color(0xffe0a13d), .4)!,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: cap - Offset(band * r * .25, band * r * .2),
            width: band * r * .7,
            height: band * r * .4,
          ),
          Paint()..color = colors.highlight.withValues(alpha: .7),
        );
      }
    }
  }

  void floor(Canvas canvas, BoardGeometry geometry) {
    canvas.drawRRect(geometry.boardShape, Paint()..color = well);
    final stones = [
      for (final name in ['floor_1', 'floor_2', 'floor_3', 'floor_4'])
        ?StarArt.garden[name],
    ];
    if (stones.isNotEmpty) {
      // 판석은 위치마다 고정된 변주를 쓰고, 밤에는 달빛 남색을 입힌다.
      final paint = Paint()
        ..filterQuality = FilterQuality.medium
        ..colorFilter = ColorFilter.mode(
          dark ? const Color(0xffa9b8d6) : const Color(0xfff4f1ea),
          BlendMode.modulate,
        );
      canvas.drawRRect(
        geometry.boardShape,
        Paint()
          ..color = dark ? const Color(0xff1b2a2a) : const Color(0xff8d9a86),
      );
      for (var y = 0; y < geometry.rows; y++) {
        for (var x = 0; x < geometry.columns; x++) {
          final image = stones[(x * 7 + y * 13 + x * y) % stones.length];
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            geometry.cellRect(Position(x, y)).inflate(geometry.cellSize * .015),
            paint,
          );
        }
      }
      return;
    }
    for (var y = 0; y < geometry.rows; y++) {
      for (var x = 0; x < geometry.columns; x++) {
        final rect = geometry.tileRect(Position(x, y));
        final radius = geometry.cellSize * .14;
        final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
        canvas.drawRRect(
          shape,
          Paint()..color = edge.withValues(alpha: dark ? .78 : .45),
        );
        final face = shape.deflate(1.3).shift(const Offset(0, 1));
        canvas.drawRRect(
          face,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(well, Colors.black, dark ? .12 : .02)!,
                Color.lerp(well, colors.tileTop, .45)!,
              ],
            ).createShader(rect),
        );
        canvas.drawRRect(
          shape.deflate(.5),
          Paint()
            ..color = colors.highlight.withValues(alpha: dark ? .09 : .38)
            ..style = PaintingStyle.stroke
            ..strokeWidth = .8,
        );
      }
    }
  }

  void raised(
    Canvas canvas,
    Rect rect,
    double cell,
    Color color, {
    double opacity = 1,
  }) {
    final depth = (cell * .05).clamp(3.0, 6.0);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(cell * .15));
    canvas.drawRRect(
      shape.shift(Offset(0, depth + 1)),
      Paint()..color = Colors.black.withValues(alpha: .2 * opacity),
    );
    canvas.drawRRect(
      shape.shift(Offset(0, depth)),
      Paint()..color = Color.lerp(color, edge, .55)!.withValues(alpha: opacity),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, colors.highlight, .3)!.withValues(alpha: opacity),
            color.withValues(alpha: opacity),
            Color.lerp(color, edge, .18)!.withValues(alpha: opacity),
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape.deflate(cell * .025),
      Paint()
        ..color = colors.highlight.withValues(alpha: .4 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, cell * .014),
    );
    final highlight = Path()
      ..moveTo(rect.left + cell * .15, rect.top + cell * .065)
      ..lineTo(rect.right - cell * .18, rect.top + cell * .065);
    canvas.drawPath(
      highlight,
      Paint()
        ..color = colors.highlight.withValues(alpha: .5 * opacity)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.3,
    );
  }
}

class MoonstoneFramePainter extends CustomPainter {
  const MoonstoneFramePainter(this.geometry, this.colors);
  final BoardGeometry geometry;
  final GameColors colors;
  @override
  void paint(Canvas canvas, Size size) =>
      BoardMaterial(colors).frame(canvas, geometry);
  @override
  bool shouldRepaint(MoonstoneFramePainter oldDelegate) =>
      !geometry.sameLayout(oldDelegate.geometry) ||
      colors != oldDelegate.colors;
}
