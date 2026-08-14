import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/feature_visibility.dart';
import 'package:super_health/app/shell_navigation.dart';

void main() {
  group('what each mode shows', () {
    test('easy mode hides analysis and keeps the doing', () {
      const easy = FeatureVisibility.easy();
      // Bookkeeping about the taking, rather than the taking.
      expect(easy.supplementHistory, isFalse);
      expect(easy.stockManagement, isFalse);
      expect(easy.supplementIngredients, isFalse);
      expect(easy.symptomsAndTags, isFalse);
      expect(easy.biomarkerCatalogAdmin, isFalse);
      expect(easy.deviceBackup, isFalse);
      expect(easy.maintenanceTools, isFalse);
    });

    test('correlations follow tags, because they are computed from them', () {
      // With tags hidden there is nothing to correlate; leaving the screen in
      // would leave a permanently empty one.
      const easy = FeatureVisibility.easy();
      expect(easy.symptomsAndTags, isFalse);
      expect(easy.trendsAndCorrelations, isFalse);
      const full = FeatureVisibility.complete();
      expect(full.symptomsAndTags, isTrue);
      expect(full.trendsAndCorrelations, isTrue);
    });

    test('the dose underlay follows ingredient collection', () {
      // It needs ingredient amounts, which easy mode does not collect.
      const easy = FeatureVisibility.easy();
      expect(easy.supplementIngredients, isFalse);
      expect(easy.doseUnderlay, isFalse);
    });

    test('easy mode turns reminders on rather than hiding them', () {
      // The one thing it enables. A reminder defaulting to off is why a
      // schedule produces nothing, and hiding the switch would not fix that.
      expect(const FeatureVisibility.easy().remindersOnByDefault, isTrue);
      expect(const FeatureVisibility.complete().remindersOnByDefault, isFalse);
    });

    test('easy mode leads with the lab-report loop', () {
      // Hiding screens makes the app smaller, not easier: the shortcut is the
      // half of the mode that makes it worth having.
      expect(const FeatureVisibility.easy().leadWithLabReport, isTrue);
      expect(const FeatureVisibility.complete().leadWithLabReport, isFalse);
    });

    test('easy mode changes the shape of the app, not only its contents', () {
      // Hiding sub-tabs left the app the same shape: five dense destinations
      // and a wall of tiles on the one that opens first. This is the flag that
      // says the shell itself is different.
      expect(const FeatureVisibility.easy().calmShell, isTrue);
      expect(const FeatureVisibility.complete().calmShell, isFalse);
    });

    test('easy mode asks the model for the short answer', () {
      expect(const FeatureVisibility.easy().briefAnswers, isTrue);
      expect(const FeatureVisibility.complete().briefAnswers, isFalse);
    });

    test('the full app hides nothing', () {
      const full = FeatureVisibility.complete();
      for (final visible in [
        full.supplementHistory,
        full.stockManagement,
        full.supplementIngredients,
        full.symptomsAndTags,
        full.trendsAndCorrelations,
        full.doseUnderlay,
        full.biomarkerCatalogAdmin,
        full.labPlanTiers,
        full.referenceRangeEditing,
        full.multipleAiRoles,
        full.maintenanceTools,
        full.deviceBackup,
        full.pastDayEditing,
      ]) {
        expect(visible, isTrue);
      }
    });

    test('a profile picks its own mode', () {
      expect(
        FeatureVisibility.forProfile(easyMode: true).supplementHistory,
        isFalse,
      );
      expect(
        FeatureVisibility.forProfile(easyMode: false).supplementHistory,
        isTrue,
      );
    });
  });

  group('the bottom bar', () {
    test('easy mode drops the supplements tab and keeps the rest', () {
      final easy = shellTabsFor(easyMode: true);

      expect(easy, hasLength(4));
      expect(easy, isNot(contains(tabIndexForSection(AppSection.catalog))));
      for (final section in [
        AppSection.biomarkers,
        AppSection.advisor,
        AppSection.settings,
      ]) {
        expect(easy, contains(tabIndexForSection(section)));
      }
    });

    test('both modes number the same destinations the same way', () {
      // The indices are canonical, not per-mode: a deep link resolves to one
      // screen regardless of which bar is on show, and only the bar is
      // shorter. Numbering easy mode separately is how a shortcut ends up
      // opening Settings when it meant to open the advisor.
      final complete = shellTabsFor(easyMode: false);

      expect(complete, [0, 1, 2, 3, 4]);
      expect(shellTabsFor(easyMode: true).every(complete.contains), isTrue);
      expect(complete[tabIndexForSection(AppSection.advisor)], 3);
    });
  });
}
