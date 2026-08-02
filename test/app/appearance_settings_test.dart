import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/app/app_theme.dart';
import 'package:super_health/app/appearance_settings.dart';

void main() {
  group('AppearanceSettingsStore', () {
    test('uses the documented device-wide defaults', () async {
      SharedPreferences.setMockInitialValues({});

      final settings = await AppearanceSettingsStore().load();

      expect(settings, AppearanceSettings.defaults);
    });

    test('persists all appearance choices', () async {
      SharedPreferences.setMockInitialValues({});
      final store = AppearanceSettingsStore();
      const selected = AppearanceSettings(
        themeMode: AppThemeMode.dark,
        palette: AppColorPalette.midnight,
        colorMode: AppColorMode.deuteranomalyFriendly,
        highContrast: true,
        language: AppLanguage.german,
      );

      expect(await store.save(selected), isTrue);
      expect(await store.load(), selected);
    });

    test('falls back safely for invalid or wrongly typed values', () async {
      SharedPreferences.setMockInitialValues({
        'appearance_theme_mode': 'night-vision',
        'appearance_palette': 'rose',
        'appearance_color_mode': 23,
        'appearance_high_contrast': 'yes',
        'appearance_language': 'français',
      });

      final settings = await AppearanceSettingsStore().load();

      expect(settings, AppearanceSettings.defaults);
    });
  });

  test('uses German translations and English as the locale fallback', () {
    expect(AppLocalizations.translationsComplete, isTrue);
    expect(
      AppLocalizations.forLocale(const Locale('de')).settings,
      'Einstellungen',
    );
    expect(AppLocalizations.forLocale(const Locale('fr')).settings, 'Settings');
    expect(AppLanguage.system.locale, isNull);
    expect(AppLanguage.english.locale, const Locale('en'));
    expect(AppLanguage.german.locale, const Locale('de'));
  });

  test('localizes dynamic names and singular or plural dashboard counts', () {
    final english = AppLocalizations.forLocale(const Locale('en'));
    final german = AppLocalizations.forLocale(const Locale('de'));

    expect(english.activeProducts(1), '1 active product');
    expect(english.activeProducts(2), '2 active products');
    expect(german.daysOverdue(1), '1 Tag überfällig');
    expect(german.daysOverdue(3), '3 Tage überfällig');
    expect(german.due('Vitamin D'), 'Vitamin D ist fällig');
  });

  test('localizes tracking counts and locale-aware numeric formats', () {
    final english = AppLocalizations.forLocale(const Locale('en'));
    final german = AppLocalizations.forLocale(const Locale('de'));

    expect(english.trackingProgress(2, 3), '2 of 3 taken');
    expect(german.trackingProgress(2, 3), '2 von 3 eingenommen');
    expect(english.scheduleCount(1), '1 schedule');
    expect(german.scheduleCount(2), '2 Einnahmepläne');
    expect(english.intakeCount(2), '2 intakes');
    expect(german.unknownCostDescription(1), startsWith('1 Einnahme'));
    expect(english.formatNumber(12.5), '12.5');
    expect(german.formatNumber(12.5), '12,5');
    expect(AppLocalizations.translationsComplete, isTrue);
  });

  test('localizes health correlation and privacy copy', () {
    final english = AppLocalizations.forLocale(const Locale('en'));
    final german = AppLocalizations.forLocale(const Locale('de'));

    expect(english.journalEntries(1), '1 journal entry in the selected range');
    expect(
      german.journalEntries(2),
      '2 Journaleinträge im ausgewählten Zeitraum',
    );
    expect(german.contextCategory('family_history'), 'Familiengeschichte');
    expect(german.correlationStrength('strong'), 'stark');
    expect(
      german.correlationSummary(
        lagDays: 1,
        sampleSize: 7,
        strength: 'moderate',
        spearman: 0.5,
        adjustedQ: 0.04,
        statisticallySignificant: true,
      ),
      contains('Verzögerung 1 T.'),
    );
    expect(AppLocalizations.translationsComplete, isTrue);
  });

  test('localizes advisor safety, proposal, and context-size copy', () {
    final english = AppLocalizations.forLocale(const Locale('en'));
    final german = AppLocalizations.forLocale(const Locale('de'));

    expect(english.pendingFileProposals(1), '1 file change awaiting approval');
    expect(
      german.pendingFileProposals(2),
      '2 Dateiänderungen warten auf Bestätigung',
    );
    expect(
      german.providerReasoning('openai', 'gpt-5', 'high'),
      'openai · gpt-5 · high-Reasoning',
    );
    expect(german.lastContext(1536, 120), contains('1,5 KB'));
    expect(german.sourceNumber(2), 'Quelle 2');
    expect(AppLocalizations.translationsComplete, isTrue);
  });

  test('every appearance theme keeps key text pairs at 4.5:1 or higher', () {
    for (final palette in AppColorPalette.values) {
      for (final colorMode in AppColorMode.values) {
        for (final highContrast in [false, true]) {
          for (final brightness in Brightness.values) {
            final theme = buildAppTheme(
              brightness: brightness,
              settings: AppearanceSettings(
                palette: palette,
                colorMode: colorMode,
                highContrast: highContrast,
              ),
            );
            final scheme = theme.colorScheme;
            final label =
                '${palette.name}/${colorMode.name}/'
                '${brightness.name}/highContrast=$highContrast';

            expect(
              colorContrastRatio(scheme.primary, scheme.onPrimary),
              greaterThanOrEqualTo(4.5),
              reason: '$label primary/onPrimary',
            );
            expect(
              colorContrastRatio(scheme.error, scheme.onError),
              greaterThanOrEqualTo(4.5),
              reason: '$label error/onError',
            );
            expect(
              colorContrastRatio(scheme.surface, scheme.onSurface),
              greaterThanOrEqualTo(4.5),
              reason: '$label surface/onSurface',
            );
            expect(
              colorContrastRatio(
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
              ),
              greaterThanOrEqualTo(4.5),
              reason: '$label primaryContainer/onPrimaryContainer',
            );
          }
        }
      }
    }
  });

  test('uses the old Biomarkers blue theme and elevated card treatment', () {
    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(
        brightness: brightness,
        settings: AppearanceSettings.defaults,
      );
      final oldBiomarkersScheme = ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: brightness,
      );

      expect(theme.colorScheme.primary, oldBiomarkersScheme.primary);
      expect(theme.cardTheme.elevation, 4);
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(12));
    }
  });

  test('high contrast strengthens surface text and outlines', () {
    final standard = buildAppTheme(
      brightness: Brightness.light,
      settings: AppearanceSettings.defaults,
    );
    final highContrast = buildAppTheme(
      brightness: Brightness.light,
      settings: const AppearanceSettings(highContrast: true),
    );

    expect(
      colorContrastRatio(
        highContrast.colorScheme.surface,
        highContrast.colorScheme.onSurface,
      ),
      greaterThan(
        colorContrastRatio(
          standard.colorScheme.surface,
          standard.colorScheme.onSurface,
        ),
      ),
    );
    expect(
      highContrast.colorScheme.outline,
      highContrast.colorScheme.onSurface,
    );
    expect(
      highContrast.inputDecorationTheme.focusedBorder!.borderSide.width,
      greaterThan(
        standard.inputDecorationTheme.focusedBorder!.borderSide.width,
      ),
    );
  });
}
