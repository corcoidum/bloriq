import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../world/world_catalog.dart';
import 'progression_rules.dart';

/// 레벨 업 한 번과 그때 받은 트랙 보상(20 초과 레벨은 null).
class LevelUp {
  const LevelUp(this.level, this.reward);
  final int level;
  final TrackReward? reward;

  @override
  String toString() => 'LevelUp($level, $reward)';
}

/// 경험치/별가루 획득 결과. 캠페인·일일 클리어 모두 이 형태로 돌려준다.
class ClearReward {
  const ClearReward({
    required this.starsAwarded,
    required this.firstClear,
    required this.xpGained,
    this.companionXpBonus = 0,
    required this.clearStardust,
    required this.levelsGained,
    required this.newPower,
    required this.bondLevelUp,
    required this.bareHanded,
    required this.newBareHanded,
    required this.newTrails,
    this.achievements = const [],
    required this.totalXp,
    required this.totalStardust,
    required this.standing,
    required this.saved,
  });

  /// 별빛 길 상한(2별)을 적용한 뒤의 별 수. 일일 클리어는 0.
  final int starsAwarded;
  final bool firstClear;
  final int xpGained;
  final int companionXpBonus;

  /// 클리어 자체의 별가루(숲 보너스 포함, 레벨 보상 제외).
  final int clearStardust;

  /// 이번에 새로 오른 레벨들(오름차순). 보상은 이미 적용되었다.
  final List<LevelUp> levelsGained;
  final PowerDefinition? newPower;

  /// 동행 정령의 유대 레벨이 올랐다면 새 레벨.
  final int? bondLevelUp;

  /// 이번 클리어가 맨손 별 조건을 만족하는지.
  final bool bareHanded;

  /// 이 단계의 맨손 별을 처음 얻었는지.
  final bool newBareHanded;

  /// 이번에 새로 얻은 궤적(레벨 보상 + 구름 유대).
  final List<String> newTrails;

  /// 이번 클리어로 달성한 별 모으기 업적(보상은 이미 적용되었다).
  final List<Achievement> achievements;
  final int totalXp, totalStardust;
  final LevelStanding standing;

  /// 저장에 성공했는지. 손상/미래 스키마 상태면 아무 것도 지급하지 않고 false.
  final bool saved;

  int get level => standing.level;

  /// 레벨 보상 별가루 합.
  int get trackStardust => levelsGained.fold(
    0,
    (sum, up) =>
        sum +
        (up.reward is StardustBundle
            ? (up.reward as StardustBundle).amount
            : 0),
  );

  Iterable<TrackReward> get _achievementRewards =>
      achievements.expand((achievement) => achievement.rewards);

  /// 업적 보상 별가루 합.
  int get achievementStardust => _achievementRewards.fold(
    0,
    (sum, reward) => sum + (reward is StardustBundle ? reward.amount : 0),
  );

  /// 클리어 별가루 + 레벨 보상 별가루 + 업적 별가루.
  int get stardustGained => clearStardust + trackStardust + achievementStardust;

  List<String> get newTitles => [
    for (final up in levelsGained)
      if (up.reward case TitleUnlock(:final titleId)) titleId,
    for (final reward in _achievementRewards)
      if (reward case TitleUnlock(:final titleId)) titleId,
  ];

  int get newStarlightCharges =>
      levelsGained.fold(
        0,
        (sum, up) =>
            sum +
            (up.reward is StarlightCharge
                ? (up.reward as StarlightCharge).charges
                : 0),
      ) +
      _achievementRewards.fold(
        0,
        (sum, reward) => sum + (reward is StarlightCharge ? reward.charges : 0),
      );
}

/// 기존 기록을 한 번만 성장 보상으로 환산한 결과.
class BackfillReward {
  const BackfillReward({
    required this.xpGained,
    required this.clearStardust,
    required this.levelsGained,
    required this.newPowers,
    required this.saved,
  });
  final int xpGained, clearStardust;
  final List<LevelUp> levelsGained;
  final List<PowerDefinition> newPowers;
  final bool saved;

