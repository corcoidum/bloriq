import 'dart:convert';

import 'package:bloriq/app/tester_seed.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/world_release.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  testWidgets('seed clears all 175 stages and the app reads them back', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'bloriq.onboarding.v1': 'skipped'});
    final seed = (await tester.runAsync(seedTesterProgress))!;
    expect(seed.records, hasLength(175));
    expect(seed.completedChapters, {for (var c = 1; c <= 35; c++) c});
    // 마지막 장만 별 2개 판이 있어 황금이 아니다.
    expect(seed.goldenChapters, {for (var c = 1; c <= 34; c++) c});
    expect(
      seed.records
          .where((record) => record.bestStars == 2)
          .map((record) => record.levelKey.split(':').first),
      ['623', '624', '625'],
    );

    // 시드가 읽은 에셋 캐시를 비워야 앱이 같은 파일을 다시 읽는다.
    rootBundle.clear();
    await openReleaseApp(tester);
    expect(find.text('175 / 175 완료'), findsOneWidget);
    expect(find.text('별 522개'), findsOneWidget);
    // 성장 기록 환산(권능·세계 열림)은 빌드 표시가 켜진 앱에서만 돈다.
    await closeReleaseApp(tester);
  });

  // `flutter test --dart-define=TESTER_ALL_CLEARED=true test/tester_seed_test.dart`
  // 로 돌리면 테스터 빌드와 같은 길(시드 + 성장 기록 환산)을 확인한다.
  testWidgets(
    'tester build opens with every world unlocked and rewards granted',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await openReleaseApp(tester);
      expect(find.text('175 / 175 완료'), findsOneWidget);
      expect(
        find.descendant(
          of: releaseKey('home-play'),
          matching: find.text('별 더 모으기 · 첫 별 23'),
        ),
        findsOneWidget,
      );
      expect(find.text('세계 7 / 7'), findsOneWidget);
      expect(find.text('완성 35 / 35'), findsOneWidget);
      expect(find.text('Lv 1'), findsNothing);
      await closeReleaseApp(tester);
    },
    skip: !testerAllCleared,
  );

  test('existing progress is never overwritten', () async {
    final saved = jsonEncode({
      'version': ProgressRepository.schemaVersion,
      'levels': <Object>[],
    });
    SharedPreferences.setMockInitialValues({
      ProgressRepository.storageKey: saved,
    });
    expect(await seedTesterProgress(), isNull);
    expect(
      (await SharedPreferences.getInstance()).getString(
        ProgressRepository.storageKey,
      ),
      saved,
    );
  });
}
