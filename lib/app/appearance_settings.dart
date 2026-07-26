import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device-wide display and accessibility choices for SuperHealth.
enum AppThemeMode {
  system,
  light,
  dark;

  ThemeMode get materialThemeMode => switch (this) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}

enum AppColorPalette { mint, midnight }

enum AppColorMode { standard, deuteranomalyFriendly }

enum AppLanguage {
  system,
  english,
  german;

  Locale? get locale => switch (this) {
    AppLanguage.system => null,
    AppLanguage.english => const Locale('en'),
    AppLanguage.german => const Locale('de'),
  };
}

class AppearanceSettings {
  const AppearanceSettings({
    this.themeMode = AppThemeMode.system,
    this.palette = AppColorPalette.mint,
    this.colorMode = AppColorMode.standard,
    this.highContrast = false,
    this.language = AppLanguage.system,
  });

  static const defaults = AppearanceSettings();

  final AppThemeMode themeMode;
  final AppColorPalette palette;
  final AppColorMode colorMode;
  final bool highContrast;
  final AppLanguage language;

  AppearanceSettings copyWith({
    AppThemeMode? themeMode,
    AppColorPalette? palette,
    AppColorMode? colorMode,
    bool? highContrast,
    AppLanguage? language,
  }) => AppearanceSettings(
    themeMode: themeMode ?? this.themeMode,
    palette: palette ?? this.palette,
    colorMode: colorMode ?? this.colorMode,
    highContrast: highContrast ?? this.highContrast,
    language: language ?? this.language,
  );

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings &&
      themeMode == other.themeMode &&
      palette == other.palette &&
      colorMode == other.colorMode &&
      highContrast == other.highContrast &&
      language == other.language;

  @override
  int get hashCode =>
      Object.hash(themeMode, palette, colorMode, highContrast, language);
}

/// Persists only device-level appearance choices. It deliberately has no
/// profile identifier: every person using this device sees the same display.
class AppearanceSettingsStore {
  static const _themeModeKey = 'appearance_theme_mode';
  static const _paletteKey = 'appearance_palette';
  static const _colorModeKey = 'appearance_color_mode';
  static const _highContrastKey = 'appearance_high_contrast';
  static const _languageKey = 'appearance_language';

  Future<AppearanceSettings> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return AppearanceSettings(
        themeMode: _themeMode(_readString(preferences, _themeModeKey)),
        palette: _palette(_readString(preferences, _paletteKey)),
        colorMode: _colorMode(_readString(preferences, _colorModeKey)),
        highContrast: _readBool(preferences, _highContrastKey) ?? false,
        language: _language(_readString(preferences, _languageKey)),
      );
    } on Object {
      // Preferences are a convenience. A malformed or unavailable value must
      // never keep the health record from opening.
      return AppearanceSettings.defaults;
    }
  }

  Future<bool> save(AppearanceSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await Future.wait<bool>([
      preferences.setString(_themeModeKey, settings.themeMode.name),
      preferences.setString(_paletteKey, settings.palette.name),
      preferences.setString(_colorModeKey, settings.colorMode.name),
      preferences.setBool(_highContrastKey, settings.highContrast),
      preferences.setString(_languageKey, settings.language.name),
    ]);
    return saved.every((value) => value);
  }

  String? _readString(SharedPreferences preferences, String key) {
    try {
      return preferences.getString(key);
    } on Object {
      return null;
    }
  }

  bool? _readBool(SharedPreferences preferences, String key) {
    try {
      return preferences.getBool(key);
    } on Object {
      return null;
    }
  }

  AppThemeMode _themeMode(String? value) => switch (value) {
    'light' => AppThemeMode.light,
    'dark' => AppThemeMode.dark,
    _ => AppThemeMode.system,
  };

  AppColorPalette _palette(String? value) => switch (value) {
    'midnight' => AppColorPalette.midnight,
    _ => AppColorPalette.mint,
  };

  AppColorMode _colorMode(String? value) => switch (value) {
    'deuteranomalyFriendly' => AppColorMode.deuteranomalyFriendly,
    _ => AppColorMode.standard,
  };

  AppLanguage _language(String? value) => switch (value) {
    'english' => AppLanguage.english,
    'german' => AppLanguage.german,
    _ => AppLanguage.system,
  };
}
