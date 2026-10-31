import 'dart:ui';

import '../l10n/app_localizations.dart';

/// 챕터 하나의 별자리 모양. 노드 순서는 챕터 안의 레벨 순서와 같고,
/// 마지막 노드는 항상 수호 정령의 별문이다.
class ConstellationDefinition {
  const ConstellationDefinition({
    required this.chapter,
    required this.nodes,
    required this.edges,
  });

  final int chapter;

  /// 0..1로 정규화한 좌표. 그리는 쪽이 영역 크기에 맞춰 늘린다.
  final List<Offset> nodes;
  final List<(int, int)> edges;

  int get guardianNode => nodes.length - 1;

  String name(AppLocalizations t) => switch (chapter) {
    1 => t.constellationName1,
    2 => t.constellationName2,
    3 => t.constellationName3,
    4 => t.constellationName4,
    _ => t.constellationName5,
  };
}

/// 코드 상수로 두어 에셋 로딩 실패나 스키마 변경 경로를 만들지 않는다.
abstract final class ConstellationCatalog {
  static const all = [
    // 달꽃자리: 초승달 곡선 끝, 하늘 높이 핀 달꽃 (Lunabel).
    // 인트로의 금빛 별이 별문에서 이 꽃(마지막 노드)까지 올라간다.
    ConstellationDefinition(
      chapter: 1,
      nodes: [
        Offset(.22, .76),
        Offset(.16, .48),
        Offset(.30, .24),
        Offset(.54, .30),
        Offset(.78, .12),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 4)],
    ),
    // 다섯빛자리: 다섯 별이 만나는 왕관 (Lumen)
    ConstellationDefinition(
      chapter: 2,
      nodes: [
        Offset(.16, .68),
        Offset(.30, .28),
        Offset(.50, .52),
        Offset(.70, .28),
        Offset(.84, .68),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 0)],
    ),
    // 봉인편지자리: 봉투와 가운데 봉인 (Ello)
    ConstellationDefinition(
      chapter: 3,
      nodes: [
        Offset(.16, .30),
        Offset(.84, .30),
        Offset(.84, .72),
        Offset(.16, .72),
        Offset(.50, .54),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 0), (0, 4), (4, 1)],
    ),
    // 바람고리자리: 안쪽으로 감기는 바람 (Hamo)
    ConstellationDefinition(
      chapter: 4,
      nodes: [
        Offset(.30, .24),
        Offset(.74, .30),
        Offset(.68, .70),
        Offset(.30, .64),
        Offset(.50, .46),
      ],
      edges: [(0, 1), (1, 2), (2, 3), (3, 4)],
    ),
    // 첫별자리: 세 수정이 솟은 별관 (Aster)
    ConstellationDefinition(
      chapter: 5,
      nodes: [
        Offset(.20, .70),
        Offset(.32, .32),
        Offset(.68, .32),
        Offset(.80, .70),
        Offset(.50, .14),
      ],
      edges: [(0, 1), (1, 4), (4, 2), (2, 3), (3, 0)],
    ),
  ];

  static ConstellationDefinition? forChapter(int chapter) =>
      all.where((c) => c.chapter == chapter).firstOrNull;
}
