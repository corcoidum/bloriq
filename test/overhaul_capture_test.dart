// 검토용 화면: flutter test test/overhaul_capture_test.dart --dart-define=CAPTURE_OVERHAUL=true
// 일반 테스트 실행에서는 캡처와 파일 쓰기를 수행하지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_repository.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  testWidgets('capture overhaul screens', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_OVERHAUL')) return;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
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
    await tester.runAsync(() => StarArt.loadPortrait(StarArt.lunabel));
    final directory = Directory('build/overhaul-captures')
      ..createSync(recursive: true);
    final key = GlobalKey();
    final board = find.byType(GameWidget<BloriqGame>);
    BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        for (final asset in [
          StarArt.riq,
          StarArt.riqHappy,
          StarArt.courier,
          StarArt.lunabel,
        ]) {
          await precacheImage(
            ResizeImage(AssetImage(asset), width: 384),
            context,
          );
          await precacheImage(
            ResizeImage(AssetImage(asset), width: 192),
            context,
          );
          await precacheImage(
            ResizeImage(AssetImage(asset), width: 256),
            context,
          );
        }
        await precacheImage(
          const ResizeImage(AssetImage(StarArt.forest), width: 1080),
          context,
        );
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

    final levels = (jsonDecode(
      File('assets/levels/levels.json').readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    Map<String, Object> entry(int id, int stars) {
      final level = levels.firstWhere((l) => l['id'] == id);
      return {
        'levelId': id,
        'revision': level['revision'] ?? 1,
        'bestMoves': (level['minimumMoves'] as int) + (stars == 3 ? 0 : 2),
        'bestStars': stars,
        'completionCount': 1,
      };
    }

    Future<void> launch(String locale, List<Map<String, Object>> done) async {
      tester.platformDispatcher.localesTestValue = [Locale(locale)];
      SharedPreferences.setMockInitialValues({
        'bloriq.audio.music': false,
        'bloriq.audio.effects': false,
        'bloriq.onboarding.v1': 'skipped',
        'bloriq.intro.v1': true,
        ProgressRepository.storageKey: jsonEncode({
          'version': ProgressRepository.schemaVersion,
          'levels': done,
        }),
      });
      final settings = await GameSettings.load();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BloriqApp(settings: settings),
        ),
      );
    }

    Future<void> solve() async {
      for (final move in const PuzzleSolver().solve(
        game().controller.state.level,
      )!) {
        await tester.ensureVisible(board);
        await tester.pump();
        final state = game().controller.state;
        final block = state.blocks.firstWhere((b) => b.id == move.blockId);
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
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    final progress = [
      for (var id = 1; id <= 4; id++) entry(id, 3),
      entry(7, 2),
    ];
    for (final locale in ['ko', 'en']) {
      await launch(locale, progress);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));
      if (locale == 'ko') await capture('$locale-quick-intro');
      if (locale == 'ko') {
        await tester.pump(const Duration(milliseconds: 600));
        await capture('$locale-quick-intro-logo');
      }
      await waitForHome(tester);
      await tester.pump(const Duration(milliseconds: 900));
      await capture('$locale-home');

      for (final id in [9, 14, 25]) {
        await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
        await selectOpenLevel(tester, id);
        for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 400));
        await capture('$locale-stage$id');
        await tapVisible(tester, find.byKey(const ValueKey('game-home')));
        final leave = find.text(locale == 'ko' ? '나가기' : 'Leave');
        if (leave.evaluate().isNotEmpty) await tapVisible(tester, leave);
        await tester.pump(const Duration(milliseconds: 400));
      }

      // 작은 폰: 장치가 많은 판도 스크롤 없이 들어간다.
      tester.view.physicalSize = const Size(360, 640);
      await tester.pump(const Duration(milliseconds: 300));
      await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
      await selectOpenLevel(tester, 9);
      for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 400));
      await capture('$locale-small-phone');
      await tapVisible(tester, find.byKey(const ValueKey('game-home')));
      final leaveSmall = find.text(locale == 'ko' ? '나가기' : 'Leave');
      if (leaveSmall.evaluate().isNotEmpty) {
        await tapVisible(tester, leaveSmall);
      }
      tester.view.physicalSize = const Size(393, 852);
      await tester.pump(const Duration(milliseconds: 400));

      // 무한 별길: 첫 판과 두 번째 판의 콤보 결과
      EndlessRepository.runInline = true;
      await tapVisible(tester, find.byKey(const ValueKey('home-endless')));
      for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await capture('$locale-endless-1');
      await solve();
      await tester.pump(const Duration(milliseconds: 2000));
      await tapVisible(tester, find.byKey(const ValueKey('result-next')));
      await tester.pump(const Duration(milliseconds: 300));
      await capture('$locale-endless-2');
      await solve();
      await tester.pump(const Duration(milliseconds: 2000));
      await capture('$locale-endless-result');
      await tapVisible(tester, find.byKey(const ValueKey('result-home')));
      await tester.pump(const Duration(milliseconds: 400));
      await capture('$locale-home-after');
      EndlessRepository.runInline = false;

      // 수호 정령 + 별자리 완성 결과
      await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
      await selectOpenLevel(tester, 5);
      for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await solve();
      await tester.pump(const Duration(milliseconds: 800));
      await capture('$locale-result-mid');
      await tester.pump(const Duration(milliseconds: 2000));
      await capture('$locale-result');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
