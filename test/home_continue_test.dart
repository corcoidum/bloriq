import 'package:bloriq/audio/game_audio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_HOME');

Finder _inPlay(String text) =>
    find.descendant(of: releaseKey('home-play'), matching: find.text(text));

void main() {
  setUp(rootBundle.clear);

  // 캡처(CAPTURE_HOME)는 그림을 미리 읽으므로 이 테스트가 가장 먼저 돈다.
  testWidgets('mid world 6: home shows that world and continues its stage', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    expect(_inPlay('이어가기 · 꿈의 서고 등대 13'), findsOneWidget);
    expect(find.text('137 / 175 완료'), findsOneWidget);
    expect(find.text('별 411개'), findsOneWidget);
    // "지금 여기" 카드는 진행 중인 세계와 장을 말하고, 그 세계 지도를 연다.
    final here = releaseKey('world-entry');
    expect(
      find.descendant(of: here, matching: find.text('꿈의 서고 등대')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: here,
        matching: find.text('이 세계 12 / 25판 · 이번 장 2 / 5판'),
      ),
      findsOneWidget,
    );
    expect(find.text('세계 6 / 7'), findsOneWidget);
    expect(find.text('완성 27 / 35'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
  });

  testWidgets('world 1 finished: continue opens the new world, not gate 1', (
    tester,
  ) async {
    seedSaga(throughWorld: 1);
    await openReleaseApp(tester);
    expect(_inPlay('새 세계 · 구름바다 등대 1'), findsOneWidget);
    expect(find.text('25 / 175 완료'), findsOneWidget);
    expect(find.text('친구 25 / 175'), findsOneWidget);
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
    expect(_inPlay('별 더 모으기 · 거울 호수 등대 4'), findsOneWidget);
    expect(find.text('175 / 175 완료'), findsOneWidget);
    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 204);
    await closeReleaseApp(tester);
  });

  testWidgets('everything perfect: continue sails the starsea', (tester) async {
    seedSaga(throughWorld: 7);
    await openReleaseApp(tester);
    expect(_inPlay('별바다 항해'), findsOneWidget);
    expect(
      find.descendant(
        of: releaseKey('world-entry'),
        matching: find.text('첫 별'),
      ),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets('a fresh player keeps the plain gate label', (tester) async {
    SharedPreferences.setMockInitialValues({
      'bloriq.onboarding.v1': 'skipped',
      GameAudio.musicKey: false,
      GameAudio.effectsKey: false,
    });
    await openReleaseApp(tester);
    expect(_inPlay('이어가기 · 별문 1'), findsOneWidget);
    expect(releaseKey('world-entry'), findsNothing);
    expect(releaseKey('home-levels'), findsOneWidget);
    await closeReleaseApp(tester);
  });
}
