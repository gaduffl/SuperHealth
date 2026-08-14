import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'appearance_settings.dart';

/// Builds SuperHealth's deterministic Material 3 themes from device settings.
///
/// [calm] is easy mode's presentation: a blossom palette and larger targets.
/// It is a per-profile decision rather than a device one, so switching to an
/// easy-mode profile changes the whole app's look — which is the point. Every
/// device-wide choice still applies on top: high contrast still strengthens
/// text, and the colour-blind-safe mode still swaps red for amber.
ThemeData buildAppTheme({
  required Brightness brightness,
  required AppearanceSettings settings,
  bool calm = false,
}) {
  final scheme = _colorScheme(brightness, settings, calm: calm);
  final outline = settings.highContrast ? scheme.onSurface : scheme.outline;
  final outlineVariant = settings.highContrast
      ? scheme.onSurfaceVariant
      : scheme.outlineVariant;
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: outlineVariant),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final theme = base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    focusColor: scheme.primary.withValues(
      alpha: settings.highContrast ? 0.30 : 0.18,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    cardTheme: CardThemeData(
      elevation: 4,
      shadowColor: brightness == Brightness.light
          ? Colors.black45
          : Colors.black,
      surfaceTintColor: brightness == Brightness.light ? Colors.white : null,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: settings.highContrast
            ? BorderSide(color: outline, width: 1.5)
            : BorderSide.none,
      ),
    ),
    dividerTheme: DividerThemeData(color: outlineVariant, space: 1),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
    chipTheme: ChipThemeData(
      side: BorderSide(color: outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: base.textTheme.labelLarge,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
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
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      type: BottomNavigationBarType.fixed,
      backgroundColor: scheme.surface,
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.onSurface.withValues(alpha: 0.6),
      elevation: 8,
    ),
    tabBarTheme: TabBarThemeData(
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelStyle: base.textTheme.labelLarge,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
  );
  return calm ? _softened(theme) : theme;
}

/// The size half of easy mode.
///
/// Nothing here hides anything — it makes what is left bigger. A 60-point
/// button is reachable without aiming, and a control that is easy to hit is
/// one fewer reason to put the phone down and ask someone else to do it.
ThemeData _softened(ThemeData theme) {
  final label = theme.textTheme.titleMedium?.copyWith(
    fontWeight: FontWeight.w700,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  ButtonStyle large(ButtonStyle style) => style.copyWith(
    // Size(0, 60), never Size.fromHeight(60) — that constructor means
    // Size(double.infinity, 60), an *infinite width* minimum. In a column it
    // looks identical, because the column already tightens the width. In a
    // slot laid out with loose constraints — a ListTile's trailing — the
    // button claimed the whole row and squeezed the tile's title down to one
    // character per line. A width floor is not what "bigger buttons" means;
    // callers that want full width wrap the button themselves.
    minimumSize: const WidgetStatePropertyAll(Size(0, 60)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 22, vertical: 14),
    ),
    textStyle: WidgetStatePropertyAll(label),
    shape: WidgetStatePropertyAll(shape),
  );
  return theme.copyWith(
    // Every Material control that honours density grows with it, so rows,
    // list tiles, and checkboxes stay in proportion with the buttons.
    visualDensity: const VisualDensity(horizontal: 1, vertical: 1),
    iconTheme: theme.iconTheme.copyWith(size: 26),
    filledButtonTheme: FilledButtonThemeData(
      style: large(FilledButton.styleFrom()),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: large(ElevatedButton.styleFrom()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: large(OutlinedButton.styleFrom()),
    ),
    textButtonTheme: TextButtonThemeData(style: large(TextButton.styleFrom())),
    listTileTheme: theme.listTileTheme.copyWith(minVerticalPadding: 16),
    cardTheme: theme.cardTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomNavigationBarTheme: theme.bottomNavigationBarTheme.copyWith(
      selectedIconTheme: const IconThemeData(size: 30),
      unselectedIconTheme: const IconThemeData(size: 28),
    ),
  );
}

/// The smallest text scale easy mode will render at.
const calmTextScaleFloor = 1.12;

/// Raises the text-size floor for easy mode without capping anyone.
///
/// A floor rather than a fixed factor, and a clamp rather than a replacement:
/// someone who has already asked their phone for larger text has said something
/// about their eyes, and shrinking that back to a designer's number would make
/// the *simple* mode the one that is hardest to read.
///
/// Applied through the media query rather than the theme's text sizes. Material
/// 3 leaves `fontSize` unset on its text roles and resolves it inside each
/// widget, so scaling the [TextTheme] would multiply a pile of nulls and change
/// nothing at all.
TextScaler calmTextScaler(TextScaler device) =>
    device.clamp(minScaleFactor: calmTextScaleFloor);

/// Easy mode's seed. A soft rose says "this is the gentle one" before a single
/// word is read, and Material derives a full accessible scheme from it.
const _blossomSeed = Color(0xFFD1688E);

ColorScheme _colorScheme(
  Brightness brightness,
  AppearanceSettings settings, {
  bool calm = false,
}) {
  final dark = brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(
    seedColor: calm ? _blossomSeed : Colors.blue,
    brightness: brightness,
  );
  final accessibilityColors = _schemeColors(
    dark: dark,
    palette: settings.palette,
    colorMode: settings.colorMode,
  );
  if (settings.colorMode == AppColorMode.deuteranomalyFriendly) {
    scheme = scheme.copyWith(
      error: accessibilityColors.error,
      onError: accessibilityColors.onError,
      errorContainer: accessibilityColors.errorContainer,
      onErrorContainer: accessibilityColors.onErrorContainer,
    );
  }
  final highContrastOnSurface = dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF000000);
  final onSurface = settings.highContrast
      ? highContrastOnSurface
      : scheme.onSurface;
  final onSurfaceVariant = settings.highContrast
      ? highContrastOnSurface
      : scheme.onSurfaceVariant;
  final outline = settings.highContrast
      ? highContrastOnSurface
      : scheme.outline;
  final outlineVariant = settings.highContrast
      ? highContrastOnSurface
      : scheme.outlineVariant;
  return scheme.copyWith(
    onSurface: onSurface,
    onSurfaceVariant: onSurfaceVariant,
    outline: outline,
    outlineVariant: outlineVariant,
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
  double linearize(double value) {
    return value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linearize(color.r) +
      0.7152 * linearize(color.g) +
      0.0722 * linearize(color.b);
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
