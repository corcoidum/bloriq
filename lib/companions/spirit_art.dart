import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'season.dart';
import '../art/game_art_assets.dart';

/// 벡터 아트: 공통 체형 안에서 계열과 다섯 장식을 구분한다.
class SpiritArt extends StatefulWidget {
  const SpiritArt({
    super.key,
    this.spirit,
    this.locked = false,
    this.size = 72,
    this.reaction = 'idle',
    this.reduceMotion = false,
    this.animateIdle = false,
  });
  final Spirit? spirit;
  final bool locked;
  final double size;
  final String reaction;
  final bool reduceMotion;
  final bool animateIdle;
  @override
  State<SpiritArt> createState() => _SpiritArtState();
}

class _SpiritArtState extends State<SpiritArt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );
  Spirit? get spirit => widget.spirit;
  bool get locked => widget.locked;
  double get size => widget.size;
  String get reaction => widget.reaction;
  bool get reduceMotion => widget.reduceMotion;
  @override
  void initState() {
    super.initState();
    _configure();
  }

  @override
  void didUpdateWidget(covariant SpiritArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  void _configure() {
    if (widget.animateIdle && !reduceMotion) {
      if (!_idle.isAnimating) _idle.repeat();
    } else {
      _idle.stop();
      _idle.value = 0;
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: locked
        ? '???'
        : spirit?.text(
                'name',
                Localizations.localeOf(context).languageCode == 'ko',
              ) ??
              'RIQ',
    child: TweenAnimationBuilder<double>(
      key: ValueKey('${spirit?.id}-$reaction-$reduceMotion'),
      tween: Tween(begin: reduceMotion ? 0 : 1, end: 0),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 650),
      builder: (_, value, child) => Transform.translate(
        offset: Offset(
          0,
          -math.sin(value * math.pi * 2).abs() * (reaction == 'clear' ? 9 : 3),
        ),
        child: Transform.rotate(
          angle: reaction == 'blocked'
              ? math.sin(value * math.pi * 2) * .15
              : 0,
          child: child,
        ),
      ),
      child: AnimatedBuilder(
        animation: _idle,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, math.sin(_idle.value * math.pi * 2) * 2),
          child: child,
        ),
        child: SizedBox.square(dimension: size, child: _image(context)),
      ),
    ),
  );
  Widget _image(BuildContext context) {
    final assets = GameArtScope.maybeOf(context);
    if (assets == null) {
      return CustomPaint(
        painter: SpiritPainter(
          spirit: spirit,
          locked: locked,
          reaction: reaction,
        ),
      );
    }
    final ready = assets.spirit(spirit?.id);
    Widget image(ui.Image value) => RawImage(
      image: value,
      fit: BoxFit.contain,
      color: locked ? const Color(0xff868194) : null,
      colorBlendMode: locked ? BlendMode.srcIn : null,
      filterQuality: FilterQuality.medium,
    );
    if (ready != null) return image(ready);
    return FutureBuilder<ui.Image>(
      future: assets.loadSpirit(spirit?.id),
      builder: (context, snapshot) {
        if (snapshot.hasData) return image(snapshot.data!);
        if (snapshot.hasError) {
          return IconButton(
            tooltip: Localizations.localeOf(context).languageCode == 'ko'
                ? '이미지 다시 불러오기'
                : 'Retry image',
            onPressed: () => setState(() {}),
            icon: const Icon(Icons.refresh),
          );
        }
        return const Center(
          child: SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
        );
      },
    );
  }
}

