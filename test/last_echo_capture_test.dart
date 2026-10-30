// 문서용 실제 위젯 캡처. 일반 테스트에서는 파일을 쓰지 않는다.
// flutter test test/last_echo_capture_test.dart --dart-define=CAPTURE_LAST_ECHO=true
import 'dart:io';
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
  testWidgets('capture Last Echo story, board and album screens', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('CAPTURE_LAST_ECHO')) return;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final family in ['Roboto', 'Ahem', 'NanumGothic']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
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
        defaultValue: 'docs/screenshots/last-echo',
      ),
    )..createSync(recursive: true);
    final key = GlobalKey();
    final board = find.byType(GameWidget<BloriqGame>);
    BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        for (final provider in <ImageProvider>[
          const ResizeImage(AssetImage(StarArt.forest), width: 1080),
          const ExactAssetImage(StarArt.boardFrame, scale: 4),
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
        final t = AppLocalizations.of(tester.element(find.byType(GameScreen)))!;
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
        for (var id = 2; id <= 5; id++) {
          await tapVisible(tester, find.text(t.next));
          await tester.ensureVisible(board);
          await tester.pump();
          if (id == 5) await capture('$prefix-stage5');
          for (final step in const PuzzleSolver().solve(
            game().controller.state.level,
          )!) {
            await move(step);
          }
          await tester.pump(const Duration(milliseconds: 400));
          await tester.ensureVisible(find.byKey(const ValueKey('skip-story')));
          await tester.pump();
          await capture('$prefix-discovery-$id');
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
        await capture('$prefix-album');
        await tapVisible(
          tester,
          find.byKey(const ValueKey('share-collection')),
        );
        expect(find.byType(EchoPostcardDialog), findsOneWidget);
        await capture('$prefix-share-collection');
        if (mode == ThemeMode.dark && locale == 'ko') {
          final data = tester
              .widget<EchoPostcardDialog>(find.byType(EchoPostcardDialog))
              .data;
          final png = await tester.runAsync(() => renderEchoPostcardPng(data));
          File('${directory.path}/collection-card.png').writeAsBytesSync(png!);
        }
        await tapVisible(tester, find.text(t.close));
        await tapVisible(tester, find.byKey(const ValueKey('spirit-s1-05')));
        await capture('$prefix-memory');
        await tapVisible(tester, find.byKey(const ValueKey('share-spirit')));
        expect(find.byType(EchoPostcardDialog), findsOneWidget);
        await capture('$prefix-share-discovery');
        if (mode == ThemeMode.dark && locale == 'ko') {
          final data = tester
              .widget<EchoPostcardDialog>(find.byType(EchoPostcardDialog))
              .data;
          final png = await tester.runAsync(() => renderEchoPostcardPng(data));
          File('${directory.path}/discovery-card.png').writeAsBytesSync(png!);
        }
        await tapVisible(tester, find.text(t.close).last);
        await tapVisible(tester, find.byKey(const ValueKey('equip-companion')));
        await tapVisible(tester, find.text(t.close).last);
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
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      }
    }
    await tester.runAsync(() => _compareBoards(directory));
  });
}

// 렌더링 결과를 나란히 배치한 검토 그림. 원본 화면/생산 에셋은 수정하지 않는다.
Future<void> _compareBoards(Directory directory) async {
  final paths = [
    'docs/screenshots/star-courier/dark-ko-play.png',
    '${directory.path}/dark-ko-echo.png',
  ];
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(const Color(0xff101a35), BlendMode.src);
  for (var i = 0; i < paths.length; i++) {
    final codec = await ui.instantiateImageCodec(
      File(paths[i]).readAsBytesSync(),
    );
    final image = (await codec.getNextFrame()).image;
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(24 + i * 417.0, 75, 393, 852),
      image: image,
      fit: BoxFit.contain,
    );
    final text = TextPainter(
      text: TextSpan(
        text: i == 0 ? '694ad9e · 이전 게임 화면' : 'THE LAST ECHO · 공통 보드 좌표',
        style: const TextStyle(
          fontFamily: 'NanumGothic',
          fontSize: 20,
          color: Color(0xfff2d795),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 393);
    text.paint(canvas, Offset(24 + i * 417.0, 26));
    text.dispose();
    image.dispose();
    codec.dispose();
  }
  final picture = recorder.endRecording();
  final output = await picture.toImage(858, 951);
  final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
  File('${directory.path}/board-comparison.png')
      .writeAsBytesSync(bytes!.buffer.asUint8List());
  output.dispose();
  picture.dispose();
}
