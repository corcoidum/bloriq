// 검토용 화면: flutter test test/constellation_capture_test.dart --dart-define=CAPTURE_CONSTELLATION=true
// 일반 테스트 실행에서는 캡처와 파일 쓰기를 수행하지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
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
  testWidgets('capture intro, victory constellation and atlas', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_CONSTELLATION')) return;
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
    final directory = Directory('build/constellation-captures')
      ..createSync(recursive: true);
    final key = GlobalKey();
    final board = find.byType(GameWidget<BloriqGame>);
    BloriqGame game() => tester.widget<GameWidget<BloriqGame>>(board).game!;

    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
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

    Future<void> launch(
      ThemeMode mode,
      String locale,
      Map<String, Object> prefs,
    ) async {
      tester.platformDispatcher.localesTestValue = [Locale(locale)];
      SharedPreferences.setMockInitialValues({
        'bloriq.audio.music': false,
        'bloriq.audio.effects': false,
        ...prefs,
      });
      final settings = await GameSettings.load();
      await settings.setThemeMode(mode);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BloriqApp(settings: settings),
        ),
      );
    }

    // 1. 첫 실행 인트로 (장면별)
    for (final (mode, locale) in [
      (ThemeMode.dark, 'ko'),
      (ThemeMode.light, 'en'),
    ]) {
      await launch(mode, locale, {});
      for (
        var i = 0;
        i < 100 &&
            find.byKey(const ValueKey('intro-screen')).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      var elapsed = 0;
      for (final (ms, scene) in [
        (300, '1-sleep'),
        (1150, '2-hop'),
        (2150, '3-lookback'),
        (2950, '4-star'),
        (3420, '5-rise'),
        (3850, '6-constellation'),
      ]) {
        await tester.pump(Duration(milliseconds: ms - elapsed));
        elapsed = ms;
        await capture('${mode.name}-$locale-intro-$scene');
      }
      await tester.pumpWidget(const SizedBox());
    }

    // 2. 다섯 번째 별문: 별자리 완성 연출과 결과
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

    final seeded = {
      'bloriq.onboarding.v1': 'skipped',
      ProgressRepository.storageKey: jsonEncode({
        'version': ProgressRepository.schemaVersion,
        'levels': [
          for (var id = 1; id <= 4; id++) entry(id, 3),
          entry(7, 2),
          entry(8, 3),
        ],
      }),
    };
    for (final (mode, locale) in [
      (ThemeMode.dark, 'ko'),
      (ThemeMode.light, 'en'),
    ]) {
      await launch(mode, locale, seeded);
      await waitForHome(tester);
      await capture('${mode.name}-$locale-home');
      await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
      await selectOpenLevel(tester, 5);
      for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 300));
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
      await tester.pump(const Duration(milliseconds: 1900));
      final strip = find.byKey(const ValueKey('victory-constellation'));
      if (strip.evaluate().isNotEmpty) await tester.ensureVisible(strip);
      await capture('${mode.name}-$locale-victory-mid');
      await tester.pump(const Duration(milliseconds: 600));
      if (strip.evaluate().isNotEmpty) await tester.ensureVisible(strip);
      await capture('${mode.name}-$locale-victory-final');

      // 3. 결과에서 연 별자리 상세, 목록
      await tapVisible(
        tester,
        find.byKey(const ValueKey('result-constellation')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await capture('${mode.name}-$locale-atlas-detail');
      await tapVisible(tester, find.byKey(const ValueKey('atlas-back')));
      await capture('${mode.name}-$locale-atlas-list');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
