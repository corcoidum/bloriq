import 'dart:convert';
import 'dart:io';

import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/power_bar.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/progression/progression_rules.dart';
import 'package:bloriq/trials/trial_catalog.dart';
import 'package:bloriq/trials/trial_repository.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_ECHO_TRIALS');
final _entry = releaseKey('world-trials');
final _list = releaseKey('trial-list');
final _condition = releaseKey('trial-condition');
final _trialTiles = find.byWidgetPredicate(
  (widget) =>
      widget is ListTile && widget.key.toString().contains('trial-stage-'),
);

void main() {
  final catalog = TrialCatalog.parse(
    File(TrialCatalog.asset).readAsStringSync(),
  );
  setUp(rootBundle.clear);

  testWidgets('황금 장의 두 판이 먼저 열리고 되돌리기 금지가 적용된다', (tester) async {
    final chapters = {...Worlds.chaptersOf(1), 6};
    seedCampaign(chapters, cleared: releaseLevels(2).take(5));
    await (await SharedPreferences.getInstance()).setString(
      ProgressionRepository.storageKey,
      jsonEncode({
        'version': 1,
        'backfilled': true,
        'completedChapters': chapters.toList(),
        'goldenChapters': [6],
      }),
    );
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await enterReleaseWorld(tester, 2);
    expect(_entry, findsNothing);
    expect(releaseKey('golden-trials-7'), findsNothing);
    await tester.drag(
      find.descendant(of: releaseWorldMap(2), matching: find.byType(PageView)),
      const Offset(300, 0),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final golden = releaseKey('golden-trials-6');
    expect(golden, findsOneWidget);
    await _shot(tester, boundary, 'golden-entry');
    await tapVisible(tester, golden);
    await waitForReleaseWidget(tester, _list);
    expect(_trialTiles, findsNWidgets(2));

    final early = catalog.forWorld(2, chapter: 1);
    final stage = early.singleWhere(
      (stage) => stage.condition == TrialCondition.noUndo,
    );
    await _select(tester, stage);
    expect(tester.widget<Text>(_condition).data, '되돌리기 금지');
    final controller = releaseGame(tester).controller;
    final solution = controller.state.level.solution;
    await _drag(tester, solution.first);
    expect(controller.state.moves, 1);
    expect(controller.canUndo, isTrue);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '되돌리기'))
          .onPressed,
      isNull,
    );
    for (final move in solution.skip(1)) {
      await _drag(tester, move);
    }
    expect(controller.state.isComplete, isTrue);
    final result = releaseKey('trial-result-return');
    await waitForReleaseWidget(tester, result);
    expect(find.text('시련 1 / 10 완료'), findsOneWidget);
    expect((await TrialRepository.load()).bestMoves(stage), stage.minimumMoves);
    await tapVisible(tester, result);
    expect(
      find.descendant(of: _list, matching: find.text('시련 1 / 10 완료')),
      findsOneWidget,
    );
    await closeReleaseApp(tester);
  });

  testWidgets('완료한 세계의 시련 목록과 권능 금지 판의 10판 보상', (tester) async {
    final levels = releaseLevels(2);
    seedCampaign({
      ...Worlds.chaptersOf(1),
      ...Worlds.chaptersOf(2),
    }, cleared: levels);
    final stages = catalog.forWorld(2);
    final stage = stages.firstWhere(
      (stage) => stage.condition == TrialCondition.noPowers,
    );
    await (await SharedPreferences.getInstance()).setString(
      TrialRepository.storageKey,
      jsonEncode({
        'version': 1,
        'bestMoves': {
          for (final entry in stages)
            if (entry.sourceId != stage.sourceId)
              '${entry.sourceId}': entry.minimumMoves,
        },
      }),
    );
    final boundary = await openReleaseApp(tester, captureArt: _capture);
    await _openFromLightroad(tester, 2);
    await waitForReleaseWidget(tester, releaseWorldMap(2));
    await tapVisible(tester, _entry);
    await waitForReleaseWidget(tester, _list);
    expect(find.text('시련 9 / 10 완료'), findsOneWidget);
    await _shot(tester, boundary, 'trial-list');
    await _select(tester, stage);

    final controller = releaseGame(tester).controller;
    expect(
      levels.singleWhere((level) => level.id == stage.sourceId).availablePowers,
      isNotEmpty,
    );
    expect(controller.state.powers, isEmpty);
    expect(find.byType(PowerBar), findsNothing);
    expect(tester.widget<Text>(_condition).data, '권능 금지');
    final solution = const PuzzleSolver().solve(controller.state.level)!;
    expect(solution, hasLength(stage.minimumMoves));
    for (final move in solution) {
      await _drag(tester, move);
    }
    expect(controller.state.isComplete, isTrue);
    final result = releaseKey('trial-result-return');
    await waitForReleaseWidget(tester, result);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('세계 시련 보상을 얻었어요'), findsOneWidget);
    expect(find.text('시련 10 / 10 완료'), findsOneWidget);
    await _shot(tester, boundary, 'trial-reward');
    final progress = await ProgressRepository.load();
    expect(progress.forLevel(stage.sourceId)!.completionCount, 1);
    final trials = await TrialRepository.load();
    expect(trials.bestMoves(stage), stage.minimumMoves);
    final rewards = trialRewards[2]!;
    final saved = await ProgressionRepository.load();
    expect(saved.ownedTitles, contains(rewards.title.id));
    expect(saved.ownedTrails, contains(rewards.trail.id));
    await tapVisible(tester, result);
    expect(find.text('시련 10 / 10 완료'), findsOneWidget);
    await closeReleaseApp(tester);
  });

  testWidgets('달빛 숲 시련이 이동 한도를 막고 320×568의 200% 글자에서 다시 시작된다', (tester) async {
    seedCampaign(Worlds.chaptersOf(1));
    await openReleaseApp(tester, locale: const Locale('en'));
    await _openFromLightroad(tester, 1);
    await tapVisible(tester, _entry);
    await waitForReleaseWidget(tester, _list);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 32);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pump();
    final stage = catalog
        .forWorld(1)
        .firstWhere((stage) => stage.moveLimit != null);
    await _select(tester, stage);
    expect(MediaQuery.textScalerOf(tester.element(_condition)).scale(10), 20);

    final controller = releaseGame(tester).controller;
    final limit = stage.moveLimit!;
    final moves = _nonWinningMoves(controller.state, limit + 1)!;
    for (final move in moves) {
      await _drag(tester, move);
    }
    expect(controller.state.moves, limit);
    expect(controller.state.isComplete, isFalse);
    expect(
      tester.widget<Text>(_condition).data,
      contains('Move limit reached'),
    );
    expect((await TrialRepository.load()).bestMoves(stage), isNull);
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Undo'));
    expect(controller.state.moves, limit - 1);
    await tapVisible(tester, find.text('Restart'));
    expect(controller.state.moves, 0);
    await closeReleaseApp(tester);
  });
}

