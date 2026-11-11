import '../daily/daily_repository.dart';
import '../domain/puzzle.dart';

enum PlayMode { campaign, daily, tutorialReplay }

class PlayContext {
  const PlayContext.campaign({this.guided = false})
    : mode = PlayMode.campaign,
      level = null,
      challenge = null,
      world = 1;

  /// 확장 세계 캠페인. 기록은 세계 1과 같은 저장소에 남는다
  /// (세계 2 = 레벨 101..125, 세계 3 = 201..225 …).
  const PlayContext.world(this.world)
    : assert(world >= 2),
      mode = PlayMode.campaign,
      guided = false,
      level = null,
      challenge = null;
  const PlayContext.tutorialReplay(this.level)
    : mode = PlayMode.tutorialReplay,
      guided = true,
      challenge = null,
      world = 1;
  PlayContext.daily(DailyChallenge daily)
    : mode = PlayMode.daily,
      guided = false,
      level = daily.level,
      challenge = daily,
      world = 1;
  final PlayMode mode;
  final bool guided;
  final Level? level;
  final DailyChallenge? challenge;

  /// 세계 번호. 1 = 달빛 숲, 2 = 구름바다 등대 … (assets/worlds/saga.json).
  final int world;
  String? get dailyDate => challenge?.date;
}

/// 게임 화면이 닫히며 홈에 남기는 요청: 이 세계의 지도를 바로 연다.
/// 세계를 막 마친 결과 화면의 "다음 세계로" 버튼이 쓴다.
class OpenWorld {
  const OpenWorld(this.world);
  final int world;
}

/// 최종 결과에서 게임을 닫은 뒤 엔딩을 연다.
class OpenEnding {
  const OpenEnding();
}
