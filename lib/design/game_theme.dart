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
    background: Color(0xFFF6F2E9),
    surface: Color(0xFFFFFAF2),
    boardSurface: Color(0xFFB6BCD1),
    tileTop: Color(0xFFF6F2E9),
    tileBottom: Color(0xFFE5E6EE),
    primary: Color(0xFF6C83BE),
    echo: Color(0xFF9472CC),
    goal: Color(0xFF8BDBB9),
    reward: Color(0xFFF0C97E),
    text: Color(0xFF25314B),
    secondaryText: Color(0xFF515C75),
    slate: Color(0xFF687891),
    cyan: Color(0xFF236A79),
    error: Color(0xFFB43E52),
    primaryInk: Color(0xFF3F5590),
    echoInk: Color(0xFF68429B),
    goalInk: Color(0xFF22654F),
    rewardInk: Color(0xFF75500D),
    outline: Color(0xFF707B9C),
    highlight: Color(0xFFFFFAF2),
    blockSymbol: Color(0xFF101827),
  );

  static const dark = GameColors(
    background: Color(0xFF101C38),
    surface: Color(0xFF1B2947),
    boardSurface: Color(0xFF141F3B),
    tileTop: Color(0xFF223254),
    tileBottom: Color(0xFF1D2B4B),
    primary: Color(0xFFA9B6EF),
    echo: Color(0xFFC2AAFF),
    goal: Color(0xFF99E0BF),
    reward: Color(0xFFF3D18B),
    text: Color(0xFFFFF1D3),
    secondaryText: Color(0xFFBDC4E6),
    slate: Color(0xFF536886),
    cyan: Color(0xFF91D7E2),
    error: Color(0xFFFFADB8),
    primaryInk: Color(0xFFA9B6EF),
    echoInk: Color(0xFFC2AAFF),
    goalInk: Color(0xFF99E0BF),
    rewardInk: Color(0xFFF3D18B),
    outline: Color(0xFF6B79BB),
    highlight: Color(0xFFFFF1D3),
    blockSymbol: Color(0xFF101C38),
  );
}

abstract final class GameTypography {
  static const canvasFontFamily = 'Jua';
  static const brand = TextStyle(
    fontFamily: canvasFontFamily,
    fontFamilyFallback: ['NanumGothic'],
    fontSize: 23,
    fontWeight: FontWeight.w400,
    letterSpacing: 2,
  );
  static const reward = TextStyle(
    fontFamily: canvasFontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w400,
  );
  static const label = TextStyle(
    fontFamily: 'NanumGothic',
    fontSize: 15,
    fontWeight: FontWeight.w600,
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
  static const dragThresholdFraction = .24;
  static const introDuration = Duration(seconds: 4);
  static const moveDuration = Duration(milliseconds: 220);
  static const celebrationDuration = Duration(milliseconds: 1450);

  /// 별자리 완성은 수호 정령 발견과 같은 길이를 쓴다. 새 별은 기본 축하 안에 켜진다.
  static const constellationCompleteDuration = Duration(milliseconds: 2200);
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
        color: colors.surface.withValues(alpha: .96),
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
          primary: brightness == Brightness.dark
              ? colors.reward
              : colors.primaryInk,
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
      fontFamily: 'NanumGothic',
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
      iconTheme: IconThemeData(color: colors.rewardInk),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      dividerColor: colors.outline.withValues(alpha: .3),
      dialogTheme: DialogThemeData(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: colors.text,
          fontWeight: FontWeight.w400,
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
          backgroundColor: colors.surface.withValues(alpha: .72),
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
