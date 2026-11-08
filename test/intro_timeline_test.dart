import 'package:bloriq/app/intro_screen.dart';
import 'package:bloriq/design/game_theme.dart';
import 'package:bloriq/design/star_art.dart';
import 'package:bloriq/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('segment clamps outside its window', () {
    expect(IntroBoardPainter.seg(0, 1, 2), 0);
    expect(IntroBoardPainter.seg(1.5, 1, 2), .5);
    expect(IntroBoardPainter.seg(3, 1, 2), 1);
  });

  test('hop squashes, stretches, rises and lands back at rest', () {
    expect(IntroBoardPainter.hop(.5, 1, .12), (0.0, 1.0, 1.0));
    final (_, anticipateX, anticipateY) = IntroBoardPainter.hop(1.09, 1, .12);
    expect(anticipateX, greaterThan(1));
    expect(anticipateY, lessThan(1));
    final (peak, stretchX, stretchY) = IntroBoardPainter.hop(1.21, 1, .12);
    expect(peak, closeTo(-.12, 1e-4));
    expect(stretchX, lessThan(1));
    expect(stretchY, greaterThan(1));
    final (landY, squashX, squashY) = IntroBoardPainter.hop(1.37, 1, .12);
    expect(landY, 0);
    expect(squashX, greaterThan(1));
    expect(squashY, lessThan(1));
    expect(IntroBoardPainter.hop(1.6, 1, .12), (0.0, 1.0, 1.0));
  });

  for (final dark in [true, false]) {
    testWidgets(
      'every 50ms frame paints without errors (${dark ? 'dark' : 'light'})',
      (tester) async {
        final progress = ValueNotifier<double>(0);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? GameTheme.dark : GameTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 360,
                height: 320,
                child: IntroScene(progress: _ValueAnimation(progress)),
              ),
            ),
          ),
        );
        for (var frame = 0; frame <= 80; frame++) {
          progress.value = frame / 80;
          await tester.pump();
          expect(tester.takeException(), isNull, reason: 'frame $frame');
        }
        expect(find.bySemanticsLabel(RegExp('Riq')), findsOneWidget);
      },
    );
  }

  testWidgets('sleeping frames still paint when the sleep face is missing', (
    tester,
  ) async {
    final saved = StarArt.riqSleepImage;
    StarArt.riqSleepImage = null;
    addTearDown(() => StarArt.riqSleepImage = saved);
    await tester.pumpWidget(
      MaterialApp(
        theme: GameTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: IntroScene(progress: AlwaysStoppedAnimation(.05)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

class _ValueAnimation extends Animation<double>
    with AnimationLocalListenersMixin, AnimationLocalStatusListenersMixin {
  _ValueAnimation(this.source) {
    source.addListener(notifyListeners);
  }
  final ValueNotifier<double> source;
  @override
  double get value => source.value;
  @override
  AnimationStatus get status => AnimationStatus.forward;
  @override
  void didRegisterListener() {}
  @override
  void didUnregisterListener() {}
}
