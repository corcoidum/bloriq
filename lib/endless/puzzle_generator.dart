import 'dart:math' as math;

import '../domain/puzzle.dart';

/// 무한 모드의 난이도 단계. 한 판을 짧게 유지하려고 최대 12이동으로 제한한다.
class EndlessTier {
  const EndlessTier({
    required this.size,
    required this.minMoves,
    required this.maxMoves,
    required this.minBlocks,
    required this.maxBlocks,
    required this.minWalls,
    required this.maxWalls,
    required this.devices,
  });

  final int size;
  final int minMoves, maxMoves;
  final int minBlocks, maxBlocks;
  final int minWalls, maxWalls;

  /// 한 판에 넣을 장치 종류 수.
  final int devices;

  static EndlessTier forCleared(int cleared) {
    if (cleared < 5) {
      return const EndlessTier(
        size: 3,
        minMoves: 3,
        maxMoves: 5,
        minBlocks: 0,
        maxBlocks: 1,
        minWalls: 0,
        maxWalls: 2,
        devices: 0,
      );
    }
    if (cleared < 15) {
      return const EndlessTier(
        size: 4,
        minMoves: 4,
        maxMoves: 8,
        minBlocks: 1,
        maxBlocks: 2,
        minWalls: 2,
        maxWalls: 6,
        devices: 0,
      );
    }
    if (cleared < 30) {
      return const EndlessTier(
        size: 4,
        minMoves: 5,
        maxMoves: 10,
        minBlocks: 1,
        maxBlocks: 3,
        minWalls: 2,
        maxWalls: 5,
        devices: 1,
      );
    }
    return const EndlessTier(
      size: 4,
      minMoves: 6,
      maxMoves: 12,
      minBlocks: 2,
      maxBlocks: 3,
      minWalls: 2,
      maxWalls: 5,
      devices: 2,
    );
  }
}

enum EndlessDevice { gate, eraser, hold, oneWay, goalOnly }

/// 깬 판 수에 따라 장치를 하나씩 풀어 준다.
List<EndlessDevice> unlockedDevices(int cleared) => [
  for (final (index, device) in EndlessDevice.values.indexed)
    if (cleared >= 15 + index * 3) device,
];

/// 회전·반전까지 같은 판을 하나로 보는 지문. 중복 판을 걸러 낸다.
String puzzleFingerprint(Level level) {
  var best = '';
  for (final mirror in [false, true]) {
    for (var rotation = 0; rotation < 4; rotation++) {
      (int, int) at(Position p) {
        var x = p.x, y = p.y, w = level.boardWidth, h = level.boardHeight;
        if (mirror) x = w - 1 - x;
        for (var i = 0; i < rotation; i++) {
          final nx = h - 1 - y, ny = x;
          x = nx;
          y = ny;
          final swap = w;
          w = h;
          h = swap;
        }
        return (x, y);
      }

      (int, int) dir(Position d) {
        var x = d.x, y = d.y;
        if (mirror) x = -x;
        for (var i = 0; i < rotation; i++) {
          final nx = -y, ny = x;
          x = nx;
          y = ny;
        }
        return (x, y);
      }

      final tokens = <String>[
        'start${at(level.startPosition)}',
        'exit${at(level.exitPosition)}',
        for (final block in level.blocks) 'block${at(block.position)}',
        for (final wall in level.obstacles) 'wall${at(wall)}',
        if (level.echoSwitch case final p?) 'switch${at(p)}',
        if (level.echoGate case final p?) 'gate${at(p)}',
        for (final p in level.echoErasers) 'eraser${at(p)}',
        for (final p in level.echoHolds) 'hold${at(p)}',
        for (final p in level.goalOnlyTiles) 'goalOnly${at(p)}',
        for (final e in level.oneWays.entries)
          'oneWay${at(e.key)}${dir(e.value)}',
      ]..sort();
      final text = tokens.join('|');
      if (best.isEmpty || text.compareTo(best) < 0) best = text;
    }
  }
  return best;
}

