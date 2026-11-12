/// 성장 규칙: 경험치, 레벨 곡선, 별가루, 보상 트랙, 능력, 유대.
///
/// 위젯이나 저장소에 의존하지 않는 순수 규칙만 둔다. 숫자를 바꿀 때는
/// test/progression_rules_test.dart 의 기대값도 함께 바꾼다.
library;

/// 한국어/영어 표시 문자열.
class ProgressionText {
  const ProgressionText(this.ko, this.en);
  final String ko, en;

  String resolve(String languageCode) => languageCode == 'ko' ? ko : en;
}

// ---------------------------------------------------------------------------
// 경험치
// ---------------------------------------------------------------------------

abstract final class XpRules {
  static const firstClearBase = 40;
  static const firstClearPerStar = 10;
  static const upgradePerStar = 15;
  static const replayClear = 5;
  static const dailyBase = 30;
  static const dailyPerStreakDay = 5;
  static const dailyStreakBonusCap = 25;
  static const constellationCompleted = 120;
  static const constellationGolden = 200;
  static const companionFirstClear = 5;
  static const maxBondFirstClear = 10;
  static const letterBondFirstClear = 5;
}

/// 캠페인 클리어 경험치. [previousBestStars] 가 null 이면 첫 클리어다.
int campaignClearXp({required int stars, int? previousBestStars}) {
  _checkStars(stars);
  if (previousBestStars == null) {
    return XpRules.firstClearBase + XpRules.firstClearPerStar * stars;
  }
  if (stars > previousBestStars) {
    return XpRules.upgradePerStar * (stars - previousBestStars);
  }
  return XpRules.replayClear;
}

/// 일일 퍼즐 경험치. [streak] 는 오늘을 포함한 연속 일수다.
int dailyClearXp(int streak) {
  final extraDays = streak < 1 ? 0 : streak - 1;
  final bonus = XpRules.dailyPerStreakDay * extraDays;
  return XpRules.dailyBase +
      (bonus > XpRules.dailyStreakBonusCap
          ? XpRules.dailyStreakBonusCap
          : bonus);
}

// ---------------------------------------------------------------------------
// 레벨 곡선
// ---------------------------------------------------------------------------

/// [level] 에서 다음 레벨로 오르는 데 필요한 경험치: 100 + 40*(n-1).
int xpToNextLevel(int level) {
  if (level < 1) throw ArgumentError.value(level, 'level');
  return 100 + 40 * (level - 1);
}

/// 레벨 1에서 [level] 에 도달하기까지의 누적 경험치.
int totalXpForLevel(int level) {
  if (level < 1) throw ArgumentError.value(level, 'level');
  final n = level - 1;
  return 100 * n + 20 * n * (n - 1);
}

/// 누적 경험치로 계산한 현재 레벨과 레벨 안의 진행도.
class LevelStanding {
  const LevelStanding({
    required this.level,
    required this.xpIntoLevel,
    required this.xpForNextLevel,
  });
  final int level, xpIntoLevel, xpForNextLevel;

  /// 0.0 이상 1.0 미만.
  double get progress => xpIntoLevel / xpForNextLevel;
  int get xpRemaining => xpForNextLevel - xpIntoLevel;

  @override
  bool operator ==(Object other) =>
      other is LevelStanding &&
      other.level == level &&
      other.xpIntoLevel == xpIntoLevel &&
      other.xpForNextLevel == xpForNextLevel;

  @override
  int get hashCode => Object.hash(level, xpIntoLevel, xpForNextLevel);

  @override
  String toString() =>
      'LevelStanding(level: $level, $xpIntoLevel/$xpForNextLevel)';
}

LevelStanding levelForXp(int xp) {
  var level = 1;
  var remaining = xp < 0 ? 0 : xp;
  while (remaining >= xpToNextLevel(level)) {
    remaining -= xpToNextLevel(level);
    level++;
  }
  return LevelStanding(
    level: level,
    xpIntoLevel: remaining,
    xpForNextLevel: xpToNextLevel(level),
  );
}

// ---------------------------------------------------------------------------
// 별가루
// ---------------------------------------------------------------------------

abstract final class StardustRules {
  static const perStar = 5;
  static const firstClearBonus = 10;

  /// 이미 깬 판을 별을 늘리지 못하고 다시 깼을 때.
  static const replayClear = 1;

  /// 황금 별자리(장의 다섯 판 모두 3별)를 처음 만들 때마다.
  static const goldenConstellation = 100;

  /// 숲 계열 유대 Lv3 보너스(+20%, 올림).
  static const forestBonusPercent = 20;
}

/// 클리어 한 번의 별가루. [previousBestStars] 가 null 이면 첫 클리어다.
///
/// 첫 클리어는 별마다 5 + 10, 별을 늘린 재도전은 늘어난 별마다 5,
/// 별을 늘리지 못한 재도전은 1. 그래서 한 판에서 받는 별가루는 어떤 순서로
/// 깨도 최대 25로 같고, 쉬운 판을 되풀이해도 거의 쌓이지 않는다.
/// [forestBonus] 는 숲 계열 유대 능력이다.
int clearStardust({
  required int stars,
  int? previousBestStars,
  bool forestBonus = false,
}) {
  _checkStars(stars);
  final int base;
  if (previousBestStars == null) {
    base = StardustRules.perStar * stars + StardustRules.firstClearBonus;
  } else if (stars > previousBestStars) {
    base = StardustRules.perStar * (stars - previousBestStars);
  } else {
    base = StardustRules.replayClear;
  }
  return forestBonus ? applyForestBonus(base) : base;
}

/// [amount] 에 20% 를 더하고 올림한다.
int applyForestBonus(int amount) {
  final scaled = amount * (100 + StardustRules.forestBonusPercent);
  return (scaled + 99) ~/ 100;
}

