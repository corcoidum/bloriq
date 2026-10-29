import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../audio/game_audio.dart';
import '../domain/puzzle.dart';
import '../progress/progress_repository.dart';

/// 홈과 게임은 하나의 기록/오디오 인스턴스를 공유한다.
class GameSession {
  GameSession({
    required List<Level> levels,
    required this.progress,
    required this.audio,
  }) : levels = List.unmodifiable(levels) {
    if (levels.isEmpty) throw const FormatException('No levels');
    WidgetsBinding.instance.addObserver(audio);
    audio.setGameVisible(false);
  }

  final List<Level> levels;
  final ProgressRepository progress;
  final GameAudio audio;

  static Future<GameSession> load({
    Future<List<Level>> Function()? loadLevels,
  }) async {
    final levels = loadLevels != null
        ? await loadLevels()
        : (jsonDecode(await rootBundle.loadString('assets/levels/levels.json'))
                  as List<dynamic>)
              .map((item) => Level.fromJson(item as Map<String, dynamic>))
              .toList();
    if (levels.isEmpty ||
        levels.map((level) => level.id).toSet().length != levels.length) {
      throw const FormatException('Empty or duplicate levels');
    }
    final progress = await ProgressRepository.load();
    final audio = await GameAudio.load();
    return GameSession(levels: levels, progress: progress, audio: audio);
  }

  int get nextLevelId => levels
      .firstWhere(
        (level) => progress.forLevel(level.id) == null,
        orElse: () => levels.first,
      )
      .id;

  int get completedCount =>
      levels.where((level) => progress.forLevel(level.id) != null).length;
  int get totalStars => levels.fold(
    0,
    (total, level) => total + (progress.forLevel(level.id)?.bestStars ?? 0),
  );

  Future<void> dispose() => audio.dispose();
}
