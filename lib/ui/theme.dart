import 'package:flutter/material.dart';

/// Qwallet's palette, taken from the logo rather than invented: the gold of the
/// wallet mark, the near-black of the wordmark, and the cream the mark sits on.
///
/// One measurement drives most of the decisions here. Gold on white is 2.89:1,
/// which fails AA even for large text, so nothing gold ever carries white text —
/// filled buttons take a near-black label (6.28:1) instead. That is also why the
/// gold is used as an accent and a fill, never as body copy.
abstract final class QwalletColors {
  /// The wallet mark. #C0902D in the logo's own SVG.
  static const gold = Color(0xFFC0902D);

  /// A darker step, for text and icons that must read as brand rather than ink.
  static const goldDeep = Color(0xFF8A6A1F);

  /// Lifted for dark surfaces, where the logo gold is too heavy to read.
  static const goldLight = Color(0xFFE8C87A);

  /// The wordmark.
  static const ink = Color(0xFF1A1815);
  static const inkOnGold = Color(0xFF1C1500);

  /// The paper the logo is printed on, and a step down for cards.
  static const cream = Color(0xFFFFFDF7);
  static const creamSunk = Color(0xFFF6F0E2);
  static const creamEdge = Color(0xFFE7DFCB);

  static const muted = Color(0xFF6B6250);

  static const nightGround = Color(0xFF141210);
  static const nightSunk = Color(0xFF1F1C18);
  static const nightInk = Color(0xFFEDE8DD);
  static const nightMuted = Color(0xFFA9A192);
  static const nightEdge = Color(0xFF3A352C);

  static const danger = Color(0xFFB3261E);
  static const dangerNight = Color(0xFFF2B8B5);
}

const _radius = 14.0;

/// Counter-sized: a till is used in a hurry, sometimes one-handed, sometimes by
/// someone holding a cup. 52 is comfortably above the 44pt minimum.
const _buttonHeight = 52.0;

ThemeData get qwalletLight => _build(
  const ColorScheme.light(
    primary: QwalletColors.gold,
    onPrimary: QwalletColors.inkOnGold,
    primaryContainer: Color(0xFFF3E4C0),
    onPrimaryContainer: Color(0xFF3D2E00),
    secondary: QwalletColors.goldDeep,
    onSecondary: Colors.white,
    secondaryContainer: QwalletColors.creamSunk,
    onSecondaryContainer: QwalletColors.ink,
    surface: QwalletColors.cream,
    onSurface: QwalletColors.ink,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: QwalletColors.cream,
    surfaceContainer: QwalletColors.creamSunk,
    surfaceContainerHigh: Color(0xFFF1EADA),
    surfaceContainerHighest: Color(0xFFEDE5D2),
    onSurfaceVariant: QwalletColors.muted,
    outline: QwalletColors.creamEdge,
    outlineVariant: Color(0xFFEFE9DA),
    error: QwalletColors.danger,
    onError: Colors.white,
  ),
  keyboard: Brightness.light,
);

ThemeData get qwalletDark => _build(
  const ColorScheme.dark(
    primary: QwalletColors.goldLight,
    onPrimary: Color(0xFF2A2000),
    primaryContainer: Color(0xFF574316),
    onPrimaryContainer: Color(0xFFFFE8B8),
    secondary: QwalletColors.goldLight,
    onSecondary: Color(0xFF2A2000),
    secondaryContainer: QwalletColors.nightSunk,
    onSecondaryContainer: QwalletColors.nightInk,
    surface: QwalletColors.nightGround,
    onSurface: QwalletColors.nightInk,
    surfaceContainerLowest: Color(0xFF0E0C0A),
    surfaceContainerLow: QwalletColors.nightGround,
    surfaceContainer: QwalletColors.nightSunk,
    surfaceContainerHigh: Color(0xFF272319),
    surfaceContainerHighest: Color(0xFF2E291F),
    onSurfaceVariant: QwalletColors.nightMuted,
    outline: QwalletColors.nightEdge,
    outlineVariant: Color(0xFF2B2721),
    error: QwalletColors.dangerNight,
    onError: Color(0xFF601410),
  ),
  keyboard: Brightness.dark,
);

ThemeData _build(ColorScheme scheme, {required Brightness keyboard}) {
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    // The system face, deliberately. A till app is read at arm's length in a
    // bright room; SF and Roboto are the two most legible faces on their own
    // platforms, and a downloaded display font would only slow the first frame.
    textTheme: base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // Size(64, h), not Size.fromHeight(h): the latter is Size(infinity, h),
        // which forces an infinite width demand and blows up any button sitting
        // in a Row. 64 is Material's own minimum width.
        minimumSize: const Size(64, _buttonHeight),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radius),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: scheme.secondary),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_radius),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: scheme.outline),
      labelStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.secondary,
      titleTextStyle: base.textTheme.bodyLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      subtitleTextStyle: base.textTheme.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
  );
}
