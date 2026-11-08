import '../domain/puzzle.dart';
import '../progression/progression_rules.dart';

/// 한 판에서 얼마나 막혀 있는지 기억한다(앱을 켜 둔 동안만, 저장하지 않음).
/// 같은 판을 여러 번 다시 시작했거나 오래 붙잡고 있으면 도움을 권한다.
class StruggleTracker {
  StruggleTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const restartThreshold = 3;
  static const timeThreshold = Duration(minutes: 3);

  final DateTime Function() _clock;
  final _openedAt = <int, DateTime>{};
  final _restarts = <int, int>{};

  /// 판을 열 때. 이미 붙잡고 있던 판이면 처음 연 시각을 그대로 둔다.
  void opened(int levelId) => _openedAt.putIfAbsent(levelId, _clock);

  void restarted(int levelId) {
    opened(levelId);
    _restarts[levelId] = (_restarts[levelId] ?? 0) + 1;
  }

  /// 깨면 기록을 지운다. 다시 하다 막히면 처음부터 다시 센다.
  void cleared(int levelId) {
    _openedAt.remove(levelId);
    _restarts.remove(levelId);
  }

  int restarts(int levelId) => _restarts[levelId] ?? 0;

  bool isStuck(int levelId) => untilStuck(levelId) == Duration.zero;

  /// 도움을 권할 때까지 남은 시간. 이미 막혔으면 0, 판을 연 적 없으면 null.
  Duration? untilStuck(int levelId) {
    final opened = _openedAt[levelId];
    if (opened == null) return null;
    if (restarts(levelId) >= restartThreshold) return Duration.zero;
    final left = timeThreshold - _clock().difference(opened);
    return left.isNegative ? Duration.zero : left;
  }
}

/// 도움 1단계 "열쇠 한 줄": 답을 다 알려 주지 않고 풀이의 핵심만 귀띔한다.
/// [solution]은 판 처음 상태에서 구한 최단 풀이다.
ProgressionText keyHint(Level level, List<PuzzleMove> solution) {
  final powerIndex = solution.indexWhere((move) => move.power != null);
  if (powerIndex >= 0) {
    final power = solution[powerIndex].power!;
    final name = powerById(power.id)?.name;
    final ko = name?.ko ?? power.id;
    final en = name?.en ?? power.id;
    final step = powerIndex + 1;
    return level.requiredPowers.contains(power)
        ? ProgressionText(
            '이 판은 $ko${_particle(ko, '이', '가')} 꼭 필요해요. '
                '$step번째 수쯤에 써 보세요.',
            'This stage needs $en. Try it around move $step.',
          )
        : ProgressionText(
            '$ko${_particle(ko, '을', '를')} $step번째 수쯤에 쓰면 길이 짧아져요.',
            'Using $en around move $step makes the path shorter.',
          );
  }
  final firstGoal = solution.indexWhere(
    (move) => move.blockId == Level.goalBlockId,
  );
  if (level.echoGate != null) {
    return const ProgressionText(
      '먼저 달 수정에 잔상을 남겨 덩굴 문을 여는 게 첫걸음이에요.',
      'First, leave an echo on the moon crystal to open the vine gate.',
    );
  }
  if (firstGoal > 0) {
    return ProgressionText(
      '처음 $firstGoal수는 블록만 옮겨 리크의 길을 터요.',
      'The first $firstGoal moves only push blocks to clear RIQ’s path.',
    );
  }
  final count = solution.length;
  return ProgressionText(
    '최단 풀이는 $count수예요. 리크부터 움직이며 시작해 보세요.',
    'The shortest path is $count moves. Start by moving RIQ.',
  );
}

/// 마지막 글자 받침에 맞춰 조사를 고른다(이/가, 을/를).
String _particle(String word, String withBatchim, String without) {
  if (word.isEmpty) return without;
  final code = word.codeUnitAt(word.length - 1) - 0xAC00;
  if (code < 0 || code > 11171) return without;
  return code % 28 == 0 ? without : withBatchim;
}

/// 도움을 받은 클리어의 최대 별 수: 풀이 따라 하기 1개, 별빛 길 2개.
int assistedStarCap({required bool followedSolution, required bool usedHint}) =>
    followedSolution
    ? 1
    : usedHint
    ? StarlightPathRules.assistedStarCap
    : 3;

/// 막힘 도움 화면 문구(ARB로 옮기기 전까지 한 곳에서 관리).
abstract final class AssistText {
  static const offer = ProgressionText('막혔나요? 도움 받기', 'Stuck? Get help');
  static const title = ProgressionText('조금 도와줄게요', 'A little help');
  static const keyTitle = ProgressionText('열쇠 한 줄', 'Key idea');
  static const starlight = ProgressionText(
    '다음 한 수 보기 · 별빛 길',
    'Show the next move · Starlight Path',
  );
  static const guide = ProgressionText(
    '풀이 따라 하기 · 별 1개',
    'Follow the solution · 1 star',
  );
  static const guideNote = ProgressionText(
    '처음부터 다시 시작해 한 수씩 빛으로 알려 줘요. 깨면 다음 판으로 갈 수 있어요.',
    'Restarts the stage and lights each move. Clear it to move on.',
  );
  static const selfNote = ProgressionText(
    '직접 풀면 별 3개까지 받을 수 있어요.',
    'Solve it yourself for up to 3 stars.',
  );
  static const guiding = ProgressionText(
    '풀이 따라 하기 중 · 빛나는 화살표를 따라가요',
    'Following the solution · follow the glowing arrow',
  );
  static const stopGuide = ProgressionText('직접 풀기', 'Solve myself');
}
