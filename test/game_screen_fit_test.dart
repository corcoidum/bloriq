import 'dart:convert';
import 'dart:io';

import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/game/mechanic_legend.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
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

/// 2세계에서 판 크기와 권능 수가 다른 대표 스테이지.
const _worldTwoStages = [101, 105, 121, 122, 125];

// 전체 조합: flutter test test/game_screen_fit_test.dart --dart-define=FULL_FIT_MATRIX=true
const _full = bool.fromEnvironment('FULL_FIT_MATRIX');

final _game = find.byType(GameWidget<BloriqGame>);

Future<void> _loadFonts() async {
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
}

/// [nextStage] 앞의 스테이지를 모두 깬 기록. 지도의 이어하기가 그 판을 연다.
Map<String, Object> _worldTwoSeed(int nextStage) {
  final decoded = jsonDecode(
    File('assets/levels/world2.json').readAsStringSync(),
  );
  final levels = (decoded is Map ? decoded['levels'] : decoded) as List;
  return {
    'bloriq.onboarding.v1': 'skipped',
    ProgressRepository.storageKey: jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': [
        for (final level in levels.cast<Map<String, Object?>>())
          if ((level['id']! as int) < nextStage)
            {
              'levelId': level['id']!,
              'revision': level['revision'] ?? 1,
              'bestMoves': level['minimumMoves']!,
              'bestStars': 3,
              'completionCount': 1,
            },
      ],
    }),
    ProgressionRepository.storageKey: jsonEncode({
      'version': 1,
      'xp': 0,
      'stardust': 0,
      'backfilled': true,
      'completedChapters': [1, 2, 3, 4, 5],
    }),
  };
}