  int get stardustGained =>
      clearStardust +
      levelsGained.fold(
        0,
        (sum, up) =>
            sum +
            (up.reward is StardustBundle
                ? (up.reward as StardustBundle).amount
                : 0),
      );
}

typedef BackfillRecord = ({String levelKey, int bestStars});

/// 플레이어 성장(경험치, 레벨, 별가루, 능력, 꾸미기, 유대, 맨손 별) 저장소.
///
/// 레벨은 경험치에서 계산하며 저장하지 않는다. 알 수 없는 필드는 보존하고,
/// 손상된 저장은 쓰지 않다가 [recover] 가 원문을 백업한 뒤에만 초기화한다.
class ProgressionRepository {
  ProgressionRepository._(this._preferences, this.writer);

  static const storageKey = 'bloriq.progression.v1';
  static const backupKey = 'bloriq.progression.corrupt-backup.v1';
  static const schemaVersion = 1;

  final SharedPreferences? _preferences;
  final Future<bool> Function(String, String)? writer;

  int _xp = 0, _stardust = 0, _charges = 0;
  final Set<int> _claimedLevels = {};
  final Set<int> _completedChapters = {};
  final Set<int> _goldenChapters = {};
  final Set<String> _ownedTrails = {defaultTrailId};
  final Set<String> _ownedTitles = {};
  final Map<String, int> _bonds = {};
  final Set<String> _bareHanded = {};
  final Set<String> _claimedAchievements = {};
  Map<int, int> _starflowersByWorld = const {};

  /// 단계 키(`id:revision`)별로 이미 보상한 최고 별 수. 백필 중복 방지용.
  final Map<String, int> _rewardedStars = {};

  /// 단계 키별로 도움(별빛 길 2, 풀이 따라 하기 1)을 쓰고 아직 깨지 않은 판의
  /// 별 상한. 다시 시작하거나 판을 나갔다 와도 남고, 그 판을 깨면 지운다.
  final Map<String, int> _assistCaps = {};

  /// 첫별자리 권능의 무료 별빛 길을 쓰고 아직 깨지 않은 판.
  final Set<String> _freeStarlightUsed = {};
  String _equippedTrail = defaultTrailId;
  String? _title, _raw;
  bool _backfilled = false;
  bool _endingSeen = false;
  Map<String, dynamic> _extra = {};

  bool saveFailed = false, corrupt = false, futureSchema = false;
  bool _writable = true;
  Future<void> _queue = Future.value();

  // ---- 읽기 -----------------------------------------------------------------

  bool get writable => _writable;
  int get xp => _xp;
  LevelStanding get standing => levelForXp(_xp);
  int get level => standing.level;
  int get stardust => _stardust;
  int get starlightCharges => _charges;
  Set<int> get claimedLevels => Set.unmodifiable(_claimedLevels);
  Set<int> get completedChapters => Set.unmodifiable(_completedChapters);
  Set<int> get goldenChapters => Set.unmodifiable(_goldenChapters);

  /// 획득한 능력(장 순서).
  List<PowerDefinition> get powers => [
    for (final power in powerCatalog)
      if (_completedChapters.contains(power.chapter)) power,
  ];
  bool hasPower(String id) => powers.any((p) => p.id == id);
  Set<String> get ownedTrails => Set.unmodifiable(_ownedTrails);
  String get equippedTrail => _equippedTrail;
  Set<String> get ownedTitles => Set.unmodifiable(_ownedTitles);
  String? get title => _title;

  /// 정령 ID → 동행 클리어 수.
  Map<String, int> get bonds => Map.unmodifiable(_bonds);
  int bondClears(String spiritId) => _bonds[spiritId] ?? 0;
  int bondLevel(String spiritId) => bondLevelForClears(bondClears(spiritId));
  Set<String> get bareHanded => Set.unmodifiable(_bareHanded);
  bool isBareHandedLevel(String levelKey) => _bareHanded.contains(levelKey);

  /// 이 판을 다음에 깰 때의 별 상한(도움을 안 썼으면 3).
  int assistCap(String levelKey) => _assistCaps[levelKey] ?? 3;

