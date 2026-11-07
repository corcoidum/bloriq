import 'dart:convert';

import 'package:flutter/services.dart';

import '../story/story_catalog.dart';

/// 세계 하나의 공개 상태. 계획만 된 세계는 사가 지도에 예고로만 보인다.
enum SagaWorldStatus { playable, planned }

/// assets/worlds/saga.json 의 세계 한 줄. 세계 1은 기존 시즌 1 데이터를 쓰므로
/// 에셋 경로가 없고, 세계 2부터는 [levelsAsset]·[storyAsset]만 넣으면 열린다.
class SagaWorld {
  SagaWorld.fromJson(Map<String, dynamic> data)
    : number = data['number'] as int,
      id = data['id'] as String,
      status = switch (data['status']) {
        'playable' => SagaWorldStatus.playable,
        'planned' => SagaWorldStatus.planned,
        _ => throw const FormatException('Unknown saga world status'),
      },
      lighthouse = data['lighthouse'] as int?,
      levelsAsset = data['levels'] as String?,
      storyAsset = data['story'] as String?,
      title = StoryText.fromJson(data['title']),
      subtitle = StoryText.fromJson(data['subtitle']),
      mechanic = StoryText.fromJson(data['mechanic']),
      teaser = StoryText.fromJson(data['teaser']),
      reveal = StoryText.fromJson(data['reveal']);

  final int number;
  final String id;
  final SagaWorldStatus status;

  /// 몇째 등대인지(1..5). 서막과 종장은 null.
  final int? lighthouse;
  final String? levelsAsset, storyAsset;

  /// [teaser]는 앞 세계를 마칠 때 보여 주는 다음 이야기 한 줄,
  /// [reveal]은 이 세계를 마치면 풀리는 수수께끼(작가용, 화면에는 완료 후만).
  final StoryText title, subtitle, mechanic, teaser, reveal;

  bool get playable => status == SagaWorldStatus.playable;

  /// 세계 2부터는 레벨·이야기 에셋으로 불러오는 확장 세계다.
  bool get expansion => number >= 2;
}

/// 모든 세계를 꿰는 큰 줄거리. 세계 순서와 공개 상태의 단일 원본이다.
class Saga {
  Saga.fromJson(Map<String, dynamic> data)
    : title = StoryText.fromJson(data['title']),
      premise = StoryText.fromJson(data['premise']),
      worlds = List.unmodifiable(
        (data['worlds'] as List).map(
          (e) => SagaWorld.fromJson(e as Map<String, dynamic>),
        ),
      ) {
    if (data['version'] != 1 || worlds.isEmpty) {
      throw const FormatException('Invalid saga');
    }
    var seenPlanned = false;
    for (var index = 0; index < worlds.length; index++) {
      final world = worlds[index];
      if (world.number != index + 1 || world.id != 'w${index + 1}') {
        throw const FormatException('Saga worlds must be numbered 1..n');
      }
      // 공개된 세계는 앞에서부터 이어져야 한다(중간이 빈 사가는 열 수 없다).
      if (world.playable && seenPlanned) {
        throw const FormatException('A playable world follows a planned one');
      }
      seenPlanned |= !world.playable;
      if (world.playable &&
          world.expansion &&
          (world.levelsAsset == null || world.storyAsset == null)) {
        throw const FormatException('Playable world needs level/story assets');
      }
    }
    if (!worlds.first.playable) {
      throw const FormatException('World 1 must be playable');
    }
  }

  static const asset = 'assets/worlds/saga.json';

  final StoryText title, premise;
  final List<SagaWorld> worlds;

  SagaWorld world(int number) => worlds[number - 1];
  SagaWorld? next(int number) => number < worlds.length ? worlds[number] : null;

  static Saga parse(String source) =>
      Saga.fromJson(jsonDecode(source) as Map<String, dynamic>);

  static Future<Saga> load() async => parse(await rootBundle.loadString(asset));
}
