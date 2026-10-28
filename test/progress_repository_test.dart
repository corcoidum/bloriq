import 'dart:convert';

import 'package:bloriq/progress/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('별 평가', () {
    test('최소 이동과 허용 범위의 양 끝을 평가한다', () {
      expect(starRating(moves: 10, minimumMoves: 10), 3);
      expect(starRating(moves: 11, minimumMoves: 10), 2);
      expect(starRating(moves: 13, minimumMoves: 10), 2);
      expect(starRating(moves: 14, minimumMoves: 10), 1);
      expect(starRating(moves: 4, minimumMoves: 2), 2);
      expect(starRating(moves: 5, minimumMoves: 2), 1);
      expect(starRating(moves: 12, minimumMoves: 9), 2);
      expect(starRating(moves: 13, minimumMoves: 9), 1);
    });

    test('불가능한 이동 수는 잘못된 입력으로 처리한다', () {
      expect(() => starRating(moves: 0, minimumMoves: 0), throwsArgumentError);
      expect(() => starRating(moves: 9, minimumMoves: 10), throwsArgumentError);
    });
  });

  test('최고 기록, 별, 완료 횟수는 재시작 후 유지된다', () async {
    final repository = await ProgressRepository.load();
    expect(repository.forLevel(1), isNull);
    final first = await repository.recordCompletion(
      levelId: 1,
      moves: 14,
      minimumMoves: 10,
    );
    expect(first.isNewBest, isTrue);
    expect(first.saved, isTrue);
    final improved = await repository.recordCompletion(
      levelId: 1,
      moves: 10,
      minimumMoves: 10,
    );
    expect(improved.isNewBest, isTrue);
    final worse = await repository.recordCompletion(
      levelId: 1,
      moves: 13,
      minimumMoves: 10,
    );
    expect(worse.isNewBest, isFalse);
    expect(worse.stars, 2);
    final again = await ProgressRepository.load();
    expect(again.forLevel(1)!.bestMoves, 10);
    expect(again.forLevel(1)!.bestStars, 3);
    expect(again.forLevel(1)!.completionCount, 3);
    expect(again.forLevel(2), isNull);
  });

  test('손상된 JSON은 실행을 막지 않고 새 기록을 저장할 수 있다', () async {
    SharedPreferences.setMockInitialValues({
      ProgressRepository.storageKey: '{bad',
    });
    final repository = await ProgressRepository.load();
    expect(repository.forLevel(1), isNull);
    await repository.recordCompletion(levelId: 2, moves: 4, minimumMoves: 4);
    expect((await ProgressRepository.load()).forLevel(2)!.bestMoves, 4);
  });

  test('잘못된 개별 레코드는 건너뛰고 정상 레코드는 유지한다', () async {
    SharedPreferences.setMockInitialValues({
      ProgressRepository.storageKey: jsonEncode({
        'version': 1,
        'levels': [
          {'levelId': 1, 'bestMoves': 4, 'bestStars': 3, 'completionCount': 2},
          {
            'levelId': 2,
            'bestMoves': -5,
            'bestStars': 99,
            'completionCount': 0,
          },
        ],
      }),
    });
    final repository = await ProgressRepository.load();
    expect(repository.forLevel(1)!.bestMoves, 4);
    expect(repository.forLevel(2), isNull);
    await repository.recordCompletion(levelId: 3, moves: 6, minimumMoves: 6);
    expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 2);
  });

  test('미래 버전의 저장 데이터는 덮어쓰지 않는다', () async {
    final raw = jsonEncode({'version': 2, 'levels': []});
    SharedPreferences.setMockInitialValues({
      ProgressRepository.storageKey: raw,
    });
    final repository = await ProgressRepository.load();
    final result = await repository.recordCompletion(
      levelId: 1,
      moves: 2,
      minimumMoves: 2,
    );
    expect(result.saved, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(
        ProgressRepository.storageKey,
      ),
      raw,
    );
  });

  test('연속 완료 저장은 이전 스냅샷으로 되돌아가지 않는다', () async {
    final repository = await ProgressRepository.load();
    await Future.wait([
      repository.recordCompletion(levelId: 1, moves: 4, minimumMoves: 2),
      repository.recordCompletion(levelId: 1, moves: 2, minimumMoves: 2),
    ]);
    final restored = (await ProgressRepository.load()).forLevel(1)!;
    expect(restored.bestMoves, 2);
    expect(restored.completionCount, 2);
  });

  test('새 코스 기록은 이전 코스 기록을 덮어쓰거나 혼동하지 않는다', () async {
    final legacy = jsonEncode({
      'version': 1,
      'levels': [
        {'levelId': 1, 'bestMoves': 2, 'bestStars': 3, 'completionCount': 4},
      ],
    });
    SharedPreferences.setMockInitialValues({
      ProgressRepository.legacyStorageKey: legacy,
    });
    final repo = await ProgressRepository.load();
    expect(repo.forLevel(1), isNull);
    await repo.recordCompletion(levelId: 1, moves: 3, minimumMoves: 3);
    expect((await ProgressRepository.load()).forLevel(1)!.bestMoves, 3);
    expect(
      (await SharedPreferences.getInstance()).getString(
        ProgressRepository.legacyStorageKey,
      ),
      legacy,
    );
  });
}