  /// 이 판에서 무료 별빛 길을 이미 썼는지(깰 때까지 유지).
  bool freeStarlightUsed(String levelKey) =>
      _freeStarlightUsed.contains(levelKey);
  bool get backfilled => _backfilled;
  bool get endingSeen => _endingSeen;

  Set<String> get claimedAchievements => Set.unmodifiable(_claimedAchievements);

  /// 한 세계에서 모은 별(판마다 보상한 최고 별의 합).
  int worldStars(int world) => _rewardedStars.entries
      .where((entry) {
        final id = int.tryParse(entry.key.split(':').first);
        return id != null && worldOfLevelId(id) == world;
      })
      .fold(0, (sum, entry) => sum + entry.value);

  /// 업적의 현재 진행 값.
  int achievementProgress(Achievement achievement) =>
      switch (achievement.kind) {
        AchievementKind.worldStars => worldStars(achievement.world!),
        AchievementKind.worldStarflowers =>
          _starflowersByWorld[achievement.world] ?? 0,
        AchievementKind.goldenConstellations => _goldenChapters.length,
        AchievementKind.bareHandedStars => _bareHanded.length,
        AchievementKind.worldGolden =>
          _goldenChapters
              .where((chapter) => worldOfChapter(chapter) == achievement.world)
              .length,
      };

  FamilyAbilities abilitiesFor({
    String? companionId,
    String? companionFamily,
  }) => FamilyAbilities.of(
    SpiritFamily.tryParse(companionFamily),
    companionId == null ? 0 : bondLevel(companionId),
  );

  // ---- 불러오기 ---------------------------------------------------------------

  static Future<ProgressionRepository> load([
    SharedPreferences? preferences,
    Future<bool> Function(String, String)? writer,
  ]) async {
    if (preferences == null) {
      try {
        preferences = await SharedPreferences.getInstance();
      } catch (_) {}
    }
    final repo = ProgressionRepository._(preferences, writer);
    try {
      final raw = preferences?.getString(storageKey);
      repo._raw = raw;
      if (raw != null) {
        final data = jsonDecode(raw);
        if (data is! Map || data['version'] is! int) {
          throw const FormatException('Progression schema');
        }
        if (data['version'] != schemaVersion) {
          repo.futureSchema = true;
          repo._writable = false;
        } else {
          repo._read(Map<String, dynamic>.from(data));
        }
      }
    } catch (_) {
      repo._reset();
      repo._writable = false;
      repo.corrupt = true;
    }
    repo.saveFailed = !repo._writable || preferences == null;
    return repo;
  }

  void _read(Map<String, dynamic> data) {
    int nonNegative(String key) {
      final value = data[key] ?? 0;
      if (value is! int || value < 0) throw FormatException(key);
      return value;
    }

    List<T> list<T>(String key) {
      final value = data[key] ?? const [];
      if (value is! List || value.any((e) => e is! T)) {
        throw FormatException(key);
      }
      return value.cast<T>();
    }

    Map<String, int> counts(String key) {
      final value = data[key] ?? const {};
      if (value is! Map ||
          value.entries.any(
            (e) => e.key is! String || e.value is! int || e.value < 0,
          )) {
        throw FormatException(key);
      }
      return value.cast<String, int>();
    }

    String? optionalString(String key) {
      final value = data[key];
      if (value != null && value is! String) throw FormatException(key);
      return value as String?;
    }

    if (data['backfilled'] != null && data['backfilled'] is! bool) {
      throw const FormatException('backfilled');
    }
    _xp = nonNegative('xp');
    _stardust = nonNegative('stardust');
    _charges = nonNegative('starlightCharges');
    _claimedLevels.addAll(list<int>('claimedLevels'));
    _completedChapters.addAll(list<int>('completedChapters'));
    _goldenChapters.addAll(list<int>('goldenChapters'));
    _ownedTrails.addAll(list<String>('ownedTrails'));
    _ownedTitles.addAll(list<String>('ownedTitles'));
    _bareHanded.addAll(list<String>('bareHanded'));
    _claimedAchievements.addAll(list<String>('claimedAchievements'));
    _bonds.addAll(counts('bonds'));
    _rewardedStars.addAll(counts('rewardedStars'));
    // 0.2 이후 필드. 없으면 빈 값으로 읽는다(옛 저장과 호환).
    for (final entry in counts('assistCaps').entries) {
      if (entry.value < 1 || entry.value > 2) {
        throw const FormatException('assistCaps');
      }
      _assistCaps[entry.key] = entry.value;
    }
    _freeStarlightUsed.addAll(list<String>('freeStarlightUsed'));
    final trail = optionalString('equippedTrail');
    _equippedTrail = trail != null && _ownedTrails.contains(trail)
        ? trail
        : defaultTrailId;
    final title = optionalString('title');
    _title = title != null && _ownedTitles.contains(title) ? title : null;
    _backfilled = data['backfilled'] == true;
    // 1.0 이전 저장에는 이 필드가 없다.
    _endingSeen = data['endingSeen'] == true;
    _extra = data;
  }