/// [seed]가 같으면 언제나 같은 판을 만든다. 조건에 맞는 판을 못 찾으면 null.
Level? generatePuzzle({
  required int seed,
  required int id,
  required int cleared,
  Set<String> recent = const {},
  int maxAttempts = 400,
}) {
  final random = math.Random(seed);
  final tier = EndlessTier.forCleared(cleared);
  final pool = unlockedDevices(cleared);
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final level = _candidate(random, id, tier, pool);
    if (level == null) continue;
    final moves = _shortest(level);
    if (moves == null || moves < tier.minMoves || moves > tier.maxMoves) {
      continue;
    }
    if (!_devicesMatter(level, moves)) continue;
    final finished = _withMinimum(level, moves);
    if (recent.contains(puzzleFingerprint(finished))) continue;
    return finished;
  }
  return null;
}

Level? _candidate(
  math.Random random,
  int id,
  EndlessTier tier,
  List<EndlessDevice> pool,
) {
  int between(int low, int high) => low + random.nextInt(high - low + 1);
  final cells = [
    for (var y = 0; y < tier.size; y++)
      for (var x = 0; x < tier.size; x++) Position(x, y),
  ]..shuffle(random);
  var next = 0;
  Position take() => cells[next++];
  final start = take(), exit = take();
  // 출발과 도착이 붙어 있으면 퍼즐이 되기 어렵다.
  if ((start.x - exit.x).abs() + (start.y - exit.y).abs() < 2) return null;

  final kinds = [...pool]..shuffle(random);
  final chosen = kinds.take(math.min(tier.devices, kinds.length)).toList();
  Position? echoSwitch, echoGate;
  final erasers = <Position>{}, holds = <Position>{}, goalOnly = <Position>{};
  final oneWays = <Position, Position>{};
  for (final device in chosen) {
    switch (device) {
      case EndlessDevice.gate:
        echoSwitch = take();
        echoGate = take();
      case EndlessDevice.eraser:
        erasers.add(take());
      case EndlessDevice.hold:
        holds.add(take());
      case EndlessDevice.goalOnly:
        goalOnly.add(take());
      case EndlessDevice.oneWay:
        const directions = [
          Position(1, 0),
          Position(-1, 0),
          Position(0, 1),
          Position(0, -1),
        ];
        oneWays[take()] = directions[random.nextInt(4)];
    }
  }
  final blocks = [
    for (var i = between(tier.minBlocks, tier.maxBlocks); i > 0; i--)
      Block(id: 'b$i', position: take()),
  ];
  final walls = [
    for (var i = between(tier.minWalls, tier.maxWalls); i > 0; i--)
      if (next < cells.length) take(),
  ];
  try {
    return Level(
      id: id,
      boardWidth: tier.size,
      boardHeight: tier.size,
      startPosition: start,
      exitPosition: exit,
      blocks: blocks,
      obstacles: walls,
      minimumMoves: 0,
      difficulty: 'endless',
      echoSwitch: echoSwitch,
      echoGate: echoGate,
      echoErasers: erasers,
      echoHolds: holds,
      oneWays: oneWays,
      goalOnlyTiles: goalOnly,
    );
  } on FormatException {
    return null;
  }
}

int? _shortest(Level level) {
  try {
    return const PuzzleSolver(maxStates: 20000).solve(level)?.length;
  } on StateError {
    return null;
  }
}

