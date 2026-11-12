import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../domain/mechanics/clock_arrow.dart';
import '../domain/mechanics/ice.dart';
import '../domain/mechanics/mirror_pair.dart';
import '../domain/mechanics/shelf_door.dart';
import '../domain/puzzle.dart';
import 'endless_rules.dart';

/// 최단 수를 보존하며 판을 돌리거나 뒤집는다.
/// [symmetry] 0..7: 비트 2는 좌우 뒤집기, 아래 두 비트는 90° 회전 수.
Level transformLevel(Level level, int symmetry) {
  if (symmetry < 0 || symmetry > 7) {
    throw ArgumentError.value(symmetry, 'symmetry');
  }
  final mirror =
      symmetry >= 4 &&
      level.mechanics.values.every((mechanic) => mechanic.reflectionSymmetric);
  final turns = symmetry % 4;
  if (turns == 0 && !mirror) return level;
  final width = level.boardWidth, height = level.boardHeight;

  Position point(Position p) {
    var x = mirror ? width - 1 - p.x : p.x;
    var y = p.y;
    var h = height, w = width;
    for (var i = 0; i < turns; i++) {
      final nx = h - 1 - y;
      y = x;
      x = nx;
      final t = w;
      w = h;
      h = t;
    }
    return Position(x, y);
  }

  Position direction(Position d) {
    var dx = mirror ? -d.x : d.x;
    var dy = d.y;
    for (var i = 0; i < turns; i++) {
      final nx = -dy;
      dy = dx;
      dx = nx;
    }
    return Position(dx, dy);
  }

  final swap = turns.isOdd;
  return Level(
    id: level.id,
    revision: level.revision,
    boardWidth: swap ? height : width,
    boardHeight: swap ? width : height,
    startPosition: point(level.startPosition),
    exitPosition: point(level.exitPosition),
    blocks: [for (final b in level.blocks) b.at(point(b.position))],
    obstacles: [for (final o in level.obstacles) point(o)],
    minimumMoves: level.minimumMoves,
    difficulty: level.difficulty,
    mechanics: [
      for (final mechanic in level.mechanics.values)
        mechanic.reorient(point, direction),
    ],
    solution: [
      for (final move in level.solution)
        PuzzleMove(move.blockId, point(move.target), power: move.power),
    ],
    world: level.world,
    bareHandedMoves: level.bareHandedMoves,
    requiredPowers: level.requiredPowers,
    featuredPower: level.featuredPower,
    availablePowers: level.availablePowers,
  );
}

/// 항해 한 판: 묶음 속 판 id 와 돌리기/뒤집기 방법.
class VoyageBoard {
  const VoyageBoard(this.id, this.symmetry);
  final int id;
  final int symmetry;

  Map<String, dynamic> toJson() => {'id': id, 'symmetry': symmetry};
  static VoyageBoard fromJson(Map<String, dynamic> json) {
    final id = json['id'], symmetry = json['symmetry'];
    if (id is! int || symmetry is! int || symmetry < 0 || symmetry > 7) {
      throw const FormatException('Invalid voyage board');
    }
    return VoyageBoard(id, symmetry);
  }
}

enum MechanicSea {
  mirror(3, MirrorPair.typeId),
  clock(4, ClockArrow.typeId),
  ice(5, Ice.typeId),
  shelf(6, ShelfDoor.typeId);

  const MechanicSea(this.world, this.mechanic);
  final int world;
  final String mechanic;
}

/// 기존 깊이별 판과 세계를 마치면 열리는 기믹 판을 같은 ID로 찾는다.
class EndlessPool {
  EndlessPool(
    Map<int, List<Level>> tiers, {
    Map<MechanicSea, List<Level>> seas = const {},
  }) : tiers = Map.unmodifiable({
         for (final entry in tiers.entries)
           entry.key: List<Level>.unmodifiable(entry.value),
       }),
       seas = Map.unmodifiable({
         for (final entry in seas.entries)
           entry.key: List<Level>.unmodifiable(entry.value),
       }),
       _byId = {
         for (final list in tiers.values)
           for (final level in list) level.id: level,
         for (final list in seas.values)
           for (final level in list) level.id: level,
       },
       _seaById = {
         for (final entry in seas.entries)
           for (final level in entry.value) level.id: entry.key,
       } {
    for (var tier = 1; tier <= 4; tier++) {
      if ((this.tiers[tier] ?? const []).isEmpty) {
        throw FormatException('Endless tier $tier is empty');
      }
    }
    final boardCount = [
      ...this.tiers.values,
      ...this.seas.values,
    ].fold(0, (total, list) => total + list.length);
    if (boardCount != _byId.length) {
      throw const FormatException('Duplicate endless board ID');
    }
  }