  void _reset() {
    _xp = 0;
    _stardust = 0;
    _charges = 0;
    _claimedLevels.clear();
    _completedChapters.clear();
    _goldenChapters.clear();
    _ownedTrails
      ..clear()
      ..add(defaultTrailId);
    _ownedTitles.clear();
    _bonds.clear();
    _bareHanded.clear();
    _claimedAchievements.clear();
    _rewardedStars.clear();
    _assistCaps.clear();
    _freeStarlightUsed.clear();
    _equippedTrail = defaultTrailId;
    _title = null;
    _backfilled = false;
    _endingSeen = false;
    _extra = {};
  }

  // ---- 지급 -------------------------------------------------------------------

  /// 캠페인 클리어 한 번을 기록하고 보상을 지급한다.
  ///
  /// [stars] 는 판정된 별 수이며 [usedStarlightPath] 이면 2별로 깎는다.
  /// 이 판에 저장된 도움 상한([assistCap])도 적용하고, 깼으므로 지운다.
  /// [previousBestStars] 가 null 이면 첫 클리어. 장 별자리가 이번에 완성되면
  /// [constellationCompletedChapter], 황금이 되면 [constellationGoldenChapter]
  /// 를 넘긴다(같은 장은 한 번만 지급된다). 월드 2는 맨손 판정이 달라
  /// (권능 미사용 + 맨손 최소 수) [bareHandedClear] 로 직접 넘긴다.
  Future<ClearReward> recordClear({
    required String levelKey,
    required int stars,
    required int? previousBestStars,
    bool usedHint = false,
    bool usedStarlightPath = false,
    String? companionId,
    String? companionFamily,
    int? constellationCompletedChapter,
    int? constellationGoldenChapter,
    bool? bareHandedClear,
    Map<int, int>? starflowersByWorld,
  }) async {
    if (starflowersByWorld != null) {
      _starflowersByWorld = Map.unmodifiable(starflowersByWorld);
    }
    final pendingCap = assistCap(levelKey);
    final assisted = usedStarlightPath || pendingCap < 3;
    final capped = capAssistedStars(stars, usedStarlightPath: assisted);
    final awarded = capped < pendingCap ? capped : pendingCap;
    final firstClear = previousBestStars == null;
    // 세계 2부터는 맨손 판정을 호출한 쪽이 한다. 저장된 도움이 있으면 맨손이 아니다.
    final bare = bareHandedClear != null
        ? bareHandedClear && !assisted
        : isBareHanded(
            stars: awarded,
            usedHint: usedHint,
            usedStarlightPath: assisted,
          );
    if (!_writable) {
      return _reward(starsAwarded: awarded, firstClear: firstClear, bare: bare);
    }

    // 유대 보너스는 이번 클리어 이전의 유대 레벨로 판단한다.
    final companionXpBonus =
        companionId != null &&
            firstClear &&
            !_rewardedStars.containsKey(levelKey)
        ? companionFirstClearXp(
            SpiritFamily.tryParse(companionFamily),
            bondLevel(companionId),
          )
        : 0;
    var xpGained =
        campaignClearXp(stars: awarded, previousBestStars: previousBestStars) +
        companionXpBonus;
    final abilities = abilitiesFor(
      companionId: companionId,
      companionFamily: companionFamily,
    );
    final dust = clearStardust(
      stars: awarded,
      previousBestStars: previousBestStars,
      forestBonus: abilities.stardustBonus,
    );
    _assistCaps.remove(levelKey);
    _freeStarlightUsed.remove(levelKey);

    PowerDefinition? newPower;
    if (constellationCompletedChapter != null &&
        _completedChapters.add(constellationCompletedChapter)) {
      xpGained += XpRules.constellationCompleted;
      newPower = powerForChapter(constellationCompletedChapter);
    }
    var goldenDust = 0;
    if (constellationGoldenChapter != null &&
        _goldenChapters.add(constellationGoldenChapter)) {
      xpGained += XpRules.constellationGolden;
      goldenDust = StardustRules.goldenConstellation;
    }

    final newTrails = <String>[];
    int? bondLevelUp;
    if (companionId != null) {
      final before = bondLevel(companionId);
      _bonds[companionId] = bondClears(companionId) + 1;
      final after = bondLevel(companionId);
      if (after > before) bondLevelUp = after;
      final unlocked = abilitiesFor(
        companionId: companionId,
        companionFamily: companionFamily,
      );
      if (unlocked.mistTrail && _ownedTrails.add(TrailIds.mist)) {
        newTrails.add(TrailIds.mist);
      }
    }

    final newBare = bare && _bareHanded.add(levelKey);
    final rewarded = [
      _rewardedStars[levelKey] ?? 0,
      previousBestStars ?? 0,
      awarded,
    ].reduce((a, b) => a > b ? a : b);
    _rewardedStars[levelKey] = rewarded;

    _xp += xpGained;
    _stardust += dust + goldenDust;
    final levels = _claimLevelRewards(newTrails);
    final reached = _claimAchievements(newTrails);
    if (constellationCompletedChapter != null &&
        worldOfChapter(constellationCompletedChapter) == Worlds.finalWorld &&
        _finalWorldComplete) {
      _grantSagaRewards(newTrails);
    }
    final saved = await retrySave();
    return _reward(
      starsAwarded: awarded,
      firstClear: firstClear,
      bare: bare,
      newBare: newBare,
      xpGained: xpGained,
      companionXpBonus: companionXpBonus,
      clearStardust: dust + goldenDust,
      achievements: reached,
      levels: levels,
      newPower: newPower,
      bondLevelUp: bondLevelUp,
      newTrails: newTrails,
      saved: saved,
    );
  }

