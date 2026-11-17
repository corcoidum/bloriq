import 'dart:convert';

import 'package:bloriq/app/home_scene.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_HOME');

HomeSceneData _scene(WidgetTester tester) =>
    tester.widget<HomeScene>(find.byType(HomeScene)).data;

/// 저장된 성장 기록에 별가루·잔영·칭호를 덧붙인다.
Future<void> _patchProgression(Map<String, Object?> extra) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = jsonDecode(
    prefs.getString(ProgressionRepository.storageKey)!,
  ) as Map<String, dynamic>;
  await prefs.setString(
    ProgressionRepository.storageKey,
    jsonEncode({...saved, ...extra}),
  );
}

Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (!_capture) return;
  // 정령 그림은 화면에 처음 나올 때 읽으므로 캡처 전에 디코딩을 기다린다.
  final friend = find.byKey(const ValueKey('home-friend'));
  if (friend.evaluate().isNotEmpty) {
    final image = tester.widget<Image>(friend).image;
    await tester.runAsync(() => precacheImage(image, tester.element(friend)));
    await tester.pump();
  }
  await captureReleaseScreen(
    tester,
    boundary,
    'docs/screenshots/home-scene/$name.png',
  );
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('mid world 6: the scene shows this chapter and the lighthouse', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    await _patchProgression({
      'ownedTitles': ['garden_keeper'],
      'title': 'garden_keeper',
    });
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    final scene = _scene(tester);
    expect(scene.world, 6);
    expect(scene.hasLighthouse, isTrue);
    expect(scene.litLighthouses, 4);
    expect(scene.glow, closeTo(12 / 25, .001));
    expect(scene.lit, [true, true, false, false, false]);
    expect(scene.pendingNode, 2);
    // 곁에 서는 것은 합류한 능력 정령뿐이다.
    expect(scene.companions, hasLength(5));
    expect(releaseKey('home-sky'), findsOneWidget);
    expect(releaseKey('home-constellation'), findsOneWidget);
    expect(
      find.descendant(
        of: releaseKey('home-chapter-dots'),
        matching: find.byType(Container),
      ),
      findsNWidgets(5),
    );
    // 칭호는 홈에 보여 주지 않는다.
    expect(releaseKey('home-title'), findsNothing);
    expect(find.text('꿈의 서고 등대 · 스테이지 13'), findsOneWidget);
    expect(releaseKey('home-daily-dot'), findsOneWidget);
    await _shot(tester, boundary, 'ko-world6');

    Image riq() => tester.widget<Image>(
      find.descendant(of: releaseKey('home-riq'), matching: find.byType(Image)),
    );
    final before = riq().image;
    await tapVisible(tester, releaseKey('home-riq'));
    expect(riq().image, isNot(before));

    await tapVisible(tester, releaseKey('home-daily'));
    await waitForReleaseWidget(tester, releaseBoard);
    await closeReleaseApp(tester);
  });

  testWidgets('a fresh player stands in the forest with the first chapter', (
    tester,
  ) async {
    seedSaga(throughWorld: 0);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    final scene = _scene(tester);
    expect(scene.world, 1);
    expect(scene.hasLighthouse, isFalse);
    expect(scene.litLighthouses, 0);
    expect(scene.lit.every((lit) => !lit), isTrue);
    expect(scene.pendingNode, 0);
    // 서막은 달빛 숲 그림을 그대로 쓴다.
    expect(releaseKey('home-sky'), findsNothing);
    expect(releaseKey('home-title'), findsNothing);
    await _shot(tester, boundary, 'ko-world1');
    await closeReleaseApp(tester);
  });

  testWidgets('a new world starts with a dark lighthouse', (tester) async {
    seedSaga(throughWorld: 1);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    final scene = _scene(tester);
    expect(scene.world, 2);
    expect(scene.hasLighthouse, isTrue);
    expect(scene.glow, 0);
    expect(scene.litLighthouses, 0);
    await _shot(tester, boundary, 'ko-world2-new');
    await closeReleaseApp(tester);
  });

  testWidgets('the finale shows the first star above five lit lighthouses', (
    tester,
  ) async {
    seedSaga(throughWorld: 6, extra: 7);
    final boundary = await openReleaseApp(
      tester,
      captureArt: _capture,
      locale: const Locale('en'),
    );
    final scene = _scene(tester);
    expect(scene.world, 7);
    expect(scene.firstStar, isTrue);
    expect(scene.hasLighthouse, isFalse);
    expect(scene.litLighthouses, 5);
    expect(find.text('Daily Echo'), findsOneWidget);
    await _shot(tester, boundary, 'en-world7');
    await closeReleaseApp(tester);
  });

  testWidgets('everything perfect: the whole sky is lit and no stage waits', (
    tester,
  ) async {
    seedSaga(throughWorld: 7);
    await openReleaseApp(tester);
    final scene = _scene(tester);
    expect(scene.glow, 1);
    expect(scene.lit.every((lit) => lit), isTrue);
    expect(scene.pendingNode, isNull);
    expect(releaseKey('home-destination'), findsNothing);
    await closeReleaseApp(tester);
  });

  testWidgets('the starlight path is free and Aster keeps the stars once', (
    tester,
  ) async {
    seedSaga(throughWorld: 1, extra: 1);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseBoard);
    // 값과 잔액은 게임 화면에 없다.
    expect(releaseKey('starlight-price'), findsNothing);
    expect(releaseKey('starlight-balance'), findsNothing);
    // 아스테르가 함께하면 판마다 첫 별빛 길은 별이 줄지 않는다.
    await tapVisible(tester, releaseKey('starlight-path'));
    expect(releaseGame(tester).hintMove, isNotNull);
    expect(releaseKey('assist-cap-badge'), findsNothing);
    expect(releaseKey('starlight-note'), findsNothing);
    // 두 번째부터는 별 2개 상한이 걸리고, 한 번만 알린다.
    await tapVisible(tester, releaseKey('starlight-path'));
    await tester.pump(const Duration(milliseconds: 800));
    expect(releaseKey('assist-cap-badge'), findsOneWidget);
    expect(find.text('별빛 길을 쓴 판은 별 2개까지 받아요'), findsOneWidget);
    expect(find.text('최대 ★2'), findsNothing);
    if (_capture) {
      await captureReleaseScreen(
        tester,
        boundary,
        'docs/screenshots/home-scene/ko-game-balance.png',
      );
    }
    await closeReleaseApp(tester);
  });
}
