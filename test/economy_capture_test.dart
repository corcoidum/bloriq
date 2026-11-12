// 검토용 화면: flutter test test/economy_capture_test.dart --dart-define=CAPTURE_ECONOMY=true
// 도움 상한 표시, 별빛 공방, 황금 별자리 수호 정령을 360×740에서 찍는다.
// 일반 테스트 실행에서는 캡처와 파일 쓰기를 수행하지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/progress/progress_repository.dart';
import 'package:bloriq/progression/progression_repository.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  testWidgets('capture assist cap, workshop and golden guardian', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('CAPTURE_ECONOMY')) return;
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    for (final family in ['Roboto', 'Ahem', 'NanumGothic']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf')))
          .load();
    }
    for (final (family, file) in [
      ('Jua', 'Jua-Regular.ttf'),
      ('GamjaFlower', 'GamjaFlower-Subset.ttf'),
      ('GowunDodum', 'GowunDodum-Regular.ttf'),
    ]) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/$file'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await tester.runAsync(StarArt.load);
    await tester.runAsync(() => StarArt.loadPortrait(StarArt.lunabel));
    final directory = Directory('docs/screenshots/economy')
      ..createSync(recursive: true);
    final key = GlobalKey();

    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${directory.path}/$name.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    final levels = (jsonDecode(
      File('assets/levels/levels.json').readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();
    Map<String, Object> entry(int id) {
      final level = levels.firstWhere((l) => l['id'] == id);
      return {
        'levelId': id,
        'revision': level['revision'] ?? 1,
        'bestMoves': level['minimumMoves'] as int,
        'bestStars': 3,
        'completionCount': 1,
      };
    }

    Future<void> launch() async {
      tester.platformDispatcher.localesTestValue = [const Locale('ko')];
      SharedPreferences.setMockInitialValues({
        'bloriq.audio.music': false,
        'bloriq.audio.effects': false,
        'bloriq.onboarding.v1': 'skipped',
        ProgressRepository.storageKey: jsonEncode({
          'version': ProgressRepository.schemaVersion,
          'levels': [for (var id = 1; id <= 5; id++) entry(id)],
        }),
        ProgressionRepository.storageKey: jsonEncode({
          'version': 1,
          'xp': 800,
          'stardust': 650,
          'completedChapters': [1],
          'goldenChapters': [1],
          'ownedTrails': ['moonlight', 'rose'],
          'equippedTrail': 'rose',
          'backfilled': true,
        }),
      });
      final settings = await GameSettings.load();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: BloriqApp(settings: settings),
        ),
      );
      await waitForHome(tester);
    }

    // 1. 별빛 길을 쓰고 다시 시작해도 남는 "최대 ★2" 표시
    await launch();
    await openCampaignMap(tester);
    await selectOpenLevel(tester, 6);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tapVisible(tester, find.byKey(const ValueKey('starlight-path')));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tapVisible(tester, find.byIcon(Icons.refresh_rounded));
    await capture('ko-assist-cap-after-restart');
    await tester.pumpWidget(const SizedBox());

    // 2. 여정 → 보상 → 황금 별자리 업적, 별빛 공방, 잔영
    await launch();
    await tapVisible(tester, find.byKey(const ValueKey('home-journey')));
    await tapVisible(tester, find.text('보상'));
    Future<void> section(String id) async {
      final list = find.byKey(const PageStorageKey('journey-rewards-list'));
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('journey-rewards-$id')),
        240,
        maxScrolls: 100,
        scrollable: find.descendant(
          of: list,
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
    }

    await section('golden');
    await capture('ko-rewards-golden');
    await section('shop');
    await capture('ko-rewards-workshop');
    await section('trails');
    await capture('ko-rewards-trails');
    await tester.pumpWidget(const SizedBox());

    // 3. 여정의 황금 별자리
    await launch();
    await openHomeJourney(tester, tab: 'constellations');
    await tapVisible(tester, find.byKey(const ValueKey('journey-chapter-1')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await capture('ko-golden-guardian');
    await tester.pumpWidget(const SizedBox());
  });
}