  bool get _finalWorldComplete =>
      Worlds.isComplete(Worlds.finalWorld, _completedChapters);

  void _grantSagaRewards(List<String> newTrails) {
    for (final reward in sagaCompletionRewards) {
      _apply(reward, newTrails);
    }
  }

  Future<bool> markEndingSeen() {
    if (!_writable || !_finalWorldComplete) return Future.value(false);
    _endingSeen = true;
    // 7-C에서 이미 세계 7을 마친 저장에도 같은 완료 보상을 지급한다.
    _grantSagaRewards([]);
    return retrySave();
  }

  /// 일일 퍼즐 클리어. [streak] 는 오늘을 포함한 연속 일수.
  Future<ClearReward> recordDailyClear(int streak) async {
    if (!_writable) {
      return _reward(starsAwarded: 0, firstClear: false, bare: false);
    }
    final xpGained = dailyClearXp(streak);
    _xp += xpGained;
    final newTrails = <String>[];
    final levels = _claimLevelRewards(newTrails);
    final saved = await retrySave();
    return _reward(
      starsAwarded: 0,
      firstClear: false,
      bare: false,
      xpGained: xpGained,
      levels: levels,
      newTrails: newTrails,
      saved: saved,
    );
  }

  /// 기존 진행 기록을 한 번만 성장 보상으로 환산한다. 이미 했으면 null.
  ///
  /// 각 기록은 최고 별로 첫 클리어한 것처럼 계산하되, [recordClear] 로 이미
  /// 보상한 단계는 그 차이만 지급한다. 완성된 장은 별자리 경험치와 능력을,
  /// 황금 장은 황금 경험치를 준다.
  Future<BackfillReward?> backfill({
    required Iterable<BackfillRecord> records,
    required Set<int> completedChapters,
    required Set<int> goldenChapters,
  }) async {
    if (!_writable || _backfilled) return null;
    var xpGained = 0, dust = 0;
    for (final record in records) {
      final best = record.bestStars;
      if (best < 1 || best > 3) continue;
      final previous = _rewardedStars[record.levelKey];
      if (previous != null && previous >= best) continue;
      xpGained += campaignClearXp(stars: best, previousBestStars: previous);
      if (previous == null) {
        dust += clearStardust(stars: best);
      }
      _rewardedStars[record.levelKey] = best;
    }
    final newPowers = <PowerDefinition>[];
    final chapters = {...completedChapters, ...goldenChapters}.toList()..sort();
    for (final chapter in chapters) {
      if (_completedChapters.add(chapter)) {
        xpGained += XpRules.constellationCompleted;
        final power = powerForChapter(chapter);
        if (power != null) newPowers.add(power);
      }
    }
    for (final chapter in goldenChapters.toList()..sort()) {
      if (_goldenChapters.add(chapter)) {
        xpGained += XpRules.constellationGolden;
        dust += StardustRules.goldenConstellation;
      }
    }
    _backfilled = true;
    _xp += xpGained;
    _stardust += dust;
    final levels = _claimLevelRewards([]);
    final saved = await retrySave();
    return BackfillReward(
      xpGained: xpGained,
      clearStardust: dust,
      levelsGained: levels,
      newPowers: newPowers,
      saved: saved,
    );
  }

