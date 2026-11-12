import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/puzzle.dart';
import '../endless/endless_pool.dart';
import '../world/world_catalog.dart';

enum TrialCondition { moveLimit, noUndo, noPowers }

class TrialStage {
  const TrialStage({
    required this.sourceId,
    required this.sourceRevision,
    required this.symmetry,
    required this.condition,
    required this.minimumMoves,
  });

  final int sourceId, sourceRevision, symmetry, minimumMoves;
  final TrialCondition condition;

  int get world => Worlds.worldOf(sourceId);
  int get chapter => Worlds.chapterOf(sourceId);
  int? get moveLimit =>
      condition == TrialCondition.moveLimit ? minimumMoves + 2 : null;
  bool get permitsUndo => condition != TrialCondition.noUndo;
  bool get permitsPowers => condition != TrialCondition.noPowers;

  bool canMove(int moves) => moveLimit == null || moves < moveLimit!;
  bool acceptsClear(int moves) => moves >= minimumMoves && canMove(moves - 1);

  Level orient(Level source) {
    if (source.id != sourceId ||
        source.revision != sourceRevision ||
        source.world != world ||
        (symmetry >= 4 &&
            source.mechanics.values.any((rule) => !rule.reflectionSymmetric))) {
      throw FormatException('Trial source mismatch: $sourceId');
    }
    final level = transformLevel(
      source,
      symmetry,
      withoutPowers: !permitsPowers,
    );
    if (level.minimumMoves != minimumMoves) {
      throw FormatException('Trial minimum mismatch: $sourceId');
    }
    return level;
  }

  factory TrialStage.fromJson(Map<String, dynamic> data) {
    final id = data['sourceId'];
    final revision = data['sourceRevision'];
    final symmetry = data['symmetry'];
    final minimum = data['minimumMoves'];
    final condition = TrialCondition.values.asNameMap()[data['condition']];
    if (id is! int ||
        id < 1 ||
        !Worlds.contains(Worlds.worldOf(id), id) ||
        revision is! int ||
        revision < 1 ||
        symmetry is! int ||
        symmetry < 1 ||
        symmetry > 7 ||
        minimum is! int ||
        minimum < 1 ||
        condition == null) {
      throw const FormatException('Invalid trial stage');
    }
    return TrialStage(
      sourceId: id,
      sourceRevision: revision,
      symmetry: symmetry,
      condition: condition,
      minimumMoves: minimum,
    );
  }
}

class TrialCatalog {
  TrialCatalog._(List<TrialStage> stages) : stages = List.unmodifiable(stages);

  static const asset = 'assets/levels/trials_v1.json';
  static const stagesPerWorld = Worlds.chapterCount * 2;
  final List<TrialStage> stages;

  List<TrialStage> forWorld(int world, {int? chapter}) => [
    for (final stage in stages)
      if (stage.world == world && (chapter == null || stage.chapter == chapter))
        stage,
  ];

  static Future<TrialCatalog> load() async =>
      parse(await rootBundle.loadString(asset));

  static TrialCatalog parse(String source) {
    final data = jsonDecode(source);
    if (data is! Map || data['version'] != 1 || data['trials'] is! List) {
      throw const FormatException('Invalid trial catalog');
    }
    final stages = (data['trials'] as List).map((entry) {
      if (entry is! Map<String, dynamic>) {
        throw const FormatException('Invalid trial entry');
      }
      return TrialStage.fromJson(entry);
    }).toList();
    final catalog = TrialCatalog._(stages);
    if (stages.length != Worlds.finalWorld * stagesPerWorld ||
        stages.map((stage) => stage.sourceId).toSet().length != stages.length) {
      throw const FormatException('Missing or repeated trial stages');
    }
    for (var world = 1; world <= Worlds.finalWorld; world++) {
      for (var chapter = 1; chapter <= Worlds.chapterCount; chapter++) {
        if (catalog.forWorld(world, chapter: chapter).length != 2) {
          throw FormatException(
            'World $world chapter $chapter needs two trials',
          );
        }
      }
    }
    return catalog;
  }
}
