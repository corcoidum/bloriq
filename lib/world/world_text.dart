import '../domain/puzzle.dart';
import '../progression/progression_rules.dart';
import '../story/story_catalog.dart';

/// 세계·사가 화면 문구. 권능 이름은 [powerCatalog]를 쓰고, 세계 이름은
/// assets/worlds/saga.json 에서 가져온다(ARB로 옮기기 전까지 한 곳에서 관리).
abstract final class WorldText {
  static ProgressionText armed(PuzzlePower power) => switch (power) {
    PuzzlePower.moonflowerLeap => const ProgressionText(
      '달꽃 도약: 바위 쪽으로 블록을 밀면 바위를 뛰어넘어요.',
      'Moonflower Leap: push a block toward a rock to jump over it.',
    ),
    PuzzlePower.lightSwap => const ProgressionText(
      '빛 교대: 블록을 아무 쪽으로나 밀면 잔상 자리로 옮겨 가요.',
      'Light Swap: push any block to trade places with the echo.',
    ),
    PuzzlePower.seal => const ProgressionText(
      '봉인: 다음 한 수 동안 지금 잔상이 그대로 남아요.',
      'Seal: your echo stays put through the next move.',
    ),
    PuzzlePower.wind => const ProgressionText(
      '바람: 블록을 밀면 막힐 때까지 미끄러져요.',
      'Wind: a pushed block slides until something stops it.',
    ),
  };

  static ProgressionText hintPower(PuzzlePower power) {
    final name = powerById(power.id)?.name;
    return ProgressionText(
      '별빛 길: 이번 수는 ${name?.ko ?? power.id}을(를) 써 보세요.',
      'Starlight Path: try ${name?.en ?? power.id} on this move.',
    );
  }

  /// "구름바다 등대로", "달빛 숲 정원으로" — 받침에 맞춰 조사를 고른다.
  static ProgressionText enter(StoryText title) =>
      ProgressionText('${title.ko}${_ro(title.ko)}', 'To the ${title.en}');

  static ProgressionText opened(StoryText title) => ProgressionText(
    '별문이 열렸어요 · 홈에서 ${title.ko}${_ro(title.ko)} 떠나요',
    'The star gate is open · set out for the ${title.en} from home',
  );

  static String _ro(String word) {
    if (word.isEmpty) return '로';
    final code = word.codeUnitAt(word.length - 1) - 0xAC00;
    if (code < 0 || code > 11171) return '로';
    final batchim = code % 28;
    // 받침이 없거나 ㄹ 받침이면 '로', 나머지는 '으로'.
    return batchim == 0 || batchim == 8 ? '로' : '으로';
  }

  static ProgressionText worldCleared(StoryText title) =>
      ProgressionText('${title.ko} 완료!', '${title.en} complete!');

  static ProgressionText gateOpened(StoryText title) => ProgressionText(
    '${title.ko}${_ro(title.ko)} 가는 별문이 열렸어요',
    'The star gate to the ${title.en} is open',
  );

  static const play = ProgressionText('이어하기', 'Continue');
  static const stage = ProgressionText('스테이지', 'Stage');
  static const requiresPower = ProgressionText('권능 필요', 'Power needed');
  static const bareHandedPossible = ProgressionText(
    '맨손으로도 풀 수 있어요',
    'Solvable bare-handed',
  );
  static const lockedStage = ProgressionText(
    '앞 장에서 3판을 깨면 열려요',
    'Clear 3 stages of the previous chapter to open',
  );
  static const chapterLocked = ProgressionText(
    '아직 잠긴 장 · 앞 장에서 3판을 깨면 열려요',
    'Chapter locked · clear 3 stages of the previous chapter',
  );
  static const close = ProgressionText('닫기', 'Close');
  static const missingArt = ProgressionText('그림 준비 중', 'Art coming soon');

  // 사가 지도
  static const sagaMap = ProgressionText('빛길 지도', 'Lightroad Map');
  static const nextStory = ProgressionText('다음 이야기', 'Next story');
  static const comingSoon = ProgressionText('곧 열려요', 'Coming soon');
  static const newRule = ProgressionText('새 규칙', 'New rule');
  static const restored = ProgressionText('빛을 되찾았어요', 'Light restored');
  static const enterWorld = ProgressionText('들어가기', 'Enter');
  static const lockedWorld = ProgressionText(
    '앞 세계의 다섯 별자리를 완성하면 열려요',
    'Opens when the previous world’s five constellations are complete',
  );
  static const mystery = ProgressionText('???', '???');

  static ProgressionText lighthouse(int number) =>
      ProgressionText('등대 $number / 5', 'Lighthouse $number / 5');
  static ProgressionText progress(int cleared, int total) =>
      ProgressionText('$cleared / $total 스테이지', '$cleared / $total stages');
  static ProgressionText litCount(int lit) =>
      ProgressionText('켜진 등대 $lit / 5', 'Lighthouses lit $lit / 5');
}
