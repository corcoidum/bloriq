import '../progression/progression_rules.dart';

/// 별바다 항해(끝없는 모드)의 규칙 수치. 순수 함수만 둔다.
///
/// 등불 게이지를 들고 판을 끝없이 이어 푼다. 최단 수보다 더 민 만큼 등불이 닳고,
/// 판을 깨면 조금, 최단 수로 깨면 많이 채워진다. 등불이 꺼지면 항해가 끝난다.
/// 수치는 tools/endless_sim.py 의 모의 플레이로 맞췄다(docs/ENDLESS.md).
abstract final class EndlessRules {
  /// 출항할 때 등불.
  static const startLantern = 10;

  /// 등불의 최대치. 아무리 잘해도 이 이상 모아 둘 수 없다.
  static const maxLantern = 15;

  /// 판을 깨면 채워지는 등불.
  static const clearRefill = 1;

  /// 최단 수로 깨면(완벽) 더 채워지는 등불. 깬 보상과 합쳐 +3.
  static const perfectBonus = 2;

  /// 별빛 한 수(다음 최단 수 보기)의 등불 값.
  static const hintCost = 2;

  /// 연속 완벽 콤보 점수 배율의 상한.
  static const maxMultiplier = 5;

  /// 판 점수의 기본 단위: 최단 수 × 10.
  static const pointsPerMove = 10;

  /// 항해를 열려면 세계 1의 첫 별자리(1장)를 완성해야 한다.
  static const unlockChapter = 1;

  /// 깊이(1부터)에 맞는 판 단계. 1~5판 잔잔한 바다, 6~15판 물결,
  /// 16~35판 너울, 그 뒤로는 폭풍 바다가 끝없이 이어진다.
  static int tierForDepth(int depth) {
    if (depth < 1) throw ArgumentError.value(depth, 'depth');
    if (depth <= 5) return 1;
    if (depth <= 15) return 2;
    if (depth <= 35) return 3;
    return 4;
  }

  /// 이번 판에서 닳은 등불: 최단 수보다 더 민 수(되돌린 수도 민 수로 센다).
  static int waste({required int pushes, required int minimum}) =>
      pushes > minimum ? pushes - minimum : 0;

  /// 완벽 클리어가 [combo]번째 이어질 때의 배율(완벽이 아니면 1).
  static int multiplier({required bool perfect, required int combo}) {
    if (!perfect) return 1;
    final value = 1 + combo;
    return value > maxMultiplier ? maxMultiplier : value;
  }

  static int boardPoints({
    required int minimum,
    required bool perfect,
    required int combo,
  }) => minimum * pointsPerMove * multiplier(perfect: perfect, combo: combo);

  /// 판을 깬 뒤 채워지는 등불.
  static int refill({required bool perfect}) =>
      clearRefill + (perfect ? perfectBonus : 0);

  /// 항해를 마치면 받는 별가루: 깬 판마다 2, 완벽마다 1 더.
  static int voyageStardust({required int boards, required int perfects}) =>
      boards * 2 + perfects;

  /// 항해를 마치면 받는 경험치: 깬 판마다 6.
  static int voyageXp(int boards) => boards * 6;
}

/// 최고 깊이가 처음 이 판 수에 닿으면 한 번 받는 보상.
class VoyageMilestone {
  const VoyageMilestone(this.depth, this.rewards);
  final int depth;
  final List<TrackReward> rewards;
  String get id => 'depth$depth';
}

const voyageMilestones = <VoyageMilestone>[
  VoyageMilestone(10, [TitleUnlock('voyage_sailor'), StardustBundle(50)]),
  VoyageMilestone(25, [TrailUnlock(TrailIds.tide), StardustBundle(100)]),
  VoyageMilestone(50, [TitleUnlock('voyage_captain'), StardustBundle(150)]),
  VoyageMilestone(100, [
    TitleUnlock('voyage_endless'),
    StardustBundle(300),
    StarlightCharge(2),
  ]),
];

/// 끝없는 모드 화면 문구(ARB로 옮기기 전까지 한 곳에서 관리).
abstract final class EndlessText {
  static const title = ProgressionText('별바다 항해', 'Starsea Voyage');
  static const tagline = ProgressionText(
    '끝없이 이어지는 바다에서 등불이 꺼질 때까지',
    'Sail an endless sea until your lantern goes out',
  );
  static const locked = ProgressionText(
    '달빛 숲 1장 별자리를 완성하면 열려요',
    'Complete the first Moonlit Forest constellation to unlock',
  );
  static const start = ProgressionText('출항하기', 'Set sail');
  static const resume = ProgressionText('이어서 항해', 'Continue voyage');
  static const newVoyage = ProgressionText('새로 출항', 'New voyage');
  static const endVoyageTitle = ProgressionText(
    '진행 중인 항해를 끝낼까요?',
    'End your current voyage?',
  );
  static const keepVoyage = ProgressionText('계속 항해', 'Keep voyage');
  static const endAndSail = ProgressionText(
    '항해 종료 후 새로 출항',
    'End voyage and sail again',
  );
  static const startSaveFailed = ProgressionText(
    '새 항해를 저장하지 못했어요. 다시 시도해 주세요.',
    'Could not save the new voyage. Please try again.',
  );