class SpiritPainter extends CustomPainter {
  const SpiritPainter({
    this.spirit,
    this.locked = false,
    this.reaction = 'idle',
    this.image,
  });
  final ui.Image? image;
  final Spirit? spirit;
  final bool locked;
  final String reaction;
  static const palette = [
    Color(0xffffd775),
    Color(0xff8fd9ad),
    Color(0xffffb598),
    Color(0xff9bd8f5),
    Color(0xffbdabef),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    if (image != null) {
      paintArt(canvas, image!, Offset.zero & size, silhouette: locked);
      return;
    }
    canvas.save();
    final side = math.min(size.width, size.height);
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 100);
    final family = spirit?.chapter ?? 4;
    final variant = spirit?.variant ?? 0;
    final accent = locked ? const Color(0xff9c9bac) : palette[family];
    final ink = locked ? const Color(0xff9c9bac) : const Color(0xff45405d);
    final body = locked
        ? const Color(0xffb4b1c1)
        : spirit == null
        ? const Color(0xfffff5df)
        : Color.lerp(accent, Colors.white, .68)!;
    final p = Paint();
    void oval(Rect r, Color color) => canvas.drawOval(r, p..color = color);
    void line(Offset a, Offset b, Color color, double width) => canvas.drawLine(
      a,
      b,
      p
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
    void star(Offset center, double r, Color color, [int points = 5]) {
      final path = Path();
      for (var i = 0; i < points * 2; i++) {
        final a = -math.pi / 2 + i * math.pi / points;
        final rr = i.isEven ? r : r * .48;
        final x = center.dx + math.cos(a) * rr,
            y = center.dy + math.sin(a) * rr;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path..close(), p..color = color);
    }

    oval(const Rect.fromLTWH(22, 83, 57, 8), ink.withValues(alpha: .09));
    // 꼬리와 짧은 발은 몸 뒤에 그린다.
    final tail = Path()
      ..moveTo(68, 68)
      ..quadraticBezierTo(91, 83, 90, 56)
      ..quadraticBezierTo(76, 66, 66, 58)
      ..close();
    canvas.drawPath(tail, p..color = spirit == null ? palette[4] : accent);
    oval(const Rect.fromLTWH(30, 76, 14, 12), accent);
    oval(const Rect.fromLTWH(56, 76, 14, 12), accent);
    if (spirit == null) {
      oval(const Rect.fromLTWH(28, 23, 15, 25), body);
      oval(const Rect.fromLTWH(60, 23, 13, 25), body);
    } else {
      switch (family) {
        case 0:
          if (variant == 0) {
            star(const Offset(34, 26), 12, accent);
          }
          if (variant == 1) {
            oval(const Rect.fromLTWH(26, 17, 16, 25), accent);
            oval(const Rect.fromLTWH(33, 15, 14, 23), body);
          }
          if (variant == 2) {
            for (var i = 0; i < 3; i++) {
              star(Offset(35 + i * 15, 27 - (i == 1 ? 7 : 0)), 8, accent);
            }
          }
          if (variant == 3) {
            star(const Offset(31, 26), 9, accent);
            star(const Offset(69, 26), 9, accent);
          }
          if (variant == 4) {
            for (var i = 0; i < 5; i++) {
              star(Offset(20 + i * 15, 25 - (i - 2).abs() * -3), 7, accent);
            }
          }
        case 1:
          line(const Offset(50, 37), const Offset(50, 18), accent, 4);
          if (variant == 0 || variant == 3) {
            oval(const Rect.fromLTWH(30, 15, 20, 11), accent);
            oval(const Rect.fromLTWH(50, 10, 20, 13), accent);
          }
          if (variant == 1 || variant == 4) {
            for (var i = 0; i < (variant == 4 ? 6 : 4); i++) {
              final a = i * math.pi / 3;
              oval(
                Rect.fromCenter(
                  center: Offset(50 + 10 * math.cos(a), 22 + 7 * math.sin(a)),
                  width: 14,
                  height: 12,
                ),
                accent,
              );
            }
            canvas.drawCircle(const Offset(50, 22), 5, p..color = palette[0]);
          }
          if (variant == 2) {
            oval(const Rect.fromLTWH(34, 15, 32, 26), const Color(0xffc9a87b));
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                const Rect.fromLTWH(31, 15, 38, 10),
                const Radius.circular(5),
              ),
              p..color = accent,
            );
          }
          if (variant == 3) {
            oval(const Rect.fromLTWH(32, 6, 15, 11), accent);
            oval(const Rect.fromLTWH(52, 1, 16, 12), accent);
          }
        case 2:
          final ears = Path()
            ..moveTo(26, 41)
            ..lineTo(20, 15)
            ..lineTo(43, 29)
            ..lineTo(50, 41)
            ..moveTo(57, 30)
            ..lineTo(80, 15)
            ..lineTo(74, 44)
            ..close();
          canvas.drawPath(ears, p..color = accent);
          if (variant == 1 || variant == 4) {
            oval(const Rect.fromLTWH(34, 16, 17, 12), accent);
            oval(const Rect.fromLTWH(49, 16, 17, 12), accent);
            canvas.drawCircle(const Offset(50, 22), 4, p..color = palette[4]);
          }
          if (variant == 2) {
            line(const Offset(27, 24), const Offset(37, 33), ink, 1.5);
            line(const Offset(73, 24), const Offset(63, 33), ink, 1.5);
          }
          if (variant == 3) {
            canvas.drawRect(
              const Rect.fromLTWH(38, 15, 24, 16),
              p..color = accent,
            );
            star(const Offset(50, 23), 5, Colors.white);
          }
        case 3:
          for (var i = 0; i < 3 + variant; i++) {
            oval(Rect.fromLTWH(22 + i * 7.0, 22 - (i % 2) * 5, 24, 24), body);
          }
          if (variant == 1 || variant == 4) {
            oval(Rect.fromLTWH(9, 48, 23, variant == 4 ? 25 : 14), accent);
            oval(Rect.fromLTWH(68, 48, 23, variant == 4 ? 25 : 14), accent);
          }
          if (variant == 2) {
            for (var i = 0; i < 3; i++) {
              line(
                Offset(75, 58 + i * 5.0),
                Offset(91, 51 + i * 7.0),
                accent,
                4,
              );
            }
          }
          if (variant == 3) {
            oval(const Rect.fromLTWH(29, 12, 12, 25), accent);
            oval(const Rect.fromLTWH(59, 12, 12, 25), accent);
          }
        case 4:
          for (var i = 0; i < (variant == 2 ? 2 : 1); i++) {
            final x = variant == 2 ? 37 + i * 26.0 : 50.0;
            final crystal = Path()
              ..moveTo(x, 10 - (variant == 4 ? 7 : 0))
              ..lineTo(x + 9, 25)
              ..lineTo(x, 38)
              ..lineTo(x - 9, 25)
              ..close();
            canvas.drawPath(crystal, p..color = accent);
          }
          if (variant == 1) {
            canvas.drawOval(
              const Rect.fromLTWH(28, 12, 44, 13),
              p
                ..color = accent
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3,
            );
            p.style = PaintingStyle.fill;
          }
          if (variant == 3) {
            oval(const Rect.fromLTWH(27, 12, 17, 22), accent);
            oval(const Rect.fromLTWH(34, 9, 15, 20), body);
          }
          if (variant == 4) {
            star(const Offset(29, 24), 8, palette[0]);
            star(const Offset(71, 24), 8, palette[0]);
          }
      }
    }
    oval(const Rect.fromLTWH(21, 33, 58, 51), ink.withValues(alpha: .15));
    oval(const Rect.fromLTWH(22, 32, 56, 50), body);
    oval(const Rect.fromLTWH(16, 57, 14, 12), body);
    oval(const Rect.fromLTWH(70, 57, 14, 12), body);
    if (!locked) {
      oval(const Rect.fromLTWH(28, 58, 12, 6), accent.withValues(alpha: .6));
      oval(const Rect.fromLTWH(60, 58, 12, 6), accent.withValues(alpha: .6));
      for (final x in [38.0, 60.0]) {
        if (reaction == 'clear' || reaction == 'welcome') {
          line(Offset(x - 3, 53), Offset(x, 50), ink, 2.4);
          line(Offset(x, 50), Offset(x + 3, 53), ink, 2.4);
        } else {
          oval(
            Rect.fromLTWH(
              x -
                  2.5 +
                  (reaction == 'lookRight'
                      ? 2
                      : reaction == 'lookLeft'
                      ? -2
                      : 0),
              47,
              reaction == 'echo' ? 6 : 5,
              reaction == 'echo' ? 9 : 7,
            ),
            ink,
          );
        }
      }
      line(const Offset(47, 62), const Offset(50, 64), ink, 1.7);
      line(const Offset(50, 64), const Offset(53, 62), ink, 1.7);
      if (spirit == null) star(const Offset(69, 44), 6, palette[0]);
      if (spirit?.guardian == true) star(const Offset(50, 73), 5, accent);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SpiritPainter old) =>
      old.spirit != spirit || old.locked != locked || old.reaction != reaction;
}

