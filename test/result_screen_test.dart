import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/victory_panel.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/player_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

Future<void> _solve(WidgetTester tester, {List<PuzzleMove>? moves}) async {
  final game = _game(tester);
  for (final move
      in moves ?? const PuzzleSolver().solve(game.controller.state.level)!) {
    await tester.ensureVisible(_board);
    await tester.pump();
    final state = game.controller.state;
    final block = state.blocks.firstWhere((b) => b.id == move.blockId);
    final rect = tester.getRect(_board);
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
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
      'bloriq.onboarding.v1': 'skipped',
      'bloriq.intro.v1': true,
    });
  });

  for (final size in const [Size(393, 852), Size(360, 760)]) {
    testWidgets('result fits one $size screen without scrolling', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpGame(tester, const BloriqApp());
      await _solve(tester);
      expect(tester.takeException(), isNull);
      final scroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('result-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scroll.position.maxScrollExtent, 0);
      for (final finder in [
        find.byKey(const ValueKey('result-score')),
        find.byKey(const ValueKey('result-next')),
        find.byKey(const ValueKey('result-reward')),
        find.byTooltip('Try again'),
        find.byTooltip('More'),
        find.byKey(const ValueKey('result-home')),
      ]) {
        expect(tester.getRect(finder).bottom, lessThanOrEqualTo(size.height));
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('200% text on a small phone scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpGame(
      tester,
      BloriqApp(settings: GameSettings(reduceMotion: true)),
    );
    await _solve(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('result-next')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('score and experience match the first clear, then 25% replay', (
    tester,
  ) async {
    await pumpGame(tester, const BloriqApp());
    final level = _game(tester).controller.state.level;
    await _solve(tester);
    final full = RunScore.of(minimumMoves: level.minimumMoves, stars: 3).total;
    expect(find.text('$full'), findsOneWidget);
    expect(find.text('+$full XP'), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Try again'));
    await _solve(tester);
    expect(find.text('$full'), findsOneWidget);
    expect(find.text('+${(full * .25).round()} XP'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('reading a memory happens in a sheet and returns to the result', (
    tester,
  ) async {
    await pumpGame(tester, const BloriqApp());
    await _solve(tester);
    await tapVisible(tester, find.byKey(const ValueKey('result-reward')));
    expect(find.byKey(const ValueKey('skip-story')), findsOneWidget);
    await tapVisible(tester, find.byKey(const ValueKey('skip-story')));
    expect(find.byKey(const ValueKey('skip-story')), findsNothing);
    expect(find.byKey(const ValueKey('result-next')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('replay hides the result and brings it back', (tester) async {
    await pumpGame(tester, const BloriqApp());
    await _solve(tester);
    expect(find.byType(VictoryPanel), findsOneWidget);
    await tapVisible(tester, find.byTooltip('Watch Echo Replay'));
    expect(find.byType(VictoryPanel), findsNothing);
    await tapVisible(tester, find.byKey(const ValueKey('skip-replay')));
    expect(find.byType(VictoryPanel), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('actions have labels for screen readers', (tester) async {
    await pumpGame(
      tester,
      BloriqApp(settings: GameSettings(reduceMotion: true)),
    );
    await _solve(tester);
    final handle = tester.ensureSemantics();
    for (final label in [
      'Try again',
      'Watch Echo Replay',
      'Echo Postcard',
      'More',
    ]) {
      expect(
        tester.getSemantics(find.byTooltip(label)).tooltip,
        label,
        reason: label,
      );
    }
    handle.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home shows the player level after earning experience', (
    tester,
  ) async {
    await pumpGame(tester, const BloriqApp());
    await _solve(tester);
    await tapVisible(tester, find.byKey(const ValueKey('result-home')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('home-player')), findsOneWidget);
    expect(find.textContaining('Lv.1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('buttons under the result cannot be tapped through it', (
    tester,
  ) async {
    await pumpGame(tester, const BloriqApp());
    await _solve(tester);
    final moves = _game(tester).controller.state.moves;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('game-home'))),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(VictoryPanel), findsOneWidget);
    expect(_game(tester).controller.state.moves, moves);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clearing keeps the board where it was', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGame(tester, const BloriqApp());
    final board = find.byType(StarBoardFrame);
    final before = tester.getRect(board);
    await _solve(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(tester.getRect(board), before);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('board and buttons fit one screen on a busy stage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpGame(tester, const BloriqApp(), levelId: 9);
    expect(tester.getRect(find.text('Undo')).bottom, lessThanOrEqualTo(852));
    expect(tester.getRect(find.text('Restart')).bottom, lessThanOrEqualTo(852));
    await tester.pumpWidget(const SizedBox());
  });
}
