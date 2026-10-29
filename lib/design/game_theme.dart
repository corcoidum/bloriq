import 'package:flutter/material.dart';

/// 색의 역할은 모든 스테이지에서 고정하고 테마별 명도만 조정한다.
@immutable
class GameColors {
  const GameColors({
    required this.background,
    required this.surface,
    required this.boardSurface,
    required this.tileTop,
    required this.tileBottom,
    required this.primary,
    required this.echo,
    required this.goal,
    required this.reward,
    required this.text,
    required this.secondaryText,
    required this.slate,
    required this.cyan,
    required this.error,
    required this.primaryInk,
    required this.echoInk,
    required this.goalInk,
    required this.rewardInk,
    required this.outline,
    required this.highlight,
    required this.blockSymbol,
  });

  final Color background;
  final Color surface;
  final Color boardSurface;
  final Color tileTop;
  final Color tileBottom;
  final Color primary;
  final Color echo;
  final Color goal;
  final Color reward;
  final Color text;
  final Color secondaryText;
  final Color slate;
  final Color cyan;
  final Color error;

  /// 밝은 브랜드 색은 면에 사용하고, 작은 글자는 대비가 높은 ink를 쓴다.
  final Color primaryInk;
  final Color echoInk;
  final Color goalInk;
  final Color rewardInk;
  final Color outline;
  final Color highlight;
  final Color blockSymbol;

  static const light = GameColors(
    background: Color(0xFFF7F9FE),
    surface: Color(0xFFFFFFFF),
    boardSurface: Color(0xFFD8E2F3),
    tileTop: Color(0xFFF7F9FE),
    tileBottom: Color(0xFFE9EFFB),
    primary: Color(0xFF6B8DFF),
    echo: Color(0xFFA78BFA),
    goal: Color(0xFF27BCA0),
    reward: Color(0xFFF7C86C),
    text: Color(0xFF25334A),
    secondaryText: Color(0xFF586982),
    slate: Color(0xFF71839D),
    cyan: Color(0xFF147C9B),
    error: Color(0xFFBE444F),
    primaryInk: Color(0xFF3E57BC),
    echoInk: Color(0xFF7054B8),
    goalInk: Color(0xFF11745F),
    rewardInk: Color(0xFF825A12),
    outline: Color(0xFF8391AA),
    highlight: Color(0xFFFFFFFF),
    blockSymbol: Color(0xFF101827),
  );

  static const dark = GameColors(
    background: Color(0xFF101827),
    surface: Color(0xFF1A2638),
    boardSurface: Color(0xFF243249),
    tileTop: Color(0xFF2D3D56),
    tileBottom: Color(0xFF27364E),
    primary: Color(0xFF85A4FF),
    echo: Color(0xFFB6A0FF),
    goal: Color(0xFF45D7B4),
    reward: Color(0xFFFFD47B),
    text: Color(0xFFF0F4FF),
    secondaryText: Color(0xFFA8B7CD),
    slate: Color(0xFF6E819E),
    cyan: Color(0xFF65CBE5),
    error: Color(0xFFFF9BA4),
    primaryInk: Color(0xFF85A4FF),
    echoInk: Color(0xFFB6A0FF),
    goalInk: Color(0xFF45D7B4),
    rewardInk: Color(0xFFFFD47B),
    outline: Color(0xFF7D8DA7),
    highlight: Color(0xFFF0F4FF),
    blockSymbol: Color(0xFF101827),
  );
}

abstract final class GameTypography {
  static const canvasFontFamily = 'Roboto';
  static const brand = TextStyle(
    fontFamily: canvasFontFamily,
    fontSize: 23,
    fontWeight: FontWeight.w900,
    letterSpacing: 2,
  );
  static const reward = TextStyle(
    fontFamily: canvasFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w800,
  );
  static const label = TextStyle(
    fontFamily: canvasFontFamily,
    fontWeight: FontWeight.w700,
  );
}

abstract final class GameSpacing {
  static const tiny = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const page = 16.0;
  static const large = 24.0;
  static const radius = 20.0;
  static const maxBoardWidth = 460.0;
}

abstract final class GameEffects {
  static const introDuration = Duration(seconds: 4);
  static const moveDuration = Duration(milliseconds: 220);
  static const celebrationDuration = Duration(milliseconds: 1450);
  static const panelDuration = Duration(milliseconds: 200);
  static const particleCount = 16;
}

abstract final class GameTheme {
  static ThemeData get light => _build(Brightness.light, GameColors.light);
  static ThemeData get dark => _build(Brightness.dark, GameColors.dark);

  static GameColors colorsOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? GameColors.dark
      : GameColors.light;

  static BoxDecoration surfaceDecoration(GameColors colors, {Color? accent}) =>
      BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(GameSpacing.radius),
        border: Border.all(
          color: (accent ?? colors.outline).withValues(
            alpha: accent == null ? .22 : .55,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: colors.blockSymbol.withValues(alpha: .06),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      );

  static ThemeData _build(Brightness brightness, GameColors colors) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: colors.primary,
          brightness: brightness,
        ).copyWith(
          primary: colors.primaryInk,
          onPrimary: brightness == Brightness.dark
              ? colors.blockSymbol
              : colors.surface,
          secondary: colors.echo,
          onSecondary: colors.blockSymbol,
          tertiary: colors.goalInk,
          onTertiary: brightness == Brightness.dark
              ? colors.blockSymbol
              : colors.surface,
          surface: colors.surface,
          onSurface: colors.text,
          onSurfaceVariant: colors.secondaryText,
          outline: colors.outline,
          error: colors.error,
          surfaceTint: Colors.transparent,
        );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.surface,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: colors.text,
        displayColor: colors.text,
      ),
      iconTheme: IconThemeData(color: colors.secondaryText),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dividerColor: colors.outline.withValues(alpha: .3),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colors.text,
          fontWeight: FontWeight.w800,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GameSpacing.radius),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: base.textTheme.bodyLarge?.copyWith(color: colors.text),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: GameSpacing.page),
          textStyle: GameTypography.label,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: colors.primaryInk,
          side: BorderSide(color: colors.outline),
          textStyle: GameTypography.label,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
