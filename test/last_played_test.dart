import 'dart:convert';

import 'package:bloriq/progress/last_played.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

Finder _inPlay(String text) =>
    find.descendant(of: releaseKey('home-play'), matching: find.text(text));

void main() {
  setUp(rootBundle.clear);

  test('old saves without the key and broken values read as null', () async {
    expect(LastPlayedRepository.parse(null), isNull);
    expect(LastPlayedRepository.parse('not json'), isNull);
    expect(LastPlayedRepository.parse('{"version":2,"levelId":5}'), isNull);
    expect(LastPlayedRepository.parse('{"version":1,"levelId":"5"}'), isNull);
    expect(LastPlayedRepository.parse('{"version":1,"levelId":0}'), isNull);
    expect(LastPlayedRepository.parse('{"version":1,"levelId":513}'), 513);

    SharedPreferences.setMockInitialValues({});
    expect((await LastPlayedRepository.load()).levelId, isNull);
  });

  test('record survives a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final repository = await LastPlayedRepository.load();
    await repository.record(204);
    expect((await LastPlayedRepository.load()).levelId, 204);
    final stored = (await SharedPreferences.getInstance()).getString(
      LastPlayedRepository.storageKey,
    );
    expect(jsonDecode(stored!), {'version': 1, 'levelId': 204});
  });

  testWidgets('continue returns to the open stage the player left unsolved', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12, lastPlayed: 515);
    await openReleaseApp(tester);
    expect(_inPlay('이어가기 · 꿈의 서고 등대 15'), findsOneWidget);
    await tapVisible(tester, releaseKey('home-play'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 515);
    await closeReleaseApp(tester);
  });

  testWidgets('a cleared or still-locked last stage falls back to progress', (
    tester,
  ) async {
    for (final last in [512, 521, 9999]) {
      rootBundle.clear();
      seedSaga(throughWorld: 5, extra: 12, lastPlayed: last);
      await openReleaseApp(tester);
      expect(
        _inPlay('이어가기 · 꿈의 서고 등대 13'),
        findsOneWidget,
        reason: 'last played $last',
      );
      await closeReleaseApp(tester);
    }
  });

  testWidgets('opening a stage from the map is remembered on the home button', (
    tester,
  ) async {
    seedSaga(throughWorld: 5, extra: 12);
    await openReleaseApp(tester);
    await enterReleaseWorld(tester, 6);
    await tapVisible(tester, releaseKey('world-stage-514'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, 514);
    await tapVisible(tester, releaseKey('game-home'));
    await waitForHome(tester);
    expect(_inPlay('이어가기 · 꿈의 서고 등대 14'), findsOneWidget);
    expect((await LastPlayedRepository.load()).levelId, 514);
    await closeReleaseApp(tester);
  });
}
