import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design/game_theme.dart';
import '../design/star_art.dart';
import 'constellation_catalog.dart';

/// 인트로·승리 패널·도감이 같은 별과 선을 그린다. 상태는 모양으로도 구분한다:
/// 잠든 별은 빈 고리, 저장 대기는 점선 고리, 밝힌 별은 채운 원, 황금은 네 갈래 별.
class ConstellationPainter extends CustomPainter {
  ConstellationPainter({
    required this.definition,
    required this.lit,
    required this.colors,
    this.golden = 0,
    this.pendingNode,
    this.highlightNode,
    this.nodeReveal = 1,
    this.spark,
    this.lineReveal = 1,
    this.silhouette,
    this.silhouetteOpacity = 0,
    this.guides = true,
  });

  final ConstellationDefinition definition;
  final List<bool> lit;
  final GameColors colors;

  /// 0이면 일반, 1이면 황금. 중간 값은 전환 연출에 쓴다.
  final double golden;
  final int? pendingNode;

  /// 이번에 켜지는 별. 이 별에 닿는 선만 [lineReveal]로 그린다.
  final int? highlightNode;
  final double nodeReveal;

  /// 위에서 [highlightNode]로 내려오는 별빛의 진행도. null이면 없다.
  final double? spark;

  /// 별자리 완성 연출에서는 모든 선을, 아니면 [highlightNode]의 선을 늘인다.
  final double lineReveal;
  final ui.Image? silhouette;
  final double silhouetteOpacity;
  final bool guides;

  bool _isLit(int index) => index < lit.length && lit[index];

  @override
  void paint(Canvas canvas, Size size) {
    final extent = math.min(size.width, size.height);
    final radius = (extent * .045).clamp(3.0, 9.0);
    final area = (Offset.zero & size).deflate(radius * 2.4);
    Offset at(int index) {
      final node = definition.nodes[index];
      return area.topLeft + Offset(node.dx * area.width, node.dy * area.height);
    }

    final paint = Paint()..isAntiAlias = true;
    if (silhouette case final image? when silhouetteOpacity > 0) {
      StarArt.draw(
        canvas,
        image,
        Rect.fromCenter(
          center: area.center,
          width: extent * .92,
          height: extent * .92,
        ),
        opacity: silhouetteOpacity.clamp(0.0, 1.0),
        tint: colors.primary,
      );
    }

    final lineColor = Color.lerp(colors.primary, colors.reward, golden)!;
    for (final (a, b) in definition.edges) {
      final from = at(a), to = at(b);
      if (guides) {
        canvas.drawLine(
          from,
          to,
          paint
            ..color = colors.outline.withValues(alpha: .22)
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke,
        );
      }
      if (!_isLit(a) || !_isLit(b)) continue;
      final growing =
          highlightNode == null || a == highlightNode || b == highlightNode;
      final reveal = growing ? lineReveal.clamp(0.0, 1.0) : 1.0;
      if (reveal <= 0) continue;
      // 새로 켜진 별에서 바깥으로 선이 자란다.
      final start = b == highlightNode ? to : from;
      final end = b == highlightNode ? from : to;
      canvas.drawLine(
        start,
        Offset.lerp(start, end, reveal)!,
        paint
          ..color = lineColor.withValues(alpha: .78)
          ..strokeWidth = math.max(1.4, radius * .32)
          ..strokeCap = StrokeCap.round,
      );
    }

    for (var i = 0; i < definition.nodes.length; i++) {
      final center = at(i);
      final node = radius * (i == definition.guardianNode ? 1.3 : 1);
      if (i == pendingNode && !_isLit(i)) {
        _dashedRing(canvas, center, node, colors.rewardInk);
        continue;
      }
      // 켜지는 중인 별은 빈 고리 위에서 자라난다.
      if (!_isLit(i) || (i == highlightNode && nodeReveal < 1)) {
        canvas.drawCircle(
          center,
          node,
          paint
            ..color = colors.outline.withValues(alpha: .75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.2, node * .22),
        );
        if (!_isLit(i)) continue;
      }
      final reveal = i == highlightNode
          ? Curves.easeOutBack.transform(nodeReveal.clamp(0.0, 1.0))
          : 1.0;
      if (reveal <= 0) continue;
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(
        center,
        node * 2.3 * reveal,
        paint..color = colors.reward.withValues(alpha: .16),
      );
      if (golden > 0) {
        canvas.drawPath(
          _sparkle(center, node * 1.7 * reveal),
          paint..color = colors.reward.withValues(alpha: golden),
        );
      }
      canvas.drawCircle(
        center,
        node * reveal * (1 - .25 * golden),
        paint..color = Color.lerp(colors.reward, colors.highlight, .15)!,
      );
    }

    if ((spark, highlightNode) case (final t?, final target?)
        when t > 0 && t < 1) {
      final from = Offset(size.width / 2, 0);
      final to = at(target);
      final eased = Curves.easeInOutCubic.transform(t);
      // 살짝 휘어 내려오는 별빛. 꼬리는 반투명 원 세 개로만 표현한다.
      Offset point(double v) =>
          Offset.lerp(from, to, v)! +
          Offset(math.sin(v * math.pi) * radius * 3, 0);
      for (var trail = 3; trail >= 0; trail--) {
        final v = (eased - trail * .06).clamp(0.0, 1.0);
        canvas.drawCircle(
          point(v),
          radius * (.7 - trail * .12),
          paint
            ..style = PaintingStyle.fill
            ..color = colors.reward.withValues(alpha: 1 - trail * .24),
        );
      }
    }
  }

  void _dashedRing(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, radius * .24)
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: center, radius: radius);
    for (var i = 0; i < 8; i++) {
      canvas.drawArc(rect, i * math.pi / 4, math.pi / 7, false, paint);
    }
  }

  static Path _sparkle(Offset center, double radius) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + i * math.pi / 4;
      final r = i.isEven ? radius : radius * .32;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant ConstellationPainter old) =>
      old.definition != definition ||
      !_sameMask(old.lit, lit) ||
      old.colors != colors ||
      old.golden != golden ||
      old.pendingNode != pendingNode ||
      old.highlightNode != highlightNode ||
      old.nodeReveal != nodeReveal ||
      old.spark != spark ||
      old.lineReveal != lineReveal ||
      old.silhouette != silhouette ||
      old.silhouetteOpacity != silhouetteOpacity ||
      old.guides != guides;

  static bool _sameMask(List<bool> a, List<bool> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
