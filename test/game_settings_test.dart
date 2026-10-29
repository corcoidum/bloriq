import 'package:bloriq/settings/game_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'first launch opens the night forest and allows normal motion',
    () async {
      final settings = await GameSettings.load();
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.reduceMotion, isFalse);
      expect(settings.saveFailed, isFalse);
      settings.dispose();
    },
  );

  test('theme and reduced motion survive a new settings instance', () async {
    for (final mode in ThemeMode.values) {
      final settings = await GameSettings.load();
      await settings.setThemeMode(mode);
      await settings.setReduceMotion(true);
      settings.dispose();

      final restored = await GameSettings.load();
      expect(restored.themeMode, mode);
      expect(restored.reduceMotion, isTrue);
      expect(restored.saveFailed, isFalse);
      restored.dispose();
    }
  });

  test('rapid interleaved changes persist the final selections', () async {
    final settings = await GameSettings.load();
    await Future.wait([
      settings.setThemeMode(ThemeMode.dark),
      settings.setReduceMotion(true),
      settings.setThemeMode(ThemeMode.light),
      settings.setReduceMotion(false),
      settings.setThemeMode(ThemeMode.system),
    ]);
    settings.dispose();
    final restored = await GameSettings.load();
    expect(restored.themeMode, ThemeMode.system);
    expect(restored.reduceMotion, isFalse);
    restored.dispose();
  });

  test(
    'unknown or malformed values safely restore independent defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        GameSettings.themeModeKey: 'future-theme',
        GameSettings.reduceMotionKey: true,
      });
      final unknown = await GameSettings.load();
      expect(unknown.themeMode, ThemeMode.dark);
      expect(unknown.reduceMotion, isTrue);
      unknown.dispose();

      SharedPreferences.setMockInitialValues({
        GameSettings.themeModeKey: 42,
        GameSettings.reduceMotionKey: 'invalid',
      });
      final malformed = await GameSettings.load();
      expect(malformed.themeMode, ThemeMode.dark);
      expect(malformed.reduceMotion, isFalse);
      malformed.dispose();
    },
  );

  test(
    'unavailable persistence retains the current session and reports failure',
    () async {
      final settings = GameSettings();
      await settings.setThemeMode(ThemeMode.dark);
      await settings.setReduceMotion(true);
      expect(settings.themeMode, ThemeMode.dark);
      expect(settings.reduceMotion, isTrue);
      expect(settings.saveFailed, isTrue);
      settings.dispose();
    },
  );

  test('in-flight writes remain safe after disposal', () async {
    final settings = await GameSettings.load();
    final saved = settings.setThemeMode(ThemeMode.dark);
    settings.dispose();
    await saved;
    final restored = await GameSettings.load();
    expect(restored.themeMode, ThemeMode.dark);
    restored.dispose();
  });
}