// ---------------------------------------------------------------------------
// 꾸미기: 궤적과 칭호
// ---------------------------------------------------------------------------

class TrailDefinition {
  const TrailDefinition(this.id, this.name);
  final String id;
  final ProgressionText name;
}

abstract final class TrailIds {
  static const moonlight = 'moonlight';
  static const petal = 'petal';
  static const firefly = 'firefly';
  static const meteor = 'meteor';
  static const mist = 'mist';
  static const aurora = 'aurora';
  static const starfall = 'starfall';
  static const firstStarlight = 'first_starlight';

  /// 별바다 항해 25판 이정표.
  static const tide = 'tide';

  // 별빛 공방에서 별가루로 사는 잔영.
  static const rose = 'rose';
  static const ember = 'ember';
  static const lilac = 'lilac';
  static const jade = 'jade';
  static const silver = 'silver';

  // 한 세계의 별자리 다섯 개를 모두 황금으로 만들면 받는 잔영.
  static const goldForest = 'gold_forest';
  static const goldCloud = 'gold_cloud';
  static const goldMirror = 'gold_mirror';

  static const cloudBloom = 'cloud_bloom';
  static const lakeBloom = 'lake_bloom';
  static const brassBloom = 'brass_bloom';
  static const frostBloom = 'frost_bloom';
  static const inkBloom = 'ink_bloom';
  static const starBloom = 'star_bloom';

  static const weeklyMoonlight = 'weekly_moonlight';
  static const weeklyRipple = 'weekly_ripple';
  static const weeklyAmber = 'weekly_amber';
  static const weeklyFrost = 'weekly_frost';
  static const weeklyNebula = 'weekly_nebula';
  static const weeklyDaybreak = 'weekly_daybreak';

  static bool isGolden(String id) => id.startsWith('gold_');
}

const defaultTrailId = TrailIds.moonlight;

const _baseTrails = <TrailDefinition>[
  TrailDefinition(TrailIds.moonlight, ProgressionText('달빛', 'Moonlight')),
  TrailDefinition(TrailIds.petal, ProgressionText('꽃잎', 'Petal')),
  TrailDefinition(TrailIds.firefly, ProgressionText('반딧불', 'Firefly')),
  TrailDefinition(TrailIds.meteor, ProgressionText('유성', 'Meteor')),
  TrailDefinition(TrailIds.mist, ProgressionText('안개', 'Mist')),
  TrailDefinition(TrailIds.aurora, ProgressionText('오로라', 'Aurora')),
  TrailDefinition(TrailIds.starfall, ProgressionText('별비', 'Starfall')),
  TrailDefinition(
    TrailIds.firstStarlight,
    ProgressionText('첫 별빛', 'First Starlight'),
  ),
  TrailDefinition(TrailIds.tide, ProgressionText('물결', 'Tide')),
  TrailDefinition(TrailIds.rose, ProgressionText('장밋빛', 'Rose')),
  TrailDefinition(TrailIds.ember, ProgressionText('불씨', 'Ember')),
  TrailDefinition(TrailIds.lilac, ProgressionText('라일락', 'Lilac')),
  TrailDefinition(TrailIds.jade, ProgressionText('비취', 'Jade')),
  TrailDefinition(TrailIds.silver, ProgressionText('은하수', 'Silver Way')),
  TrailDefinition(
    TrailIds.goldForest,
    ProgressionText('황금 달빛', 'Golden Moonlight'),
  ),
  TrailDefinition(TrailIds.goldCloud, ProgressionText('황금 구름', 'Golden Cloud')),
  TrailDefinition(
    TrailIds.goldMirror,
    ProgressionText('황금 물결', 'Golden Ripple'),
  ),
  TrailDefinition(TrailIds.cloudBloom, ProgressionText('구름꽃', 'Cloud Bloom')),
  TrailDefinition(TrailIds.lakeBloom, ProgressionText('물빛꽃', 'Lake Bloom')),
  TrailDefinition(TrailIds.brassBloom, ProgressionText('금빛 꽃잎', 'Brass Bloom')),
  TrailDefinition(TrailIds.frostBloom, ProgressionText('서리꽃', 'Frost Bloom')),
  TrailDefinition(TrailIds.inkBloom, ProgressionText('잉크꽃', 'Ink Bloom')),
  TrailDefinition(TrailIds.starBloom, ProgressionText('별빛 꽃잎', 'Star Bloom')),
  TrailDefinition(
    TrailIds.weeklyMoonlight,
    ProgressionText('은월빛', 'Silver Moonlight'),
  ),
  TrailDefinition(
    TrailIds.weeklyRipple,
    ProgressionText('물빛 별무리', 'Ripple Stars'),
  ),
  TrailDefinition(
    TrailIds.weeklyAmber,
    ProgressionText('호박 별빛', 'Amber Stars'),
  ),
  TrailDefinition(
    TrailIds.weeklyFrost,
    ProgressionText('서리 별빛', 'Frost Starlight'),
  ),
  TrailDefinition(
    TrailIds.weeklyNebula,
    ProgressionText('보랏빛 성운', 'Violet Nebula'),
  ),
  TrailDefinition(TrailIds.weeklyDaybreak, ProgressionText('첫새벽', 'Daybreak')),
];

/// 별빛 공방: 별가루로 사는 잔영과 값. 세계 하나(별가루 약 1,700)를
/// 다 깨면 두세 개를 살 수 있는 정도로 맞췄다.
class ShopItem {
  const ShopItem(this.trailId, this.price);
  final String trailId;
  final int price;
}

const trailShop = <ShopItem>[
  ShopItem(TrailIds.rose, 300),
  ShopItem(TrailIds.ember, 400),
  ShopItem(TrailIds.lilac, 500),
  ShopItem(TrailIds.jade, 800),
  ShopItem(TrailIds.silver, 1200),
];

