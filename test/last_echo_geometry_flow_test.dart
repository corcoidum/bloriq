import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/domain/puzzle.dart';
import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';
import 'support/story_session.dart';

void main() {
  for (final screen in [
    const Size(320, 568),
    const Size(360, 800),
    const Size(393, 852),
    const Size(412, 915),
    const Size(600, 960),
    const Size(852, 393),
  ]) {
    for (final dpr in [1.0, 2.0, 3.0]) {
      testWidgets(
        '$screen DPR$dpr stages 1/6/14/25: geometry, hit, frame, resize and Undo',
        (tester) async {
          SharedPreferences.setMockInitialValues({
            'bloriq.audio.music': false,
            'bloriq.audio.effects': false,
          });
          tester.view.devicePixelRatio = dpr;
          tester.view.physicalSize = screen * dpr;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final session = await loadStorySession(tester);
          final settings = GameSettings(reduceMotion: true);
          final board = find.byType(GameWidget<BloriqGame>);
          BloriqGame game() =>
              tester.widget<GameWidget<BloriqGame>>(board).game!;
          for (final id in [1, 6, 14, 25]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: GameTheme.dark,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: GameScreen(
                  key: ValueKey(id),
                  session: session,
                  initialLevelId: id,
                  settings: settings,
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 350));
            await tester.ensureVisible(board);
            await tester.pump();
            final initial = game().controller.state;
            final geometry = game().geometry;
            final rect = tester.getRect(board);
            expect(rect.size, geometry.canvasSize);
            expect(geometry.cellSize, greaterThanOrEqualTo(48));
            final frame = tester.getRect(find.byType(StarBoardFrame));
            expect((rect.topLeft - frame.topLeft).dx, closeTo(24, .001));
            expect((rect.topLeft - frame.topLeft).dy, closeTo(24, .001));
            for (final block in initial.blocks) {
              expect(
                geometry.positionAt(geometry.center(block.position)),
                block.position,
              );
            }
            final move = const PuzzleSolver().solve(initial.level)!.first;
            final block = initial.blocks.firstWhere(
              (b) => b.id == move.blockId,
            );
            final delta = Offset(
              (move.target.x - block.position.x).toDouble(),
              (move.target.y - block.position.y).toDouble(),
            );
            await tester.dragFrom(
              rect.topLeft + geometry.center(block.position),
              delta * geometry.cellSize * .7,
            );
            await tester.pump(const Duration(milliseconds: 100));
            expect(game().controller.state.moves, 1);
            final afterMove = game().controller.state;
            final current = afterMove.blocks.firstWhere(
              (b) => b.id == move.blockId,
            );
            final pointer = await tester.startGesture(
              tester.getTopLeft(board) +
                  game().geometry.center(current.position),
            );
            await pointer.moveBy(Offset(game().geometry.cellSize * .4, 0));
            await tester.pump();
            tester.view.physicalSize =
                Size(screen.width + 12, screen.height + 12) * dpr;
            await tester.pump();
            expect(game().currentPreview, isNull);
            expect(game().controller.state, same(afterMove));
            expect(game().controller.canUndo, true);
            await pointer.up();
            await tester.pump();
            await tapVisible(tester, find.text('Undo'));
            expect(game().controller.state.moves, 0);
            expect(game().controller.state.echo, initial.echo);
            tester.view.physicalSize = screen * dpr;
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          await disposeStorySession(tester, session);
          settings.dispose();
        },
      );
    }
  }
}
