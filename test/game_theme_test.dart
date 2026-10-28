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
  test('requested core palettes remain fixed', () {
    expect(GameColors.light.background, const Color(0xFFF7F9FE));
    expect(GameColors.light.primary, const Color(0xFF6B8DFF));
    expect(GameColors.light.echo, const Color(0xFFA78BFA));
    expect(GameColors.light.goal, const Color(0xFF27BCA0));
    expect(GameColors.light.reward, const Color(0xFFF7C86C));
    expect(GameColors.dark.background, const Color(0xFF101827));
    expect(GameColors.dark.boardSurface, const Color(0xFF243249));
    expect(GameColors.dark.primary, const Color(0xFF85A4FF));
    expect(GameColors.dark.echo, const Color(0xFFB6A0FF));
    expect(GameColors.dark.goal, const Color(0xFF45D7B4));
    expect(GameColors.dark.reward, const Color(0xFFFFD47B));
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