  static ProgressionText endVoyageBody(int depth, int cleared, int score) =>
      ProgressionText(
        '$depth번째 바다에서 진행 중이에요. $cleared판 클리어와 $score점은 '
            '최고 기록에 반영돼요. 새 항해는 1번째 바다에서 시작해요.',
        'You are on Sea $depth. Your $cleared clears and $score points count '
            'toward your records. A new voyage starts at Sea 1.',
      );

  static ProgressionText voyageProgress(int cleared, int score) =>
      ProgressionText(
        '$cleared판 클리어 · $score점',
        '$cleared cleared · $score pts',
      );

  static const again = ProgressionText('다시 출항', 'Sail again');
  static const home = ProgressionText('홈으로', 'Home');
  static const lantern = ProgressionText('등불', 'Lantern');
  static const score = ProgressionText('점수', 'Score');
  static const hint = ProgressionText('별빛 한 수', 'Starlight move');
  static const best = ProgressionText('최고', 'Best');
  static const weekBest = ProgressionText('이번 주', 'This week');
  static const bestDepth = ProgressionText('최고 깊이', 'Deepest');
  static const perfect = ProgressionText('완벽!', 'Perfect!');
  static const cleared = ProgressionText('건넜어요', 'Crossed');
  static const lanternOut = ProgressionText('등불이 꺼졌어요', 'The lantern went out');
  static const newRecord = ProgressionText('새 기록!', 'New record!');
  static const rewards = ProgressionText('항해 보상', 'Voyage rewards');
  static const rulesTitle = ProgressionText('항해 규칙', 'How to sail');
  static const noHint = ProgressionText('등불이 모자라요', 'Not enough lantern light');

  static const rules = <ProgressionText>[
    ProgressionText(
      '판을 깨면 바로 다음 바다로 이어져요. 갈수록 넓고 깊어져요.',
      'Each cleared board leads straight to the next, wider and deeper sea.',
    ),
    ProgressionText(
      '최단 수보다 더 민 만큼 등불이 닳아요. 되돌리기·다시 시작해도 민 수는 그대로예요.',
      'Every push beyond the shortest path burns lantern light, even ones you undo.',
    ),
    ProgressionText(
      '판을 깨면 등불 +1, 최단 수로 깨면 +3(최대 15).',
      'Clearing a board refills 1, a perfect clear refills 3 (max 15).',
    ),
    ProgressionText(
      '완벽이 이어지면 점수가 2배, 3배… 최대 5배까지 불어나요.',
      'Back-to-back perfects multiply your score ×2, ×3… up to ×5.',
    ),
    ProgressionText(
      '막히면 별빛 한 수(등불 2)로 다음 수를 볼 수 있어요.',
      'Stuck? A Starlight move (2 light) shows the next step.',
    ),
  ];

  static ProgressionText depth(int depth) =>
      ProgressionText('$depth번째 바다', 'Sea $depth');
  static ProgressionText boards(int boards) =>
      ProgressionText('$boards판', '$boards boards');
  static ProgressionText combo(int multiplier) =>
      ProgressionText('콤보 ×$multiplier', 'Combo ×$multiplier');
  static ProgressionText nextCombo(int multiplier) =>
      ProgressionText('다음 완벽 ×$multiplier', 'Next perfect ×$multiplier');
  static ProgressionText trailBadge(String name) =>
      ProgressionText('이동 잔영 · $name', 'Trail · $name');
  static ProgressionText levelBadge(int level) =>
      ProgressionText('별지기 Lv $level!', 'Keeper Lv $level!');
  static ProgressionText bestLine(int score, int depth) => ProgressionText(
    '최고 $score점 · $depth판',
    'Best $score pts · $depth boards',
  );
  static ProgressionText reached(int boards, int perfects) => ProgressionText(
    '$boards판을 건넜어요 · 완벽 $perfects번',
    'Crossed $boards boards · $perfects perfect',
  );
  static ProgressionText hintCostLabel(int cost) =>
      ProgressionText('등불 −$cost', '−$cost light');
  static ProgressionText milestone(int depth) =>
      ProgressionText('$depth판 이정표', '$depth-board milestone');
}
