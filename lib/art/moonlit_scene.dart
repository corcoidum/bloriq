import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'game_art_assets.dart';
import '../design/game_theme.dart';

/// 배경만 장식한다. 이 레이어에는 퍼즐 hit test나 게임 상태 변경이 없다.
class MoonlitScene extends StatelessWidget {
  const MoonlitScene({
    super.key,
    required this.assets,
    required this.chapter,
    required this.stage,
    required this.restored,
    required this.dark,
    required this.reduceMotion,
    required this.intro,
    required this.child,
  });
  final GameArtAssets assets;
  final int chapter;
  final int stage;
  final int restored;
  final bool dark;
  final bool reduceMotion;
  final bool intro;
  final Widget child;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: AnimatedBuilder(
          animation: assets,
          builder: (context, _) {
            final image = assets.background(chapter);
            return TweenAnimationBuilder<double>(
              key: ValueKey('scene-$chapter-$intro-$reduceMotion'),
              tween: Tween(begin: intro && !reduceMotion ? .55 : 1, end: 1),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              builder: (context, value, _) => CustomPaint(
                painter: _ScenePainter(
                  image,
                  assets.tile('ornament'),
                  [
                    for (final name in [
                      'decor_flowers',
                      'decor_mist',
                      'decor_stars',
                      'decor_petals',
                    ])
                      assets.tile(name),
                  ],
                  stage,
                  restored,
                  dark,
                  value,
                ),
              ),
            );
          },
        ),
      ),
      child,
    ],
  );
}

class _ScenePainter extends CustomPainter {
  const _ScenePainter(
    this.image,
    this.ornament,
    this.decorations,
    this.stage,
    this.restored,
    this.dark,
    this.reveal,
  );
  final ui.Image? image;
  final ui.Image? ornament;
  final List<ui.Image?> decorations;
  final int stage;
  final int restored;
  final bool dark;
  final double reveal;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xff282844), BlendMode.src);
    if (image != null) {
      final scale = math.max(
        size.width / image!.width,
        size.height / image!.height,
      );
      final width = image!.width * scale, height = image!.height * scale;
      paintArt(
        canvas,
        image!,
        Rect.fromLTWH(
          (size.width - width) / 2,
          (size.height - height) / 2,
          width,
          height,
        ),
        opacity: reveal,
      );
    }
    // 밝기 보정은 원화 위의 단색 막이며 원화/광원/식물 자체를 코드로 그리지 않는다.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color.fromRGBO(13, 17, 40, dark ? .38 : .12),
    );
    final variant = (stage - 1) % 5;
    final flowers = decorations[0],
        mist = decorations[1],
        stars = decorations[2],
        petals = decorations[3];
    if (flowers != null && variant.isEven) {
      paintArt(
        canvas,
        flowers,
        Rect.fromLTWH(0, size.height * .81, 110, 110),
        opacity: .8,
      );
    }
    if (mist != null && variant > 0) {
      paintArt(
        canvas,
        mist,
        Rect.fromLTWH(0, size.height * .46, size.width, size.width * .55),
        opacity: .12,
      );
    }
    if (stars != null) {
      paintArt(
        canvas,
        stars,
        Rect.fromLTWH(size.width - 100, size.height * .18, 90, 110),
        opacity: .1 + restored.clamp(0, 5) * .12,
      );
    }
    if (petals != null && variant >= 2) {
      paintArt(
        canvas,
        petals,
        Rect.fromLTWH(size.width - 60, size.height * .56, 60, 120),
        opacity: .65,
      );
    }
    if (ornament != null) {
      final variant = (stage - 1) % 5;
      for (var i = 0; i <= variant; i++) {
        final width = 36.0 + (i % 2) * 8;
        final x = i.isEven ? 4.0 + i * 2 : size.width - width - 4 - i * 2;
        final y = size.height * (.25 + i * .115);
        paintArt(
          canvas,
          ornament!,
          Rect.fromLTWH(x, y, width, width * 1.35),
          opacity: .45 + restored.clamp(0, 5) * .08,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScenePainter old) =>
      old.image != image ||
      old.ornament != ornament ||
      old.stage != stage ||
      old.restored != restored ||
      old.dark != dark ||
      old.reveal != reveal;
}

/// 아이보리 원화 테두리는 터치 영역 밖, 셀과 입력은 기존 geometry 그대로다.
class MoonlitBoardFrame extends StatelessWidget {
  const MoonlitBoardFrame({
    super.key,
    required this.assets,
    required this.child,
  });
  final GameArtAssets assets;
  final Widget child;
  static const inset = 14.0;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: IgnorePointer(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: CustomPaint(
              painter: _PaperSurface(assets.tile('empty'), false),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: IgnorePointer(
          child: RawImage(
            image: assets.tile('frame'),
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
      Padding(padding: const EdgeInsets.all(inset), child: child),
    ],
  );
}

class MoonlitControlPlate extends StatelessWidget {
  const MoonlitControlPlate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final assets = GameArtScope.maybeOf(context);
    if (assets == null) return child;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ButtonSurface(assets.tile('button'))),
          ),
        ),
        Theme(
          data: GameTheme.light,
          child: DefaultTextStyle.merge(
            style: TextStyle(color: GameColors.light.text),
            child: child,
          ),
        ),
      ],
    );
  }
}

class MoonlitPaper extends StatelessWidget {
  const MoonlitPaper({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final assets = GameArtScope.maybeOf(context);
    if (assets == null) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _PaperSurface(
                  assets.tile('empty'),
                  Theme.of(context).brightness == Brightness.dark,
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _PaperSurface extends CustomPainter {
  const _PaperSurface(this.image, this.dark);
  final ui.Image? image;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    paintStoneSurface(canvas, image!, Offset.zero & size, dark: dark);
  }

  @override
  bool shouldRepaint(covariant _PaperSurface old) =>
      old.image != image || old.dark != dark;
}

class _ButtonSurface extends CustomPainter {
  const _ButtonSurface(this.image);
  final ui.Image? image;
  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) return;
    // 단일 버튼 PNG의 투명한 상하 캔버스를 제외해 눌리는 면을 44px 이상으로 표시한다.
    final src = Rect.fromLTWH(
      image!.width * .025,
      image!.height * .20,
      image!.width * .95,
      image!.height * .59,
    );
    canvas.drawImageRect(
      image!,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _ButtonSurface old) => old.image != image;
}
