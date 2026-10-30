import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import '../game/block_art.dart';

/// 카드에는 게임 결과만 전달한다. 퍼즐 좌표나 이동 이력은 받지 않는다.
class EchoPostcardData {
  const EchoPostcardData({
    required this.levelId,
    required this.moves,
    required this.bestMoves,
    required this.stars,
    required this.levelText,
    required this.movesText,
    required this.bestText,
  }) : assert(levelId > 0),
       assert(moves >= 0),
       assert(bestMoves >= 0),
       assert(stars >= 1 && stars <= 3);

  final int levelId;
  final int moves;
  final int bestMoves;
  final int stars;
  final String levelText;
  final String movesText;
  final String bestText;
}

/// 동일한 결과에 동일한 이미지를 만든다. 실제 이동 좌표는 사용하지 않는다.
class EchoPostcardPainter extends CustomPainter {
  const EchoPostcardPainter(this.data, {this.colors = GameColors.light});

  final EchoPostcardData data;
  final GameColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1080, size.height / 1080);
    final bounds = const Rect.fromLTWH(0, 0, 1080, 1080);
    canvas.drawRect(bounds, Paint()..color = colors.background);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(45, 45, 990, 990),
        const Radius.circular(60),
      ),
      Paint()..color = colors.surface,
    );
    _text(
      canvas,
      'BLORIQ',
      const Offset(105, 100),
      54,
      colors.text,
      FontWeight.w900,
      3,
    );
    _text(
      canvas,
      data.levelText,
      const Offset(107, 175),
      34,
      colors.secondaryText,
      FontWeight.w600,
      0,
    );

    final art = const Rect.fromLTWH(105, 252, 870, 420);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(art, const Radius.circular(48)));
    canvas.drawRect(art, Paint()..color = colors.tileBottom);
    if (StarArt.forestImage case final image?) {
      paintImage(canvas: canvas, rect: art, image: image, fit: BoxFit.cover);
    }
    BlockArt.echo(canvas, const Offset(255, 470), 220, colors);
    BlockArt.block(canvas, const Offset(520, 470), 330, colors);
    BlockArt.exit(canvas, const Offset(790, 470), 230, colors);
    canvas.restore();

    for (var i = 0; i < 3; i++) {
      _star(
        canvas,
        Offset(133 + i * 65, 742),
        26,
        i < data.stars ? colors.reward : colors.outline.withValues(alpha: .3),
      );
    }
    _text(
      canvas,
      data.movesText,
      const Offset(105, 790),
      38,
      colors.text,
      FontWeight.w800,
      0,
    );
    _text(
      canvas,
      data.bestText,
      const Offset(105, 844),
      30,
      colors.secondaryText,
      FontWeight.w600,
      0,
    );
    _text(
      canvas,
      'Every Move Leaves an Echo.',
      const Offset(105, 934),
      29,
      colors.primaryInk,
      FontWeight.w700,
      0,
    );
    _text(
      canvas,
      'CORCOIDUM',
      const Offset(755, 941),
      21,
      colors.secondaryText,
      FontWeight.w800,
      2,
    );
    canvas.restore();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset offset,
    double fontSize,
    Color color,
    FontWeight weight,
    double spacing,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: GameTypography.canvasFontFamily,
          color: color,
          fontSize: fontSize,
          fontWeight: weight,
          letterSpacing: spacing,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 870);
    painter.paint(canvas, offset);
    painter.dispose();
  }

  void _star(Canvas canvas, Offset center, double radius, Color color) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + i * math.pi / 5;
      final r = i.isEven ? radius : radius * .45;
      final p = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant EchoPostcardPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.colors != colors;
}

/// 미리보기와 같은 painter를 사용해 정확히 1080×1080 PNG를 만든다.
Future<Uint8List> renderEchoPostcardPng(
  EchoPostcardData data, {
  GameColors colors = GameColors.light,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  EchoPostcardPainter(
    data,
    colors: colors,
  ).paint(canvas, const Size(1080, 1080));
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(1080, 1080);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode postcard');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

/// Android 시스템 공유 시트에 PNG만 전달한다.
Future<void> shareEchoPostcard(Uint8List png, {Rect? origin}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['bloriq-echo-postcard.png'],
      sharePositionOrigin: origin,
    ),
  );
}

class EchoPostcardDialog extends StatefulWidget {
  const EchoPostcardDialog({
    super.key,
    required this.data,
    required this.title,
    required this.shareLabel,
    required this.closeLabel,
    required this.errorLabel,
    this.share = shareEchoPostcard,
    this.onShareTap,
  });

  final EchoPostcardData data;
  final VoidCallback? onShareTap;
  final String title;
  final String shareLabel;
  final String closeLabel;
  final String errorLabel;
  final Future<void> Function(Uint8List png, {Rect? origin}) share;

  @override
  State<EchoPostcardDialog> createState() => _EchoPostcardDialogState();
}

class _EchoPostcardDialogState extends State<EchoPostcardDialog> {
  bool _sharing = false;
  bool _failed = false;

  Future<void> _share() async {
    if (_sharing) return;
    widget.onShareTap?.call();
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      _sharing = true;
      _failed = false;
    });
    try {
      final png = await renderEchoPostcardPng(
        widget.data,
        colors: GameTheme.colorsOf(context),
      );
      await widget.share(png, origin: origin);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.auto_awesome_outlined),
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            image: true,
            label:
                '${widget.data.levelText}, ${widget.data.movesText}, '
                '${widget.data.bestText}, ${widget.data.stars}/3',
            child: AspectRatio(
              aspectRatio: 1,
              child: CustomPaint(
                painter: EchoPostcardPainter(
                  widget.data,
                  colors: GameTheme.colorsOf(context),
                ),
              ),
            ),
          ),
          if (_failed)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                widget.errorLabel,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(widget.closeLabel),
      ),
      FilledButton.icon(
        onPressed: _sharing ? null : _share,
        icon: _sharing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.ios_share),
        label: Text(widget.shareLabel),
      ),
    ],
  );
}
