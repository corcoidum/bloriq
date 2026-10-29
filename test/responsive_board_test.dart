import 'package:bloriq/art/game_art_assets.dart';

import 'support/art_test_assets.dart';

import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/companions/season.dart';
import 'package:bloriq/companions/spirit_art.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(prepareMoonlitArt);
  setUp(() => rootBundle.clear());
  const moonlit = bool.fromEnvironment('CAPTURE_MOONLIT');
  const capture = bool.fromEnvironment('CAPTURE_V51') || moonlit;
  const folder = moonlit
      ? 'docs/screenshots/moonlit/matrix'
      : 'docs/screenshots/v51';
  Future<void> fonts() async {
    if (!capture) return;
    final file = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    for (final name in ['Roboto', 'Ahem']) {
      await (FontLoader(name)..addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())),
          ))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader('CormorantGaramond')..addFont(
          rootBundle.load('assets/art/moonlit/fonts/CormorantGaramond.ttf'),
        ))
        .load();
    Directory(folder).createSync(recursive: true);
  }

  Future<void> save(WidgetTester tester, GlobalKey key, String name) async {
    if (!capture) return;
    await tester.pump();
    await tester.runAsync(() async {
      final render =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await render.toImage();
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$folder/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final screen in [
      const Size(320, 568),
      const Size(360, 800),
      const Size(393, 852),
      const Size(412, 915),
      const Size(600, 960),
    ]) {
      testWidgets('$mode $screen stages 1/6/14/25 align and hit same cells', (
        tester,
      ) async {
        await fonts();
        tester.view.physicalSize = screen;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({
          GameAudio.musicKey: false,
          GameAudio.effectsKey: false,
        });
        final settings = await GameSettings.load();
        await settings.setThemeMode(mode);
        await settings.setReduceMotion(true);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: BloriqApp(settings: settings),
          ),
        );
        final board = find.byType(GameWidget<BloriqGame>);
        for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 100));
        for (final id in [1, 6, 14, 25]) {
          if (id != 1) {
            await tester.ensureVisible(find.text('Levels'));
            await tester.pump();
            await tester.tap(find.text('Levels'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.scrollUntilVisible(
              find.text('Level $id').last,
              160,
              scrollable: find.byType(Scrollable).last,
            );
            await tester.ensureVisible(find.text('Level $id').last);
            await tester.tap(find.text('Level $id').last);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
          await tester.ensureVisible(board);
          await tester.pump();
          final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
          final rect = tester.getRect(board), g = game.geometry;
          expect(g.boardSize.width, closeTo(rect.width, .001));
          expect(g.boardSize.height, closeTo(rect.height, .001));
          for (final b in game.controller.state.blocks) {
            expect(g.cellAt(g.center(b.position)), b.position);
          }
          // 대표 셀을 실제 Flutter GestureDetector로 눌러 Flame의 드래그 선택과 비교한다.
          final block = game.controller.state.blocks.first;
          final gesture = await tester.startGesture(
            rect.topLeft + g.center(block.position),
          );
          await gesture.moveBy(Offset(g.cellSize * .6, 0));
          await tester.pump();
          expect(game.currentPreview?.from, block.position);
          await gesture.cancel();
          await tester.pump();
          expect(game.controller.state.moves, 0);
          expect(tester.takeException(), isNull);
          if (capture) {
            await tester.runAsync(
              () => GameArtAssets.shared.prepareChapter((id - 1) ~/ 5),
            );
            await tester.pump();
          }
          await save(
            tester,
            key,
            '${mode.name}-${screen.width.toInt()}-stage-$id',
          );
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        settings.dispose();
      });
    }
  }
  testWidgets('character design sheet: Riq and 25 spirits', (tester) async {
    if (!capture) return;
    await fonts();
    tester.view.physicalSize = const Size(1080, 1380);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final season = await Season.load(), key = GlobalKey();
    await tester.runAsync(
      () =>
          GameArtAssets.shared.prepareSpirits(season.spirits.map((s) => s.id)),
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: GameArtScope(
          assets: GameArtAssets.shared,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: const Color(0xfffff9ed),
              body: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    const Text(
                      'BLORIQ · BLORIA / SEASON 1',
                      style: TextStyle(fontSize: 32),
                    ),
                    const SpiritArt(size: 120, reduceMotion: true),
                    const Text('RIQ · 리크', style: TextStyle(fontSize: 20)),
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 5,
                        childAspectRatio: .85,
                        children: season.spirits
                            .map(
                              (s) => Column(
                                children: [
                                  SpiritArt(
                                    spirit: s,
                                    size: 120,
                                    reduceMotion: true,
                                  ),
                                  Text(
                                    '${s.stage}. ${s.text('name', true)} / ${s.text('name', false)}',
                                    style: const TextStyle(fontSize: 18),
                                  ),
                                  Text(s.guardian ? 'GUARDIAN' : s.family),
                                ],
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await save(tester, key, 'character-sheet');
    await tester.pumpWidget(const SizedBox());
  });
}
