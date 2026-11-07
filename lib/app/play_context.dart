import '../daily/daily_repository.dart';
import '../domain/puzzle.dart';

enum PlayMode { campaign, daily, tutorialReplay }

class PlayContext {
  const PlayContext.campaign({this.guided = false})
    : mode = PlayMode.campaign,
      level = null,
      challenge = null,
      world = 1;

  /// 구름바다 등대 캠페인. 기록은 월드 1과 같은 저장소에 레벨 101..125로 남는다.
  const PlayContext.world2()
    : mode = PlayMode.campaign,
      guided = false,
      level = null,
      challenge = null,
      world = 2;
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

  /// 1 = 달빛 숲, 2 = 구름바다 등대.
  final int world;
  String? get dailyDate => challenge?.date;
}
