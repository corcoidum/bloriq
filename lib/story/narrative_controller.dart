import 'dart:async';

import 'package:flutter/foundation.dart';

enum CompanionReaction {
  idle,
  look,
  echo,
  blocked,
  gate,
  complete,
  welcome,
  memory,
}

/// 표시 이벤트만 받는다. 퍼즐의 유효 이동·턴·보상은 결정하지 않는다.
class NarrativeController extends ChangeNotifier {
  CompanionReaction reaction = CompanionReaction.idle;
  int lookDirection = 0;
  Timer? _reset;
  bool _disposed = false;
  void react(CompanionReaction value, {int direction = 0}) {
    if (_disposed) return;
    if (reaction == value &&
        value == CompanionReaction.look &&
        direction == lookDirection) {
      return;
    }
    _reset?.cancel();
    reaction = value;
    lookDirection = direction;
    notifyListeners();
    if (value != CompanionReaction.idle &&
        value != CompanionReaction.complete) {
      _reset = Timer(
        const Duration(milliseconds: 850),
        () => react(CompanionReaction.idle),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reset?.cancel();
    super.dispose();
  }
}