  /// ProgressRepository의 저장을 기준으로 이전 기록과 미지급 보상을 복구한다.
  Future<void> reconcileStarflowerAchievements(Map<int, int> totals) async {
    _starflowersByWorld = Map.unmodifiable(totals);
    if (!_writable) return;
    final reached = _claimAchievements(
      [],
      only: AchievementKind.worldStarflowers,
    );
    if (reached.isNotEmpty) await retrySave();
  }

  // ---- 소비와 꾸미기 ---------------------------------------------------------

  /// 별가루가 충분하면 차감하고 true.
  Future<bool> spendStardust(int amount) async {
    if (!_writable || amount < 0 || amount > _stardust) return false;
    _stardust -= amount;
    await retrySave();
    return true;
  }

  /// 별빛 공방에서 잔영을 산다. 이미 가졌거나 별가루가 모자라면 false.
  /// 사면 바로 장착한다.
  Future<bool> buyTrail(String trailId) async {
    final item = shopItemFor(trailId);
    if (!_writable ||
        item == null ||
        _ownedTrails.contains(trailId) ||
        item.price > _stardust) {
      return false;
    }
    _stardust -= item.price;
    _ownedTrails.add(trailId);
    _equippedTrail = trailId;
    await retrySave();
    return true;
  }

  /// 풀이 따라 하기처럼 별빛 길 밖의 도움을 이 판에 기록한다.
  /// 상한은 더 낮은 쪽을 남긴다.
  Future<bool> markAssist(String levelKey, int cap) async {
    if (!_writable || cap < 1 || cap > 2) return false;
    if (assistCap(levelKey) <= cap) return true;
    _assistCaps[levelKey] = cap;
    return retrySave();
  }

  /// 지금 별빛 길을 쓰면 어떤 수단으로 얼마를 내는지.
  /// [freeUsedThisAttempt] 는 이번 시도에서 무료 사용을 이미 했는지(UI 상태).
  /// [levelKey] 를 주면 그 판에서 이미 쓴 무료 사용도 센다.
  StarlightPathQuote quoteStarlightPath({
    required bool freeUsedThisAttempt,
    String? levelKey,
    String? companionId,
    String? companionFamily,
  }) => starlightPathQuote(
    powerUnlocked: hasPower(PowerIds.starlightPath),
    freeUsedThisAttempt:
        freeUsedThisAttempt ||
        (levelKey != null && _freeStarlightUsed.contains(levelKey)),
    charges: _charges,
    goldenConstellations: _goldenChapters.length,
    starlightDiscount: abilitiesFor(
      companionId: companionId,
      companionFamily: companionFamily,
    ).starlightDiscount,
  );

