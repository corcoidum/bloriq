import 'dart:convert';
import 'dart:io';

import 'package:bloriq/constellation/constellation_state.dart';
import 'package:bloriq/constellation/victory_constellation.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';

final _board = find.byType(GameWidget<BloriqGame>);
BloriqGame _game(WidgetTester tester) =>
    tester.widget<GameWidget<BloriqGame>>(_board).game!;

final _levels = (jsonDecode(
  File('assets/levels/levels.json').readAsStringSync(),
) as List).cast<Map<String, dynamic>>();

Map<String, Object> _entry(int id, int stars) {
  final level = _levels.firstWhere((l) => l['id'] == id);
  return {
    'levelId': id,
    'revision': level['revision'] ?? 1,
    'bestMoves': (level['minimumMoves'] as int) + (stars == 3 ? 0 : 2),
    'bestStars': stars,
    'completionCount': 1,
  };
}

void _seed(List<Map<String, Object>> entries) {
  SharedPreferences.setMockInitialValues({
    'bloriq.audio.music': false,
    'bloriq.audio.effects': false,
    if (entries.isNotEmpty)
      ProgressRepository.storageKey: jsonEncode({
        'version': ProgressRepository.schemaVersion,
        'levels': entries,
      }),
  });
}

Future<void> _solve(WidgetTester tester) async {
  final game = _game(tester);
  final solution = const PuzzleSolver().solve(game.controller.state.level)!;
  for (final move in solution) {
    await tester.ensureVisible(_board);
    await tester.pump();
    final before = game.controller.state;
    final block = before.blocks.firstWhere((b) => b.id == move.blockId);
    final board = tester.getRect(_board);
    final cell = board.width / before.level.boardWidth;
    await tester.dragFrom(
      board.topLeft +
          Offset(
            (block.position.x + .5) * cell,
            (block.position.y + .5) * cell,
          ),
      Offset(
        (move.target.x - block.position.x) * cell,
        (move.target.y - block.position.y) * cell,
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
  expect(game.controller.state.isComplete, isTrue);
  // 별자리 완성 상한(2.6초)보다 길게 기다린다.
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(rootBundle.clear);

  testWidgets('first clear wakes a star; replaying the same gate does not', (
    tester,
  ) async {
    _seed([]);
    await pumpGame(tester, const BloriqApp());
    await _solve(tester);
    expect(find.text('A star in Moonflower woke up'), findsOneWidget);
    expect(find.byKey(const ValueKey('victory-constellation')), findsOneWidget);
    expect(find.byKey(const ValueKey('result-constellation')), findsNothing);

    await tapVisible(tester, find.text('Try again'));
    await _solve(tester);
    expect(find.byKey(const ValueKey('victory-constellation')), findsNothing);
    expect((await ProgressRepository.load()).forLevel(1)!.completionCount, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'the fifth gate restores the constellation and opens it in the atlas',
    (tester) async {
      _seed([for (var id = 1; id <= 4; id++) _entry(id, 2)]);
      await pumpGame(tester, const BloriqApp(), levelId: 5);
      await _solve(tester);
      expect(find.text('Moonflower shines again'), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const ValueKey('result-constellation')),
      );
      expect(find.byKey(const ValueKey('atlas-detail-1')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('atlas-play-2')),
        120,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('atlas-detail-1')),
          matching: find.byType(Scrollable),
        ),
      );
      await tapVisible(tester, find.byKey(const ValueKey('atlas-play-2')));
      expect(_game(tester).controller.state.level.id, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a better clear that completes 15/15 turns it golden', (
    tester,
  ) async {
    _seed([for (var id = 1; id <= 4; id++) _entry(id, 3), _entry(5, 2)]);
    await pumpGame(tester, const BloriqApp(), levelId: 5);
    await _solve(tester);
    expect(find.text('Moonflower turned golden'), findsOneWidget);
    expect(find.text('A star in Moonflower woke up'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('home shows the atlas and opens a picked gate', (tester) async {
    _seed([_entry(1, 3)]);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('bloriq.onboarding.v1', 'skipped');
    await tester.pumpWidget(const BloriqApp());
    await waitForHome(tester);
    await tapVisible(tester, find.byKey(const ValueKey('home-atlas')));
    await tapVisible(tester, find.byKey(const ValueKey('atlas-chapter-1')));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('atlas-play-3')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('atlas-detail-1')),
        matching: find.byType(Scrollable),
      ),
    );
    await tapVisible(tester, find.byKey(const ValueKey('atlas-play-3')));
    for (var i = 0; i < 50 && _board.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(_game(tester).controller.state.level.id, 3);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unsaved clear shows the waiting star in words', (
    tester,
  ) async {
    _seed([]);
    final session = await loadStorySession(tester);
    final atlas = ConstellationAtlas.derive(session.levels, session.progress);
    await tester.pumpWidget(
      MaterialApp(
        theme: GameTheme.dark,
        locale: const Locale('ko'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: VictoryConstellation(
            chapter: atlas.forLevel(1)!,
            levelId: 1,
            progress: 1,
            reduceMotion: true,
            guardianAsset: null,
            pending: true,
          ),
        ),
      ),
    );
    expect(find.text('기록이 저장되면 이 별이 켜져요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
