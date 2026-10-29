import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import '../domain/puzzle.dart';
import '../game/bloriq_game.dart';

import '../design/game_theme.dart';
import '../art/game_art_assets.dart';
import '../l10n/app_localizations.dart';
import '../postcard/echo_postcard.dart';
import 'season.dart';
import 'spirit_art.dart';

/// 기존 Echo Postcard의 PNG 공유 경로를 재사용한다.
class SpiritCardPainter extends CustomPainter {
  const SpiritCardPainter({
    required this.spirits,
    required this.heading,
    required this.subtitle,
    required this.colors,
    this.level,
    this.artAssets,
  });
  final List<Spirit> spirits;
  final String heading;
  final String subtitle;
  final GameColors colors;
  final Level? level;
  final GameArtAssets? artAssets;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1080);
    final logicalHeight = size.height / size.width * 1080;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 1080, logicalHeight),
      Paint()..color = colors.background,
    );
    canvas.translate(0, (logicalHeight - 1080) / 2);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1080, 1080),
      Paint()..color = colors.background,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 42, 996, 996),
        const Radius.circular(64),
      ),
      Paint()..color = colors.surface,
    );
    final paper = artAssets?.tile('empty');
    if (paper != null) {
      paintStoneSurface(
        canvas,
        paper,
        const Rect.fromLTWH(45, 45, 990, 990),
        dark: colors == GameColors.dark,
      );
    }
    final frame = artAssets?.tile('frame');
    if (frame != null) {
      paintArt(canvas, frame, const Rect.fromLTWH(45, 45, 990, 990));
    }
    void text(String text, double y, double fontSize, Color color) {
      final p = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: GameTypography.canvasFontFamily,
            fontSize: fontSize,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: 870);
      p.paint(canvas, Offset(105, y));
      p.dispose();
    }

    text('BLORIQ', 100, 52, colors.text);
    text(heading, 190, 40, colors.text);
    text(subtitle, 260, 27, colors.secondaryText);
    if (level != null) {
      // 도전 카드는 실제 초기 보드를 사용한다. 경로와 정답은 포함하지 않는다.
      final game = BloriqGame(PuzzleController(level!), artAssets: artAssets)
        ..onGameResize(Vector2(590, 590))
        ..configureAppearance(colors: colors, reduceMotion: true);
      canvas.save();
      canvas.translate(245, 325);
      game.render(canvas);
      canvas.restore();
    } else if (spirits.length == 1) {
      canvas.save();
      canvas.translate(300, 335);
      SpiritPainter(
        spirit: spirits.single,
        image: artAssets?.spirit(spirits.single.id),
        reaction: 'welcome',
      ).paint(canvas, const Size(480, 480));
      canvas.restore();
    } else {
      for (var i = 0; i < spirits.length; i++) {
        canvas.save();
        canvas.translate(105 + (i % 5) * 174, 340 + (i ~/ 5) * 105);
        SpiritPainter(
          spirit: spirits[i],
          image: artAssets?.spirit(spirits[i].id),
        ).paint(canvas, const Size(120, 105));
        canvas.restore();
      }
    }
    text('Every Move Leaves an Echo.', 935, 30, colors.primaryInk);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SpiritCardPainter old) =>
      old.spirits != spirits ||
      old.colors != colors ||
      old.heading != heading ||
      old.subtitle != subtitle ||
      old.level != level ||
      old.artAssets != artAssets;
}

Future<void> showSpiritPostcard(
  BuildContext context, {
  required List<Spirit> spirits,
  required String heading,
  required String subtitle,
  required bool reduceMotion,
  Level? level,
}) async {
  final t = AppLocalizations.of(context)!;
  final assets = GameArtScope.maybeOf(context);
  try {
    await assets?.prepareSpirits(spirits.map((s) => s.id));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.artLoadError)));
    }
    return;
  }
  if (!context.mounted) return;
  var portrait = false;
  var sharing = false;
  var failed = false;
  await showDialog<void>(
    context: context,
    animationStyle: reduceMotion ? AnimationStyle.noAnimation : null,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final painter = SpiritCardPainter(
          spirits: spirits,
          heading: heading,
          subtitle: subtitle,
          colors: GameTheme.colorsOf(context),
          level: level,
          artAssets: assets,
        );
        return AlertDialog(
          title: Text(t.postcard),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: portrait ? 1080 / 1920 : 1,
                  child: CustomPaint(painter: painter),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.portraitCard),
                  value: portrait,
                  onChanged: sharing
                      ? null
                      : (value) => setState(() => portrait = value),
                ),
                if (failed) Text(t.shareError),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.close),
            ),
            FilledButton(
              onPressed: sharing
                  ? null
                  : () async {
                      final box = context.findRenderObject() as RenderBox?;
                      final origin = box == null
                          ? null
                          : box.localToGlobal(Offset.zero) & box.size;
                      setState(() {
                        sharing = true;
                        failed = false;
                      });
                      try {
                        final recorder = ui.PictureRecorder();
                        painter.paint(
                          Canvas(recorder),
                          Size(1080, portrait ? 1920 : 1080),
                        );
                        final picture = recorder.endRecording();
                        try {
                          final image = await picture.toImage(
                            1080,
                            portrait ? 1920 : 1080,
                          );
                          try {
                            final data = await image.toByteData(
                              format: ui.ImageByteFormat.png,
                            );
                            if (data == null) {
                              throw StateError('PNG encoding failed');
                            }
                            await shareEchoPostcard(
                              data.buffer.asUint8List(
                                data.offsetInBytes,
                                data.lengthInBytes,
                              ),
                              origin: origin,
                            );
                          } finally {
                            image.dispose();
                          }
                        } finally {
                          picture.dispose();
                        }
                      } catch (_) {
                        if (context.mounted) setState(() => failed = true);
                      } finally {
                        if (context.mounted) setState(() => sharing = false);
                      }
                    },
              child: Text(t.shareImage),
            ),
          ],
        );
      },
    ),
  );
}
