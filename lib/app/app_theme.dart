import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance_settings.dart';

/// Builds SuperHealth's deterministic Material 3 themes from device settings.
ThemeData buildAppTheme({
  required Brightness brightness,
  required AppearanceSettings settings,
}) {
  final scheme = _colorScheme(brightness, settings);
  final outline = settings.highContrast ? scheme.onSurface : scheme.outline;
  final outlineVariant = settings.highContrast
      ? scheme.onSurfaceVariant
      : scheme.outlineVariant;
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: outlineVariant),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    focusColor: scheme.primary.withValues(
      alpha: settings.highContrast ? 0.30 : 0.18,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: outlineVariant,
          width: settings.highContrast ? 1.5 : 1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(
          color: scheme.primary,
          width: settings.highContrast ? 3 : 2,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: settings.highContrast
            ? BorderSide(color: outline, width: 1.5)
            : BorderSide.none,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: outline, width: settings.highContrast ? 2 : 1),
      ),
    ),
  );
}

ColorScheme _colorScheme(Brightness brightness, AppearanceSettings settings) {
  final dark = brightness == Brightness.dark;
  final colors = _schemeColors(
    dark: dark,
    palette: settings.palette,
    colorMode: settings.colorMode,
  );
  final highContrastOnSurface = dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  final onSurface = settings.highContrast
      ? highContrastOnSurface
      : colors.onSurface;
  final onSurfaceVariant = settings.highContrast
      ? highContrastOnSurface
      : colors.onSurfaceVariant;
  final outline = settings.highContrast
      ? highContrastOnSurface
      : colors.outline;
  final outlineVariant = settings.highContrast
      ? highContrastOnSurface
      : colors.outlineVariant;
  return ColorScheme(
    brightness: brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.primaryContainer,
    onPrimaryContainer: colors.onPrimaryContainer,
    secondary: colors.secondary,
    onSecondary: colors.onSecondary,
    secondaryContainer: colors.secondaryContainer,
    onSecondaryContainer: colors.onSecondaryContainer,
    tertiary: colors.tertiary,
    onTertiary: colors.onTertiary,
    tertiaryContainer: colors.tertiaryContainer,
    onTertiaryContainer: colors.onTertiaryContainer,
    error: colors.error,
    onError: colors.onError,
    errorContainer: colors.errorContainer,
    onErrorContainer: colors.onErrorContainer,
    surface: colors.surface,
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
    inverseSurface: dark ? const Color(0xFFDFE4E0) : const Color(0xFF2C3230),
    onInverseSurface: dark ? const Color(0xFF2C3230) : const Color(0xFFDFE4E0),
    inversePrimary: colors.primaryContainer,
    surfaceTint: colors.primary,
  );
}

_SchemeColors _schemeColors({
  required bool dark,
  required AppColorPalette palette,
  required AppColorMode colorMode,
}) {
  final friendly = colorMode == AppColorMode.deuteranomalyFriendly;
  if (palette == AppColorPalette.mint) {
    return dark
        ? (friendly ? _mintFriendlyDark : _mintDark)
        : (friendly ? _mintFriendlyLight : _mintLight);
  }
  return dark
      ? (friendly ? _midnightFriendlyDark : _midnightDark)
      : (friendly ? _midnightFriendlyLight : _midnightLight);
}

class _SchemeColors {
  const _SchemeColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.outlineVariant,
  });

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiary;
  final Color onTertiary;
  final Color tertiaryContainer;
  final Color onTertiaryContainer;
  final Color error;
  final Color onError;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;
  final Color outlineVariant;
}

const _mintLight = _SchemeColors(
  primary: Color(0xFF006A63),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFA9F4E5),
  onPrimaryContainer: Color(0xFF00201D),
  secondary: Color(0xFF4A635F),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFCCE8E2),
  onSecondaryContainer: Color(0xFF06201D),
  tertiary: Color(0xFF456179),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFCDE5FF),
  onTertiaryContainer: Color(0xFF001E31),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF6FBF8),
  onSurface: Color(0xFF171D1B),
  onSurfaceVariant: Color(0xFF3F4946),
  outline: Color(0xFF6F7976),
  outlineVariant: Color(0xFFBEC9C5),
);

const _mintDark = _SchemeColors(
  primary: Color(0xFF89D9CC),
  onPrimary: Color(0xFF003731),
  primaryContainer: Color(0xFF005048),
  onPrimaryContainer: Color(0xFFA9F4E5),
  secondary: Color(0xFFB0CCC6),
  onSecondary: Color(0xFF1C3531),
  secondaryContainer: Color(0xFF324B46),
  onSecondaryContainer: Color(0xFFCCE8E2),
  tertiary: Color(0xFFADCAE5),
  onTertiary: Color(0xFF153349),
  tertiaryContainer: Color(0xFF2D4A61),
  onTertiaryContainer: Color(0xFFCDE5FF),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF0F1513),
  onSurface: Color(0xFFDFE4E0),
  onSurfaceVariant: Color(0xFFBEC9C5),
  outline: Color(0xFF89938F),
  outlineVariant: Color(0xFF3F4946),
);

const _midnightLight = _SchemeColors(
  primary: Color(0xFF2D5F9E),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFD5E3FF),
  onPrimaryContainer: Color(0xFF001C3B),
  secondary: Color(0xFF535F70),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFD7E3F8),
  onSecondaryContainer: Color(0xFF101C2B),
  tertiary: Color(0xFF6A5478),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFF3DAFF),
  onTertiaryContainer: Color(0xFF251431),
  error: Color(0xFFBA1A1A),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDAD6),
  onErrorContainer: Color(0xFF410002),
  surface: Color(0xFFF9F9FF),
  onSurface: Color(0xFF191C20),
  onSurfaceVariant: Color(0xFF41474F),
  outline: Color(0xFF717780),
  outlineVariant: Color(0xFFC1C7D0),
);

