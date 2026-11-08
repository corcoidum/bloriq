// 문서용 화면: flutter test test/visual_capture_test.dart --dart-define=CAPTURE_DESIGN=true
// 일반 테스트 실행에서는 캡처와 파일 쓰기를 수행하지 않는다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/domain/puzzle.dart';
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
  testWidgets('capture design screens', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 플랫폼 기본 글꼴은 테스트에서 Ahem으로 대체된다. 캡처만 실제 글꼴을 쓴다.
    const fontPath = String.fromEnvironment(
      'DESIGN_FONT',
      defaultValue: '/System/Library/Fonts/Supplemental/Arial Unicode.ttf',
    );
    final font = File(fontPath);
    if (!font.existsSync()) {
      fail(
        'Provide a Unicode TTF with --dart-define=DESIGN_FONT=/absolute/font.ttf',
      );
    }
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
      await loader.load();
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    Directory('docs/screenshots').createSync(recursive: true);
    final board = find.byType(GameWidget<BloriqGame>);
    BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;
    final boundary = GlobalKey();

    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('docs/screenshots/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pump();
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> select(int id) async {
      await tap(find.text('Levels'));
      await tap(find.text('Level $id').last);
    }

    Future<void> step(PuzzleMove move) async {
      await tester.ensureVisible(board);
      await tester.pump();
      final state = game().controller.state;
      final block = state.blocks.firstWhere(
        (block) => block.id == move.blockId,
      );
      final rect = tester.getRect(board);
      final cell = rect.width / state.level.boardWidth;
      await tester.dragFrom(
        rect.topLeft +
            Offset(
              (block.position.x + .5) * cell,
              (block.position.y + .5) * cell,
            ),
        Offset(
          (move.target.x - block.position.x) * cell,
          (move.target.y - block.position.y) * cell,
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    Future<void> solve() async {
      for (final move in const PuzzleSolver().solve(
        game().controller.state.level,
      )!) {
        await step(move);
      }
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      SharedPreferences.setMockInitialValues({
        GameAudio.musicKey: false,
        GameAudio.effectsKey: false,
      });
      final settings = await GameSettings.load();
      await settings.setThemeMode(mode);
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: BloriqApp(settings: settings),
        ),
      );
      for (var frame = 0; frame < 100 && board.evaluate().isEmpty; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
      final prefix = mode.name;
      await capture('$prefix-stage-1');
      await select(2);
      for (final move in const PuzzleSolver().solve(
        game().controller.state.level,
      )!) {
        await step(move);
        if (game().controller.state.echo != null) break;
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(game().controller.state.echo, isNotNull);
      await capture('$prefix-stage-2-echo');
      await select(14);
      await capture('$prefix-stage-14-gate');
      final gateSolution = const PuzzleSolver().solve(
        game().controller.state.level,
      )!;
      for (final move in gateSolution) {
        await step(move);
        if (game().controller.state.isGateOpen) break;
      }
      expect(game().controller.state.isGateOpen, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      await capture('$prefix-stage-14-open-gate');
      await select(20);
      await capture('$prefix-stage-20');
      await tap(find.byTooltip('Settings'));
      await capture('$prefix-settings');
      await tap(find.text('Close'));
      await tap(find.byTooltip('How to play'));
      await capture('$prefix-help');
      await tap(find.text('Close'));
      await select(1);
      await solve();
      await tester.pump(const Duration(milliseconds: 220));
      await capture('$prefix-victory-escape');
      await tester.pump(const Duration(milliseconds: 280));
      await capture('$prefix-victory-burst');
      await tester.pump(const Duration(milliseconds: 500));
      await capture('$prefix-victory-stars');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.ensureVisible(find.text('Next level'));
      await tester.pump();
      await capture('$prefix-victory-new-best');
      await tap(find.text('Try again'));
      await solve();
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.ensureVisible(find.text('Next level'));
      await tester.pump();
      expect(find.text('New personal best!'), findsNothing);
      await capture('$prefix-victory-repeat');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      settings.dispose();
    }
  });
}