Level _withMinimum(
  Level level,
  int moves, {
  Position? echoSwitch,
  Position? echoGate,
  Set<Position>? erasers,
  Set<Position>? holds,
  Map<Position, Position>? oneWays,
  Set<Position>? goalOnly,
  List<Position>? obstacles,
  bool clearGate = false,
}) => Level(
  id: level.id,
  boardWidth: level.boardWidth,
  boardHeight: level.boardHeight,
  startPosition: level.startPosition,
  exitPosition: level.exitPosition,
  blocks: level.blocks,
  obstacles: obstacles ?? level.obstacles,
  minimumMoves: moves,
  difficulty: level.difficulty,
  echoSwitch: clearGate ? null : echoSwitch ?? level.echoSwitch,
  echoGate: clearGate ? null : echoGate ?? level.echoGate,
  echoErasers: erasers ?? level.echoErasers,
  echoHolds: holds ?? level.echoHolds,
  oneWays: oneWays ?? level.oneWays,
  goalOnlyTiles: goalOnly ?? level.goalOnlyTiles,
);

/// 장치를 빼도 최소 이동이 같으면 있으나 마나 한 장치이므로 버린다.
bool _devicesMatter(Level level, int moves) {
  bool same(Level changed) => _shortest(changed) == moves;
  if (level.echoGate != null) {
    // 문이 영원히 닫혀 있어도 똑같이 풀리면 문을 열 필요가 없는 판이다.
    final locked = _safe(
      () => _withMinimum(
        level,
        0,
        clearGate: true,
        obstacles: [...level.obstacles, level.echoGate!],
      ),
    );
    if (locked == null || same(locked)) return false;
  }
  if (level.echoErasers.isNotEmpty &&
      same(_withMinimum(level, 0, erasers: const {}))) {
    return false;
  }
  if (level.echoHolds.isNotEmpty &&
      same(_withMinimum(level, 0, holds: const {}))) {
    return false;
  }
  if (level.oneWays.isNotEmpty &&
      same(_withMinimum(level, 0, oneWays: const {}))) {
    return false;
  }
  if (level.goalOnlyTiles.isNotEmpty &&
      same(_withMinimum(level, 0, goalOnly: const {}))) {
    return false;
  }
  return true;
}

Level? _safe(Level Function() build) {
  try {
    return build();
  } on FormatException {
    return null;
  }
}

/// 회전·반전한 판. 규칙이 대칭이라 최소 이동은 그대로다.
Level transformLevel(
  Level level, {
  required int id,
  required int rotation,
  required bool mirror,
}) {
  var w = level.boardWidth, h = level.boardHeight;
  Position at(Position p) {
    var x = p.x, y = p.y, width = level.boardWidth, height = level.boardHeight;
    if (mirror) x = width - 1 - x;
    for (var i = 0; i < rotation; i++) {
      final nx = height - 1 - y, ny = x;
      x = nx;
      y = ny;
      final swap = width;
      width = height;
      height = swap;
    }
    return Position(x, y);
  }

  Position dir(Position d) {
    var x = d.x, y = d.y;
    if (mirror) x = -x;
    for (var i = 0; i < rotation; i++) {
      final nx = -y, ny = x;
      x = nx;
      y = ny;
    }
    return Position(x, y);
  }

  if (rotation.isOdd) {
    final swap = w;
    w = h;
    h = swap;
  }
  return Level(
    id: id,
    boardWidth: w,
    boardHeight: h,
    startPosition: at(level.startPosition),
    exitPosition: at(level.exitPosition),
    blocks: [
      for (final block in level.blocks)
        Block(id: block.id, position: at(block.position)),
    ],
    obstacles: [for (final p in level.obstacles) at(p)],
    minimumMoves: level.minimumMoves,
    difficulty: 'endless',
    echoSwitch: level.echoSwitch == null ? null : at(level.echoSwitch!),
    echoGate: level.echoGate == null ? null : at(level.echoGate!),
    echoErasers: {for (final p in level.echoErasers) at(p)},
    echoHolds: {for (final p in level.echoHolds) at(p)},
    oneWays: {
      for (final entry in level.oneWays.entries)
        at(entry.key): dir(entry.value),
    },
    goalOnlyTiles: {for (final p in level.goalOnlyTiles) at(p)},
  );
}
