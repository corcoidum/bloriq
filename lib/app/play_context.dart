import '../daily/daily_repository.dart';
import '../domain/puzzle.dart';

enum PlayMode { campaign, daily, tutorialReplay }

class PlayContext {
  const PlayContext.campaign({this.guided = false})
    : mode = PlayMode.campaign,
      level = null,
      challenge = null;
  const PlayContext.tutorialReplay(this.level)
    : mode = PlayMode.tutorialReplay,
      guided = true,
      challenge = null;
  PlayContext.daily(DailyChallenge daily)
    : mode = PlayMode.daily,
      guided = false,
      level = daily.level,
      challenge = daily;
  final PlayMode mode;
  final bool guided;
  final Level? level;
  final DailyChallenge? challenge;
  String? get dailyDate => challenge?.date;
}