const _midnightDark = _SchemeColors(
  primary: Color(0xFFA8C7FF),
  onPrimary: Color(0xFF00315C),
  primaryContainer: Color(0xFF174777),
  onPrimaryContainer: Color(0xFFD5E3FF),
  secondary: Color(0xFFBBC7DB),
  onSecondary: Color(0xFF253140),
  secondaryContainer: Color(0xFF3B4858),
  onSecondaryContainer: Color(0xFFD7E3F8),
  tertiary: Color(0xFFD7BDE6),
  onTertiary: Color(0xFF3A2948),
  tertiaryContainer: Color(0xFF513E5F),
  onTertiaryContainer: Color(0xFFF3DAFF),
  error: Color(0xFFFFB4AB),
  onError: Color(0xFF690005),
  errorContainer: Color(0xFF93000A),
  onErrorContainer: Color(0xFFFFDAD6),
  surface: Color(0xFF111318),
  onSurface: Color(0xFFE1E2E8),
  onSurfaceVariant: Color(0xFFC1C7D0),
  outline: Color(0xFF8B919A),
  outlineVariant: Color(0xFF41474F),
);

// These variants use blue/teal for primary actions and amber/orange for
// errors, so important meaning never depends on a red-versus-green pairing.
const _mintFriendlyLight = _SchemeColors(
  primary: Color(0xFF006B67),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFF9CF2E9),
  onPrimaryContainer: Color(0xFF00201E),
  secondary: Color(0xFF426461),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFC5E9E4),
  onSecondaryContainer: Color(0xFF00201E),
  tertiary: Color(0xFF3F627D),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFCBE6FF),
  onTertiaryContainer: Color(0xFF001E2F),
  error: Color(0xFF8A3F00),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDCC3),
  onErrorContainer: Color(0xFF2E1500),
  surface: Color(0xFFF5FBF9),
  onSurface: Color(0xFF171D1C),
  onSurfaceVariant: Color(0xFF3D4A48),
  outline: Color(0xFF6D7A77),
  outlineVariant: Color(0xFFBDCAC7),
);

const _mintFriendlyDark = _SchemeColors(
  primary: Color(0xFF83DAD0),
  onPrimary: Color(0xFF003734),
  primaryContainer: Color(0xFF00504C),
  onPrimaryContainer: Color(0xFF9CF2E9),
  secondary: Color(0xFFA9D0CB),
  onSecondary: Color(0xFF133936),
  secondaryContainer: Color(0xFF2B4F4B),
  onSecondaryContainer: Color(0xFFC5E9E4),
  tertiary: Color(0xFFA9CBE8),
  onTertiary: Color(0xFF12354E),
  tertiaryContainer: Color(0xFF294C66),
  onTertiaryContainer: Color(0xFFCBE6FF),
  error: Color(0xFFFFB77E),
  onError: Color(0xFF4A2300),
  errorContainer: Color(0xFF693000),
  onErrorContainer: Color(0xFFFFDCC3),
  surface: Color(0xFF101514),
  onSurface: Color(0xFFDFE4E2),
  onSurfaceVariant: Color(0xFFBDCAC7),
  outline: Color(0xFF879490),
  outlineVariant: Color(0xFF3D4A48),
);

const _midnightFriendlyLight = _SchemeColors(
  primary: Color(0xFF005FAF),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFD5E3FF),
  onPrimaryContainer: Color(0xFF001C3B),
  secondary: Color(0xFF4E627A),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFD1E5FF),
  onSecondaryContainer: Color(0xFF071E33),
  tertiary: Color(0xFF62587B),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFE9DEFF),
  onTertiaryContainer: Color(0xFF201637),
  error: Color(0xFF8A3F00),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFFFDCC3),
  onErrorContainer: Color(0xFF2E1500),
  surface: Color(0xFFF9F9FF),
  onSurface: Color(0xFF191C20),
  onSurfaceVariant: Color(0xFF41474F),
  outline: Color(0xFF717780),
  outlineVariant: Color(0xFFC1C7D0),
);

const _midnightFriendlyDark = _SchemeColors(
  primary: Color(0xFFA8C7FF),
  onPrimary: Color(0xFF00315C),
  primaryContainer: Color(0xFF174777),
  onPrimaryContainer: Color(0xFFD5E3FF),
  secondary: Color(0xFFB4C9E5),
  onSecondary: Color(0xFF1E3349),
  secondaryContainer: Color(0xFF364B62),
  onSecondaryContainer: Color(0xFFD1E5FF),
  tertiary: Color(0xFFCCC0EB),
  onTertiary: Color(0xFF33294B),
  tertiaryContainer: Color(0xFF4A4061),
  onTertiaryContainer: Color(0xFFE9DEFF),
  error: Color(0xFFFFB77E),
  onError: Color(0xFF4A2300),
  errorContainer: Color(0xFF693000),
  onErrorContainer: Color(0xFFFFDCC3),
  surface: Color(0xFF111318),
  onSurface: Color(0xFFE1E2E8),
  onSurfaceVariant: Color(0xFFC1C7D0),
  outline: Color(0xFF8B919A),
  outlineVariant: Color(0xFF41474F),
);

/// WCAG's relative luminance formula for opaque sRGB colors.
double relativeLuminance(Color color) {
  double linearize(int channel) {
    final value = channel / 255;
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.red) +
      0.7152 * linearize(color.green) +
      0.0722 * linearize(color.blue);
}

double colorContrastRatio(Color first, Color second) {
  final firstLuminance = relativeLuminance(first);
  final secondLuminance = relativeLuminance(second);
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
