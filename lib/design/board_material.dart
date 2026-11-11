import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/puzzle.dart';
import '../game/board_geometry.dart';
import '../world/world_theme.dart';
import 'game_theme.dart';
import 'star_art.dart';

/// 판·룬석·받침에 같은 광원과 돌의 두께를 적용한다. 그림과 입력은 분리된다.
class BoardMaterial {
  const BoardMaterial(this.colors, {this.skin});
  final GameColors colors;
  final WorldBoardSkin? skin;
  WorldPalette? get _palette => skin?.palette;
  bool get dark => colors == GameColors.dark;
  Color get edge => dark ? const Color(0xff202e49) : const Color(0xff6c7f98);
  Color get well => dark ? const Color(0xff15263d) : const Color(0xffd0d6df);
  static const moss = Color(0xff7fa865);

  void frame(Canvas canvas, BoardGeometry geometry) {
    final palette = _palette;
    final board = RRect.fromRectAndRadius(
      geometry.framedBoardRect,
      Radius.circular(geometry.boardRadius),
    );
    // 배치 여백 안에서 돌 테두리의 실제 두께만 줄인다.
    final rim = board.inflate(8);
    canvas.drawRRect(
      rim.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: dark ? .32 : .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(
      rim,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette != null
              ? [
                  palette.border,
                  Color.lerp(palette.border, palette.board, .45)!,
                ]
              : dark
              ? const [Color(0xff283b4e), Color(0xff172635)]
              : const [Color(0xffa2b4c4), Color(0xff667d93)],
        ).createShader(rim.outerRect),
    );
    final reflection =
        palette?.accent ??
        (dark ? const Color(0xff678094) : const Color(0xffe0e9f1));
    canvas.drawRRect(
      rim.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            reflection.withValues(alpha: .55),
            reflection.withValues(alpha: 0),
          ],
          stops: const [0, .55],
        ).createShader(rim.outerRect),
    );
    canvas.drawRRect(
      board.inflate(2),
      Paint()
        ..color =
            palette?.background ??
            (dark ? const Color(0xff101d2a) : const Color(0xff52677a)),
    );
    if (palette != null && palette.accents.isNotEmpty) {
      for (final (index, accent) in palette.accents.indexed) {
        final at = Offset(
          rim.left + rim.width * (index + 1) / (palette.accents.length + 1),
          rim.top + 2,
        );
        final star = Paint()
          ..color = accent
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(at - const Offset(3, 0), at + const Offset(3, 0), star);
        canvas.drawLine(at - const Offset(0, 3), at + const Offset(0, 3), star);
      }
    }
  }

  void floor(Canvas canvas, BoardGeometry geometry) {
    final palette = _palette;
    final wellColor = palette == null
        ? well
        : Color.lerp(palette.board, palette.background, .38)!;
    canvas.drawRRect(geometry.boardShape, Paint()..color = wellColor);
    final wood = skin?.woodFloor == true && skin?.floor == null
        ? StarArt.plankImage
        : null;
    final customFloor = skin?.floor ?? wood;
    final stones = [
      if (customFloor != null)
        customFloor
      else if (palette == null)
        for (final name in ['floor_1', 'floor_2', 'floor_3', 'floor_4'])
          ?StarArt.garden[name],
    ];
    if (stones.isNotEmpty) {
      // 판석은 위치마다 고정된 변주를 쓰고, 밤에는 달빛 남색을 입힌다.
      final paint = Paint()..filterQuality = FilterQuality.medium;
      final useWood = wood != null;
      if (customFloor == null) {
        paint.colorFilter = ColorFilter.mode(
          dark ? const Color(0xffa9b8d6) : const Color(0xfff4f1ea),
          BlendMode.modulate,
        );
        canvas.drawRRect(
          geometry.boardShape,
          Paint()
            ..color = dark ? const Color(0xff1b2a2a) : const Color(0xff8d9a86),
        );
      } else if (useWood && palette != null) {
        paint.colorFilter = ColorFilter.mode(
          Color.lerp(palette.board, palette.border, .38)!,
          BlendMode.color,
        );
      }
      for (var y = 0; y < geometry.rows; y++) {
        for (var x = 0; x < geometry.columns; x++) {
          final image = stones[(x * 7 + y * 13 + x * y) % stones.length];
          final position = Position(x, y);
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(
              0,
              0,
              image.width.toDouble(),
              image.height.toDouble(),
            ),
            useWood
                ? geometry.tileRect(position)
                : geometry.cellRect(position).inflate(geometry.cellSize * .015),
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
          Paint()
            ..color = (palette?.background ?? edge).withValues(
              alpha: dark ? .78 : .45,
            ),
        );
        final face = shape.deflate(1.3).shift(const Offset(0, 1));
        canvas.drawRRect(
          face,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: palette != null
                  ? [
                      Color.lerp(palette.board, palette.border, .23)!,
                      palette.board,
                    ]
                  : [
                      Color.lerp(well, Colors.black, dark ? .12 : .02)!,
                      Color.lerp(well, colors.tileTop, .45)!,
                    ],
            ).createShader(rect),
        );
        canvas.drawRRect(
          shape.deflate(.5),
          Paint()
            ..color = (palette?.accent ?? colors.highlight).withValues(
              alpha: palette != null ? .55 : (dark ? .09 : .38),
            )
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
  const MoonstoneFramePainter(this.geometry, this.colors, {this.skin});
  final BoardGeometry geometry;
  final GameColors colors;
  final WorldBoardSkin? skin;
  @override
  void paint(Canvas canvas, Size size) =>
      BoardMaterial(colors, skin: skin).frame(canvas, geometry);
  @override
  bool shouldRepaint(MoonstoneFramePainter oldDelegate) =>
      !geometry.sameLayout(oldDelegate.geometry) ||
      colors != oldDelegate.colors ||
      skin != oldDelegate.skin;
}
