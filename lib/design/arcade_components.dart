import 'package:flutter/material.dart';

import '../settings/game_settings.dart';
import 'game_theme.dart';
import 'star_art.dart';

bool prefersReducedMotion(BuildContext context, GameSettings settings) =>
    settings.reduceMotion ||
    MediaQuery.disableAnimationsOf(context) ||
    MediaQuery.accessibleNavigationOf(context) ||
    WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion;

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return Text(
      'BLORIQ',
      style: GameTypography.brand.copyWith(color: colors.rewardInk),
    );
  }
}

/// 매 스테이지 상단 중앙에 고정하는 금빛 게임 로고.
class GameWordmark extends StatelessWidget {
  const GameWordmark({super.key, this.size = 32});
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final style = GameTypography.brand.copyWith(
      fontSize: size,
      letterSpacing: size * .16,
      height: 1,
    );
    return Semantics(
      header: true,
      label: 'BLORIQ',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: size * .42, color: colors.goal),
            SizedBox(width: size * .18),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.highlight,
                  colors.reward,
                  const Color(0xFFE0A85A),
                ],
              ).createShader(bounds),
              child: Text(
                'BLORIQ',
                style: style.copyWith(
                  shadows: [
                    Shadow(
                      color: colors.reward.withValues(alpha: .55),
                      blurRadius: size * .45,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: size * .18),
            Icon(Icons.auto_awesome, size: size * .42, color: colors.echo),
          ],
        ),
      ),
    );
  }
}

class ArcadeBackdrop extends StatelessWidget {
  const ArcadeBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: colors.background),
        Positioned.fill(
          child: ExcludeSemantics(
            child: Image.asset(
              StarArt.forest,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              cacheWidth: 1080,
            ),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(color: colors.background.withValues(alpha: .08)),
        ),
        child,
      ],
    );
  }
}

class ArcadeSurface extends StatelessWidget {
  const ArcadeSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(GameSpacing.page),
    this.accent,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    return Container(
      padding: padding,
      decoration: GameTheme.surfaceDecoration(colors, accent: accent),
      child: child,
    );
  }
}

class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: GameTypography.label.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}