ShopItem? shopItemFor(String trailId) {
  for (final item in trailShop) {
    if (item.trailId == trailId) return item;
  }
  return null;
}

abstract final class ShopText {
  static const heading = ProgressionText('별빛 공방', 'Starlight Workshop');
  static const intro = ProgressionText(
    '별가루로 새 이동 잔영을 살 수 있어요',
    'Trade stardust for new move trails',
  );
  static const owned = ProgressionText('가졌어요', 'Owned');
  static const bought = ProgressionText('새 잔영을 달았어요', 'New trail equipped');
  static const short = ProgressionText('별가루가 모자라요', 'Not enough stardust');
}

TrailDefinition? trailById(String? id) {
  for (final trail in trails) {
    if (trail.id == id) return trail;
  }
  return null;
}

class TitleDefinition {
  const TitleDefinition(this.id, this.name);
  final String id;
  final ProgressionText name;
}

const _baseTitles = <TitleDefinition>[
  TitleDefinition(
    'crescent_apprentice',
    ProgressionText('초승달 견습생', 'Crescent Apprentice'),
  ),
  TitleDefinition('garden_keeper', ProgressionText('정원지기', 'Garden Keeper')),
  TitleDefinition(
    'star_navigator',
    ProgressionText('별길 항해사', 'Star Navigator'),
  ),
  TitleDefinition('spirit_friend', ProgressionText('정령의 벗', 'Spirit Friend')),
  TitleDefinition('moon_guardian', ProgressionText('달의 수호자', 'Moon Guardian')),
  // 별 모으기 업적 칭호
  TitleDefinition(
    'forest_star_keeper',
    ProgressionText('달빛 숲의 별지기', 'Star Keeper of the Forest'),
  ),
  TitleDefinition(
    'lighthouse_star_keeper',
    ProgressionText('구름바다의 별지기', 'Star Keeper of the Cloud Sea'),
  ),
  TitleDefinition(
    'mirror_lake_keeper',
    ProgressionText('호수의 거울지기', 'Mirror Keeper of the Lake'),
  ),
  TitleDefinition(
    'clocktower_bellkeeper',
    ProgressionText('멈춘 시각의 종지기', 'Bellkeeper of the Still Hour'),
  ),
  TitleDefinition(
    'frost_memory_keeper',
    ProgressionText('서리 속 기억 지기', 'Keeper of Frostbound Memories'),
  ),
  TitleDefinition(
    'first_echo_librarian',
    ProgressionText('첫 잔상의 사서', 'Librarian of the First Echo'),
  ),
  TitleDefinition(
    sagaCompletionTitleId,
    ProgressionText('첫 별의 잔상', 'Echo of the First Star'),
  ),
  TitleDefinition('golden_first', ProgressionText('첫 황금 별자리', 'First Gold')),
  TitleDefinition(
    'golden_collector',
    ProgressionText('황금 별자리 수집가', 'Gold Collector'),
  ),
  TitleDefinition(
    'golden_sky',
    ProgressionText('황금 하늘지기', 'Keeper of the Gold Sky'),
  ),
  TitleDefinition(
    'barehand_explorer',
    ProgressionText('맨손 탐험가', 'Bare-Handed Explorer'),
  ),
  TitleDefinition(
    'barehand_artisan',
    ProgressionText('맨손 장인', 'Bare-Handed Artisan'),
  ),
  TitleDefinition(
    'barehand_legend',
    ProgressionText('맨손 전설', 'Bare-Handed Legend'),
  ),
  // 별바다 항해 이정표 칭호
  TitleDefinition(
    'voyage_sailor',
    ProgressionText('별바다 견습 항해사', 'Starsea Deckhand'),
  ),
  TitleDefinition(
    'voyage_captain',
    ProgressionText('별바다 선장', 'Starsea Captain'),
  ),
  TitleDefinition(
    'voyage_endless',
    ProgressionText('끝없는 항해자', 'Endless Voyager'),
  ),
  TitleDefinition(
    'cloud_bloom_keeper',
    ProgressionText('구름꽃 정원지기', 'Cloud Bloom Gardener'),
  ),
  TitleDefinition(
    'lake_bloom_keeper',
    ProgressionText('물빛꽃 정원지기', 'Lake Bloom Gardener'),
  ),
  TitleDefinition(
    'brass_bloom_keeper',
    ProgressionText('금빛 꽃잎의 종지기', 'Brass Bloom Bellkeeper'),
  ),
  TitleDefinition(
    'frost_bloom_keeper',
    ProgressionText('서리꽃 지기', 'Frost Bloom Keeper'),
  ),
  TitleDefinition(
    'ink_bloom_keeper',
    ProgressionText('잉크꽃의 사서', 'Ink Bloom Librarian'),
  ),
  TitleDefinition(
    'star_bloom_keeper',
    ProgressionText('첫 별의 정원지기', 'Gardener of the First Star'),
  ),
  TitleDefinition(
    'weekly_dawn_keeper',
    ProgressionText('새벽 별자리지기', 'Dawn Sky Keeper'),
  ),
  TitleDefinition(
    'weekly_star_friend',
    ProgressionText('길 잃은 별의 벗', 'Friend of Wandering Stars'),
  ),
  TitleDefinition(
    'weekly_chronicler',
    ProgressionText('별자리 기록가', 'Constellation Chronicler'),
  ),
  TitleDefinition(
    'weekly_navigator',
    ProgressionText('밤하늘 항해자', 'Night Sky Navigator'),
  ),
  TitleDefinition(
    'weekly_nebula_guide',
    ProgressionText('성운의 길잡이', 'Nebula Guide'),
  ),
  TitleDefinition(
    'weekly_calendar_keeper',
    ProgressionText('별빛 달력지기', 'Star Calendar Keeper'),
  ),
];

