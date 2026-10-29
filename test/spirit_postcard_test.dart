import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bloriq/companions/season.dart';
import 'package:bloriq/companions/spirit_postcard.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('discovery, guardian, collection and actual puzzle cards export in both sizes', () async {
    final season = await Season.load();
    final levels = jsonDecode(
      await rootBundle.loadString('assets/levels/levels.json'),
    ) as List;
    final level = Level.fromJson(levels[13] as Map<String, dynamic>);
    final source = PuzzleState.initial(level);
    for (final h in [1080, 1920]) {
      final variants = [
        SpiritCardPainter(
          spirits: [season.forStage(1)],
          heading: 'Lumi',
          subtitle: 'Crescent Garden',
          colors: GameColors.light,
        ),
        SpiritCardPainter(
          spirits: [season.forStage(5)],
          heading: 'Astel',
          subtitle: 'Guardian',
          colors: GameColors.dark,
        ),
        SpiritCardPainter(
          spirits: season.spirits,
          heading: '25 / 25',
          subtitle: 'Collection',
          colors: GameColors.light,
        ),
        SpiritCardPainter(
          spirits: const [],
          heading: 'Can you reach the star?',
          subtitle: 'Level 14',
          colors: GameColors.dark,
          level: level,
        ),
      ];
      final images = <Uint8List>[];
      for (final painter in variants) {
        final recorder = ui.PictureRecorder();
        painter.paint(ui.Canvas(recorder), ui.Size(1080, h.toDouble()));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1080, h);
        try {
          expect(image.width, 1080);
          expect(image.height, h);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List();
          expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
          images.add(bytes);
        } finally {
          image.dispose();
          picture.dispose();
        }
      }
      expect(images[0], isNot(orderedEquals(images[1])));
      expect(images[2], isNot(orderedEquals(images[3])));
    }
    expect(
      PuzzleState.initial(level).blocks.map((b) => b.position),
      source.blocks.map((b) => b.position),
    );
    expect(source.moves, 0);
    expect(source.echo, isNull);
  });
}
