import 'dart:async';
import 'dart:io';

import 'package:bloriq/audio/game_audio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeBackend implements AudioBackend {
  final events = <String>[];
  Completer<void>? startGate;
  bool failNextStart = false;

  @override
  Future<void> startMusic() async {
    events.add('start');
    if (failNextStart) {
      failNextStart = false;
      throw StateError('playback blocked');
    }
    await startGate?.future;
  }

  @override
  Future<void> stopMusic() async => events.add('stop');
  @override
  Future<void> playEffect(SoundEffect effect) async => events.add(effect.name);
  @override
  Future<void> stopEffects() async => events.add('stop effects');
  @override
  Future<void> dispose() async => events.add('dispose');
}

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'music starts only after interaction and pauses in background',
    () async {
      final backend = FakeBackend();
      final audio = await GameAudio.load(backend: backend);
      expect(backend.events, isEmpty);
      audio.onUserInteraction();
      await flush();
      expect(backend.events, ['start']);
      audio.didChangeAppLifecycleState(AppLifecycleState.paused);
      await flush();
      expect(backend.events, ['start', 'stop', 'stop effects']);
      audio.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await flush();
      expect(backend.events.last, 'start');
      await audio.dispose();
      expect(backend.events.last, 'dispose');
    },
  );

  test('a mute during a delayed start eventually stops music', () async {
    final backend = FakeBackend()..startGate = Completer<void>();
    final audio = await GameAudio.load(backend: backend);
    audio.onUserInteraction();
    await flush();
    audio.setMusicEnabled(false);
    backend.startGate!.complete();
    await flush();
    expect(backend.events, ['start', 'stop']);
    await audio.dispose();
    final restored = await GameAudio.load(backend: FakeBackend());
    expect(restored.musicEnabled, false);
    await restored.dispose();
  });

  test(
    'effects mute and rapidly toggled settings persist independently',
    () async {
      final backend = FakeBackend();
      final audio = await GameAudio.load(backend: backend);
      audio.play(SoundEffect.move);
      await flush();
      audio.setEffectsEnabled(false);
      audio.play(SoundEffect.blocked);
      audio.setMusicEnabled(false);
      audio.setMusicEnabled(true);
      await audio.dispose();
      expect(backend.events, contains('move'));
      expect(backend.events, isNot(contains('blocked')));
      final restored = await GameAudio.load(backend: FakeBackend());
      expect(restored.musicEnabled, true);
      expect(restored.effectsEnabled, false);
      await restored.dispose();
    },
  );

  test(
    'playback errors are contained and subsequent interaction retries',
    () async {
      final backend = FakeBackend()..failNextStart = true;
      final audio = await GameAudio.load(backend: backend);
      audio.onUserInteraction();
      await flush();
      audio.onUserInteraction();
      await flush();
      expect(backend.events, ['start', 'start']);
      await audio.dispose();
    },
  );

  test('wrong settings types do not prevent app startup', () async {
    SharedPreferences.setMockInitialValues({
      GameAudio.musicKey: 'invalid',
      GameAudio.effectsKey: false,
    });
    final audio = await GameAudio.load(backend: FakeBackend());
    expect(audio.musicEnabled, true);
    expect(audio.effectsEnabled, false);
    await audio.dispose();
  });

  test('bundled effects and music have WAV headers and nonempty samples', () {
    for (final name in ['bgm', ...SoundEffect.values.map((e) => e.name)]) {
      final bytes = File('assets/audio/$name.wav').readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(4)), 'RIFF');
      expect(String.fromCharCodes(bytes.skip(8).take(4)), 'WAVE');
      expect(bytes.length, greaterThan(100));
    }
  });
}
