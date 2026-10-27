import 'package:bloriq/main.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('레벨 1에서 블록 이동, undo, restart, 경로 그리기와 클리어', (tester) async {
    await tester.pumpWidget(const BloriqApp());
    // Flame 렌더링 루프가 계속 실행되므로 pumpAndSettle 대신 로딩을 기다린다.
    for (
      var i = 0;
      i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.byType(GameWidget<BloriqGame>), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));

    final board = tester.getRect(find.byType(GameWidget<BloriqGame>));
    Offset cell(int x, int y) =>
        board.topLeft +
        Offset(board.width * (x + .5) / 5, board.height * (y + .5) / 5);
    Future<void> moveBlock() async {
      final gesture = await tester.startGesture(cell(0, 1));
      await gesture.moveTo(cell(1, 1));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    expect(find.text('Moves: 0'), findsOneWidget);
    await moveBlock();
    expect(find.text('Moves: 1'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(find.text('Moves: 0'), findsOneWidget);
    await moveBlock();
    expect(find.text('Moves: 1'), findsOneWidget);
    await tester.tap(find.text('Restart'));
    await tester.pump();
    expect(find.text('Moves: 0'), findsOneWidget);
    await moveBlock();
    expect(find.text('Moves: 1'), findsOneWidget);

    final line = await tester.startGesture(cell(0, 0));
    await line.moveTo(cell(0, 4));
    await tester.pump();
    await line.moveTo(cell(4, 4));
    await tester.pump();
    await line.up();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Path complete!'), findsOneWidget);
    expect(find.text('You escaped! Moves: 1.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Next level'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('Moves: 0'), findsOneWidget);
  });
}
