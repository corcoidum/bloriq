// 검토용 화면: flutter test test/endless_capture_test.dart --dart-define=CAPTURE_ENDLESS=true
// 일반 테스트 실행에서는 캡처와 파일 쓰기를 수행하지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/endless/endless_pool.dart';
import 'package:bloriq/endless/endless_repository.dart';
import 'package:bloriq/endless/endless_run.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  testWidgets('capture the starsea voyage', (tester) async {
    if (!const bool.fromEnvironment('CAPTURE_ENDLESS')) return;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.platformDispatcher.localesTestValue = [const Locale('ko')];
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
    await tester.runAsync(StarArt.load);
    final directory = Directory('docs/screenshots/endless')
      ..createSync(recursive: true);
    final key = GlobalKey();
    final pool = EndlessPool.parse(File(EndlessPool.asset).readAsStringSync());

    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    String week() {
      final now = DateTime.now();
      final day = DateTime.utc(now.year, now.month, now.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      return monday.toIso8601String().substring(0, 10);
    }

    Future<void> launch(VoyageRun? run) async {
      SharedPreferences.setMockInitialValues({
        'bloriq.onboarding.v1': 'skipped',
        GameAudio.musicKey: false,
        GameAudio.effectsKey: false,
        ProgressionRepository.storageKey: jsonEncode({
          'version': 1,
          'xp': 420,
          'stardust': 260,
          'backfilled': true,
          'completedChapters': [1, 2],
        }),
        EndlessRepository.storageKey: jsonEncode({
          'version': 1,
          'bestScore': 2380,
          'bestDepth': 23,
          'voyages': 4,
          'totalBoards': 61,
          'weekKey': week(),
          'weekBest': 1640,
          'milestones': ['depth10'],
          'run': run?.toJson(),
        }),
      });
      final settings = await GameSettings.load();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BloriqApp(settings: settings),
        ),
      );
      await waitForHome(tester);
    }

    Future<void> openVoyage() async {
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find
            .byKey(const ValueKey('endless-harbor'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }
    }

    BloriqGame game() => tester
        .widget<GameWidget<BloriqGame>>(find.byType(GameWidget<BloriqGame>))
        .game!;

    Future<void> push(PuzzleMove move) async {
      final board = find.byType(GameWidget<BloriqGame>);
      final block = game().controller.state.blocks.firstWhere(
        (b) => b.id == move.blockId,
      );
      final geometry = game().geometry;
      await tester.dragFrom(
        tester.getTopLeft(board) + geometry.center(block.position),
        Offset(
              (move.target.x - block.position.x).toDouble(),
              (move.target.y - block.position.y).toDouble(),
            ) *
            geometry.cellSize *
            .7,
      );
      // 버튼 색 전환(200ms)이 끝난 모습을 찍도록 두 번 나눠 흘린다.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    // 1. 홈과 항구: 12번째 바다를 항해하던 중.
    VoyageRun midRun() {
      final run = VoyageRun.start(pool, seed: 77);
      while (run.depth < 12) {
        final minimum = pool.level(run.board)!.minimumMoves;
        for (var i = 0; i < minimum + (run.depth.isEven ? 1 : 0); i++) {
          run.pushed();
        }
        run.clear(minimum, pool);
      }
      return run;
    }

    await launch(midRun());
    await capture('home');
    await openVoyage();
    await capture('harbor');

    // 2. 항해 중: 판, 등불, 점수, 콤보.
    await tapVisible(tester, find.byKey(const ValueKey('endless-resume')));
    await tester.pump(const Duration(milliseconds: 400));
    final solution = const PuzzleSolver().solve(game().controller.state.level)!;
    await push(solution.first);
    await capture('sailing');
    for (final move in solution.skip(1)) {
      await push(move);
    }
    await tester.pump(const Duration(milliseconds: 300));
    await capture('perfect');
    await tester.pump(const Duration(seconds: 2));

    // 3. 등불이 꺼진 뒤의 결과.
    final last = midRun();
    while (last.depth < 25) {
      final minimum = pool.level(last.board)!.minimumMoves;
      for (var i = 0; i < minimum; i++) {
        last.pushed();
      }
      last.clear(minimum, pool);
    }
    final minimum = pool.level(last.board)!.minimumMoves;
    last.lanternAtStart = 1;
    for (var i = 0; i < minimum; i++) {
      last.pushed();
    }
    await tester.pumpWidget(const SizedBox());
    await launch(last);
    await openVoyage();
    await tapVisible(tester, find.byKey(const ValueKey('endless-resume')));
    await tester.pump(const Duration(milliseconds: 400));
    await push(
      const PuzzleSolver().solve(game().controller.state.level)!.first,
    );
    await tester.pump(const Duration(seconds: 1));
    await capture('lantern-out');
    await tester.pumpWidget(const SizedBox());
  });
}