/// 한 스테이지가 스크롤 없이 화면 안에 들어오는지 확인한다.
void _check(
  WidgetTester tester,
  List<String> problems,
  String name,
  double height,
  double bottom, {
  double minCell = 48,
}) {
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
  final board = tester.getRect(_game);
  final columns = tester
      .widget<GameWidget<BloriqGame>>(_game)
      .game!
      .controller
      .state
      .level
      .boardWidth;
  if (board.width / columns < minCell) {
    problems.add('$name: cell ${board.width ~/ columns}px');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  /// 언어·글자 크기·폰 조합마다 [body]를 돌린다.
  Future<List<String>> forEachPhone(
    WidgetTester tester,
    Future<void> Function(
      String name,
      double height,
      double bottom,
      List<String> problems,
    )
    body,
  ) async {
    await _loadFonts();
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetPadding);
    final problems = <String>[];
    for (final locale in _full ? ['ko', 'en'] : ['ko']) {
      tester.platformDispatcher.localesTestValue = [Locale(locale)];
      for (final scale in _full ? [1.0, 1.15, 1.3] : [1.3]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        for (final (width, height, top, bottom)
            in _full ? _phones : _phones.take(2)) {
          tester.view.physicalSize = Size(width, height);
          tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
          await body(
            '$locale x$scale ${width.toInt()}x${height.toInt()}',
            height,
            bottom,
            problems,
          );
        }
      }
    }
    return problems;
  }

  testWidgets('every stage fits one screen on every phone', (tester) async {
    final problems = await forEachPhone(tester, (
      name,
      height,
      bottom,
      problems,
    ) async {
      for (var id = 1; id <= 25; id++) {
        SharedPreferences.setMockInitialValues({});
        await pumpGame(tester, const BloriqApp(), levelId: id);
        _check(tester, problems, '$name stage $id', height, bottom);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });
    expect(problems, isEmpty, reason: problems.take(40).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 9)));

  testWidgets('world 2 stages with the power bar fit one screen', (
    tester,
  ) async {
    final problems = await forEachPhone(tester, (
      name,
      height,
      bottom,
      problems,
    ) async {
      for (final id in _worldTwoStages) {
        // 지도는 게임 화면이 아니므로 넉넉한 크기로 지나간 뒤 폰 크기로 돌아온다.
        final phone = tester.view.physicalSize;
        final textScale = tester.platformDispatcher.textScaleFactor;
        tester.view.physicalSize = const Size(412, 915);
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        SharedPreferences.setMockInitialValues(_worldTwoSeed(id));
        await tester.pumpWidget(const BloriqApp());
        await waitForHome(tester);
        await openHomeJourney(tester);
        await tapVisible(tester, find.byKey(const ValueKey('journey-world-2')));
        await tester.pump(const Duration(milliseconds: 400));
        await tapVisible(tester, find.byKey(const ValueKey('world-continue')));
        for (var i = 0; i < 100 && _game.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        tester.view.physicalSize = phone;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester
              .widget<GameWidget<BloriqGame>>(_game)
              .game!
              .controller
              .state
              .level
              .id,
          id,
        );
        _check(tester, problems, '$name world2 $id', height, bottom);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });
    expect(problems, isEmpty, reason: problems.take(40).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('a starsea voyage board fits one screen', (tester) async {
    final problems = await forEachPhone(tester, (
      name,
      height,
      bottom,
      problems,
    ) async {
      final phone = tester.view.physicalSize;
      final textScale = tester.platformDispatcher.textScaleFactor;
      tester.view.physicalSize = const Size(412, 915);
      tester.platformDispatcher.textScaleFactorTestValue = 1;
      SharedPreferences.setMockInitialValues({
        'bloriq.onboarding.v1': 'skipped',
        ProgressionRepository.storageKey: jsonEncode({
          'version': 1,
          'xp': 0,
          'stardust': 0,
          'backfilled': true,
          'completedChapters': [1, 2, 3, 4, 5],
        }),
      });
      await tester.pumpWidget(const BloriqApp());
      await waitForHome(tester);
      await openPlayModes(tester);
      await tapVisible(tester, find.byKey(const ValueKey('home-voyage')));
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byKey(const ValueKey('endless-start')).evaluate().isNotEmpty) {
          break;
        }
      }
      await tapVisible(tester, find.byKey(const ValueKey('endless-start')));
      for (var i = 0; i < 100 && _game.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      tester.view.physicalSize = phone;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      _check(tester, problems, '$name voyage', height, bottom, minCell: 40);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
    expect(problems, isEmpty, reason: problems.take(40).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('the world map stays usable on every phone', (tester) async {
    final problems = await forEachPhone(tester, (
      name,
      height,
      bottom,
      problems,
    ) async {
      // 앞으로 할 판이 있는 지도, 마지막 장, 다음 이야기가 붙는 완료 지도.
      for (final (next, first) in [(101, 101), (121, 121), (126, 101)]) {
        final phone = tester.view.physicalSize;
        final textScale = tester.platformDispatcher.textScaleFactor;
        tester.view.physicalSize = const Size(412, 915);
        tester.platformDispatcher.textScaleFactorTestValue = 1;
        SharedPreferences.setMockInitialValues(_worldTwoSeed(next));
        await tester.pumpWidget(const BloriqApp());
        await waitForHome(tester);
        await openHomeJourney(tester);
        await tapVisible(tester, find.byKey(const ValueKey('journey-world-2')));
        await tester.pump(const Duration(milliseconds: 400));
        final play = find.byKey(const ValueKey('world-continue'));
        expect(play, findsOneWidget, reason: 'map $next did not open');
        tester.view.physicalSize = phone;
        tester.platformDispatcher.textScaleFactorTestValue = textScale;
        await tester.pump(const Duration(milliseconds: 300));
        final map = '$name map $next';
        final error = tester.takeException();
        if (error != null) problems.add('$map: $error');
        if (tester.getRect(play).bottom > height - bottom) {
          problems.add('$map: play button is below the screen');
        }
        // 작은 화면에서는 스크롤로 마지막 판까지 닿아야 한다.
        final last = find.byKey(ValueKey('world-stage-${first + 4}'));
        await tester.ensureVisible(last);
        await tester.pump();
        if (tester.getRect(last).bottom > tester.getRect(play).top + 1) {
          problems.add('$map: last stage is hidden behind the play button');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      }
    });
    expect(problems, isEmpty, reason: problems.take(40).join('\n'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('a tall phone shows a whole chapter without scrolling', (
    tester,
  ) async {
    await _loadFonts();
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    tester.platformDispatcher.localesTestValue = [const Locale('ko')];
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(393, 852);
    SharedPreferences.setMockInitialValues(_worldTwoSeed(101));
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await openHomeJourney(tester);
    await tapVisible(tester, find.byKey(const ValueKey('journey-world-2')));
    await tester.pump(const Duration(milliseconds: 400));
    final page = find.byKey(const ValueKey('world-chapter-scroll')).first;
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: page, matching: find.byType(Scrollable)).first,
    );
    expect(scroll.position.maxScrollExtent, 0);
  });

  testWidgets('the folded legend switches text when an icon is tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MechanicLegend(
            compact: true,
            items: [
              LegendItem(LegendKind.eraser, 'dandelion rule'),
              LegendItem(LegendKind.hold, 'amber rule'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('amber rule'), findsOneWidget);
    expect(find.text('dandelion rule'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('legend-eraser')));
    await tester.pump();
    expect(find.text('dandelion rule'), findsOneWidget);
    expect(find.text('amber rule'), findsNothing);
  });
}