/// 기존 클리어 타임라인 안에서 빛의 구체 → 실루엣 → 정령을 표시한다.
/// 보상 저장이나 게임 규칙을 실행하지 않으며, 건너뛰기는 즉시 최종 모습이다.
class SpiritAwakening extends StatelessWidget {
  const SpiritAwakening({
    super.key,
    required this.spirit,
    required this.progress,
    required this.reduceMotion,
  });
  final Spirit spirit;
  final double progress;
  final bool reduceMotion;
  @override
  Widget build(BuildContext context) {
    final phase = reduceMotion ? 1.0 : ((progress - .78) / .22).clamp(0.0, 1.0);
    final reveal = ((phase - .15) / .6).clamp(0.0, 1.0);
    return SizedBox.square(
      dimension: 120,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AwakeningLight(phase, spirit.guardian),
            ),
          ),
          Opacity(
            opacity: reveal,
            child: Transform.scale(
              scale: .3 + .7 * Curves.easeOut.transform(reveal),
              child: SpiritArt(
                spirit: spirit,
                size: 120,
                reaction: phase < .65 ? 'idle' : 'welcome',
                reduceMotion: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AwakeningLight extends CustomPainter {
  const _AwakeningLight(this.phase, this.guardian);
  final double phase;
  final bool guardian;
  @override
  void paint(Canvas canvas, Size size) {
    if (phase >= 1) return;
    final color = guardian
        ? SpiritPainter.palette[0]
        : SpiritPainter.palette[4];
    final center = size.center(Offset.zero);
    final paint = Paint()..color = color.withValues(alpha: (1 - phase) * .7);
    canvas.drawCircle(center, 12 + 22 * phase, paint);
    if (guardian) {
      canvas.drawCircle(
        center,
        20 + 38 * phase,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      paint.style = PaintingStyle.fill;
    }
    for (var i = 0; i < (guardian ? 12 : 6); i++) {
      final angle = i * math.pi * 2 / (guardian ? 12 : 6);
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * (18 + 36 * phase),
        2.5,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AwakeningLight old) =>
      old.phase != phase || old.guardian != guardian;
}