  /// 별빛 길을 결제한다. 별가루가 모자라면 null(변화 없음).
  /// 성공하면 이번 클리어는 [recordClear] 에 `usedStarlightPath: true` 로 넘긴다.
  /// [levelKey] 를 주면(캠페인) 그 판에 2별 상한과 무료 사용을 저장해서,
  /// 다시 시작하거나 판을 나갔다 와도 지워지지 않는다.
  /// [onUsed]는 비용을 확정한 직후 저장을 기다리기 전에 실행된다.
  Future<StarlightPathQuote?> useStarlightPath({
    required bool freeUsedThisAttempt,
    String? levelKey,
    String? companionId,
    String? companionFamily,
    void Function(StarlightPathQuote)? onUsed,
  }) async {
    if (!_writable) return null;
    final quote = quoteStarlightPath(
      freeUsedThisAttempt: freeUsedThisAttempt,
      levelKey: levelKey,
      companionId: companionId,
      companionFamily: companionFamily,
    );
    if (quote.source == StarlightPathSource.stardust &&
        quote.cost > _stardust) {
      return null;
    }
    if (levelKey != null) {
      if (assistCap(levelKey) > StarlightPathRules.assistedStarCap) {
        _assistCaps[levelKey] = StarlightPathRules.assistedStarCap;
      }
      if (quote.source == StarlightPathSource.free) {
        _freeStarlightUsed.add(levelKey);
      }
    }
    switch (quote.source) {
      case StarlightPathSource.free:
        onUsed?.call(quote);
        if (levelKey != null) await retrySave();
        return quote;
      case StarlightPathSource.charge:
        _charges--;
      case StarlightPathSource.stardust:
        _stardust -= quote.cost;
    }
    onUsed?.call(quote);
    await retrySave();
    return quote;
  }

  Future<bool> equipTrail(String id) async {
    if (!_writable || !_ownedTrails.contains(id)) return false;
    _equippedTrail = id;
    return retrySave();
  }

  /// 보유한 칭호를 고른다. null 이면 칭호를 내린다.
  Future<bool> setTitle(String? id) async {
    if (!_writable || (id != null && !_ownedTitles.contains(id))) {
      return false;
    }
    _title = id;
    return retrySave();
  }

  // ---- 내부 -------------------------------------------------------------------

  /// 별바다 항해 한 번을 마쳤을 때. [rewards] 는 이번에 처음 넘은 이정표 보상이다.
  Future<ClearReward> recordVoyage({
    required int xp,
    required int stardust,
    List<TrackReward> rewards = const [],
  }) async {
    if (!_writable) {
      return _reward(starsAwarded: 0, firstClear: false, bare: false);
    }
    _xp += xp;
    _stardust += stardust;
    final newTrails = <String>[];
    for (final reward in rewards) {
      _apply(reward, newTrails);
    }
    final levels = _claimLevelRewards(newTrails);
    final saved = await retrySave();
    return _reward(
      starsAwarded: 0,
      firstClear: false,
      bare: false,
      xpGained: xp,
      clearStardust: stardust,
      levels: levels,
      newTrails: newTrails,
      saved: saved,
    );
  }

  /// 현재 레벨까지 아직 받지 않은 레벨 보상을 모두 적용한다.
  List<LevelUp> _claimLevelRewards(List<String> newTrails) {
    final current = level;
    final gained = <LevelUp>[];
    for (var l = 2; l <= current; l++) {
      if (!_claimedLevels.add(l)) continue;
      final reward = rewardForLevel(l);
      if (reward != null) _apply(reward, newTrails);
      gained.add(LevelUp(l, reward));
    }
    return gained;
  }

