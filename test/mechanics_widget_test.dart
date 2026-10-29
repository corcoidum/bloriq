import 'support/start_game.dart';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('기믹 설명과 실제 드래그 미리보기 및 이동이 일치한다', (tester) async {
    final level = Level(
      id: 1,
      boardWidth: 4,
      boardHeight: 3,
      startPosition: const Position(0, 1),
      exitPosition: const Position(3, 2),
      blocks: const [],
      obstacles: const [],
      minimumMoves: 4,
      difficulty: 'test',
      echoErasers: {const Position(0, 1)},
      echoHolds: {const Position(1, 1)},
      oneWays: {const Position(2, 1): const Position(1, 0)},
      goalOnlyTiles: {const Position(3, 1)},
    );
    await pumpGame(tester, BloriqApp(loadLevels: () async => [level]));
    final boardFinder = find.byType(GameWidget<BloriqGame>);
    for (var i = 0; i < 100 && boardFinder.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(boardFinder, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Crossed tiles erase the echo'), findsOneWidget);
    expect(
      find.textContaining('Pause tiles keep the previous echo'),
      findsOneWidget,
    );
    expect(find.textContaining('arrow tile'), findsOneWidget);
    expect(find.textContaining('Triangle tiles'), findsOneWidget);

    final game = tester.widget<GameWidget<BloriqGame>>(boardFinder).game!;
    final board = tester.getRect(boardFinder);
    final cell = board.width / 4;
    Offset position(int x, int y) =>
        board.topLeft + Offset(cell * (x + .5), cell * (y + .5));
    Future<void> move(int x, int y, int dx, int dy) async {
      await tester.dragFrom(position(x, y), Offset(cell * dx, cell * dy));
      await tester.pump(const Duration(milliseconds: 300));
    }

    final gesture = await tester.startGesture(position(0, 1));
    await gesture.moveBy(Offset(cell * .6, 0));
    await tester.pump();
    expect(game.currentPreview?.isValid, isTrue);
    expect(game.currentPreview?.nextState?.echo, isNull);
    expect(game.controller.state.moves, 0);
    await gesture.cancel();
    await tester.pump();
    expect(game.currentPreview, isNull);
    expect(game.controller.state.moves, 0);

    await move(0, 1, 1, 0);
    expect(game.controller.state.echo, isNull);
    await move(1, 1, 1, 0);
    expect(game.controller.state.echo, isNull);
    await move(2, 1, 0, -1);
    expect(game.controller.state.moves, 2);
    expect(game.controller.state.goal.position, const Position(2, 1));
    await move(2, 1, 1, 0);
    expect(game.controller.state.goal.position, const Position(3, 1));
    expect(game.controller.state.echo, const Position(2, 1));
  });
}