  static const asset = 'assets/levels/endless_pool_v1.json';
  static const worldAsset = 'assets/levels/endless_pool_v2.json';

  static const _baseMechanics = {
    'echoEraser',
    'echoHold',
    'oneWay',
    'goalOnly',
    'echoGate',
  };

  final Map<int, List<Level>> tiers;
  final Map<MechanicSea, List<Level>> seas;
  final Map<int, Level> _byId;
  final Map<int, MechanicSea> _seaById;

  int get length => _byId.length;

  static EndlessPool parse(String source, {String? worldSource}) {
    final tiers = <int, List<Level>>{};
    for (final raw
        in (jsonDecode(source) as List).cast<Map<String, dynamic>>()) {
      final tier = raw['tier'];
      if (tier is! int || tier < 1 || tier > 4) {
        throw const FormatException('Invalid endless tier');
      }
      final level = Level.fromJson({...raw, 'difficulty': 'endless-$tier'});
      if (!level.mechanics.keys.every(_baseMechanics.contains)) {
        throw FormatException(
          'Unexpected mechanic on endless board ${level.id}',
        );
      }
      (tiers[tier] ??= []).add(level);
    }
    final seas = <MechanicSea, List<Level>>{};
    if (worldSource != null) {
      for (final raw
          in (jsonDecode(worldSource) as List).cast<Map<String, dynamic>>()) {
        final world = raw['mechanicWorld'];
        final sea = MechanicSea.values
            .where((sea) => sea.world == world)
            .firstOrNull;
        if (sea == null) {
          throw const FormatException('Invalid endless mechanic world');
        }
        final level = Level.fromJson({
          ...raw,
          'difficulty': 'endless-world-$world',
        });
        if (!level.mechanics.containsKey(sea.mechanic) ||
            !level.mechanics.keys.every(
              (kind) => kind == sea.mechanic || _baseMechanics.contains(kind),
            ) ||
            level.minimumMoves < 6 ||
            level.minimumMoves > 14 ||
            level.availablePowers.isNotEmpty) {
          throw FormatException('Invalid ${sea.mechanic} board ${level.id}');
        }
        (seas[sea] ??= []).add(level);
      }
    }
    return EndlessPool(tiers, seas: seas);
  }

  /// loadString 은 큰 파일을 별도 isolate 에서 풀므로, 바이트를 받아 직접 푼다.
  static Future<EndlessPool> load() async {
    final base = await rootBundle.load(asset);
    final world = await rootBundle.load(worldAsset);
    return parse(
      utf8.decode(
        base.buffer.asUint8List(base.offsetInBytes, base.lengthInBytes),
      ),
      worldSource: utf8.decode(
        world.buffer.asUint8List(world.offsetInBytes, world.lengthInBytes),
      ),
    );
  }

  MechanicSea? seaOf(int boardId) => _seaById[boardId];

  bool isAvailable(VoyageBoard board, Set<int> completedWorlds) {
    final sea = seaOf(board.id);
    return _byId.containsKey(board.id) &&
        (sea == null || completedWorlds.contains(sea.world));
  }

  /// 판을 화면에 놓을 모양으로 꺼낸다. 묶음이 바뀌어 id 가 없으면 null.
  Level? level(VoyageBoard board) => switch (_byId[board.id]) {
    final level? => transformLevel(level, board.symmetry),
    null => null,
  };

  /// [depth]번째 바다의 판. 항해 씨앗과 깊이로 정해지므로 같은 항해를 다시 열어도
  /// 같은 판이 나온다. 이번 항해에서 이미 나온 판([used])은 되도록 피한다.
  VoyageBoard pick({
    required int seed,
    required int depth,
    required Set<int> used,
    Set<int> completedWorlds = const {},
  }) {
    final rng = math.Random(seed ^ (depth * 7919));
    final tier = EndlessRules.tierForDepth(depth);
    final worldBoards = [
      if (depth >= 6 && depth % 3 == 0)
        for (final sea in MechanicSea.values)
          if (completedWorlds.contains(sea.world)) ...?seas[sea],
    ];
    final list = worldBoards.isEmpty ? tiers[tier]! : worldBoards;
    final fresh = [
      for (final level in list)
        if (!used.contains(level.id)) level,
    ];
    final from = fresh.isEmpty ? list : fresh;
    final level = from[rng.nextInt(from.length)];
    final symmetries =
        level.mechanics.values.every((rule) => rule.reflectionSymmetric)
        ? 8
        : 4;
    return VoyageBoard(level.id, rng.nextInt(symmetries));
  }
}
