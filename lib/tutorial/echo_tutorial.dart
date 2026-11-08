import 'package:shared_preferences/shared_preferences.dart';

import '../domain/puzzle.dart';

class Onboarding {
  Onboarding(this.preferences, this.status);
  static const storageKey = 'bloriq.onboarding.v1';
  final SharedPreferences? preferences;
  String status;
  bool saveFailed = false;
  Future<void> _queue = Future.value();
  bool get pending => status == 'unseen' || status == 'inProgress';

  static Future<Onboarding> load({required bool returningPlayer}) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final status = preferences.getString(storageKey);
      return Onboarding(
        preferences,
        {'complete', 'skipped', 'inProgress'}.contains(status) &&
                !(returningPlayer && status == 'inProgress')
            ? status!
            : returningPlayer
            ? 'skipped'
            : 'unseen',
      );
    } catch (_) {
      return Onboarding(null, returningPlayer ? 'skipped' : 'unseen');
    }
  }

  Future<void> mark(String value) {
    status = value;
    _queue = _queue.then((_) async {
      try {
        saveFailed =
            !(await preferences?.setString(storageKey, value) ?? false);
      } catch (_) {
        saveFailed = true;
      }
    });
    return _queue;
  }
}

/// 안내 입력만 제한한다. 이동의 성공/실패는 실제 엔진이 결정한다.
class EchoTutorial {
  int step = 0;
  bool get complete => step >= 3;
  Position get target => step == 1
      ? const Position(0, 1)
      : step == 0
      ? const Position(1, 1)
      : const Position(2, 1);
  bool accepts(String id, Position destination) =>
      !complete && id == Level.goalBlockId && destination == target;
  void observe(PuzzleState before, Position destination, bool moved) {
    if (complete) return;
    if ((step == 1 && !moved && before.echo == destination) ||
        (step != 1 && moved)) {
      step++;
    }
  }
}
