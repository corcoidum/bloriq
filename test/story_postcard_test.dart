import 'dart:convert';
import 'dart:io';

import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/postcard/echo_postcard.dart';
import 'package:bloriq/story/story_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'discovery and five-friend collection reuse 1080px PNG exporter',
    (tester) async {
      await tester.runAsync(StarArt.load);
      final catalog = StoryCatalog.fromJson(
        jsonDecode(File('assets/story/season1.json').readAsStringSync()),
      );
      for (final friends in [
        [catalog.released.first],
        catalog.released,
      ]) {
        final bytes = await tester.runAsync(
          () => renderEchoPostcardPng(
            EchoPostcardData(
              levelId: 1,
              moves: 0,
              bestMoves: 0,
              stars: 1,
              levelText: '',
              movesText: '',
              bestText: '',
              story: StoryCardContent(
                title: '초승달 정원',
                detail: '새 친구 · Mori',
                quote: '별문 너머에서 누군가 우리를 기다리고 있었어.',
                portraitAssets: friends.map((s) => s.asset!).toList(),
              ),
            ),
          ),
        );
        expect(bytes!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        expect(bytes.length, greaterThan(10000));
      }
    },
  );
}
