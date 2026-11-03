import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

/// 실제 폰의 화면 크기와 상태바, 내비게이션 바. (너비, 높이, 위, 아래)
const _phones = [
  (320.0, 568.0, 24.0, 0.0),
  (360.0, 640.0, 24.0, 48.0),
  (360.0, 740.0, 28.0, 48.0),
  (360.0, 800.0, 32.0, 48.0),
  (384.0, 854.0, 32.0, 24.0),
  (393.0, 852.0, 47.0, 34.0),
  (412.0, 915.0, 32.0, 24.0),
];

// 전체 조합: flutter test test/game_screen_fit_test.dart --dart-define=FULL_FIT_MATRIX=true
const _full = bool.fromEnvironment('FULL_FIT_MATRIX');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every stage fits one screen on every phone', (tester) async {
    for (final family in ['NanumGothic', 'Roboto']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
          .load();
    }
    await (FontLoader(
      'Jua',
    )..addFont(rootBundle.load('assets/fonts/Jua-Regular.ttf'))).load();
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    final game = find.byType(GameWidget<BloriqGame>);
    final problems = <String>[];
    for (final locale in _full ? ['ko', 'en'] : ['ko']) {
      tester.platformDispatcher.localesTestValue = [Locale(locale)];
      for (final scale in _full ? [1.0, 1.15, 1.3] : [1.3]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final (width, height, top, bottom)
            in _full ? _phones : _phones.take(2)) {
          tester.view.physicalSize = Size(width, height);
          tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
          for (var id = 1; id <= 25; id++) {
            SharedPreferences.setMockInitialValues({});
            await pumpGame(tester, const BloriqApp(), levelId: id);
            final name =
                '$locale x$scale ${width.toInt()}x${height.toInt()} stage $id';
            final error = tester.takeException();
            if (error != null) problems.add('$name: $error');
            if (find.byType(SingleChildScrollView).evaluate().isNotEmpty) {
              problems.add('$name: needs scrolling');
            }
            for (final label in ['Undo', '되돌리기', 'Restart', '다시 시작']) {
              final finder = find.text(label);
              if (finder.evaluate().isEmpty) continue;
              if (tester.getRect(finder).bottom > height - bottom) {
                problems.add('$name: $label is below the screen');
              }
            }
            final board = tester.getRect(game);
            final columns = tester
                .widget<GameWidget<BloriqGame>>(game)
                .game!
                .controller
                .state
                .level
                .boardWidth;
            if (board.width / columns < 48) {
              problems.add('$name: cell ${board.width ~/ columns}px');
            }
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          }
        }
      }
    }
    expect(problems, isEmpty, reason: problems.take(40).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 9)));
}
