// flutter test test/hybrid_visual_capture_test.dart --dart-define=CAPTURE_HYBRID=true
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloriq/game/bloriq_game.dart';
import 'package:bloriq/main.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:bloriq/settings/game_settings.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

void main() {
  testWidgets('capture P0 tutorial and P1 Daily chapters consent controls', (
    tester,
  ) async {
    const star = bool.fromEnvironment('CAPTURE_STAR');
    if (!const bool.fromEnvironment('CAPTURE_HYBRID') && !star) return;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    const fontPath = String.fromEnvironment(
      'DESIGN_FONT',
      defaultValue: 'C:/Windows/Fonts/malgun.ttf',
    );
    for (final family in ['Roboto', 'Ahem']) {
      final loader = FontLoader(family)
        ..addFont(
          Future.value(ByteData.sublistView(File(fontPath).readAsBytesSync())),
        );
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Jua',
    )..addFont(rootBundle.load('assets/fonts/Jua-Regular.ttf'))).load();
    await (FontLoader(
      'NanumGothic',
    )..addFont(rootBundle.load('assets/fonts/NanumGothic-Regular.ttf'))).load();
    await tester.runAsync(StarArt.load);
    final output = Directory(
      star ? 'docs/screenshots/star-courier' : 'docs/screenshots/hybrid',
    )..createSync(recursive: true);
    final boundary = GlobalKey();
    final board = find.byType(GameWidget<BloriqGame>);
    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull, reason: name);
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('${output.path}/$name.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    Future<void> move(int x, int dx) async {
      await tester.ensureVisible(board);
      await tester.pump();
      final rect = tester.getRect(board),
          cell = tester.getRect(board).width / 3;
      await tester.dragFrom(
        rect.topLeft + Offset((x + .5) * cell, cell * 1.5),
        Offset(dx * cell, 0),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final locale in ['ko', 'en']) {
        rootBundle.clear();
        SharedPreferences.setMockInitialValues({
          'bloriq.audio.music': false,
          'bloriq.audio.effects': false,
        });
        tester.platformDispatcher.localesTestValue = [Locale(locale)];
        final settings = GameSettings(themeMode: mode);
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: BloriqApp(
              settings: settings,
              clock: () => DateTime(2026, 10, 29),
            ),
          ),
        );
        for (var i = 0; i < 200 && board.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(() async {
          final context = tester.element(find.byType(MaterialApp));
          for (final provider in <ImageProvider>[
            const ResizeImage(AssetImage(StarArt.forest), width: 1080),
            const ResizeImage(AssetImage(StarArt.courier), width: 512),
            const AssetImage(StarArt.portal),
            const ExactAssetImage(StarArt.boardFrame, scale: 4),
          ]) {
            if (context.mounted) {
              await precacheImage(provider, context);
            }
          }
        });
        await tester.runAsync(
          () => precacheImage(
            const ResizeImage(AssetImage(StarArt.restingCourier), width: 768),
            tester.element(find.byType(MaterialApp)),
          ),
        );
        await tester.pump();
        final prefix = '${mode.name}-$locale';
        await capture('$prefix-tutorial-move');
        await move(0, 1);
        await capture('$prefix-tutorial-echo');
        await move(1, -1);
        await capture('$prefix-tutorial-next');
        if (star) {
          await tapVisible(tester, find.byKey(const ValueKey('skip-tutorial')));
          await capture('$prefix-play');
        }
        await move(1, 1);
        await tester.pump(const Duration(milliseconds: 1700));
        if (star) {
          await capture('$prefix-victory');
          final t = AppLocalizations.of(
            tester.element(find.byType(GameScreen)),
          )!;
          await tapVisible(tester, find.text(t.postcard));
          await capture('$prefix-postcard');
          await tapVisible(tester, find.text(locale == 'ko' ? '닫기' : 'Close'));
        }
        await tapVisible(tester, find.byKey(const ValueKey('game-home')));
        await tester.pump(const Duration(milliseconds: 350));
        await capture('$prefix-home');
        await tester.ensureVisible(find.byKey(const ValueKey('daily-play')));
        await tester.pump();
        await capture('$prefix-daily');
        await tapVisible(tester, find.byKey(const ValueKey('home-levels')));
        await capture('$prefix-chapters');
        await tapVisible(tester, find.text(locale == 'ko' ? '닫기' : 'Close'));
        await tapVisible(
          tester,
          find.byTooltip(locale == 'ko' ? '설정' : 'Settings'),
        );
        if (star) await capture('$prefix-settings');
        await tester.ensureVisible(
          find.byKey(const ValueKey('analytics-consent')),
        );
        await tester.pump();
        await capture('$prefix-privacy');
        if (star) {
          final ko = locale == 'ko';
          await tapVisible(tester, find.text(ko ? '닫기' : 'Close'));
          await tapVisible(
            tester,
            find.byTooltip(ko ? '게임 방법' : 'How to play'),
          );
          await capture('$prefix-help');
          await tapVisible(tester, find.text(ko ? '닫기' : 'Close'));
          await tapVisible(tester, find.byTooltip(ko ? '설정' : 'Settings'));
          await tapVisible(tester, find.byKey(const ValueKey('replay-intro')));
          await capture('$prefix-intro-first');
          await tester.pump(const Duration(milliseconds: 900));
          await capture('$prefix-intro-echo');
          await tester.pump(const Duration(milliseconds: 1600));
          await capture('$prefix-intro-burst');
          await tapVisible(tester, find.byKey(const ValueKey('skip-intro')));
        }
        await tester.pumpWidget(const SizedBox());
        settings.dispose();
      }
    }
  });
}