  /// 목표에 닿았지만 아직 받지 않은 업적 보상을 모두 적용한다.
  /// 업데이트 전에 이미 모은 별도 다음 클리어 때 한꺼번에 받는다.
  List<Achievement> _claimAchievements(
    List<String> newTrails, {
    AchievementKind? only,
  }) {
    final reached = <Achievement>[];
    for (final achievement in achievements) {
      if ((only != null && achievement.kind != only) ||
          achievementProgress(achievement) < achievement.target ||
          !_claimedAchievements.add(achievement.id)) {
        continue;
      }
      for (final reward in achievement.rewards) {
        _apply(reward, newTrails);
      }
      reached.add(achievement);
    }
    return reached;
  }

  void _apply(TrackReward reward, List<String> newTrails) {
    switch (reward) {
      case StardustBundle(:final amount):
        _stardust += amount;
      case TrailUnlock(:final trailId):
        if (_ownedTrails.add(trailId)) newTrails.add(trailId);
      case TitleUnlock(:final titleId):
        _ownedTitles.add(titleId);
        _title ??= titleId;
      case StarlightCharge(:final charges):
        _charges += charges;
    }
  }

  ClearReward _reward({
    required int starsAwarded,
    required bool firstClear,
    required bool bare,
    bool newBare = false,
    int xpGained = 0,
    int companionXpBonus = 0,
    int clearStardust = 0,
    List<LevelUp> levels = const [],
    PowerDefinition? newPower,
    int? bondLevelUp,
    List<String> newTrails = const [],
    List<Achievement> achievements = const [],
    bool saved = false,
  }) => ClearReward(
    starsAwarded: starsAwarded,
    firstClear: firstClear,
    xpGained: xpGained,
    companionXpBonus: companionXpBonus,
    clearStardust: clearStardust,
    levelsGained: List.unmodifiable(levels),
    newPower: newPower,
    bondLevelUp: bondLevelUp,
    bareHanded: bare,
    newBareHanded: newBare,
    newTrails: List.unmodifiable(newTrails),
    achievements: List.unmodifiable(achievements),
    totalXp: _xp,
    totalStardust: _stardust,
    standing: standing,
    saved: saved,
  );

  Map<String, dynamic> _snapshot() => {
    ..._extra,
    'version': schemaVersion,
    'xp': _xp,
    'stardust': _stardust,
    'starlightCharges': _charges,
    'claimedLevels': _claimedLevels.toList()..sort(),
    'completedChapters': _completedChapters.toList()..sort(),
    'goldenChapters': _goldenChapters.toList()..sort(),
    'ownedTrails': _ownedTrails.toList()..sort(),
    'equippedTrail': _equippedTrail,
    'ownedTitles': _ownedTitles.toList()..sort(),
    'title': _title,
    'bonds': Map.fromEntries(
      _bonds.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'bareHanded': _bareHanded.toList()..sort(),
    'claimedAchievements': _claimedAchievements.toList()..sort(),
    'rewardedStars': Map.fromEntries(
      _rewardedStars.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'backfilled': _backfilled,
    'endingSeen': _endingSeen,
    'assistCaps': Map.fromEntries(
      _assistCaps.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
    'freeStarlightUsed': _freeStarlightUsed.toList()..sort(),
  };

  Future<bool> retrySave() async {
    final snapshot = jsonEncode(_snapshot());
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

  /// 손상된 원문 백업이 성공한 경우에만 초기화한다. 이후 [backfill] 을 다시
  /// 호출하면 진행 기록에서 성장 보상이 복구된다.
  Future<bool> recover() async {
    if (!corrupt || futureSchema || _preferences == null || _raw == null) {
      return false;
    }
    try {
      final backup =
          await (writer?.call(backupKey, _raw!) ??
              _preferences.setString(backupKey, _raw!));
      if (!backup) return false;
    } catch (_) {
      return false;
    }
    _reset();
    _writable = true;
    corrupt = false;
    return retrySave();
  }

  Future<void> flush() => _queue;
}
