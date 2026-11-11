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

Future<void> _dismissBackfill(WidgetTester tester) async {
  final backfill = releaseKey('dismiss-backfill');
  if (backfill.evaluate().isNotEmpty) await tapVisible(tester, backfill);
}

void main() {
  setUp(rootBundle.clear);

  // 캡처(CAPTURE_HOME)는 그림을 미리 읽으므로 이 테스트가 가장 먼저 돈다.
  testWidgets('constellation atlas opens on the current world and plays it', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await _dismissBackfill(tester);
    await tapVisible(tester, releaseKey('home-atlas'));
    await tester.pumpAndSettle();
    // 열린 세계 여섯 개만 고를 수 있고, 진행 중인 세계 6이 골라져 있다.
    expect(releaseKey('world-chip-7'), findsNothing);
    expect(
      tester.widget<ChoiceChip>(releaseKey('world-chip-6')).selected,
      isTrue,
    );
    expect(releaseKey('atlas-list-world-6'), findsOneWidget);
    expect(releaseKey('atlas-chapter-26'), findsOneWidget);
    await _shot(tester, boundary, 'atlas-world6');

    // 세계 1로 바꾸면 예전 도감이 그대로 나온다.
    await tapVisible(tester, releaseKey('world-chip-1'));
    await tester.pumpAndSettle();
    expect(releaseKey('atlas-chapter-1'), findsOneWidget);
    await tapVisible(tester, releaseKey('world-chip-6'));
    await tester.pumpAndSettle();

    final third = releaseKey('atlas-chapter-28');
    await tester.scrollUntilVisible(
      third,
      160,
      scrollable: find
          .descendant(
            of: releaseKey('atlas-list-world-6'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tapVisible(tester, third);
    await tester.pumpAndSettle();
    expect(releaseKey('atlas-detail-28'), findsOneWidget);
    final play = releaseKey('atlas-play-513');
    await tester.scrollUntilVisible(
      play,
      160,
      scrollable: find
          .descendant(
            of: releaseKey('atlas-detail-28'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tapVisible(tester, play);
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 513);
    await closeReleaseApp(tester);
  });

  testWidgets('a locked chapter of the current world cannot be opened', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    await openReleaseApp(tester);
    await _dismissBackfill(tester);
    await tapVisible(tester, releaseKey('home-atlas'));
    await tester.pumpAndSettle();
    final fifth = releaseKey('atlas-chapter-30');
    await tester.scrollUntilVisible(
      fifth,
      160,
      scrollable: find
          .descendant(
            of: releaseKey('atlas-list-world-6'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(tester.widget<InkWell>(fifth).onTap, isNull);
    await closeReleaseApp(tester);
  });

  testWidgets('spirit album shows the current world and keeps season 1', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await _dismissBackfill(tester);
    await tapVisible(tester, releaseKey('home-album'));
    await tester.pumpAndSettle();
    expect(find.text('꿈의 서고 등대 · 친구 12 / 25'), findsOneWidget);
    expect(releaseKey('album-progress'), findsNothing);
    // 진행 중인 3장이 펼쳐져 있고, 만난 친구만 이름이 보인다.
    final met = releaseKey('spirit-${releaseSpiritId(6, 512)}');
    final unmet = releaseKey('spirit-${releaseSpiritId(6, 513)}');
    await tester.ensureVisible(met);
    await tester.pumpAndSettle();
    expect(tester.widget<InkWell>(met).onTap, isNotNull);
    expect(tester.widget<InkWell>(unmet).onTap, isNull);
    await _shot(tester, boundary, 'album-world6');
    await tapVisible(tester, met);
    await tester.pumpAndSettle();
    expect(
      releaseKey('spirit-detail-${releaseSpiritId(6, 512)}'),
      findsOneWidget,
    );
    await tester.tap(find.text('닫기').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, releaseKey('world-chip-1'));
    await tester.pumpAndSettle();
    expect(releaseKey('album-progress'), findsOneWidget);
    expect(releaseKey('album-world-progress'), findsNothing);
    await closeReleaseApp(tester);
  });

  testWidgets('journey constellations page through every open world', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    await openReleaseApp(tester);
    await _dismissBackfill(tester);
    await tapVisible(tester, releaseKey('home-journey'));
    await tester.pumpAndSettle();
    await tester.fling(find.byType(TabBarView), const Offset(-250, 0), 800);
    await tester.pumpAndSettle();
    // 세계 1의 5장 + 세계 2~6의 25장, 그중 세계 6의 3장에서 시작한다.
    expect(
      tester.widget<Text>(releaseKey('journey-constellation-page-count')).data,
      startsWith('28 / 30'),
    );
    expect(find.textContaining('꿈의 서고 등대 · '), findsOneWidget);
    // 열린 판은 세계 안의 번호로 보이고, 누르면 그 판이 열린다.
    await tapVisible(tester, releaseKey('journey-play-513'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 513);
    await closeReleaseApp(tester);
  });

  testWidgets('a world-1 player sees no world chips', (tester) async {
    seedSaga(throughWorld: 0);
    await openReleaseApp(tester);
    await tapVisible(tester, releaseKey('home-atlas'));
    await tester.pumpAndSettle();
    expect(releaseKey('world-chips'), findsNothing);
    expect(releaseKey('atlas-chapter-1'), findsOneWidget);
    await closeReleaseApp(tester);
  });
}
