import 'support/art_test_assets.dart';

import 'package:bloriq/audio/game_audio.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(prepareMoonlitArt);
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      GameAudio.musicKey: false,
      GameAudio.effectsKey: false,
    });
  });
  testWidgets(
    'Korean collection, large text and locked spoilers fit a small screen',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ko')];
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = await ProgressRepository.load();
      await repo.recordCompletion(levelId: 1, moves: 2, minimumMoves: 2);
      await tester.pumpWidget(const BloriqApp());
      final board = find.byType(GameWidget<BloriqGame>);
      for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.byTooltip('정령 도감'));
      await tester.pump();
      await tester.tap(find.byTooltip('정령 도감'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('???'), findsWidgets);
      expect(find.text('모아'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('루미'));
      await tester.pump();
      await tester.tap(find.text('루미'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('동행하기'));
      await tester.pump();
      await tester.tap(find.text('동행하기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect((await ProgressRepository.load()).companionId, 'spirit_01');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final ratio in [2.625, 3.0]) {
    testWidgets(
      'Flutter and Flame retain the same board at fractional DPR $ratio',
      (tester) async {
        tester.view.physicalSize = Size(393 * ratio, 852 * ratio);
        tester.view.devicePixelRatio = ratio;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const BloriqApp());
        final board = find.byType(GameWidget<BloriqGame>);
        for (var i = 0; i < 100 && board.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 300));
        final game = tester.widget<GameWidget<BloriqGame>>(board).game!;
        expect(
          game.geometry.boardSize.width,
          closeTo(tester.getSize(board).width, 1e-8),
        );
        expect(
          game.geometry.boardSize.height,
          closeTo(tester.getSize(board).height, 1e-8),
        );
        final from = game.controller.state.goal.position, g = game.geometry;
        await tester.dragFrom(
          tester.getTopLeft(board) + g.center(from),
          Offset(g.cellSize, 0),
        );
        await tester.pump();
        expect(game.controller.state.moves, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
