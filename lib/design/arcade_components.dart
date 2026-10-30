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

class ArcadeBackdrop extends StatelessWidget {
  const ArcadeBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = GameTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
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
              color: dark
                  ? Colors.white
                  : colors.background.withValues(alpha: .92),
              colorBlendMode: dark ? BlendMode.modulate : BlendMode.srcOver,
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
