import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 게임 이벤트별 효과음. 모두 앱에 포함된 원본 합성 음원이다.
enum SoundEffect { move, echo, blocked, gate, complete }

abstract interface class AudioBackend {
  Future<void> startMusic();
  Future<void> stopMusic();
  Future<void> playEffect(SoundEffect effect);
  Future<void> stopEffects();
  Future<void> dispose();
}

class PlayerAudioBackend implements AudioBackend {
  AudioPlayer? _music;
  AudioPlayer? _effect;
  final _context = AudioContextConfig(
    focus: AudioContextConfigFocus.mixWithOthers,
  ).build();

  @override
  Future<void> startMusic() async {
    final player = _music ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource('audio/bgm.wav'), volume: .25, ctx: _context);
  }

  @override
  Future<void> stopMusic() async {
    if (_music != null) await _music!.stop();
  }

  @override
  Future<void> playEffect(SoundEffect effect) async {
    final player = _effect ??= AudioPlayer();
    await player.play(
      AssetSource('audio/${effect.name}.wav'),
      volume: .55,
      ctx: _context,
    );
  }

  @override
  Future<void> stopEffects() async {
    if (_effect != null) await _effect!.stop();
  }

  @override
  Future<void> dispose() async {
    try {
      await _music?.dispose();
    } finally {
      await _effect?.dispose();
    }
  }
}

/// UI 설정 및 앱 생명주기를 플레이어에서 분리하고, 음원 오류는 게임에서 격리한다.
class GameAudio with WidgetsBindingObserver {
  GameAudio({
    required this.backend,
    SharedPreferences? preferences,
    bool musicEnabled = true,
    bool effectsEnabled = true,
  }) : // 공개 설정 이름과 내부 상태를 구분한다.
       // ignore: prefer_initializing_formals
       _preferences = preferences,
       // ignore: prefer_initializing_formals
       _musicEnabled = musicEnabled,
       // ignore: prefer_initializing_formals
       _effectsEnabled = effectsEnabled;

  static const musicKey = 'bloriq.audio.music';
  static const effectsKey = 'bloriq.audio.effects';
  final AudioBackend backend;
  final SharedPreferences? _preferences;
  bool _musicEnabled;
  bool _effectsEnabled;
  bool _active = true;
  bool _interacted = false;
  bool _musicPlaying = false;
  bool _disposed = false;
  Future<void> _queue = Future.value();
  Future<void> _effectQueue = Future.value();
  Future<void> _settingsQueue = Future.value();

  bool get musicEnabled => _musicEnabled;
  bool get effectsEnabled => _effectsEnabled;

  static Future<GameAudio> load({AudioBackend? backend}) async {
    SharedPreferences? preferences;
    var music = true;
    var effects = true;
    try {
      preferences = await SharedPreferences.getInstance();
      // 손상된 설정은 해당 항목의 기본값으로 복구한다.
      try {
        music = preferences.getBool(musicKey) ?? true;
      } catch (_) {}
      try {
        effects = preferences.getBool(effectsKey) ?? true;
      } catch (_) {}
    } catch (_) {
      // 설정 저장소를 사용할 수 없어도 게임은 정상 실행한다.
    }
    return GameAudio(
      backend: backend ?? PlayerAudioBackend(),
      preferences: preferences,
      musicEnabled: music,
      effectsEnabled: effects,
    );
  }

  void _enqueue(Future<void> Function() operation) {
    _queue = _queue.then((_) async {
      try {
        await operation();
      } catch (_) {
        // 기기 또는 브라우저의 오디오 실패는 퍼즐 진행을 방해하지 않는다.
      }
    });
  }

  void _enqueueEffect(Future<void> Function() operation) {
    _effectQueue = _effectQueue.then((_) async {
      try {
        await operation();
      } catch (_) {
        // 재생 실패는 다음 효과음 시도에 영향을 주지 않는다.
      }
    });
  }

  /// 웹 자동 재생 정책을 고려하여 첫 사용자 입력 이후 음악을 시작한다.
  void onUserInteraction() {
    if (_disposed) return;
    _interacted = true;
    _syncMusic();
  }

  void _syncMusic() {
    _enqueue(() async {
      final shouldPlay = !_disposed && _active && _interacted && _musicEnabled;
      if (shouldPlay && !_musicPlaying) {
        await backend.startMusic();
        _musicPlaying = true;
      } else if (!shouldPlay && _musicPlaying) {
        try {
          await backend.stopMusic();
        } finally {
          _musicPlaying = false;
        }
      }
    });
  }

  void setMusicEnabled(bool enabled) {
    if (_disposed) return;
    _musicEnabled = enabled;
    if (enabled) _interacted = true;
    _saveSetting(musicKey, enabled);
    _syncMusic();
  }

  void setEffectsEnabled(bool enabled) {
    if (_disposed) return;
    _effectsEnabled = enabled;
    _saveSetting(effectsKey, enabled);
    if (!enabled) _enqueueEffect(backend.stopEffects);
  }

  void _saveSetting(String key, bool value) {
    // 빠르게 연속 토글해도 마지막 설정이 저장되도록 직렬화한다.
    _settingsQueue = _settingsQueue.then((_) async {
      try {
        await _preferences?.setBool(key, value);
      } catch (_) {
        // 환경설정을 저장하지 못해도 해당 세션에서는 설정을 유지한다.
      }
    });
  }

  void play(SoundEffect effect) {
    if (_disposed || !_effectsEnabled || !_active) return;
    _enqueueEffect(() async {
      if (!_disposed && _effectsEnabled && _active) {
        await backend.playEffect(effect);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _active = state == AppLifecycleState.resumed;
    _syncMusic();
    if (!_active) _enqueueEffect(backend.stopEffects);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _syncMusic();
    _enqueueEffect(backend.stopEffects);
    await Future.wait([_queue, _effectQueue, _settingsQueue]);
    try {
      await backend.dispose();
    } catch (_) {
      // 플랫폼이 사라진 경우에도 안전하게 종료한다.
    }
  }
}
