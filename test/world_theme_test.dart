import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/arcade_components.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:bloriq/world/saga.dart';
import 'package:bloriq/world/world_map.dart';
import 'package:bloriq/world/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  test('saga accepts an optional theme and validates palette colors', () {
    final saga = Saga.parse(File(Saga.asset).readAsStringSync());
    expect(saga.world(1).theme, isNull);
    final theme = saga.world(2).theme!;
    expect(theme.palette!.board, const Color(0xff95c5e5));
    expect(theme.palette!.border, const Color(0xffe8f5ff));
    expect(theme.floor, 'assets/art/world2/board/floor_1.png');
    expect(theme.rock, 'assets/art/world2/board/rock_1.png');
    expect(theme.bgm, 'assets/audio/bgm_w2.wav');
    expect(
      () => WorldTheme.parse({
        'palette': {
          'background': '#263B58',
          'board': 'invalid',
          'border': '#E8F5FF',
          'accent': '#B7F2FA',
        },
      }),
      throwsFormatException,
    );
  });

  testWidgets('optional floor and rock assets decode for the board', (
    tester,
  ) async {
    final skin = await tester.runAsync(
      () => WorldTheme.fromJson({
        'floor': 'assets/art/moon_garden/floor_1.png',
        'rock': 'assets/art/moon_garden/rock.png',
      }).loadBoardSkin(),
    );
    expect(skin!.palette, isNull);
    expect(skin.floor?.width, greaterThan(0));
    expect(skin.rock?.width, greaterThan(0));
    skin.dispose();
  });

  testWidgets('cloud-sea colors apply only to the world 2 play screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.localesTestValue = [const Locale('ko')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues({
      'bloriq.onboarding.v1': 'skipped',
      GameAudio.musicKey: false,
      GameAudio.effectsKey: false,
      ProgressionRepository.storageKey: jsonEncode({
        'version': 1,
        'backfilled': true,
        'completedChapters': [1, 2, 3, 4, 5],
      }),
    });
    const capture = bool.fromEnvironment('CAPTURE_WORLD_THEME');
    if (capture) await tester.runAsync(_loadCaptureArt);
    final settings = GameSettings(reduceMotion: true);
    addTearDown(settings.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: BloriqApp(settings: settings, firstRunIntro: false),
      ),
    );
    await waitForHome(tester);
    final backdrop = find.byType(ArcadeBackdrop);
    expect(tester.widget<ArcadeBackdrop>(backdrop).background, isNull);

    await openHomeJourney(tester);
    await tapVisible(tester, find.byKey(const ValueKey('journey-world-2')));
    final mapScaffold = find.descendant(
      of: find.byType(WorldMap),
      matching: find.byType(Scaffold),
    );
    expect(
      tester.widget<Scaffold>(mapScaffold).backgroundColor,
      GameColors.dark.background,
    );

    await tapVisible(tester, find.byKey(const ValueKey('world-continue')));
    final playBackdrop = find.descendant(
      of: find.byType(GameScreen),
      matching: backdrop,
    );
    final frame = tester.widget<StarBoardFrame>(find.byType(StarBoardFrame));
    expect(frame.skin?.palette?.board, const Color(0xff95c5e5));
    expect(
      tester.widget<ArcadeBackdrop>(playBackdrop).background,
      const Color(0xff263b58),
    );
    expect(tester.takeException(), isNull);
    if (capture) await tester.runAsync(() => _capture(boundary));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

Future<void> _loadCaptureArt() async {
  for (final (family, file) in [
    ('Roboto', 'NanumGothic-Regular.ttf'),
    ('NanumGothic', 'NanumGothic-Regular.ttf'),
    ('Jua', 'Jua-Regular.ttf'),
    ('GamjaFlower', 'GamjaFlower-Subset.ttf'),
    ('GowunDodum', 'GowunDodum-Regular.ttf'),
  ]) {
    await (FontLoader(
      family,
    )..addFont(rootBundle.load('assets/fonts/$file'))).load();
  }
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  await StarArt.load();
}

Future<void> _capture(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  try {
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('docs/screenshots/foundation')
      ..createSync(recursive: true);
    File('${dir.path}/world2-cloud-sea.png')
        .writeAsBytesSync(bytes.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
