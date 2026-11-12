import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_HOME');

Finder _inPlay(String text) =>
    find.descendant(of: releaseKey('home-play'), matching: find.text(text));

void main() {
  setUp(rootBundle.clear);

  testWidgets(
    'mid world 6: home names the destination and continues directly',
    (tester) async {
      seedSaga(throughWorld: 5, extra: 12);
      final boundary = await openReleaseApp(tester, captureArt: _capture);
      expect(_inPlay('이어하기'), findsOneWidget);
      expect(find.text('꿈의 서고 등대 · 스테이지 13'), findsOneWidget);
      for (final oldKey in [
        'saga-map',
        'home-atlas',
        'home-album',
        'world-entry',
      ]) {
        expect(releaseKey(oldKey), findsNothing);
      }
      expect(releaseKey('home-journey').hitTestable(), findsOneWidget);
      expect(releaseKey('home-play-modes').hitTestable(), findsOneWidget);
      if (_capture) {
        await captureReleaseScreen(
          tester,
          boundary,
          'docs/screenshots/home/home-world6.png',
        );
      }
      await tapVisible(tester, releaseKey('home-play'));
      await waitForReleaseWidget(tester, releaseBoard);
      expect(releaseGame(tester).controller.state.level.id, 513);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('world 1 finished: continue opens the new world', (tester) async {
    seedSaga(throughWorld: 1);
    await openReleaseApp(tester);
    expect(find.text('구름바다 등대 · 스테이지 1'), findsOneWidget);
    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 101);
    await closeReleaseApp(tester);
  });

  testWidgets('everything cleared: continue polishes the first weak stage', (
    tester,
  ) async {
    seedSaga(throughWorld: 7, stars: {204: 2});
    await openReleaseApp(tester);
    expect(_inPlay('별 더 모으기'), findsOneWidget);
    expect(find.text('거울 호수 등대 · 스테이지 4'), findsOneWidget);
    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 204);
    await closeReleaseApp(tester);
  });

  testWidgets('everything perfect: continue sails the starsea', (tester) async {
    seedSaga(throughWorld: 7);
    await openReleaseApp(tester);
    expect(_inPlay('별바다 항해'), findsOneWidget);
    expect(releaseKey('home-destination'), findsNothing);
    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseKey('endless-screen'));
    await closeReleaseApp(tester);
  });

  testWidgets('a fresh player can see stage 1 and choose from the lightroad', (
    tester,
  ) async {
    seedSaga(throughWorld: 0);
    await openReleaseApp(tester);
    expect(_inPlay('이어하기'), findsOneWidget);
    expect(find.text('달빛 숲 정원 · 스테이지 1'), findsOneWidget);
    await openCampaignMap(tester);
    expect(releaseKey('level-grid'), findsOneWidget);
    await closeReleaseApp(tester);
  });
}
