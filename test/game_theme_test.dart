import 'dart:math' as math;

import 'package:bloriq/design/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (math.max(a, b) + .05) / (math.min(a, b) + .05);
}

void main() {
  test('forest themes preserve mint, Echo and gold semantic roles', () {
    for (final colors in [GameColors.light, GameColors.dark]) {
      expect(colors.goal.g, greaterThan(colors.goal.r));
      expect(colors.echo.b, greaterThan(colors.echo.g));
      expect(colors.reward.r, greaterThan(colors.reward.b));
    }
    expect(GameColors.dark.background.computeLuminance(), lessThan(.03));
    expect(GameColors.light.background.computeLuminance(), greaterThan(.8));
    expect(GameTypography.canvasFontFamily, 'Jua');
  });

  test('body and semantic text maintain at least 4.5:1 contrast', () {
    for (final colors in [GameColors.light, GameColors.dark]) {
      for (final background in [colors.background, colors.surface]) {
        for (final foreground in [
          colors.text,
          colors.secondaryText,
          colors.primaryInk,
          colors.echoInk,
          colors.goalInk,
          colors.rewardInk,
        ]) {
          expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
        }
      }
      expect(
        contrast(colors.blockSymbol, colors.primary),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(colors.blockSymbol, colors.goal),
        greaterThanOrEqualTo(4.5),
      );
      for (final tile in [colors.tileTop, colors.tileBottom]) {
        expect(contrast(colors.echoInk, tile), greaterThanOrEqualTo(4.5));
      }
    }
  });

  test(
    'Material controls use the same palette with readable filled buttons',
    () {
      for (final theme in [GameTheme.light, GameTheme.dark]) {
        final colors = theme.brightness == Brightness.light
            ? GameColors.light
            : GameColors.dark;
        expect(theme.scaffoldBackgroundColor, colors.background);
        expect(theme.dialogTheme.backgroundColor, colors.surface);
        expect(theme.colorScheme.onSurface, colors.text);
        expect(
          contrast(theme.colorScheme.onPrimary, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      }
    },
  );
}
