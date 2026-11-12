import 'dart:convert';
import 'dart:io';

import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:bloriq/trials/trial_catalog.dart';
import 'package:bloriq/trials/trial_repository.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/world_release.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = File(TrialCatalog.asset).readAsStringSync();
  final catalog = TrialCatalog.parse(manifest);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (var world = 1; world <= Worlds.finalWorld; world++) {
    test('세계 $world 시련 10판을 변환한 뒤에도 최단 수가 일치한다', () {
      final levels = world == 1
          ? (jsonDecode(File('assets/levels/levels.json').readAsStringSync())
                    as List)
                .map((data) => Level.fromJson(data as Map<String, dynamic>))
                .toList()
          : releaseLevels(world);
      final stages = catalog.forWorld(world);
      expect(stages, hasLength(10));
      for (var chapter = 1; chapter <= Worlds.chapterCount; chapter++) {
        expect(catalog.forWorld(world, chapter: chapter), hasLength(2));
      }
      expect(
        stages.map((stage) => stage.condition),
        containsAll([TrialCondition.moveLimit, TrialCondition.noUndo]),
      );
      for (final stage in stages) {
        final source = levels.singleWhere(
          (level) => level.id == stage.sourceId,
        );
        final board = stage.orient(source);
        final powers = world == 1
            ? const <PuzzlePower>{}
            : board.availablePowers;
        if (stage.condition == TrialCondition.noPowers) {
          expect(board.availablePowers, isEmpty);
          expect(source.solvableBareHanded, isTrue);
          expect(world, greaterThan(1));
          expect(source.availablePowers, isNotEmpty);
        }
        expect(identical(board, source), isFalse);
        final solution = const PuzzleSolver(maxStates: 2000000)
            .solve(board, powers: powers);
        expect(
          solution,
          hasLength(stage.minimumMoves),
          reason: 'Trial ${stage.sourceId}',
        );
      }
    });
  }

  test('이동 제한은 최단 수 +2까지 허용하고 다른 조건의 제한은 분리한다', () {
    final stages = catalog.forWorld(2);
    final limit = stages.firstWhere(
      (stage) => stage.condition == TrialCondition.moveLimit,
    );
    final cap = limit.minimumMoves + 2;
    expect(limit.moveLimit, cap);
    expect(limit.canMove(cap - 1), isTrue);
    expect(limit.canMove(cap), isFalse);
    expect(limit.acceptsClear(cap), isTrue);
    expect(limit.acceptsClear(cap + 1), isFalse);
    expect(limit.acceptsClear(limit.minimumMoves - 1), isFalse);
    final noUndo = stages.firstWhere(
      (stage) => stage.condition == TrialCondition.noUndo,
    );
    expect(noUndo.permitsUndo, isFalse);
    expect(noUndo.permitsPowers, isTrue);
    expect(noUndo.moveLimit, isNull);
    final noPowers = stages.firstWhere(
      (stage) => stage.condition == TrialCondition.noPowers,
    );
    expect(noPowers.permitsUndo, isTrue);
    expect(noPowers.permitsPowers, isFalse);
    expect(noPowers.moveLimit, isNull);
  });

  test('시련만 저장하고 연속 저장 뒤에도 최고 이동 수를 복원한다', () async {
    SharedPreferences.setMockInitialValues({
      ProgressRepository.storageKey: 'campaign-snapshot',
    });
    final stage = catalog.forWorld(1).first;
    final repository = await TrialRepository.load();
    expect(repository.bestMoves(stage), isNull);
    expect(
      await Future.wait([
        repository.recordClear(stage, stage.minimumMoves + 2),
        repository.recordClear(stage, stage.minimumMoves),
        repository.recordClear(stage, stage.minimumMoves + 1),
      ]),
      everyElement(isTrue),
    );
    expect((await TrialRepository.load()).bestMoves(stage), stage.minimumMoves);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ProgressRepository.storageKey), 'campaign-snapshot');
    expect(prefs.getString(TrialRepository.storageKey), isNotNull);
  });

  test('실패한 시련 저장은 집계하지 않고 재시도할 수 있다', () async {
    final prefs = await SharedPreferences.getInstance();
    var canSave = false;
    final repository = await TrialRepository.load(
      writer: (key, value) async =>
          canSave && await prefs.setString(key, value),
    );
    final stage = catalog
        .forWorld(1)
        .firstWhere((stage) => stage.moveLimit != null);
    expect(await repository.recordClear(stage, stage.moveLimit! + 1), isFalse);
    expect(await repository.recordClear(stage, stage.minimumMoves), isFalse);
    expect(repository.bestMoves(stage), isNull);
    canSave = true;
    expect(await repository.recordClear(stage, stage.moveLimit!), isTrue);
    expect((await TrialRepository.load()).bestMoves(stage), stage.moveLimit);
  });

  test('알 수 없는 시련 저장 버전은 덮어쓰지 않는다', () async {
    const raw = '{"version":2,"bestMoves":{"4":5}}';
    SharedPreferences.setMockInitialValues({TrialRepository.storageKey: raw});
    final repository = await TrialRepository.load();
    final stage = catalog.forWorld(1).first;
    expect(await repository.recordClear(stage, stage.minimumMoves), isFalse);
    expect(
      (await SharedPreferences.getInstance()).getString(
        TrialRepository.storageKey,
      ),
      raw,
    );
  });

  test('10판째 보상은 한 번만 지급하고 다음 실행에서 복원한다', () async {
    seedCampaign(Worlds.chaptersOf(1));
    final session = await GameSession.load();
    final stages = (await session.trialCatalog).forWorld(1);
    final reward = trialRewards[1]!;
    try {
      for (final (index, stage) in stages.indexed) {
        final result = await session.recordTrialClear(
          stage,
          stage.minimumMoves,
        );
        expect(result, (
          saved: true,
          cleared: index + 1,
          newReward: index == 9,
        ));
      }
      expect(session.progression.ownedTrails, contains(reward.trail.id));
      expect(session.progression.ownedTitles, contains(reward.title.id));
      expect(
        (await session.recordTrialClear(
          stages.last,
          stages.last.minimumMoves,
        )).newReward,
        isFalse,
      );
      expect(
        await session.progression.awardTrialReward(1),
        TrialRewardStatus.alreadyOwned,
      );
    } finally {
      await session.dispose();
    }
    final restored = await GameSession.load();
    try {
      expect(restored.trialProgress.clearedCount(stages), 10);
      expect(restored.progression.ownedTrails, contains(reward.trail.id));
      expect(restored.progression.ownedTitles, contains(reward.title.id));
    } finally {
      await restored.dispose();
    }
  });

  test('시련만 저장된 채 종료했어도 다음 실행에서 칭호와 잔영을 지급한다', () async {
    seedCampaign(Worlds.chaptersOf(1));
    final records = await TrialRepository.load();
    final stages = catalog.forWorld(1);
    for (final stage in stages) {
      expect(await records.recordClear(stage, stage.minimumMoves), isTrue);
    }
    final reward = trialRewards[1]!;
    expect(
      (await ProgressionRepository.load()).ownedTitles,
      isNot(contains(reward.title.id)),
    );
    final session = await GameSession.load();
    try {
      final saved = await ProgressionRepository.load();
      expect(saved.ownedTitles, contains(reward.title.id));
      expect(saved.ownedTrails, contains(reward.trail.id));
    } finally {
      await session.dispose();
    }
  });
}
