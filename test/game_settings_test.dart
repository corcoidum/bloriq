import 'package:bloriq/settings/game_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('first launch allows normal motion', () async {
    final settings = await GameSettings.load();
    expect(settings.reduceMotion, isFalse);
    expect(settings.saveFailed, isFalse);
    settings.dispose();
  });

  test('reduced motion survives a new settings instance', () async {
    final settings = await GameSettings.load();
    await settings.setReduceMotion(true);
    settings.dispose();

    final restored = await GameSettings.load();
    expect(restored.reduceMotion, isTrue);
    expect(restored.saveFailed, isFalse);
    restored.dispose();
  });

  test('rapid changes persist the final selection', () async {
    final settings = await GameSettings.load();
    await Future.wait([
      settings.setReduceMotion(true),
      settings.setReduceMotion(false),
      settings.setReduceMotion(true),
    ]);
    settings.dispose();
    final restored = await GameSettings.load();
    expect(restored.reduceMotion, isTrue);
    restored.dispose();
  });

  test('a stale theme value and malformed motion fall back safely', () async {
    // 예전 버전이 남긴 테마 값은 무시한다(테마는 늘 다크).
    SharedPreferences.setMockInitialValues({
      'bloriq.settings.themeMode': 'light',
      GameSettings.reduceMotionKey: 'invalid',
    });
    final malformed = await GameSettings.load();
    expect(malformed.reduceMotion, isFalse);
    malformed.dispose();
  });

  test(
    'unavailable persistence retains the current session and reports failure',
    () async {
      final settings = GameSettings();
      await settings.setReduceMotion(true);
      expect(settings.reduceMotion, isTrue);
      expect(settings.saveFailed, isTrue);
      settings.dispose();
    },
  );

  test('in-flight writes remain safe after disposal', () async {
    final settings = await GameSettings.load();
    final saved = settings.setReduceMotion(true);
    settings.dispose();
    await saved;
    final restored = await GameSettings.load();
    expect(restored.reduceMotion, isTrue);
    restored.dispose();
  });
}