Future<void> _openFromLightroad(WidgetTester tester, int world) async {
  await openLightroad(tester, world);
  await tapVisible(tester, releaseKey('saga-enter-$world'));
}

Future<void> _select(WidgetTester tester, TrialStage stage) async {
  final tile = releaseKey('trial-stage-${stage.sourceId}');
  await tester.scrollUntilVisible(
    tile,
    140,
    scrollable: find.descendant(of: _list, matching: find.byType(Scrollable)),
  );
  await tapVisible(tester, tile);
  await waitForReleaseWidget(tester, releaseBoard);
}

Future<void> _drag(WidgetTester tester, PuzzleMove move) async {
  final game = releaseGame(tester);
  if (move.power case final power?) {
    await tapVisible(tester, releaseKey('power-${power.id}'));
  }
  await tester.ensureVisible(releaseBoard);
  await tester.pump();
  final geometry = game.geometry;
  final source = game.controller.state.positionOf(move.blockId)!;
  final dx = (move.target.x - source.x).sign.toDouble();
  final dy = (move.target.y - source.y).sign.toDouble();
  final direction = dx != 0 ? Offset(dx, 0) : Offset(0, dy);
  await tester.dragFrom(
    tester.getTopLeft(releaseBoard) + geometry.center(source),
    direction * geometry.cellSize * .74,
  );
  await tester.pump();
}

List<PuzzleMove>? _nonWinningMoves(PuzzleState state, int left) {
  if (left == 0) return [];
  for (final (move, next) in PuzzleSolver.successors(state)) {
    if (!next.isComplete && move.power == null) {
      if (_nonWinningMoves(next, left - 1) case final rest?) {
        return [move, ...rest];
      }
    }
  }
  return null;
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      key,
      'docs/screenshots/trials/$name.png',
    );
  }
}
