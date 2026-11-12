import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_HOME');
final _starWorld = releaseKey('journey-constellation-world');
final _spiritWorld = releaseKey('journey-companion-world');

DropdownButton<int> _picker(WidgetTester tester, Finder key) =>
    tester.widget<DropdownButton<int>>(
      find.descendant(of: key, matching: find.byType(DropdownButton<int>)),
    );

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
    expect(_picker(tester, _starWorld).value, 6);
    expect(find.text('별자리 복원 27 / 35'), findsOneWidget);
    expect(releaseKey('journey-stage-513').hitTestable(), findsOneWidget);
    await _shot(tester, boundary, 'atlas-world6');

    await chooseJourneyWorld(tester, _starWorld, 1);
    expect(releaseKey('journey-stage-1'), findsOneWidget);
    await chooseJourneyWorld(tester, _starWorld, 6);
    await tapVisible(tester, releaseKey('journey-chapter-3'));
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
      expect(_picker(tester, _starWorld).items!.last.enabled, isFalse);
      await tapVisible(tester, releaseKey('journey-chapter-5'));
      final locked = releaseKey('journey-stage-521');
      expect(tester.widget<OutlinedButton>(locked).onPressed, isNull);
      expect(releaseKey('journey-play-stage'), findsNothing);
      await closeReleaseApp(tester);
    },
  );

  testWidgets('companions shows campaign and world totals and spirit details', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await openHomeJourney(tester, tab: 'companions');
    expect(_picker(tester, _spiritWorld).value, 6);
    expect(find.text('전체 수집 137 / 175'), findsOneWidget);
    expect(find.text('이 세계 12 / 25'), findsOneWidget);
    await tapVisible(tester, releaseKey('album-world-6-chapter-3'));
    final met = releaseKey('spirit-${releaseSpiritId(6, 512)}');
    final unmet = releaseKey('spirit-${releaseSpiritId(6, 513)}');
    expect(tester.widget<InkWell>(met).onTap, isNotNull);
    expect(tester.widget<InkWell>(unmet).onTap, isNull);
    await _shot(tester, boundary, 'album-world6');

    await tapVisible(tester, met);
    expect(
      releaseKey('spirit-detail-${releaseSpiritId(6, 512)}'),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('닫기').last);
    await chooseJourneyWorld(tester, _spiritWorld, 1);
    expect(find.text('이 세계 25 / 25'), findsOneWidget);
    expect(releaseKey('album-progress'), findsOneWidget);
    await closeReleaseApp(tester);
  });

  testWidgets('a fresh player sees seven worlds with only the first enabled', (
    tester,
  ) async {
    seedSaga(throughWorld: 0);
    await openReleaseApp(tester);
    await openHomeJourney(tester, tab: 'constellations');
    final items = _picker(tester, _starWorld).items!;
    expect(items, hasLength(7));
    expect(items.where((item) => item.enabled).map((item) => item.value), [1]);
    expect(releaseKey('journey-stage-1'), findsOneWidget);
    await closeReleaseApp(tester);
  });
}
