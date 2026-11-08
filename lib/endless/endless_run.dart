import 'endless_pool.dart';
import 'endless_rules.dart';

/// 한 판을 깼을 때의 결과.
class BoardResult {
  const BoardResult({
    required this.depth,
    required this.minimum,
    required this.pushes,
    required this.perfect,
    required this.multiplier,
    required this.points,
    required this.refill,
  });
  final int depth, minimum, pushes, multiplier, points, refill;
  final bool perfect;
}

/// 진행 중인 항해 한 번. 화면과 상관없는 순수 상태라 저장하고 다시 열 수 있다.
///
/// 등불은 판을 시작할 때의 값([lanternAtStart])에서 이번 판의 낭비와 별빛 한 수
/// 값을 뺀 것이다. 그래서 판 도중에 앱을 닫았다 열어도 닳은 등불은 그대로다.
class VoyageRun {
  VoyageRun._(
    this._used, {
    required this.seed,
    required this.depth,
    required this.lanternAtStart,
    required this.score,
    required this.combo,
    required this.perfects,
    required this.pushes,
    required this.hintsSpent,
    required this.board,
  });

  /// 새 항해. 첫 판을 고른다.
  factory VoyageRun.start(EndlessPool pool, {required int seed}) {
    final used = <int>{};
    final board = pool.pick(seed: seed, depth: 1, used: used);
    used.add(board.id);
    return VoyageRun._(
      used,
      seed: seed,
      depth: 1,
      lanternAtStart: EndlessRules.startLantern,
      score: 0,
      combo: 0,
      perfects: 0,
      pushes: 0,
      hintsSpent: 0,
      board: board,
    );
  }

  final int seed;

  /// 지금 풀고 있는 판의 번호(1부터). 깬 판 수는 depth - 1.
  int depth;
  int lanternAtStart;
  int score;

  /// 연속 완벽 횟수.
  int combo;
  int perfects;

  /// 이번 판에서 민 횟수(되돌린 수 포함). 다시 시작해도 줄지 않는다.
  int pushes;

  /// 이번 판에서 별빛 한 수로 쓴 등불.
  int hintsSpent;
  VoyageBoard board;
  final Set<int> _used;

  int get cleared => depth - 1;

  /// 지금 등불(0 미만으로 내려가지 않게 보여 준다).
  int lanternFor(int minimum) {
    final value =
        lanternAtStart -
        EndlessRules.waste(pushes: pushes, minimum: minimum) -
        hintsSpent;
    return value < 0 ? 0 : value;
  }

  /// 등불이 꺼졌는지. 판을 막 깬 수는 꺼짐으로 보지 않는다(깬 뒤 다시 채워진다).
  bool isOut(int minimum) => lanternFor(minimum) <= 0;

  void pushed() => pushes++;

  bool canHint(int minimum) => lanternFor(minimum) > EndlessRules.hintCost;

  void hinted() => hintsSpent += EndlessRules.hintCost;

  /// 판을 깼다. 점수와 등불을 정산하고 다음 판으로 넘어간다.
  BoardResult clear(int minimum, EndlessPool pool) {
    final perfect = pushes <= minimum && hintsSpent == 0;
    combo = perfect ? combo + 1 : 0;
    if (perfect) perfects++;
    final multiplier = EndlessRules.multiplier(perfect: perfect, combo: combo);
    final points = EndlessRules.boardPoints(
      minimum: minimum,
      perfect: perfect,
      combo: combo,
    );
    final refill = EndlessRules.refill(perfect: perfect);
    final result = BoardResult(
      depth: depth,
      minimum: minimum,
      pushes: pushes,
      perfect: perfect,
      multiplier: multiplier,
      points: points,
      refill: refill,
    );
    score += points;
    final left =
        lanternAtStart -
        EndlessRules.waste(pushes: pushes, minimum: minimum) -
        hintsSpent;
    lanternAtStart = (left < 0 ? 0 : left) + refill;
    if (lanternAtStart > EndlessRules.maxLantern) {
      lanternAtStart = EndlessRules.maxLantern;
    }
    depth++;
    pushes = 0;
    hintsSpent = 0;
    board = pool.pick(seed: seed, depth: depth, used: _used);
    _used.add(board.id);
    return result;
  }

  Map<String, dynamic> toJson() => {
    'seed': seed,
    'depth': depth,
    'lantern': lanternAtStart,
    'score': score,
    'combo': combo,
    'perfects': perfects,
    'pushes': pushes,
    'hintsSpent': hintsSpent,
    'board': board.toJson(),
    'used': _used.toList()..sort(),
  };

  static VoyageRun fromJson(Map<String, dynamic> json) {
    int read(String key) {
      final value = json[key];
      if (value is! int || value < 0) {
        throw FormatException('Invalid voyage field $key');
      }
      return value;
    }

    final used = json['used'];
    if (used is! List || used.any((id) => id is! int)) {
      throw const FormatException('Invalid voyage history');
    }
    final depth = read('depth');
    if (depth < 1) throw const FormatException('Invalid voyage depth');
    return VoyageRun._(
      used.cast<int>().toSet(),
      seed: read('seed'),
      depth: depth,
      lanternAtStart: read('lantern'),
      score: read('score'),
      combo: read('combo'),
      perfects: read('perfects'),
      pushes: read('pushes'),
      hintsSpent: read('hintsSpent'),
      board: VoyageBoard.fromJson(
        Map<String, dynamic>.from(json['board'] as Map),
      ),
    );
  }
}
