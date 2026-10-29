import 'package:bloriq/game/bloriq_game.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> waitForHome(WidgetTester tester) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final skip = find.byKey(const ValueKey('skip-intro'));
    if (skip.evaluate().isNotEmpty) {
      await tester.tap(skip);
      await tester.pump();
    }
    final play = find.byKey(const ValueKey('home-play'));
    if (play.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(play).onPressed != null) {
      return;
    }
  }
  fail('Home did not become ready');
}

Future<void> selectOpenLevel(WidgetTester tester, int id) async {
  final target = find.byKey(ValueKey('level-$id'));
  final grid = find.byKey(const ValueKey('level-grid'));
  await tester.scrollUntilVisible(
    target,
    160,
    scrollable: find.descendant(of: grid, matching: find.byType(Scrollable)),
  );
  await tapVisible(tester, target);
  await tester.pump(const Duration(milliseconds: 350));
}

/// 기존 보드 테스트도 실제 인트로와 홈을 거쳐 시작한다.
Future<void> pumpGame(
  WidgetTester tester,
  Widget widget, {
  int levelId = 1,
}) async {
  await tester.pumpWidget(widget);
  await waitForHome(tester);
  await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
  await selectOpenLevel(tester, levelId);
  for (
    var i = 0;
    i < 100 && find.byType(GameWidget<BloriqGame>).evaluate().isEmpty;
    i++
  ) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(find.byType(GameWidget<BloriqGame>), findsOneWidget);
  await tester.pump(const Duration(milliseconds: 300));
}
