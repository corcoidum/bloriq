import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:bloriq/world/world_spirit_album.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD_ART');

void main() {
  setUp(rootBundle.clear);

  for (var world = 2; world <= Worlds.finalWorld; world++) {
    testWidgets(
      'world $world displays its board art and reveals the guardian',
      (tester) async {
        final firstChapter = releaseLevels(world).take(Worlds.stagesPerChapter);
        final guardian = firstChapter.last;
        final id = 's$world-05';
        final portrait = 'assets/art/world$world/spirits/$id.png';
        seedCampaign({
          for (
            var chapter = 1;
            chapter < Worlds.globalChapter(world, 1);
            chapter++
          )
            chapter,
        }, cleared: firstChapter.take(Worlds.stagesPerChapter - 1));
        final boundary = await openReleaseApp(tester, captureArt: _capture);
        await enterReleaseWorld(tester, world);
        expect(releaseKey('world-guardian-${guardian.id}'), findsNothing);
        await tapVisible(tester, releaseKey('world-continue'));
        await waitForReleaseWidget(tester, releaseBoard);
        expect(releaseGame(tester).controller.state.level.id, guardian.id);
        final frame = find.byType(StarBoardFrame);
        for (var i = 0; i < 200; i++) {
          if (tester.widget<StarBoardFrame>(frame).skin?.floors.length == 4) {
            break;
          }
          // 엔진의 PNG 디코딩이 끝날 때까지 실제 이벤트도 처리한다.
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 20));
        }
        final skin = tester.widget<StarBoardFrame>(frame).skin!;
        expect(skin.floors, hasLength(4));
        expect(skin.rocks, hasLength(2));
        expect(skin.mechanicArt, hasLength(world >= 3 && world <= 6 ? 1 : 0));
        if (_capture) {
          await tester.runAsync(
            () => precacheImage(
              ResizeImage(AssetImage(portrait), width: 512),
              tester.element(releaseBoard),
            ),
          );
        }
        await _shot(tester, boundary, world, 'board');

        await solveVisibleBoard(tester);
        final reveal = releaseKey('world-guardian-reveal');
        await waitForReleaseWidget(tester, reveal);
        _expectPortrait(tester, reveal, portrait);
        await tapVisible(tester, reveal);
        final atlas = releaseKey('guardian-atlas-${guardian.id}');
        _expectPortrait(tester, atlas, portrait);
        await _shot(tester, boundary, world, 'guardian-atlas');
        await tapVisible(
          tester,
          find.descendant(of: atlas, matching: find.text('닫기')),
        );

        await tapVisible(tester, releaseKey('game-home'));
        await waitForHome(tester);
        await enterReleaseWorld(tester, world);
        await tapVisible(tester, releaseKey('world-album'));
        final row = releaseKey('world-spirit-$id');
        final scroll = find.descendant(
          of: releaseKey('world-spirit-list'),
          matching: find.byType(Scrollable),
        );
        await tester.scrollUntilVisible(row, 150, scrollable: scroll);
        _expectPortrait(tester, row, portrait);
        expect(
          find.descendant(
            of: releaseKey('world-spirit-s$world-06'),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
        await _shot(tester, boundary, world, 'spirit-album');
        await closeReleaseApp(tester);
      },
    );
  }
}

void _expectPortrait(WidgetTester tester, Finder parent, String asset) {
  final image = find.descendant(
    of: parent,
    matching: find.byType(WorldSpiritPortrait),
  );
  expect(tester.widget<WorldSpiritPortrait>(image).asset, asset);
}

Future<void> _shot(
  WidgetTester tester,
  GlobalKey boundary,
  int world,
  String name,
) async {
  if (_capture) {
    await captureReleaseScreen(
      tester,
      boundary,
      'docs/screenshots/world$world/art/$name.png',
    );
  }
}
