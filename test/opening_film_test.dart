import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/art/game_art_assets.dart';
import 'package:bloriq/intro/opening_film.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await GameArtAssets.shared.loadCore();
    await GameArtAssets.shared.prepareChapter(0);
    final brand = FontLoader('CormorantGaramond')
      ..addFont(
        rootBundle.load('assets/art/moonlit/fonts/CormorantGaramond.ttf'),
      );
    await brand.load();
    if (Platform.isMacOS) {
      final korean = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf')
                  .readAsBytes(),
            ),
          ),
        );
      await korean.load();
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opening gates gameplay, skip immediately enters without saves', (
    tester,
  ) async {
    final settings = GameSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: OpeningGate(
          enabled: true,
          assets: GameArtAssets.shared,
          settings: settings,
          child: const Scaffold(body: Text('puzzle')),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    });
    await tester.pump();
    expect(find.text('puzzle'), findsNothing);
    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(find.text('puzzle'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    settings.dispose();
  });

  testWidgets(
    'reduced motion shows final tableau and directly begins adventure',
    (tester) async {
      final settings = GameSettings(reduceMotion: true);
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: OpeningFilm(
            assets: GameArtAssets.shared,
            settings: settings,
            onDone: () => done = true,
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
      expect(find.text('Watch the story'), findsNothing);
      expect(find.text('Begin adventure'), findsOneWidget);
      await tester.tap(find.text('Begin adventure'));
      expect(done, isTrue);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  testWidgets(
    'silent playback completes in twelve seconds and supports lifecycle pause',
    (tester) async {
      SharedPreferences.setMockInitialValues({'bloriq.audio.music': false});
      final settings = GameSettings();
      await tester.pumpWidget(
        MaterialApp(
          home: OpeningFilm(
            assets: GameArtAssets.shared,
            settings: settings,
            onDone: () {},
          ),
        ),
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pump();
      await tester.tap(find.text('Watch the story'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('Begin adventure'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(seconds: 8));
      expect(find.text('Begin adventure'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      settings.dispose();
    },
  );

  test(
    'export actual opening painter to H264 MP4 and preview frames',
    () async {
      if (!const bool.fromEnvironment('EXPORT_OPENING')) return;
      const ffmpeg = String.fromEnvironment('FFMPEG');
      expect(ffmpeg, isNotEmpty);
      final out = Directory('docs/screenshots/opening')
        ..createSync(recursive: true);
      final encode = await Process.start(ffmpeg, [
        '-y',
        '-f',
        'rawvideo',
        '-pix_fmt',
        'rgba',
        '-s',
        '720x1280',
        '-r',
        '24',
        '-i',
        'pipe:0',
        '-i',
        'assets/audio/opening.wav',
        '-c:v',
        'libx264',
        '-preset',
        'fast',
        '-crf',
        '21',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-movflags',
        '+faststart',
        '-t',
        '12',
        'assets/video/bloriq-opening.mp4',
      ]);
      final errors = <int>[];
      final errorDone = encode.stderr.forEach(errors.addAll);
      final stdoutDone = encode.stdout.drain<void>();
      for (var frame = 0; frame < 288; frame++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        OpeningFilmPainter(
          assets: GameArtAssets.shared,
          seconds: frame / 24,
        ).paint(canvas, const Size(720, 1280));
        final picture = recorder.endRecording();
        final image = await picture.toImage(720, 1280);
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        encode.stdin.add(
          rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        );
        await encode.stdin.flush();
        if ([24, 132, 216, 287].contains(frame)) {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          await File('${out.path}/frame-$frame.png').writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
        }
        image.dispose();
        picture.dispose();
      }
      await encode.stdin.close();
      final code = await encode.exitCode;
      await Future.wait([errorDone, stdoutDone]);
      expect(code, 0, reason: String.fromCharCodes(errors));
      expect(
        File('assets/video/bloriq-opening.mp4').lengthSync(),
        greaterThan(100000),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
