import '../domain/puzzle.dart';

enum PlayMode { campaign, daily, tutorialReplay }

class PlayContext {
  const PlayContext.campaign({this.guided = false})
    : mode = PlayMode.campaign,
      level = null,
      dailyDate = null;
  const PlayContext.tutorialReplay(this.level)
    : mode = PlayMode.tutorialReplay,
      guided = true,
      dailyDate = null;
  const PlayContext.daily(this.level, this.dailyDate)
    : mode = PlayMode.daily,
      guided = false;
  final PlayMode mode;
  final bool guided;
  final Level? level;
  final String? dailyDate;
}
