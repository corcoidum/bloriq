import 'dart:io';

import 'package:bloriq/dev/echo_samples.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/saga_seed.dart';
import 'support/start_game.dart';
import 'support/world_release.dart';

const _captureImprint = bool.fromEnvironment('CAPTURE_IMPRINT');

void main() {
  setUp(rootBundle.clear);
  final samples = parseEchoSamples(
    File('assets/levels/echo_samples_v1.json').readAsStringSync(),
  );

  test(
    'ten sample boards use world 1 rules and stay apart from the campaign',
    () {
      expect(samples, hasLength(10));
      expect(samples.map((level) => level.id), [
        for (var i = 0; i < 10; i++) echoSampleFirstId + i,
      ]);
      for (final level in samples) {
        expect(level.world, 1, reason: '${level.id}');
        expect(level.availablePowers, isEmpty, reason: '${level.id}');
        expect(
          level.minimumMoves,
          inInclusiveRange(5, 12),
          reason: '${level.id}',
        );
      }
    },
  );

  test('the Dart solver agrees with the recorded minimum and solution', () {
    for (final level in samples) {
      final solution = const PuzzleSolver().solve(level);
      expect(solution, isNotNull, reason: '${level.id}');
      expect(solution, hasLength(level.minimumMoves), reason: '${level.id}');
      // Python 검증기가 적어 둔 풀이를 그대로 따라가도 별문에 닿는다.
      final controller = PuzzleController(level);
      for (final move in level.solution) {
        expect(controller.apply(move), isTrue, reason: '${level.id}');
      }
      expect(controller.state.isComplete, isTrue, reason: '${level.id}');
      expect(controller.state.moves, level.minimumMoves);
    }
  });

  testWidgets('samples open from play modes and keep a best for this run', (
    tester,
  ) async {
    seedSaga(throughWorld: 0);
    await openReleaseApp(tester);
    await tapVisible(tester, releaseKey('home-play-modes'));
    await tapVisible(tester, releaseKey('home-echo-samples'));
    await waitForReleaseWidget(tester, releaseKey('echo-sample-1'));
    expect(find.text('샘플 1 · 4×4'), findsOneWidget);
    await tapVisible(tester, releaseKey('echo-sample-1'));
    await waitForReleaseWidget(tester, releaseBoard);
    expect(releaseGame(tester).controller.state.level.id, echoSampleFirstId);
    expect(find.text('샘플 1'), findsOneWidget);
    await solveVisibleBoard(tester);
    await tapVisible(tester, releaseKey('result-next'));
    await waitForReleaseWidget(tester, releaseKey('echo-sample-1'));
    final minimum = samples.first.minimumMoves;
    expect(find.text('내 기록 $minimum수 · 최소 $minimum수'), findsOneWidget);
    await closeReleaseApp(tester);
  });

  testWidgets('the moonlight board shows the real gate turn and undo', (
    tester,
  ) async {
    seedSaga(throughWorld: 0);
    final boundary = await openReleaseApp(
      tester,
      captureArt: _captureImprint,
      reduceMotion: false,
    );
    Future<void> capture(String name) async {
      if (_captureImprint) {
        await captureReleaseScreen(
          tester,
          boundary,
          'docs/screenshots/moonlight-imprint/$name.png',
        );
      }
    }

    await tester.pump(const Duration(milliseconds: 500));
    await capture('home');
    await openHomeJourney(tester);
    await capture('journey');
    await tapVisible(tester, releaseKey('journey-close'));
    await tapVisible(tester, releaseKey('home-play-modes'));
    await tapVisible(tester, releaseKey('home-echo-samples'));
    final sample = releaseKey('echo-sample-6');
    await tester.scrollUntilVisible(sample, 140);
    await tapVisible(tester, sample);
    await waitForReleaseWidget(tester, releaseBoard);
    await tester.pump(const Duration(milliseconds: 450));
    final game = releaseGame(tester);
    final level = game.controller.state.level;
    final rect = tester.getRect(releaseBoard);
    expect(level.id, 9006);

    Future<void> play(PuzzleMove move) async {
      final from = game.controller.state.positionOf(move.blockId)!;
      final offset = Offset(
        (move.target.x - from.x).toDouble(),
        (move.target.y - from.y).toDouble(),
      );
      await tester.dragFrom(
        rect.topLeft + game.geometry.center(from),
        offset * game.geometry.cellSize * .74,
      );
      await tester.pump();
    }

    for (final move in level.solution.take(5)) {
      await play(move);
      await tester.pump(const Duration(milliseconds: 240));
    }
    expect(game.controller.state.isGateOpen, isFalse);
    await capture('gate-closed');
    await play(level.solution[5]);
    expect(game.controller.state.isGateOpen, isTrue);
    expect(game.controller.state.echo, level.echoSwitch);
    await tester.pump(const Duration(milliseconds: 100));
    await capture('gate-signal');
    await tester.pump(const Duration(milliseconds: 140));
    await capture('gate-open');
    expect(tester.getRect(releaseBoard), rect);
    await tapVisible(tester, find.text('되돌리기'));
    expect(game.controller.state.isGateOpen, isFalse);
    for (final move in level.solution.skip(5)) {
      await play(move);
      await tester.pump(const Duration(milliseconds: 240));
    }
    expect(game.controller.state.isComplete, isTrue);
    await tester.pump(const Duration(seconds: 2));
    await capture('result');
    await closeReleaseApp(tester);
  });
}