class TrialReward {
  const TrialReward(this.trail, this.title);
  final TrailDefinition trail;
  final TitleDefinition title;
}

const trialRewards = <int, TrialReward>{
  1: TrialReward(
    TrailDefinition(
      'trial_forest',
      ProgressionText('숲의 달빛', 'Forest Moonlight'),
    ),
    TitleDefinition(
      'trial_forest_keeper',
      ProgressionText('달빛 숲의 시련지기', 'Forest Trial Keeper'),
    ),
  ),
  2: TrialReward(
    TrailDefinition('trial_cloud', ProgressionText('여명의 구름', 'Dawn Cloud')),
    TitleDefinition(
      'trial_cloud_keeper',
      ProgressionText('구름바다의 시련지기', 'Cloud Sea Trial Keeper'),
    ),
  ),
  3: TrialReward(
    TrailDefinition('trial_lake', ProgressionText('푸른 물비늘', 'Blue Ripple')),
    TitleDefinition(
      'trial_lake_keeper',
      ProgressionText('거울 호수의 시련지기', 'Mirror Lake Trial Keeper'),
    ),
  ),
  4: TrialReward(
    TrailDefinition('trial_clock', ProgressionText('호박빛 진자', 'Amber Pendulum')),
    TitleDefinition(
      'trial_clock_keeper',
      ProgressionText('시계탑의 시련지기', 'Clocktower Trial Keeper'),
    ),
  ),
  5: TrialReward(
    TrailDefinition('trial_ice', ProgressionText('새벽 서리', 'Morning Frost')),
    TitleDefinition(
      'trial_ice_keeper',
      ProgressionText('얼음 동굴의 시련지기', 'Ice Cave Trial Keeper'),
    ),
  ),
  6: TrialReward(
    TrailDefinition('trial_library', ProgressionText('자줏빛 잉크', 'Violet Ink')),
    TitleDefinition(
      'trial_library_keeper',
      ProgressionText('꿈의 서고의 시련지기', 'Dream Library Trial Keeper'),
    ),
  ),
  7: TrialReward(
    TrailDefinition(
      'trial_star',
      ProgressionText('새벽 별빛', 'Daybreak Starlight'),
    ),
    TitleDefinition(
      'trial_star_keeper',
      ProgressionText('첫 별의 시련지기', 'First Star Trial Keeper'),
    ),
  ),
};

final trails = List<TrailDefinition>.unmodifiable([
  ..._baseTrails,
  for (final reward in trialRewards.values) reward.trail,
]);

final titles = List<TitleDefinition>.unmodifiable([
  ..._baseTitles,
  for (final reward in trialRewards.values) reward.title,
]);

