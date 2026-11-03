import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';
import '../l10n/app_localizations.dart';
import 'progress_repository.dart';

/// 한 판의 점수. 어떤 모드든 이동 수와 난이도만으로 결정된다.
class RunScore {
  const RunScore({
    required this.base,
    required this.starMultiplier,
    required this.comboMultiplier,
  });

  factory RunScore.of({
    required int minimumMoves,
    required int stars,
    double combo = 1,
  }) => RunScore(
    base: 50 + minimumMoves * 10,
    starMultiplier: switch (stars) {
      3 => 2.0,
      2 => 1.5,
      _ => 1.0,
    },
    comboMultiplier: combo,
  );

  final int base;
  final double starMultiplier;
  final double comboMultiplier;

  int get total => (base * starMultiplier * comboMultiplier).round();
}

/// 경험치에서 계산한 레벨. 레벨 자체는 저장하지 않는다.
class PlayerLevel {
  const PlayerLevel._(this.level, this.into, this.needed);

  factory PlayerLevel.fromXp(int xp) {
    var level = 1;
    var left = math.max(0, xp);
    while (left >= xpForLevel(level)) {
      left -= xpForLevel(level);
      level++;
    }
    return PlayerLevel._(level, left, xpForLevel(level));
  }

  /// 이 레벨에서 다음 레벨로 오르는 데 필요한 경험치.
  static int xpForLevel(int level) => 300 + 100 * (level - 1);

  final int level;
  final int into;
  final int needed;

  double get fraction => into / needed;

  String title(AppLocalizations t) => level >= 30
      ? t.playerTitle6
      : level >= 20
      ? t.playerTitle5
      : level >= 15
      ? t.playerTitle4
      : level >= 10
      ? t.playerTitle3
      : level >= 5
      ? t.playerTitle2
      : t.playerTitle1;
}

/// 한 번의 지급 결과. 결과 화면이 경험치 바와 레벨업 연출에 쓴다.
class XpAward {
  const XpAward({
    required this.gained,
    required this.before,
    required this.after,
    required this.saved,
  });
  final int gained;
  final PlayerLevel before;
  final PlayerLevel after;
  final bool saved;
  bool get leveledUp => after.level > before.level;
}

/// 경험치를 보관한다. 손상되거나 미래 버전인 기록은 덮어쓰지 않는다.
class PlayerRepository {
  PlayerRepository._(this._preferences, this.writer);

  static const storageKey = 'bloriq.player.v1';
  static const schemaVersion = 1;

  /// 그냥 다시 깬 판의 경험치 비율. 무한 파밍을 막는다.
  static const replayRate = .25;

  final SharedPreferences? _preferences;
  final Future<bool> Function(String, String)? writer;
  Future<void> _queue = Future.value();
  int _xp = 0;
  bool _writable = true;
  bool saveFailed = false;

  int get xp => _xp;
  PlayerLevel get level => PlayerLevel.fromXp(_xp);

  /// 처음 불러오면 기존 기록의 별을 경험치로 한 번만 환산한다.
  static Future<PlayerRepository> load(
    List<Level> levels,
    ProgressRepository progress, {
    Future<bool> Function(String, String)? writer,
  }) async {
    SharedPreferences? preferences;
    try {
      preferences = await SharedPreferences.getInstance();
    } catch (_) {}
    final repo = PlayerRepository._(preferences, writer);
    String? raw;
    try {
      raw = preferences?.getString(storageKey);
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map ||
            data['version'] != schemaVersion ||
            data['xp'] is! int ||
            (data['xp'] as int) < 0) {
          throw const FormatException('Player schema');
        }
        repo._xp = data['xp'] as int;
      }
    } catch (_) {
      repo._writable = false;
      repo.saveFailed = true;
      return repo;
    }
    if (raw == null) {
      for (final level in levels) {
        final record = progress.forLevel(level.id, revision: level.revision);
        if (record == null) continue;
        repo._xp += RunScore.of(
          minimumMoves: level.minimumMoves,
          stars: record.bestStars,
        ).total;
      }
      await repo.retrySave();
    }
    if (preferences == null) repo.saveFailed = true;
    return repo;
  }

  Future<XpAward> award(int gained) async {
    final before = level;
    _xp += math.max(0, gained);
    final saved = await retrySave();
    return XpAward(gained: gained, before: before, after: level, saved: saved);
  }

  Future<bool> retrySave() async {
    final snapshot = jsonEncode({'version': schemaVersion, 'xp': _xp});
    var saved = false;
    final task = _queue.then((_) async {
      if (!_writable || _preferences == null) return;
      try {
        saved =
            await (writer?.call(storageKey, snapshot) ??
                _preferences.setString(storageKey, snapshot));
      } catch (_) {}
    });
    _queue = task;
    await task;
    saveFailed = !saved;
    return saved;
  }

  Future<void> flush() => _queue;
}
