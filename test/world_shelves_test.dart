import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_HOME');
Future<void> _shot(WidgetTester tester, GlobalKey boundary, String name) async {
  if (!_capture) return;
  await captureReleaseScreen(
    tester,
    boundary,
    'docs/screenshots/home/$name.png',
  );
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('constellations open on the current world and chapter', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await openHomeJourney(tester, tab: 'constellations');
    expect(find.text('별자리 복원 27 / 35'), findsOneWidget);
    expect(releaseKey('journey-stage-513').hitTestable(), findsOneWidget);
    await _shot(tester, boundary, 'atlas-world6');

    // 세계 번호를 누르면 하늘이 그 세계로 옮겨 간다.
    await tapVisible(tester, releaseKey('journey-sky-world-1'));
    expect(releaseKey('journey-stage-1').hitTestable(), findsOneWidget);
    await tapVisible(tester, releaseKey('journey-sky-world-6'));
    await tapVisible(tester, releaseKey('journey-stage-513'));
    await tapVisible(tester, releaseKey('journey-play-stage'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 513);
    await closeReleaseApp(tester);
  });

  testWidgets(
    'locked worlds and stages cannot be started from constellations',
    (tester) async {
      seedSaga(throughWorld: 5, extra: 12);
      await openReleaseApp(tester);
      await openHomeJourney(tester, tab: 'constellations');
      // 아직 열리지 않은 장의 별은 눌러도 고를 수 없다.
      final locked = releaseKey('journey-stage-521');
      expect(tester.widget<GestureDetector>(locked).onTap, isNull);
      // 잠긴 세계는 구경만 할 수 있고 시작 버튼이 없다.
      await tapVisible(tester, releaseKey('journey-sky-world-7'));
      expect(
        tester.widget<GestureDetector>(releaseKey('journey-stage-601')).onTap,
        isNull,
      );
      expect(releaseKey('journey-play-stage'), findsNothing);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('a fresh player sees seven worlds with only the first enabled', (
    tester,
  ) async {
    seedSaga(throughWorld: 0);
    await openReleaseApp(tester);
    await openHomeJourney(tester, tab: 'constellations');
    // 일곱 세계가 모두 한 하늘에 있고, 첫 세계의 별만 고를 수 있다.
    for (var world = 1; world <= 7; world++) {
      expect(releaseKey('journey-sky-world-$world'), findsOneWidget);
      final first = releaseKey('journey-stage-${(world - 1) * 100 + 1}');
      expect(
        tester.widget<GestureDetector>(first).onTap,
        world == 1 ? isNotNull : isNull,
      );
    }
    expect(releaseKey('journey-stage-1').hitTestable(), findsOneWidget);
    await closeReleaseApp(tester);
  });
}
