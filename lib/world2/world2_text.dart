import '../domain/puzzle.dart';
import '../progression/progression_rules.dart';

/// 월드 2 화면 문구. 권능 이름은 [powerCatalog]를 쓰고, 나머지 짧은 문구만
/// 여기 둔다(ARB로 옮기기 전까지 한 곳에서 관리).
abstract final class World2Text {
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

  static const enter = ProgressionText(
    '구름바다 등대로',
    'To the Cloud-Sea Lighthouse',
  );
  static const opened = ProgressionText(
    '별문이 열렸어요 · 홈에서 구름바다 등대로 떠나요',
    'The star gate is open · set out for the Cloud-Sea Lighthouse from home',
  );
  static const locked = ProgressionText(
    '달빛 숲의 다섯 별자리를 모두 완성하면 열려요.',
    'Opens when all five Moonlit Forest constellations are complete.',
  );
  static const play = ProgressionText('이어하기', 'Continue');
  static const stage = ProgressionText('스테이지', 'Stage');
  static const requiresPower = ProgressionText('권능 필요', 'Power needed');
  static const bareHandedPossible = ProgressionText(
    '맨손으로도 풀 수 있어요',
    'Solvable bare-handed',
  );
  static const lockedStage = ProgressionText(
    '앞 스테이지를 먼저 깨요',
    'Clear the previous stage first',
  );
  static const chapterLocked = ProgressionText('아직 잠긴 장', 'Chapter locked');
  static const close = ProgressionText('닫기', 'Close');
  static const missingArt = ProgressionText('그림 준비 중', 'Art coming soon');
}
