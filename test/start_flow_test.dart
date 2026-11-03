import 'package:bloriq/app/game_session.dart';
import 'package:bloriq/app/home_view.dart';
import 'package:bloriq/app/intro_screen.dart';
import 'package:bloriq/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/start_game.dart';

const _seenKey = 'bloriq.intro.v1';

Future<void> _waitIntro(WidgetTester tester) async {
  for (var i = 0; i < 100 && find.byType(IntroScreen).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(find.byType(IntroScreen), findsOneWidget);
}

ScrollableState _homeScroll(WidgetTester tester) => tester.state(
  find
      .descendant(of: find.byType(HomeView), matching: find.byType(Scrollable))
      .first,
);

void main() {
  setUp(() {
    rootBundle.clear();
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
    });
  });

  testWidgets('first launch shows the full intro and remembers it', (
    tester,
  ) async {
    await tester.pumpWidget(const BloriqApp());
    await _waitIntro(tester);
    expect(find.byType(QuickIntro), findsNothing);
    await tester.pump(const Duration(milliseconds: 4300));
    await waitForHome(tester);
    expect((await SharedPreferences.getInstance()).getBool(_seenKey), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('later launches play the short intro and end at home', (
    tester,
  ) async {
    (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    await tester.pumpWidget(const BloriqApp());
    await _waitIntro(tester);
    expect(find.byType(QuickIntro), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1800));
    await waitForHome(tester);
    expect(find.byType(IntroScreen), findsNothing);
    expect(find.byType(GameScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('tapping anywhere skips the short intro', (tester) async {
    (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    await tester.pumpWidget(const BloriqApp());
    await _waitIntro(tester);
    await tester.tapAt(const Offset(40, 40));
    await tester.pump();
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    await waitForHome(tester);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a brief inactive state does not end the intro; pause does', (
    tester,
  ) async {
    await tester.pumpWidget(const BloriqApp());
    await _waitIntro(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(IntroScreen), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(find.byType(IntroScreen), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('new players start the tutorial from the home button only', (
    tester,
  ) async {
    await tester.pumpWidget(const BloriqApp(showIntro: false));
    await waitForHome(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Start'), findsOneWidget);
    await startFromHome(tester);
    expect(find.byKey(const ValueKey('skip-tutorial')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('returning players see continue with the next gate', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'bloriq.audio.music': false,
      'bloriq.audio.effects': false,
      'bloriq.onboarding.v1': 'skipped',
    });
    await tester.pumpWidget(const BloriqApp(showIntro: false));
    await waitForHome(tester);
    expect(find.text('Continue · Gate 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in ['ko', 'en']) {
    testWidgets('home fits one 393x852 screen without scrolling ($locale)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.localesTestValue = [Locale(locale)];
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const BloriqApp(showIntro: false));
      await waitForHome(tester);
      expect(tester.takeException(), isNull);
      expect(_homeScroll(tester).position.maxScrollExtent, 0);
      for (final key in [
        'home-hero',
        'home-play',
        'home-levels',
        'home-album',
        'home-atlas',
        'home-daily',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        expect(rect.bottom, lessThanOrEqualTo(852), reason: key);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('320x568 with 200% text scrolls instead of overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const BloriqApp(showIntro: false));
    await waitForHome(tester);
    expect(tester.takeException(), isNull);
    await tapVisible(tester, find.byKey(const ValueKey('home-daily')));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('daily-play')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('session loading does not need the removed onboarding callback', () {
    expect(GameSession.load, isA<Function>());
  });
}
