// 문서용 실제 위젯 캡처. 일반 테스트에서는 파일을 쓰지 않는다.
// flutter test test/last_echo_capture_test.dart --dart-define=CAPTURE_SEASON1=true
import 'dart:io';
import 'dart:convert';

import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:bloriq/story/companion_view.dart';

import 'dart:ui' as ui;

import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/postcard/echo_postcard.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  testWidgets(
    'capture moonstone Season 1 boards, all friends, endings and cards',
    (tester) async {
      if (!const bool.fromEnvironment('CAPTURE_SEASON1')) return;
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final family in ['Roboto', 'Ahem', 'NanumGothic']) {
        await (FontLoader(
              family,
            )..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
            .load();
      }
      await (FontLoader(
        'Jua',
      )..addFont(rootBundle.load('assets/fonts/Jua-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      await tester.runAsync(StarArt.load);
      final directory = Directory(
        const String.fromEnvironment(
          'CAPTURE_DIRECTORY',
          defaultValue: 'build/moonstone-captures',
        ),
      )..createSync(recursive: true);
      final key = GlobalKey();
      final catalog = StoryCatalog.fromJson(
        jsonDecode(File('assets/story/season1.json').readAsStringSync()),
      );
      final board = find.byType(GameWidget<BloriqGame>);
      BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;
      Future<void> capture(String name) async {
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          for (final provider in <ImageProvider>[
            const ResizeImage(AssetImage(StarArt.forest), width: 1080),
            const ExactAssetImage(StarArt.boardFrame, scale: 4),
            for (final friend in catalog.released)
              ResizeImage(AssetImage(friend.asset!), width: 384),
            for (final asset in [
              StarArt.riq,
              StarArt.riqHappy,
              StarArt.riqThinking,
              StarArt.riqSurprised,
              StarArt.courier,
              'assets/art/last_echo/pomi.png',
              'assets/art/last_echo/doto.png',
              'assets/art/last_echo/lulu.png',
              'assets/art/last_echo/lunabel.png',
            ]) ...[
              ResizeImage(AssetImage(asset), width: 384),
              ResizeImage(AssetImage(asset), width: 192),
            ],
          ]) {
            await precacheImage(provider, context);
          }
        });
        await tester.pump();
        expect(tester.takeException(), isNull, reason: name);
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('${directory.path}/$name.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> move(PuzzleMove move) async {
        await tester.ensureVisible(board);
        await tester.pump();
        final layout = game().geometry;
        final block = game().controller.state.blocks.firstWhere(
          (b) => b.id == move.blockId,
        );
        await tester.dragFrom(
          tester.getTopLeft(board) + layout.center(block.position),
          Offset(
                (move.target.x - block.position.x).toDouble(),
                (move.target.y - block.position.y).toDouble(),
              ) *
              layout.cellSize *
              .7,
        );
        await tester.pump(const Duration(milliseconds: 80));
      }

      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        for (final locale in ['ko', 'en']) {
          rootBundle.clear();
          SharedPreferences.setMockInitialValues({
            'bloriq.audio.music': false,
            'bloriq.audio.effects': false,
          });
          tester.platformDispatcher.localesTestValue = [Locale(locale)];
          final settings = GameSettings(themeMode: mode);
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: BloriqApp(
                settings: settings,
                clock: () => DateTime(2026, 10, 30),
              ),
            ),
          );
          for (var i = 0; i < 150 && board.evaluate().isEmpty; i++) {
            await tester.pump(const Duration(milliseconds: 20));
          }
          await tester.pump(const Duration(milliseconds: 350));
          final t = AppLocalizations.of(
            tester.element(find.byType(GameScreen)),
          )!;
          final prefix = '${mode.name}-$locale';
          await capture('$prefix-tutorial');
          final solution = const PuzzleSolver().solve(
            game().controller.state.level,
          )!;
          await move(solution.first);
          await tester.pump(const Duration(milliseconds: 250));
          await capture('$prefix-echo');
          await move(PuzzleMove(solution.first.blockId, const Position(0, 1)));
          await tester.pump(const Duration(milliseconds: 250));
          await capture('$prefix-blocked');
          await move(solution.last);
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.byKey(const ValueKey('skip-story')));
          await tester.pump();
          await capture('$prefix-discovery-mori');
          await tester.pump(const Duration(milliseconds: 1500));
          for (var id = 2; id <= 25; id++) {
            await tapVisible(tester, find.text(t.next));
            await tester.ensureVisible(board);
            await tester.pump();
            if ([2, 3, 4, 5, 9, 14, 25].contains(id)) {
              await capture('$prefix-stage$id');
              if (mode == ThemeMode.dark && locale == 'ko') {
                await tester.runAsync(() async {
                  final render = tester.renderObject<RenderRepaintBoundary>(
                    find.byType(StarBoardFrame),
                  );
                  final image = await render.toImage(pixelRatio: 2);
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  File('${directory.path}/board-$id.png')
                      .writeAsBytesSync(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
            for (final step in const PuzzleSolver().solve(
              game().controller.state.level,
            )!) {
              await move(step);
            }
            await tester.pump(const Duration(milliseconds: 400));
            await tester.ensureVisible(
              find.byKey(const ValueKey('skip-story')),
            );
            await tester.pump();
            if (id % 5 == 0 || mode == ThemeMode.dark && locale == 'ko') {
              await capture('$prefix-discovery-$id');
            }
            await tester.pump(const Duration(milliseconds: 2300));
          }
          final session = tester
              .widget<GameScreen>(find.byType(GameScreen))
              .session;
          await tester.runAsync(() async {
            for (final friend in session.collection.owned) {
              await StarArt.loadPortrait(friend.asset!);
            }
          });
          await tapVisible(tester, find.byKey(const ValueKey('result-album')));
          for (var number = 1; number <= 5; number++) {
            if (number > 1) {
              await tapVisible(
                tester,
                find.byKey(ValueKey('album-chapter-${number - 1}')),
              );
              await tapVisible(
                tester,
                find.byKey(ValueKey('album-chapter-$number')),
              );
            }
            await capture('$prefix-album-$number');
            await tapVisible(
              tester,
              find.byKey(
                ValueKey(
                  number == 1 ? 'share-collection' : 'share-chapter-$number',
                ),
              ),
            );
            final shared = tester
                .widget<EchoPostcardDialog>(find.byType(EchoPostcardDialog))
                .data;
            expect(
              shared.story!.detail,
              catalog.chapter(number).name.inLocale(locale),
            );
            expect(shared.story!.portraitAssets.length, 5);
            await capture('$prefix-share-chapter-$number');
            if (mode == ThemeMode.dark && locale == 'ko') {
              final png = await tester.runAsync(
                () => renderEchoPostcardPng(shared),
              );
              File('${directory.path}/chapter-$number-card.png')
                  .writeAsBytesSync(png!);
            }
            await tapVisible(tester, find.text(t.close));
            await tapVisible(
              tester,
              find.byKey(
                ValueKey(
                  'spirit-s1-${(number * 5).toString().padLeft(2, '0')}',
                ),
              ),
            );
            await capture('$prefix-guardian-$number');
            await tapVisible(
              tester,
              find.byKey(const ValueKey('share-spirit')),
            );
            await capture('$prefix-share-guardian-$number');
            if (mode == ThemeMode.dark && locale == 'ko') {
              final data = tester
                  .widget<EchoPostcardDialog>(find.byType(EchoPostcardDialog))
                  .data;
              final png = await tester.runAsync(
                () => renderEchoPostcardPng(data),
              );
              File('${directory.path}/guardian-$number-card.png')
                  .writeAsBytesSync(png!);
            }
            await tapVisible(tester, find.text(t.close).last);
            await tapVisible(
              tester,
              find.byKey(const ValueKey('equip-companion')),
            );
            await tapVisible(tester, find.text(t.close).last);
          }
          await tapVisible(tester, find.byTooltip(t.close));
          await tapVisible(tester, find.byKey(const ValueKey('game-home')));
          await tester.pump(const Duration(milliseconds: 400));
          await capture('$prefix-home');
          await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
          await capture('$prefix-map');
          await tapVisible(tester, find.text(t.close));
          await tester.ensureVisible(find.byKey(const ValueKey('daily-play')));
          await tester.pump();
          await capture('$prefix-daily');
          await tester.pumpWidget(
            RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: mode == ThemeMode.dark
                    ? GameTheme.dark
                    : GameTheme.light,
                home: Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'SEASON 1 · 25 FRIENDS · 48px',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 6,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                for (final friend in catalog.released)
                                  SizedBox(
                                    width: 66,
                                    child: Column(
                                      children: [
                                        SpiritPortrait(
                                          spirit: friend,
                                          size: 48,
                                        ),
                                        Text(
                                          friend.name.inLocale(locale),
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await capture('$prefix-portraits-48');
          await tester.pumpWidget(const SizedBox());
          settings.dispose();
        }
      }
      await tester.runAsync(() => _compareBoards(directory));
    },
  );
}

// 사용자 제공 전/후 보드를 종횡비를 유지해 나란히 배치한다.
Future<void> _compareBoards(Directory directory) async {
  for (final id in [2, 3, 4, 5, 9]) {
    final paths = [
      'docs/screenshots/moonstone-season1/before/level-$id.png',
      '${directory.path}/board-$id.png',
    ];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(const Color(0xff101a35), BlendMode.src);
    for (var i = 0; i < paths.length; i++) {
      final codec = await ui.instantiateImageCodec(
        File(paths[i]).readAsBytesSync(),
      );
      final image = (await codec.getNextFrame()).image;
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(20 + i * 510.0, 70, 490, 490),
        image: image,
        fit: BoxFit.contain,
      );
      final text = TextPainter(
        text: TextSpan(
          text: i == 0 ? '첨부 화면 · 별문 $id' : '달빛 석판 · 별문 $id',
          style: const TextStyle(
            fontFamily: 'NanumGothic',
            fontSize: 22,
            color: Color(0xfff2d795),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 490);
      text.paint(canvas, Offset(20 + i * 510.0, 24));
      text.dispose();
      image.dispose();
      codec.dispose();
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(1040, 580);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('${directory.path}/compare-level-$id.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
    picture.dispose();
  }
}
