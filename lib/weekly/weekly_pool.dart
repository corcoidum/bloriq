import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../daily/daily_repository.dart';
import '../endless/endless_pool.dart';

DateTime weeklyMonday(DateTime date) {
  final day = civilDay(date);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

String weeklyKey(DateTime date) => localDateKey(weeklyMonday(date));

int weeklyOrdinal(String key) =>
    weeklyMonday(DateTime.parse(key))
        .difference(DateTime.utc(1970, 1, 5))
        .inDays ~/
    7;

DateTime nextWeeklyBoundary(DateTime now) {
  final days = DateTime.daysPerWeek + DateTime.monday - now.weekday;
  return now.isUtc
      ? DateTime.utc(now.year, now.month, now.day + days)
      : DateTime(now.year, now.month, now.day + days);
}

class WeeklyPool {
  const WeeklyPool({required this.daily, required this.voyage});

  static const stageCount = 5;
  static const worldAsset = EndlessPool.worldAsset;

  final List<Map<String, dynamic>> daily, voyage;

  static const _mechanicWorlds = {
    'echoEraser': 1,
    'echoHold': 1,
    'oneWay': 1,
    'goalOnly': 1,
    'echoGate': 1,
    'mirrorPair': 3,
    'clockArrow': 4,
    'ice': 5,
    'shelfDoor': 6,
  };

  static Future<WeeklyPool> load(DailyRepository daily) async {
    Future<List<Map<String, dynamic>>> read(String asset) async {
      final bytes = await rootBundle.load(asset);
      return (jsonDecode(
        utf8.decode(
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        ),
      ) as List).cast<Map<String, dynamic>>();
    }

    return WeeklyPool(
      daily: daily.pool,
      voyage: [...await read(EndlessPool.asset), ...await read(worldAsset)],
    );
  }

  /// 월요일 키와 현재 해금 상태로 첫 배정을 만든다. 이후에는 저장된 배치를 쓴다.
  List<Map<String, dynamic>> pick(String key, Set<int> completedWorlds) {
    final rng = math.Random(weeklyOrdinal(key));
    List<Map<String, dynamic>> eligible(List<Map<String, dynamic>> pool) =>
        [
            for (final board in pool)
              if ((board['specialRules'] as List).every(
                (rule) => completedWorlds.contains(
                  _mechanicWorlds[(rule as Map)['type']],
                ),
              ))
                board,
          ]
          ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int))
          ..shuffle(rng);

    final dailyBoards = eligible(daily);
    final voyageBoards = eligible(voyage);
    final worldBoard = voyageBoards
        .where((board) => board['mechanicWorld'] != null)
        .firstOrNull;
    final selected = <Map<String, dynamic>>[];
    final ids = <int>{};
    for (final board in [
      ...dailyBoards.take(2),
      ?worldBoard,
      ...voyageBoards,
      ...dailyBoards.skip(2),
    ]) {
      if (ids.add(board['id'] as int)) {
        // 항해 묶음에는 Level에 필요한 난이도 문자열이 없다.
        selected.add({...board, 'difficulty': board['difficulty'] ?? 'weekly'});
      }
      if (selected.length == stageCount) return selected;
    }
    throw const FormatException('Not enough unlocked weekly boards');
  }
}
