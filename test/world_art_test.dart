import 'dart:ui' as ui;

import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/world/world_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/start_game.dart';
import 'support/world_release.dart';

const _capture = bool.fromEnvironment('CAPTURE_WORLD_ART');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(rootBundle.clear);

  test(
    'only the six expansion portraits used by the ending are bundled',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final assets = manifest.listAssets().toSet();
      final portraits = <String>{};
      for (var world = 2; world <= Worlds.finalWorld; world++) {
        final source = await rootBundle.loadString(
          'assets/story/world$world.json',
        );
        final story = WorldStory.parse(source, world);
        for (final spirit in story.spirits.take(Worlds.stageCount - 1)) {
          expect(spirit.asset, isNull);
        }
        final spirit = story.spirits.last;
        final asset = 'assets/art/world$world/spirits/${spirit.id}.png';
        expect(spirit.asset, asset);
        expect(assets, contains(asset));
        expect(portraits.add(asset), isTrue);
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        try {
          final frame = await codec.getNextFrame();
          expect(
            (frame.image.width, frame.image.height),
            (512, 512),
            reason: asset,
          );
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      }
      expect(portraits, hasLength(6));
      expect(
        assets.where(
          (path) => RegExp(r'^assets/art/world[2-7]/spirits/').hasMatch(path),
        ),
        unorderedEquals(portraits),
      );
    },
  );

  for (var world = 2; world <= Worlds.finalWorld; world++) {
    testWidgets('world $world displays its board art without a guardian card', (
      tester,
    ) async {
      final firstChapter = releaseLevels(world).take(Worlds.stagesPerChapter);
      final guardian = firstChapter.last;
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
      await _shot(tester, boundary, world, 'board');

      await solveVisibleBoard(tester);
      // 능력 없는 수호 정령은 결과 팝업과 지도에 카드로 나오지 않는다.
      await waitForReleaseWidget(tester, releaseKey('result-next'));
      expect(releaseKey('world-guardian-reveal'), findsNothing);
      await tapVisible(tester, releaseKey('game-home'));
      await waitForHome(tester);
      await enterReleaseWorld(tester, world);
      expect(releaseKey('world-guardian-${guardian.id}'), findsNothing);
      expect(releaseKey('world-album'), findsNothing);
      await closeReleaseApp(tester);
    });
  }
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