TitleDefinition? titleById(String? id) {
  for (final title in titles) {
    if (title.id == id) return title;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 보상 트랙 (레벨 2..20)
// ---------------------------------------------------------------------------

sealed class TrackReward {
  const TrackReward();
}

final class StardustBundle extends TrackReward {
  const StardustBundle(this.amount);
  final int amount;
}

final class TrailUnlock extends TrackReward {
  const TrailUnlock(this.trailId);
  final String trailId;
}

final class TitleUnlock extends TrackReward {
  const TitleUnlock(this.titleId);
  final String titleId;
}

/// 월요일 키로 고르는 12주 순환. 같은 색과 칭호는 소유 목록에 한 번만 들어간다.
const weeklyRewards = <TrackReward>[
  TrailUnlock(TrailIds.weeklyMoonlight),
  TitleUnlock('weekly_dawn_keeper'),
  TrailUnlock(TrailIds.weeklyRipple),
  TitleUnlock('weekly_star_friend'),
  TrailUnlock(TrailIds.weeklyAmber),
  TitleUnlock('weekly_chronicler'),
  TrailUnlock(TrailIds.weeklyFrost),
  TitleUnlock('weekly_navigator'),
  TrailUnlock(TrailIds.weeklyNebula),
  TitleUnlock('weekly_nebula_guide'),
  TrailUnlock(TrailIds.weeklyDaybreak),
  TitleUnlock('weekly_calendar_keeper'),
];

/// 별빛 길 무료 사용권 +[charges].
final class StarlightCharge extends TrackReward {
  const StarlightCharge([this.charges = 1]);
  final int charges;
}

class TrackEntry {
  const TrackEntry(this.level, this.reward);
  final int level;
  final TrackReward reward;
}

const rewardTrack = <TrackEntry>[
  TrackEntry(2, StardustBundle(50)),
  TrackEntry(3, TrailUnlock(TrailIds.petal)),
  TrackEntry(4, TitleUnlock('crescent_apprentice')),
  TrackEntry(5, StarlightCharge()),
  TrackEntry(6, StardustBundle(80)),
  TrackEntry(7, TrailUnlock(TrailIds.firefly)),
  TrackEntry(8, TitleUnlock('garden_keeper')),
  TrackEntry(9, StardustBundle(100)),
  TrackEntry(10, StarlightCharge()),
  TrackEntry(11, StardustBundle(120)),
  TrackEntry(12, TitleUnlock('star_navigator')),
  TrackEntry(13, TrailUnlock(TrailIds.meteor)),
  TrackEntry(14, StardustBundle(150)),
  TrackEntry(15, StarlightCharge()),
  TrackEntry(16, TitleUnlock('spirit_friend')),
  TrackEntry(17, StardustBundle(200)),
  TrackEntry(18, StarlightCharge()),
  TrackEntry(19, StardustBundle(250)),
  TrackEntry(20, TitleUnlock('moon_guardian')),
];

const rewardTrackMaxLevel = 20;

TrackReward? rewardForLevel(int level) {
  for (final entry in rewardTrack) {
    if (entry.level == level) return entry.reward;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 능력 (장 별자리 완성 시 획득)
// ---------------------------------------------------------------------------

abstract final class PowerIds {
  static const moonflowerLeap = 'moonflower_leap';
  static const lightSwap = 'light_swap';
  static const seal = 'seal';
  static const wind = 'wind';
  static const starlightPath = 'starlight_path';
}

class PowerDefinition {
  const PowerDefinition({
    required this.id,
    required this.chapter,
    required this.name,
    required this.description,
    this.activeInWorld1 = false,
  });
  final String id;
  final int chapter;
  final ProgressionText name, description;

  /// 시즌 1(월드 1) 퍼즐에서 실제로 쓸 수 있는지.
  final bool activeInWorld1;
}

const powerCatalog = <PowerDefinition>[
  PowerDefinition(
    id: PowerIds.moonflowerLeap,
    chapter: 1,
    name: ProgressionText('달꽃 도약', 'Moonflower Leap'),
    description: ProgressionText('장애물 하나를 뛰어넘는다.', 'Leap over one obstacle.'),
  ),
  PowerDefinition(
    id: PowerIds.lightSwap,
    chapter: 2,
    name: ProgressionText('빛 교대', 'Light Swap'),
    description: ProgressionText(
      '잔상와 블록의 자리를 바꾼다.',
      'Swap places with your echo.',
    ),
  ),
  PowerDefinition(
    id: PowerIds.seal,
    chapter: 3,
    name: ProgressionText('봉인', 'Seal'),
    description: ProgressionText(
      '잔상를 한 턴 더 붙잡아 둔다.',
      'Keep your echo for one more turn.',
    ),
  ),
  PowerDefinition(
    id: PowerIds.wind,
    chapter: 4,
    name: ProgressionText('바람', 'Wind'),
    description: ProgressionText(
      '막힐 때까지 미끄러져 나아간다.',
      'Slide until something blocks you.',
    ),
  ),
  PowerDefinition(
    id: PowerIds.starlightPath,
    chapter: 5,
    name: ProgressionText('별빛 길', 'Starlight Path'),
    description: ProgressionText(
      '다음 최적의 한 수를 보여 준다.',
      'Reveal the next best move.',
    ),
    activeInWorld1: true,
  ),
];

PowerDefinition? powerForChapter(int chapter) {
  for (final power in powerCatalog) {
    if (power.chapter == chapter) return power;
  }
  return null;
}

PowerDefinition? powerById(String? id) {
  for (final power in powerCatalog) {
    if (power.id == id) return power;
  }
  return null;
}

// ---------------------------------------------------------------------------
// 별빛 길
// ---------------------------------------------------------------------------

abstract final class StarlightPathRules {
  static const baseCost = 20;
  static const starlightBondDiscount = 5;
  static const goldenDiscountPerConstellation = 2;
  static const goldenDiscountCap = 10;

  /// 별빛 길을 쓴 클리어의 최대 별 수.
  static const assistedStarCap = 2;
}

int goldenStarlightDiscount(int goldenConstellations) =>
    (goldenConstellations * StarlightPathRules.goldenDiscountPerConstellation)
        .clamp(0, StarlightPathRules.goldenDiscountCap);

int starlightPathCost({
  bool starlightDiscount = false,
  int goldenConstellations = 0,
}) =>
    StarlightPathRules.baseCost -
    (starlightDiscount ? StarlightPathRules.starlightBondDiscount : 0) -
    goldenStarlightDiscount(goldenConstellations);

enum StarlightPathSource {
  /// `starlight_path` 능력: 시도마다 한 번 무료.
  free,

  /// 보상 트랙의 무료 사용권.
  charge,

  /// 별가루 결제.
  stardust,
}

class StarlightPathQuote {
  const StarlightPathQuote(this.source, this.cost);
  final StarlightPathSource source;

  /// 별가루 비용. [source] 가 stardust 가 아니면 0.
  final int cost;

  @override
  bool operator ==(Object other) =>
      other is StarlightPathQuote &&
      other.source == source &&
      other.cost == cost;

  @override
  int get hashCode => Object.hash(source, cost);

  @override
  String toString() => 'StarlightPathQuote($source, $cost)';
}

/// 무료(능력) → 사용권 → 별가루 순으로 결제 수단을 고른다.
StarlightPathQuote starlightPathQuote({
  required bool powerUnlocked,
  required bool freeUsedThisAttempt,
  required int charges,
  bool starlightDiscount = false,
  int goldenConstellations = 0,
}) {
  if (powerUnlocked && !freeUsedThisAttempt) {
    return const StarlightPathQuote(StarlightPathSource.free, 0);
  }
  if (charges > 0) {
    return const StarlightPathQuote(StarlightPathSource.charge, 0);
  }
  return StarlightPathQuote(
    StarlightPathSource.stardust,
    starlightPathCost(
      starlightDiscount: starlightDiscount,
      goldenConstellations: goldenConstellations,
    ),
  );
}

/// 별빛 길을 쓴 클리어는 최대 2별.
int capAssistedStars(int stars, {required bool usedStarlightPath}) =>
    usedStarlightPath && stars > StarlightPathRules.assistedStarCap
    ? StarlightPathRules.assistedStarCap
    : stars;

/// 맨손 별: 3별이고 힌트(별빛 길 포함)를 쓰지 않은 클리어.
bool isBareHanded({
  required int stars,
  required bool usedHint,
  bool usedStarlightPath = false,
}) => stars == 3 && !usedHint && !usedStarlightPath;

// ---------------------------------------------------------------------------
// 유대와 계열 능력
// ---------------------------------------------------------------------------

/// Lv1..5 에 필요한 누적 동행 클리어 수.
const bondThresholds = <int>[0, 3, 8, 15, 25];
const bondMaxLevel = 5;

/// 계열 능력이 켜지는 유대 레벨.
const bondAbilityLevel = 3;

int bondLevelForClears(int clears) {
  var level = 0;
  for (final threshold in bondThresholds) {
    if (clears >= threshold) level++;
  }
  return level < 1 ? 1 : level;
}

/// 다음 유대 레벨까지 남은 클리어 수. 최대 레벨이면 null.
int? clearsToNextBond(int clears) {
  for (final threshold in bondThresholds) {
    if (clears < threshold) return threshold - clears;
  }
  return null;
}

enum SpiritFamily {
  forest,
  starlight,
  letter,
  cloud,
  memory;

  static SpiritFamily? tryParse(String? id) {
    for (final family in values) {
      if (family.name == id) return family;
    }
    return null;
  }
}

/// 동행한 정령의 유대 레벨로 캠페인 첫 클리어 보너스를 계산한다.
int companionFirstClearXp(SpiritFamily? family, int bondLevel) {
  final bondBonus = bondLevel >= bondMaxLevel
      ? XpRules.maxBondFirstClear
      : XpRules.companionFirstClear;
  final letterBonus =
      family == SpiritFamily.letter && bondLevel >= bondAbilityLevel
      ? XpRules.letterBondFirstClear
      : 0;
  return bondBonus + letterBonus;
}

/// 동행 정령의 계열과 유대 레벨이 켜 주는 능력.
class FamilyAbilities {
  const FamilyAbilities({
    this.stardustBonus = false,
    this.starlightDiscount = false,
    this.extraMemoryLine = false,
    this.mistTrail = false,
    this.showMinimumMoves = false,
  });

  factory FamilyAbilities.of(SpiritFamily? family, int bondLevel) {
    if (family == null || bondLevel < bondAbilityLevel) return none;
    return switch (family) {
      SpiritFamily.forest => const FamilyAbilities(stardustBonus: true),
      SpiritFamily.starlight => const FamilyAbilities(starlightDiscount: true),
      SpiritFamily.letter => const FamilyAbilities(extraMemoryLine: true),
      SpiritFamily.cloud => const FamilyAbilities(mistTrail: true),
      SpiritFamily.memory => const FamilyAbilities(showMinimumMoves: true),
    };
  }

  static const none = FamilyAbilities();

  /// 숲: 별가루 +20%.
  final bool stardustBonus;

  /// 별빛: 별빛 길 비용 −5.
  final bool starlightDiscount;

  /// 편지: 기억 문장 한 줄 더.
  final bool extraMemoryLine;

  /// 구름: `mist` 궤적 해금.
  final bool mistTrail;

  /// 기억: 스테이지 시작 시 최소 이동 수 표시.
  final bool showMinimumMoves;

  @override
  bool operator ==(Object other) =>
      other is FamilyAbilities &&
      other.stardustBonus == stardustBonus &&
      other.starlightDiscount == starlightDiscount &&
      other.extraMemoryLine == extraMemoryLine &&
      other.mistTrail == mistTrail &&
      other.showMinimumMoves == showMinimumMoves;

  @override
  int get hashCode => Object.hash(
    stardustBonus,
    starlightDiscount,
    extraMemoryLine,
    mistTrail,
    showMinimumMoves,
  );
}

void _checkStars(int stars) {
  if (stars < 1 || stars > 3) throw ArgumentError.value(stars, 'stars');
}

// ---------------------------------------------------------------------------
// 별 모으기 업적: 세계별 별 개수, 황금 별자리 수, 맨손 별 수
// ---------------------------------------------------------------------------

enum AchievementKind {
  /// 한 세계에서 모은 별(판마다 최고 별, 최대 75).
  worldStars,

  /// 한 세계에서 달성한 판 도전 과제(최대 75).
  worldStarflowers,

  /// 황금 별자리(장의 다섯 판을 모두 3별로) 개수. 모든 세계를 합친다.
  goldenConstellations,

  /// 맨손 별을 받은 판 개수. 모든 세계를 합친다.
  bareHandedStars,

  /// 한 세계 안의 황금 별자리 개수(최대 5).
  worldGolden,
}

/// 전역 장 번호(세계 n = (n-1)*5+1..)로 세계 번호를 구한다.
int worldOfChapter(int chapter) => (chapter - 1) ~/ 5 + 1;

class Achievement {
  const Achievement({
    required this.id,
    required this.kind,
    required this.target,
    required this.name,
    required this.rewards,
    this.world,
  });
  final String id;
  final AchievementKind kind;
  final int target;

  /// 세계 단위 업적의 세계 번호.
  final int? world;
  final ProgressionText name;
  final List<TrackReward> rewards;
}

const sagaCompletionTitleId = 'first_star_echo';
const sagaCompletionRewards = [
  TitleUnlock(sagaCompletionTitleId),
  TrailUnlock(TrailIds.firstStarlight),
];

const _starAchievements = <Achievement>[
  Achievement(
    id: 'w1-stars-25',
    kind: AchievementKind.worldStars,
    world: 1,
    target: 25,
    name: ProgressionText('달빛 숲 별 25개', '25 Forest stars'),
    rewards: [StardustBundle(100)],
  ),
  Achievement(
    id: 'w1-stars-50',
    kind: AchievementKind.worldStars,
    world: 1,
    target: 50,
    name: ProgressionText('달빛 숲 별 50개', '50 Forest stars'),
    rewards: [StarlightCharge(2)],
  ),
  Achievement(
    id: 'w1-stars-75',
    kind: AchievementKind.worldStars,
    world: 1,
    target: 75,
    name: ProgressionText('달빛 숲 별 75개', 'All 75 Forest stars'),
    rewards: [TrailUnlock(TrailIds.aurora), TitleUnlock('forest_star_keeper')],
  ),
  Achievement(
    id: 'w2-stars-25',
    kind: AchievementKind.worldStars,
    world: 2,
    target: 25,
    name: ProgressionText('구름바다 별 25개', '25 Cloud-Sea stars'),
    rewards: [StardustBundle(150)],
  ),
  Achievement(
    id: 'w2-stars-50',
    kind: AchievementKind.worldStars,
    world: 2,
    target: 50,
    name: ProgressionText('구름바다 별 50개', '50 Cloud-Sea stars'),
    rewards: [StarlightCharge(3)],
  ),
  Achievement(
    id: 'w2-stars-75',
    kind: AchievementKind.worldStars,
    world: 2,
    target: 75,
    name: ProgressionText('구름바다 별 75개', 'All 75 Cloud-Sea stars'),
    rewards: [
      TrailUnlock(TrailIds.starfall),
      TitleUnlock('lighthouse_star_keeper'),
    ],
  ),
  Achievement(
    id: 'w3-stars-25',
    kind: AchievementKind.worldStars,
    world: 3,
    target: 25,
    name: ProgressionText('거울 호수 별 25개', '25 Mirror Lake stars'),
    rewards: [StardustBundle(200)],
  ),
  Achievement(
    id: 'w3-stars-50',
    kind: AchievementKind.worldStars,
    world: 3,
    target: 50,
    name: ProgressionText('거울 호수 별 50개', '50 Mirror Lake stars'),
    rewards: [StarlightCharge(3)],
  ),
  Achievement(
    id: 'w3-stars-75',
    kind: AchievementKind.worldStars,
    world: 3,
    target: 75,
    name: ProgressionText('거울 호수 별 75개', 'All 75 Mirror Lake stars'),
    rewards: [TitleUnlock('mirror_lake_keeper')],
  ),
  Achievement(
    id: 'w4-stars-25',
    kind: AchievementKind.worldStars,
    world: 4,
    target: 25,
    name: ProgressionText('시계탑 별 25개', '25 Clocktower stars'),
    rewards: [StardustBundle(200)],
  ),
  Achievement(
    id: 'w4-stars-50',
    kind: AchievementKind.worldStars,
    world: 4,
    target: 50,
    name: ProgressionText('시계탑 별 50개', '50 Clocktower stars'),
    rewards: [StarlightCharge(3)],
  ),
  Achievement(
    id: 'w4-stars-75',
    kind: AchievementKind.worldStars,
    world: 4,
    target: 75,
    name: ProgressionText('시계탑 별 75개', 'All 75 Clocktower stars'),
    rewards: [TitleUnlock('clocktower_bellkeeper')],
  ),
  Achievement(
    id: 'w5-stars-25',
    kind: AchievementKind.worldStars,
    world: 5,
    target: 25,
    name: ProgressionText('얼음 동굴 별 25개', '25 Ice Cave stars'),
    rewards: [StardustBundle(200)],
  ),
  Achievement(
    id: 'w5-stars-50',
    kind: AchievementKind.worldStars,
    world: 5,
    target: 50,
    name: ProgressionText('얼음 동굴 별 50개', '50 Ice Cave stars'),
    rewards: [StarlightCharge(3)],
  ),
  Achievement(
    id: 'w5-stars-75',
    kind: AchievementKind.worldStars,
    world: 5,
    target: 75,
    name: ProgressionText('얼음 동굴 별 75개', 'All 75 Ice Cave stars'),
    rewards: [TitleUnlock('frost_memory_keeper')],
  ),
  Achievement(
    id: 'w6-stars-25',
    kind: AchievementKind.worldStars,
    world: 6,
    target: 25,
    name: ProgressionText('꿈의 서고 별 25개', '25 Dream Library stars'),
    rewards: [StardustBundle(200)],
  ),
  Achievement(
    id: 'w6-stars-50',
    kind: AchievementKind.worldStars,
    world: 6,
    target: 50,
    name: ProgressionText('꿈의 서고 별 50개', '50 Dream Library stars'),
    rewards: [StarlightCharge(3)],
  ),
  Achievement(
    id: 'w6-stars-75',
    kind: AchievementKind.worldStars,
    world: 6,
    target: 75,
    name: ProgressionText('꿈의 서고 별 75개', 'All 75 Dream Library stars'),
    rewards: [TitleUnlock('first_echo_librarian')],
  ),
  Achievement(
    id: 'w7-stars-25',
    kind: AchievementKind.worldStars,
    world: 7,
    target: 25,
    name: ProgressionText('첫 별의 별 25개', '25 First Star stars'),
    rewards: [StardustBundle(200)],
  ),
  Achievement(
    id: 'w7-stars-50',
    kind: AchievementKind.worldStars,
    world: 7,
    target: 50,
    name: ProgressionText('첫 별의 별 50개', '50 First Star stars'),
    rewards: [StarlightCharge(3)],
  ),
  Achievement(
    id: 'w7-stars-75',
    kind: AchievementKind.worldStars,
    world: 7,
    target: 75,
    name: ProgressionText('첫 별의 별 75개', 'All 75 First Star stars'),
    rewards: sagaCompletionRewards,
  ),
  Achievement(
    id: 'golden-1',
    kind: AchievementKind.goldenConstellations,
    target: 1,
    name: ProgressionText('황금 별자리 1개', '1 golden constellation'),
    rewards: [StardustBundle(80), TitleUnlock('golden_first')],
  ),
  Achievement(
    id: 'golden-5',
    kind: AchievementKind.goldenConstellations,
    target: 5,
    name: ProgressionText('황금 별자리 5개', '5 golden constellations'),
    rewards: [StardustBundle(200), TitleUnlock('golden_collector')],
  ),
  Achievement(
    id: 'golden-10',
    kind: AchievementKind.goldenConstellations,
    target: 10,
    name: ProgressionText('황금 별자리 10개', '10 golden constellations'),
    rewards: [StardustBundle(400), TitleUnlock('golden_sky')],
  ),
  Achievement(
    id: 'w1-golden-5',
    kind: AchievementKind.worldGolden,
    world: 1,
    target: 5,
    name: ProgressionText('달빛 숲 황금 하늘', 'Golden Forest sky'),
    rewards: [TrailUnlock(TrailIds.goldForest), StardustBundle(300)],
  ),
  Achievement(
    id: 'w2-golden-5',
    kind: AchievementKind.worldGolden,
    world: 2,
    target: 5,
    name: ProgressionText('구름바다 황금 하늘', 'Golden Cloud-Sea sky'),
    rewards: [TrailUnlock(TrailIds.goldCloud), StardustBundle(300)],
  ),
  Achievement(
    id: 'w3-golden-5',
    kind: AchievementKind.worldGolden,
    world: 3,
    target: 5,
    name: ProgressionText('거울 호수 황금 하늘', 'Golden Mirror Lake sky'),
    rewards: [TrailUnlock(TrailIds.goldMirror), StardustBundle(300)],
  ),
  Achievement(
    id: 'bare-5',
    kind: AchievementKind.bareHandedStars,
    target: 5,
    name: ProgressionText('맨손 별 5개', '5 bare-handed stars'),
    rewards: [StardustBundle(50), TitleUnlock('barehand_explorer')],
  ),
  Achievement(
    id: 'bare-15',
    kind: AchievementKind.bareHandedStars,
    target: 15,
    name: ProgressionText('맨손 별 15개', '15 bare-handed stars'),
    rewards: [StarlightCharge(2), TitleUnlock('barehand_artisan')],
  ),
  Achievement(
    id: 'bare-30',
    kind: AchievementKind.bareHandedStars,
    target: 30,
    name: ProgressionText('맨손 별 30개', '30 bare-handed stars'),
    rewards: [StardustBundle(300), TitleUnlock('barehand_legend')],
  ),
];

const _starflowerRewards = [
  (
    2,
    ProgressionText('구름바다', 'Cloud Sea'),
    TrailIds.cloudBloom,
    'cloud_bloom_keeper',
  ),
  (
    3,
    ProgressionText('거울 호수', 'Mirror Lake'),
    TrailIds.lakeBloom,
    'lake_bloom_keeper',
  ),
  (
    4,
    ProgressionText('시계탑', 'Clocktower'),
    TrailIds.brassBloom,
    'brass_bloom_keeper',
  ),
  (
    5,
    ProgressionText('얼음 동굴', 'Ice Cave'),
    TrailIds.frostBloom,
    'frost_bloom_keeper',
  ),
  (
    6,
    ProgressionText('꿈의 서고', 'Dream Library'),
    TrailIds.inkBloom,
    'ink_bloom_keeper',
  ),
  (
    7,
    ProgressionText('첫 별', 'First Star'),
    TrailIds.starBloom,
    'star_bloom_keeper',
  ),
];

/// 목표에 닿으면 자동으로 받는다(한 번만).
final achievements = List<Achievement>.unmodifiable([
  ..._starAchievements,
  for (final (world, name, trailId, titleId) in _starflowerRewards)
    for (final (target, reward) in <(int, TrackReward)>[
      (25, const StardustBundle(200)),
      (50, TrailUnlock(trailId)),
      (75, TitleUnlock(titleId)),
    ])
      Achievement(
        id: 'w$world-starflowers-$target',
        kind: AchievementKind.worldStarflowers,
        world: world,
        target: target,
        name: ProgressionText(
          '${name.ko} 별꽃 $target개',
          '${name.en} · $target starflowers',
        ),
        rewards: List.unmodifiable([reward]),
      ),
]);

Achievement? achievementById(String id) {
  for (final achievement in achievements) {
    if (achievement.id == id) return achievement;
  }
  return null;
}

/// 레벨 id로 세계 번호를 구한다(세계 n = 레벨 (n-1)*100+1..).
int worldOfLevelId(int levelId) => (levelId - 1) ~/ 100 + 1;

ProgressionText achievementReached(ProgressionText name) =>
    ProgressionText('업적 달성 · ${name.ko}', 'Achievement · ${name.en}');

abstract final class AchievementText {
  static const heading = ProgressionText('별 모으기', 'Star collection');
  static const stars = ProgressionText('세계별 별', 'Stars by world');
  static const starflowers = ProgressionText('세계별 별꽃', 'Starflowers by world');
  static const mastery = ProgressionText('황금 별자리 · 맨손 별', 'Gold & bare-handed');
  static const golden = ProgressionText('황금 별자리', 'Golden constellations');
  static const bareHanded = ProgressionText('맨손 별', 'Bare-handed stars');
}

/// 황금 별자리 화면 문구.
abstract final class GoldenText {
  static const guardian = ProgressionText(
    '황금 별자리의 수호 정령',
    'Guardian of a golden constellation',
  );
  static const howTo = ProgressionText(
    '장의 다섯 판을 모두 별 3개로 깨면 별자리가 황금빛이 돼요',
    'Earn 3 stars on all five stages to turn it gold',
  );
}

/// 도움을 쓴 판의 표시.
abstract final class AssistCapText {
  static ProgressionText badge(int cap) =>
      ProgressionText('최대 ★$cap', 'Max ★$cap');
  static const kept = ProgressionText(
    '이 판에서 쓴 도움은 다시 시작해도 남아요. 깰 때까지 별 상한이 그대로예요',
    'Help used here stays after a restart. The star limit holds until you clear it',
  );
}
