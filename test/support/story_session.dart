import 'package:bloriq/app/game_session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 위젯 테스트의 fake async 안에서 저장 큐를 생성하고 끝낸다.
Future<GameSession> loadStorySession(WidgetTester tester) async {
  rootBundle.clear();
  GameSession? result;
  Object? error;
  GameSession.load().then(
    (value) => result = value,
    onError: (Object e) {
      error = e;
    },
  );
  for (var i = 0; i < 200 && result == null && error == null; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (error != null) throw error!;
  expect(result, isNotNull);
  return result!;
}

Future<void> disposeStorySession(
  WidgetTester tester,
  GameSession session,
) async {
  var done = false;
  session.dispose().then((_) => done = true);
  for (var i = 0; i < 50 && !done; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done, true);
}
