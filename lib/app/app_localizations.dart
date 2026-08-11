import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

enum AppDayPeriod { morning, afternoon, evening }

/// Small typed localization surface for strings owned by the app shell.
/// Unknown device locales intentionally use English.
class AppLocalizations {
  const AppLocalizations._(this._messages);

  static const supportedLocales = [Locale('en'), Locale('de')];
  static const delegate = _AppLocalizationsDelegate();

  final Map<_AppText, String> _messages;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ?? english;

  static AppLocalizations forLocale(Locale locale) =>
      locale.languageCode == 'de' ? german : english;

  static const english = AppLocalizations._(_english);
  static const german = AppLocalizations._(_german);

  /// Guards the typed message registry against silently falling back to
  /// English when a locale map omits a key.
  static bool get translationsComplete =>
      _english.length == _AppText.values.length &&
      _german.length == _AppText.values.length &&
      _AppText.values.every(
        (key) => _english.containsKey(key) && _german.containsKey(key),
      );

  String _text(_AppText key) => _messages[key] ?? _english[key]!;

  /// Keeps one-off screen copy explicit in both supported languages without
  /// allowing an untranslated fallback.
  String pick(String englishText, String germanText) =>
      identical(this, german) ? germanText : englishText;

  String get appName => _text(_AppText.appName);
  String get openingRecord => _text(_AppText.openingRecord);
  String get couldNotStart => _text(_AppText.couldNotStart);
  String get welcome => _text(_AppText.welcome);
  String get onboardingDescription => _text(_AppText.onboardingDescription);
  String get isolatedProfiles => _text(_AppText.isolatedProfiles);
  String get isolatedProfilesDescription =>
      _text(_AppText.isolatedProfilesDescription);
  String get localFirstByok => _text(_AppText.localFirstByok);
  String get localFirstByokDescription =>
      _text(_AppText.localFirstByokDescription);
  String get createFirstProfile => _text(_AppText.createFirstProfile);
  String get restoreFromOneDrive => _text(_AppText.restoreFromOneDrive);
  String get additionalPhoneHint => _text(_AppText.additionalPhoneHint);
  String get restoreOrTransferExistingData =>
      _text(_AppText.restoreOrTransferExistingData);
  String get restoreOrTransferDescription =>
      _text(_AppText.restoreOrTransferDescription);
  String get startFresh => _text(_AppText.startFresh);
  String get startFreshDescription => _text(_AppText.startFreshDescription);
  String get setupExistingData => _text(_AppText.setupExistingData);
  String get initialSetup => _text(_AppText.initialSetup);
  String get initialSetupDescription => _text(_AppText.initialSetupDescription);
  String get finishSetup => _text(_AppText.finishSetup);
  String get finishSetupDescription => _text(_AppText.finishSetupDescription);
  String get setupProfile => _text(_AppText.setupProfile);
  String get setupLegacyJson => _text(_AppText.setupLegacyJson);
  String get setupPdfs => _text(_AppText.setupPdfs);
  String get setupCloud => _text(_AppText.setupCloud);
  String get setupAdvisor => _text(_AppText.setupAdvisor);
  String get done => _text(_AppText.done);
  String get importData => _text(_AppText.importData);
  String get attachPdfs => _text(_AppText.attachPdfs);
  String get skipForNow => _text(_AppText.skipForNow);
  String get setUp => _text(_AppText.setUp);
  String get restoreSyncDecisionTitle =>
      _text(_AppText.restoreSyncDecisionTitle);
  String get restoreSyncDecisionDescription =>
      _text(_AppText.restoreSyncDecisionDescription);
  String get resumeAndMerge => _text(_AppText.resumeAndMerge);
  String get resumeAndMergeDescription =>
      _text(_AppText.resumeAndMergeDescription);
  String get publishRestoredData => _text(_AppText.publishRestoredData);
  String get publishRestoredDataDescription =>
      _text(_AppText.publishRestoredDataDescription);
  String get confirmPublishTitle => _text(_AppText.confirmPublishTitle);
  String get confirmPublishDescription =>
      _text(_AppText.confirmPublishDescription);
  String get publishConfirmationLabel =>
      _text(_AppText.publishConfirmationLabel);
  String get today => _text(_AppText.today);
  String get supplements => _text(_AppText.supplements);
  String get health => _text(_AppText.health);
  String get advisor => _text(_AppText.advisor);
  String get settings => _text(_AppText.settings);
  String get switchProfile => _text(_AppText.switchProfile);
  String get newProfile => _text(_AppText.newProfile);
  String get appearanceAccessibility => _text(_AppText.appearanceAccessibility);
  String get deviceWideAppearance => _text(_AppText.deviceWideAppearance);
  String get language => _text(_AppText.language);
  String get themeMode => _text(_AppText.themeMode);
  String get savingAppearance => _text(_AppText.savingAppearance);
  String get themeModeDescription => _text(_AppText.themeModeDescription);
  String get system => _text(_AppText.system);
  String get light => _text(_AppText.light);
  String get dark => _text(_AppText.dark);
  String get colorPalette => _text(_AppText.colorPalette);
  String get mint => _text(_AppText.mint);
  String get midnight => _text(_AppText.midnight);
  String get colorVision => _text(_AppText.colorVision);
  String get standard => _text(_AppText.standard);
  String get deuteranomalyFriendly => _text(_AppText.deuteranomalyFriendly);
  String get colorVisionExplanation => _text(_AppText.colorVisionExplanation);
  String get highContrast => _text(_AppText.highContrast);
  String get highContrastDescription => _text(_AppText.highContrastDescription);
  String get todayDoses => _text(_AppText.todayDoses);
  String get biomarkersDue => _text(_AppText.biomarkersDue);
  String get lowStock => _text(_AppText.lowStock);
  String get householdInventory => _text(_AppText.householdInventory);
  String get labPlans => _text(_AppText.labPlans);
  String get createFirstPlan => _text(_AppText.createFirstPlan);
  String get savedChecklists => _text(_AppText.savedChecklists);
  String get latestBelow => _text(_AppText.latestBelow);
  String get latestAbove => _text(_AppText.latestAbove);
  String get comparisonDescription => _text(_AppText.comparisonDescription);
  String get rangeUnavailable => _text(_AppText.rangeUnavailable);
  String get quickTrack => _text(_AppText.quickTrack);
  String get quickTrackDescription => _text(_AppText.quickTrackDescription);
  String get supplementIntake => _text(_AppText.supplementIntake);
  String get symptom => _text(_AppText.symptom);
  String get tag => _text(_AppText.tag);
  String get recentActivity => _text(_AppText.recentActivity);
  String get noActivityYet => _text(_AppText.noActivityYet);
  String get noActivityDescription => _text(_AppText.noActivityDescription);
  String get neverMeasured => _text(_AppText.neverMeasured);
  String get needsAttention => _text(_AppText.needsAttention);
  String get needsAttentionDescription =>
      _text(_AppText.needsAttentionDescription);
  String get taken => _text(_AppText.taken);
  String get refill => _text(_AppText.refill);
  String get privacyBoundary => _text(_AppText.privacyBoundary);
  String get privacyBoundaryDescription =>
      _text(_AppText.privacyBoundaryDescription);
  String get keysNeverSynced => _text(_AppText.keysNeverSynced);
  String get keysNeverSyncedDescription =>
      _text(_AppText.keysNeverSyncedDescription);
  String get supplementFallback => _text(_AppText.supplementFallback);
  String get whichSupplement => _text(_AppText.whichSupplement);
  String get confirm => _text(_AppText.confirm);
  String get cancel => _text(_AppText.cancel);

  String greeting(AppDayPeriod period, String profileName) => switch (period) {
    AppDayPeriod.morning => _text(
      _AppText.greetingMorning,
    ).replaceFirst('{name}', profileName),
    AppDayPeriod.afternoon => _text(
      _AppText.greetingAfternoon,
    ).replaceFirst('{name}', profileName),
    AppDayPeriod.evening => _text(
      _AppText.greetingEvening,
    ).replaceFirst('{name}', profileName),
  };

  String doseProgress(int takenCount, int totalCount) =>
      '$takenCount/$totalCount';

  String activeProducts(int count) => _count(
    count,
    singular: _AppText.activeProduct,
    plural: _AppText.activeProducts,
  );

  String measured(int count) => _count(
    count,
    singular: _AppText.measuredSingular,
    plural: _AppText.measuredPlural,
  );

  String unavailableCount(int count) => _count(
    count,
    singular: _AppText.unavailableSingular,
    plural: _AppText.unavailablePlural,
  );

  String neverMeasuredCount(int count) => _count(
    count,
    singular: _AppText.neverMeasuredSingular,
    plural: _AppText.neverMeasuredPlural,
  );

  String score(int value) =>
      _text(_AppText.score).replaceFirst('{score}', value.toString());

  String due(String biomarkerName) =>
      _text(_AppText.due).replaceFirst('{name}', biomarkerName);

  String daysOverdue(int count) => _count(
    count,
    singular: _AppText.dayOverdue,
    plural: _AppText.daysOverdue,
  );

  String low(String supplementName) =>
      _text(_AppText.low).replaceFirst('{name}', supplementName);

  String remaining(double quantity, String unit) => _text(_AppText.remaining)
      .replaceFirst(
        '{quantity}',
        NumberFormat.decimalPattern(_locale).format(quantity),
      )
      .replaceFirst('{unit}', unit);

  String get catalog => _text(_AppText.catalog);
  String get stock => _text(_AppText.stock);
  String get history => _text(_AppText.history);
  String get nothingScheduled => _text(_AppText.nothingScheduled);
  String get manual => _text(_AppText.manual);
  String get noDosesForThisDay => _text(_AppText.noDosesForThisDay);
  String get addScheduleFromCatalog => _text(_AppText.addScheduleFromCatalog);
  String get scheduleFreeDay => _text(_AppText.scheduleFreeDay);
  String get adherence30Day => _text(_AppText.adherence30Day);
  String get scheduledThroughCurrentTime =>
      _text(_AppText.scheduledThroughCurrentTime);
  String get undoCheckIn => _text(_AppText.undoCheckIn);
  String get skipDose => _text(_AppText.skipDose);
  String get markTaken => _text(_AppText.markTaken);
  String get skipped => _text(_AppText.skipped);
  String get missed => _text(_AppText.missed);
  String get scheduled => _text(_AppText.scheduled);
  String get searchProductsOrIngredients =>
      _text(_AppText.searchProductsOrIngredients);
  String get clearSearch => _text(_AppText.clearSearch);
  String get active => _text(_AppText.active);
  String get paused => _text(_AppText.paused);
  String get all => _text(_AppText.all);
  String get addSupplement => _text(_AppText.addSupplement);
  String get noMatchingSupplements => _text(_AppText.noMatchingSupplements);
  String get changeFilterOrAddProduct =>
      _text(_AppText.changeFilterOrAddProduct);
  String get logIntake => _text(_AppText.logIntake);
  String get addSchedule => _text(_AppText.addSchedule);
  String get adjustStock => _text(_AppText.adjustStock);
  String get editProduct => _text(_AppText.editProduct);
  String get pauseProduct => _text(_AppText.pauseProduct);
  String get reactivate => _text(_AppText.reactivate);
  String get delete => _text(_AppText.delete);
  String get deleteSchedule => _text(_AppText.deleteSchedule);
  String get pastIntakeRecordsKept => _text(_AppText.pastIntakeRecordsKept);
  String get householdCatalog => _text(_AppText.householdCatalog);
  String get plannedMonthlyCost => _text(_AppText.plannedMonthlyCost);
  String get knownPackagePrices => _text(_AppText.knownPackagePrices);
  String get householdStock => _text(_AppText.householdStock);
  String get stockProjectionDescription =>
      _text(_AppText.stockProjectionDescription);
  String get noStockToManage => _text(_AppText.noStockToManage);
  String get addSupplementAndContainerCount =>
      _text(_AppText.addSupplementAndContainerCount);
  String get noCompatibleHouseholdSchedule =>
      _text(_AppText.noCompatibleHouseholdSchedule);
  String get purchase => _text(_AppText.purchase);
  String get historyAnalytics => _text(_AppText.historyAnalytics);
  String get weeklyAdherence => _text(_AppText.weeklyAdherence);
  String get weeklyAdherenceDescription =>
      _text(_AppText.weeklyAdherenceDescription);
  String get filterSupplementsAndIngredients =>
      _text(_AppText.filterSupplementsAndIngredients);
  String get clearFilter => _text(_AppText.clearFilter);
  String get supplementExposure => _text(_AppText.supplementExposure);
  String get supplementExposureDescription =>
      _text(_AppText.supplementExposureDescription);
  String get noSupplementExposure => _text(_AppText.noSupplementExposure);
  String get logNonSkippedIntake => _text(_AppText.logNonSkippedIntake);
  String get ingredientExposure => _text(_AppText.ingredientExposure);
  String get ingredientExposureDescription =>
      _text(_AppText.ingredientExposureDescription);
  String get noIngredientTotals => _text(_AppText.noIngredientTotals);
  String get addIngredientsAndIntakes =>
      _text(_AppText.addIngredientsAndIntakes);
  String get ingredientSnapshot => _text(_AppText.ingredientSnapshot);
  String get knownIntakeCost => _text(_AppText.knownIntakeCost);
  String get knownIntakeCostDescription =>
      _text(_AppText.knownIntakeCostDescription);
  String get temporalContext => _text(_AppText.temporalContext);
  String get temporalContextDescription =>
      _text(_AppText.temporalContextDescription);
  String get noSymptomOrTagEvents => _text(_AppText.noSymptomOrTagEvents);
  String get eventsShownAlongsideHistory =>
      _text(_AppText.eventsShownAlongsideHistory);
  String get intakeHistory => _text(_AppText.intakeHistory);
  String get intakeHistoryDescription =>
      _text(_AppText.intakeHistoryDescription);
  String get noIntakeHistory => _text(_AppText.noIntakeHistory);
  String get intakeHistoryEmptyDescription =>
      _text(_AppText.intakeHistoryEmptyDescription);
  String get deletedSupplement => _text(_AppText.deletedSupplement);
  String get noDueScheduledDoses => _text(_AppText.noDueScheduledDoses);
  String get futureDosesExcluded => _text(_AppText.futureDosesExcluded);
  String get pinComparisonSeries => _text(_AppText.pinComparisonSeries);
  String get unpinComparisonSeries => _text(_AppText.unpinComparisonSeries);
  String get chooseSupplement => _text(_AppText.chooseSupplement);

  String trackingProgress(int takenCount, int totalCount) =>
      _text(_AppText.trackingProgress)
          .replaceFirst('{taken}', takenCount.toString())
          .replaceFirst('{total}', totalCount.toString());

  String scheduleCount(int count) => _count(
    count,
    singular: _AppText.scheduleSingular,
    plural: _AppText.schedulePlural,
  );

  String daysPerWeek(int count) =>
      _text(_AppText.daysPerWeek).replaceFirst('{count}', count.toString());

  String deleteProductTitle(String name) =>
      _text(_AppText.deleteProductTitle).replaceFirst('{name}', name);

  String get deleteProductDescription =>
      _text(_AppText.deleteProductDescription);
  String get deleteScheduleTitle => _text(_AppText.deleteScheduleTitle);
  String get deleteIntakeTitle => _text(_AppText.deleteIntakeTitle);
  String get deleteIntakeDescription => _text(_AppText.deleteIntakeDescription);

  String daysProjected(int count) =>
      _text(_AppText.daysProjected).replaceFirst('{count}', count.toString());

  String buyForWeeks(int quantity, int weeks) => _text(_AppText.buyForWeeks)
      .replaceFirst('{quantity}', quantity.toString())
      .replaceFirst('{weeks}', weeks.toString());

  String historyRangeDays(int days) =>
      _text(_AppText.historyRangeDays).replaceFirst('{days}', days.toString());

  String intakeCount(int count) => _count(
    count,
    singular: _AppText.intakeSingular,
    plural: _AppText.intakePlural,
  );

  String showMoreHistory(int count) =>
      _text(_AppText.showMoreHistory).replaceFirst('{count}', count.toString());

  String weeklyAdherenceSemantic(
    DateTime weekStarting,
    int takenCount,
    int skippedCount,
    int missedCount,
    int dueCount,
  ) => _text(_AppText.weeklyAdherenceSemantic)
      .replaceFirst('{week}', formatShortDate(weekStarting))
      .replaceFirst('{taken}', takenCount.toString())
      .replaceFirst('{skipped}', skippedCount.toString())
      .replaceFirst('{missed}', missedCount.toString())
      .replaceFirst('{due}', dueCount.toString());

  String weeklyAdherenceSummary(
    int takenCount,
    int skippedCount,
    int missedCount,
    int dueCount,
  ) => _text(_AppText.weeklyAdherenceSummary)
      .replaceFirst('{taken}', takenCount.toString())
      .replaceFirst('{skipped}', skippedCount.toString())
      .replaceFirst('{missed}', missedCount.toString())
      .replaceFirst('{due}', dueCount.toString());

  String unknownCostDescription(int count) => _text(
    count == 1
        ? _AppText.unknownCostSingularDescription
        : _AppText.unknownCostDescription,
  ).replaceFirst('{count}', count.toString());

  String dailyKnownCostsSemantic(Iterable<(DateTime, double)> costs) =>
      _text(_AppText.dailyKnownCostsSemantic).replaceFirst(
        '{costs}',
        costs
            .map((item) => '${formatShortDate(item.$1)} ${formatEur(item.$2)}')
            .join('; '),
      );

  String dailyKnownCostTooltip(DateTime day, double cost) =>
      '${formatShortDate(day)}: ${formatEur(cost)}';

  String eventScore(int value) =>
      _text(_AppText.eventScore).replaceFirst('{score}', value.toString());

  String knownCostCoverage(int knownCount, int eligibleCount) =>
      eligibleCount == 0
      ? _text(_AppText.noNonSkippedIntakes)
      : _text(_AppText.knownCostCoverage)
            .replaceFirst('{known}', knownCount.toString())
            .replaceFirst('{eligible}', eligibleCount.toString());

  String knownSubtotal(double value) =>
      _text(_AppText.knownSubtotal).replaceFirst('{cost}', formatEur(value));

  String formatTrackingDate(DateTime date) =>
      DateFormat('EEEE, d MMMM', _locale).format(date);

  String formatTrackingWeekday(DateTime date) =>
      DateFormat.E(_locale).format(date);

  String formatHistoryDate(DateTime date) =>
      DateFormat('d MMM y', _locale).format(date);

  String formatTrackingDateTime(DateTime date) =>
      DateFormat.yMd(_locale).add_Hm().format(date);

  String formatNumber(double value, {int decimalDigits = 1}) =>
      NumberFormat.decimalPatternDigits(
        locale: _locale,
        decimalDigits: decimalDigits,
      ).format(value);

  String formatEur(double value, {int decimalDigits = 2}) =>
      NumberFormat.currency(
        locale: _locale,
        symbol: '€',
        decimalDigits: decimalDigits,
      ).format(value);

  String formatPercent(double value) =>
      NumberFormat.percentPattern(_locale).format(value);

  String get journal => _text(_AppText.journal);
  String get biomarkers => _text(_AppText.biomarkers);
  String get context => _text(_AppText.context);
  String get quickCheckIn => _text(_AppText.quickCheckIn);
  String get quickCheckInDescription => _text(_AppText.quickCheckInDescription);
  String get trackHealthEvent => _text(_AppText.trackHealthEvent);
  String get reusableCheckIns => _text(_AppText.reusableCheckIns);
  String get reusableCheckInsExamples =>
      _text(_AppText.reusableCheckInsExamples);
  String get symptomTrend => _text(_AppText.symptomTrend);
  String get changeDateRange => _text(_AppText.changeDateRange);
  String get lastYear => _text(_AppText.lastYear);
  String get allHistory => _text(_AppText.allHistory);
  String get symptoms => _text(_AppText.symptoms);
  String get tags => _text(_AppText.tags);
  String get noJournalEntries => _text(_AppText.noJournalEntries);
  String get noJournalEntriesDescription =>
      _text(_AppText.noJournalEntriesDescription);
  String get exploratoryCorrelations => _text(_AppText.exploratoryCorrelations);
  String get correlationsDescription => _text(_AppText.correlationsDescription);
  String get analyze => _text(_AppText.analyze);
  String get minimumCorrelationDays => _text(_AppText.minimumCorrelationDays);
  String get minimumCorrelationDaysDescription =>
      _text(_AppText.minimumCorrelationDaysDescription);
  String get spearmanUnavailable => _text(_AppText.spearmanUnavailable);
  String get adjustedQUnavailable => _text(_AppText.adjustedQUnavailable);
  String get statisticallySignificant =>
      _text(_AppText.statisticallySignificant);
  String get notStatisticallySignificant =>
      _text(_AppText.notStatisticallySignificant);
  String get correlationCaveat => _text(_AppText.correlationCaveat);
  String get edit => _text(_AppText.edit);
  String get deleteJournalEntryTitle => _text(_AppText.deleteJournalEntryTitle);
  String get deleteJournalEntryDescription =>
      _text(_AppText.deleteJournalEntryDescription);
  String get healthContext => _text(_AppText.healthContext);
  String get healthContextDescription =>
      _text(_AppText.healthContextDescription);
  String get addHealthContext => _text(_AppText.addHealthContext);
  String get noHealthContext => _text(_AppText.noHealthContext);
  String get noHealthContextDescription =>
      _text(_AppText.noHealthContextDescription);
  String get privacy => _text(_AppText.privacy);
  String get privacyDescription => _text(_AppText.privacyDescription);
  String get sharedInventoryPrivateFacts =>
      _text(_AppText.sharedInventoryPrivateFacts);
  String get sharedInventoryPrivateFactsDescription =>
      _text(_AppText.sharedInventoryPrivateFactsDescription);

  String journalEntries(int count) => _count(
    count,
    singular: _AppText.journalEntrySingular,
    plural: _AppText.journalEntryPlural,
  );

  String lastDays(int days) =>
      _text(_AppText.lastDays).replaceFirst('{days}', days.toString());

  String trendSemantics(String name, int count, double min, double max) =>
      _text(_AppText.trendSemantics)
          .replaceFirst('{name}', name)
          .replaceFirst('{count}', count.toString())
          .replaceFirst('{min}', formatNumber(min))
          .replaceFirst('{max}', formatNumber(max));

  String scoreOutOfTen(int score) =>
      _text(_AppText.scoreOutOfTen).replaceFirst('{score}', score.toString());

  String durationMinutes(int minutes) => _text(
    _AppText.durationMinutes,
  ).replaceFirst('{minutes}', minutes.toString());

  String correlationStrength(String value) => switch (value) {
    'strong' => _text(_AppText.correlationStrong),
    'moderate' => _text(_AppText.correlationModerate),
    'weak' => _text(_AppText.correlationWeak),
    _ => value,
  };

  String correlationSummary({
    required int lagDays,
    required int sampleSize,
    required String strength,
    required double? spearman,
    required double? adjustedQ,
    required bool statisticallySignificant,
  }) => _text(_AppText.correlationSummary)
      .replaceFirst('{lag}', lagDays.toString())
      .replaceFirst('{sample}', sampleSize.toString())
      .replaceFirst('{strength}', correlationStrength(strength))
      .replaceFirst(
        '{spearman}',
        spearman == null ? spearmanUnavailable : spearmanValue(spearman),
      )
      .replaceFirst(
        '{q}',
        adjustedQ == null
            ? adjustedQUnavailable
            : adjustedQValue(adjustedQ, statisticallySignificant),
      );

  String spearmanValue(double value) => _text(
    _AppText.spearmanValue,
  ).replaceFirst('{value}', formatNumber(value, decimalDigits: 2));

  String adjustedQValue(double value, bool statisticallySignificant) =>
      _text(_AppText.adjustedQValue)
          .replaceFirst('{value}', formatNumber(value, decimalDigits: 3))
          .replaceFirst(
            '{significance}',
            statisticallySignificant
                ? this.statisticallySignificant
                : notStatisticallySignificant,
          );

  String pearson(double coefficient) => _text(
    _AppText.pearsonValue,
  ).replaceFirst('{value}', formatNumber(coefficient, decimalDigits: 2));

  String contextCategory(String kind) => switch (kind) {
    'condition' => _text(_AppText.contextConditions),
    'medication' => _text(_AppText.contextMedicines),
    'goal' => _text(_AppText.contextGoals),
    'family_history' => _text(_AppText.contextFamilyHistory),
    _ => kind,
  };

  String deleteNamedRecordTitle(String name) =>
      _text(_AppText.deleteNamedRecordTitle).replaceFirst('{name}', name);

  String get deleteNamedRecordDescription =>
      _text(_AppText.deleteNamedRecordDescription);

  String get configureAdvisor => _text(_AppText.configureAdvisor);
  String get configureAdvisorDescription =>
      _text(_AppText.configureAdvisorDescription);
  String get webSearchEnabled => _text(_AppText.webSearchEnabled);
  String get codeExecutionEnabled => _text(_AppText.codeExecutionEnabled);
  String get proposalSafetyCopy => _text(_AppText.proposalSafetyCopy);
  String get advisorFileProposals => _text(_AppText.advisorFileProposals);
  String get advisorFileProposalsDescription =>
      _text(_AppText.advisorFileProposalsDescription);
  String get noPendingFileChanges => _text(_AppText.noPendingFileChanges);
  String get noPendingFileChangesDescription =>
      _text(_AppText.noPendingFileChangesDescription);
  String get reject => _text(_AppText.reject);
  String get reviewAndApply => _text(_AppText.reviewAndApply);
  String get exactPath => _text(_AppText.exactPath);
  String get completeNewContent => _text(_AppText.completeNewContent);
  String get askHealthData => _text(_AppText.askHealthData);
  String get completeProfileSent => _text(_AppText.completeProfileSent);
  String get send => _text(_AppText.send);
  String get advisorWelcomeTitle => _text(_AppText.advisorWelcomeTitle);
  String get advisorWelcomeDescription =>
      _text(_AppText.advisorWelcomeDescription);
  String get welcomePromptSupplements =>
      _text(_AppText.welcomePromptSupplements);
  String get welcomePromptPatterns => _text(_AppText.welcomePromptPatterns);
  String get welcomePromptBiomarkers => _text(_AppText.welcomePromptBiomarkers);

  String providerReasoning(String provider, String model, String? reasoning) =>
      reasoning == null
      ? '$provider · $model'
      : _text(_AppText.providerReasoning)
            .replaceFirst('{provider}', provider)
            .replaceFirst('{model}', model)
            .replaceFirst('{reasoning}', reasoning);

  String pendingFileProposals(int count) => _count(
    count,
    singular: _AppText.pendingFileProposalSingular,
    plural: _AppText.pendingFileProposalPlural,
  );

  String get advisorConversations => _text(_AppText.advisorConversations);
  String get advisorNewConversation => _text(_AppText.advisorNewConversation);
  String get advisorUntitledConversation =>
      _text(_AppText.advisorUntitledConversation);
  String get advisorNoConversations => _text(_AppText.advisorNoConversations);
  String get advisorNoConversationsDescription =>
      _text(_AppText.advisorNoConversationsDescription);
  String get advisorDeleteConversation =>
      _text(_AppText.advisorDeleteConversation);
  String get advisorDeleteConversationDescription =>
      _text(_AppText.advisorDeleteConversationDescription);

  String advisorConversationSummary(int messages, String lastAt) => _text(
    messages == 1
        ? _AppText.advisorConversationSummarySingular
        : _AppText.advisorConversationSummaryPlural,
  ).replaceFirst('{count}', '$messages').replaceFirst('{at}', lastAt);

  String lastContext(int bytes, int? tokens) => _text(_AppText.lastContext)
      .replaceFirst('{size}', formatNumber(bytes / 1024))
      .replaceFirst(
        '{tokens}',
        tokens == null
            ? '—'
            : formatNumber(tokens.toDouble(), decimalDigits: 0),
      );

  String confirmFileOperation(String operation) => _text(
    _AppText.confirmFileOperation,
  ).replaceFirst('{operation}', operation);

  String confirmOperation(String operation) =>
      _text(_AppText.confirmOperation).replaceFirst('{operation}', operation);

  String updatedFile(String path) =>
      _text(_AppText.updatedFile).replaceFirst('{path}', path);

  String sourceNumber(int number) =>
      _text(_AppText.sourceNumber).replaceFirst('{number}', number.toString());

  String formatDashboardDate(DateTime date) =>
      DateFormat('EEEE, d MMMM', _locale).format(date);

  String formatTime(DateTime date) => DateFormat.Hm(_locale).format(date);

  String formatShortDate(DateTime date) =>
      DateFormat.MMMd(_locale).format(date);

  String _count(
    int count, {
    required _AppText singular,
    required _AppText plural,
  }) => '$count ${_text(count == 1 ? singular : plural)}';

  String get _locale => identical(this, german) ? 'de' : 'en';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations.forLocale(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

enum _AppText {
  appName,
  openingRecord,
  couldNotStart,
  welcome,
  onboardingDescription,
  isolatedProfiles,
  isolatedProfilesDescription,
  localFirstByok,
  localFirstByokDescription,
  createFirstProfile,
  restoreFromOneDrive,
  additionalPhoneHint,
  restoreOrTransferExistingData,
  restoreOrTransferDescription,
  startFresh,
  startFreshDescription,
  setupExistingData,
  initialSetup,
  initialSetupDescription,
  finishSetup,
  finishSetupDescription,
  setupProfile,
  setupLegacyJson,
  setupPdfs,
  setupCloud,
  setupAdvisor,
  done,
  importData,
  attachPdfs,
  skipForNow,
  setUp,
  restoreSyncDecisionTitle,
  restoreSyncDecisionDescription,
  resumeAndMerge,
  resumeAndMergeDescription,
  publishRestoredData,
  publishRestoredDataDescription,
  confirmPublishTitle,
  confirmPublishDescription,
  publishConfirmationLabel,
  today,
  supplements,
  health,
  advisor,
  settings,
  switchProfile,
  newProfile,
  appearanceAccessibility,
  deviceWideAppearance,
  language,
  themeMode,
  savingAppearance,
  themeModeDescription,
  system,
  light,
  dark,
  colorPalette,
  mint,
  midnight,
  colorVision,
  standard,
  deuteranomalyFriendly,
  colorVisionExplanation,
  highContrast,
  highContrastDescription,
  todayDoses,
  biomarkersDue,
  lowStock,
  householdInventory,
  labPlans,
  createFirstPlan,
  savedChecklists,
  latestBelow,
  latestAbove,
  comparisonDescription,
  rangeUnavailable,
  quickTrack,
  quickTrackDescription,
  supplementIntake,
  symptom,
  tag,
  recentActivity,
  noActivityYet,
  noActivityDescription,
  needsAttention,
  needsAttentionDescription,
  taken,
  refill,
  privacyBoundary,
  privacyBoundaryDescription,
  keysNeverSynced,
  keysNeverSyncedDescription,
  supplementFallback,
  whichSupplement,
  confirm,
  cancel,
  greetingMorning,
  greetingAfternoon,
  greetingEvening,
  activeProduct,
  activeProducts,
  measuredSingular,
  measuredPlural,
  unavailableSingular,
  unavailablePlural,
  neverMeasuredSingular,
  neverMeasuredPlural,
  neverMeasured,
  score,
  due,
  dayOverdue,
  daysOverdue,
  low,
  remaining,
  catalog,
  stock,
  history,
  nothingScheduled,
  manual,
  noDosesForThisDay,
  addScheduleFromCatalog,
  scheduleFreeDay,
  adherence30Day,
  scheduledThroughCurrentTime,
  undoCheckIn,
  skipDose,
  markTaken,
  skipped,
  missed,
  scheduled,
  searchProductsOrIngredients,
  clearSearch,
  active,
  paused,
  all,
  addSupplement,
  noMatchingSupplements,
  changeFilterOrAddProduct,
  logIntake,
  addSchedule,
  adjustStock,
  editProduct,
  pauseProduct,
  reactivate,
  delete,
  deleteSchedule,
  pastIntakeRecordsKept,
  householdCatalog,
  plannedMonthlyCost,
  knownPackagePrices,
  householdStock,
  stockProjectionDescription,
  noStockToManage,
  addSupplementAndContainerCount,
  noCompatibleHouseholdSchedule,
  purchase,
  historyAnalytics,
  weeklyAdherence,
  weeklyAdherenceDescription,
  filterSupplementsAndIngredients,
  clearFilter,
  supplementExposure,
  supplementExposureDescription,
  noSupplementExposure,
  logNonSkippedIntake,
  ingredientExposure,
  ingredientExposureDescription,
  noIngredientTotals,
  addIngredientsAndIntakes,
  ingredientSnapshot,
  knownIntakeCost,
  knownIntakeCostDescription,
  temporalContext,
  temporalContextDescription,
  noSymptomOrTagEvents,
  eventsShownAlongsideHistory,
  intakeHistory,
  intakeHistoryDescription,
  noIntakeHistory,
  intakeHistoryEmptyDescription,
  deletedSupplement,
  noDueScheduledDoses,
  futureDosesExcluded,
  pinComparisonSeries,
  unpinComparisonSeries,
  chooseSupplement,
  trackingProgress,
  scheduleSingular,
  schedulePlural,
  daysPerWeek,
  deleteProductTitle,
  deleteProductDescription,
  deleteScheduleTitle,
  deleteIntakeTitle,
  deleteIntakeDescription,
  daysProjected,
  buyForWeeks,
  historyRangeDays,
  intakeSingular,
  intakePlural,
  showMoreHistory,
  weeklyAdherenceSemantic,
  weeklyAdherenceSummary,
  unknownCostDescription,
  unknownCostSingularDescription,
  dailyKnownCostsSemantic,
  eventScore,
  noNonSkippedIntakes,
  knownCostCoverage,
  knownSubtotal,
  journal,
  biomarkers,
  context,
  quickCheckIn,
  quickCheckInDescription,
  trackHealthEvent,
  reusableCheckIns,
  reusableCheckInsExamples,
  symptomTrend,
  changeDateRange,
  lastYear,
  allHistory,
  symptoms,
  tags,
  noJournalEntries,
  noJournalEntriesDescription,
  exploratoryCorrelations,
  correlationsDescription,
  analyze,
  minimumCorrelationDays,
  minimumCorrelationDaysDescription,
  spearmanUnavailable,
  adjustedQUnavailable,
  statisticallySignificant,
  notStatisticallySignificant,
  correlationCaveat,
  edit,
  deleteJournalEntryTitle,
  deleteJournalEntryDescription,
  healthContext,
  healthContextDescription,
  addHealthContext,
  noHealthContext,
  noHealthContextDescription,
  privacy,
  privacyDescription,
  sharedInventoryPrivateFacts,
  sharedInventoryPrivateFactsDescription,
  journalEntrySingular,
  journalEntryPlural,
  lastDays,
  trendSemantics,
  scoreOutOfTen,
  durationMinutes,
  correlationStrong,
  correlationModerate,
  correlationWeak,
  correlationSummary,
  contextConditions,
  contextMedicines,
  contextGoals,
  contextFamilyHistory,
  deleteNamedRecordTitle,
  deleteNamedRecordDescription,
  spearmanValue,
  adjustedQValue,
  pearsonValue,
  configureAdvisor,
  configureAdvisorDescription,
  webSearchEnabled,
  codeExecutionEnabled,
  proposalSafetyCopy,
  advisorFileProposals,
  advisorFileProposalsDescription,
  noPendingFileChanges,
  noPendingFileChangesDescription,
  reject,
  reviewAndApply,
  exactPath,
  completeNewContent,
  askHealthData,
  completeProfileSent,
  send,
  advisorWelcomeTitle,
  advisorWelcomeDescription,
  welcomePromptSupplements,
  welcomePromptPatterns,
  welcomePromptBiomarkers,
  providerReasoning,
  pendingFileProposalSingular,
  pendingFileProposalPlural,
  advisorConversations,
  advisorNewConversation,
  advisorUntitledConversation,
  advisorNoConversations,
  advisorNoConversationsDescription,
  advisorConversationSummarySingular,
  advisorConversationSummaryPlural,
  advisorDeleteConversation,
  advisorDeleteConversationDescription,
  lastContext,
  confirmFileOperation,
  confirmOperation,
  updatedFile,
  sourceNumber,
}

const _english = <_AppText, String>{
  _AppText.appName: 'SuperHealth',
  _AppText.openingRecord: 'Opening your private health record…',
  _AppText.couldNotStart: 'SuperHealth could not start',
  _AppText.welcome: 'Welcome to SuperHealth',
  _AppText.onboardingDescription:
      'One private place for supplements, symptoms, biomarkers, lab planning, and a full-context AI advisor.',
  _AppText.isolatedProfiles: 'Isolated profiles',
  _AppText.isolatedProfilesDescription:
      'Only the selected profile enters an AI request or export.',
  _AppText.localFirstByok: 'Local-first and BYOK',
  _AppText.localFirstByokDescription:
      'No Google login, billing worker, or app-owned AI keys.',
  _AppText.createFirstProfile: 'Create first profile',
  _AppText.restoreFromOneDrive: 'Restore from OneDrive',
  _AppText.additionalPhoneHint:
      'On an additional phone, restore the shared snapshot before creating a local profile.',
  _AppText.restoreOrTransferExistingData: 'Restore or transfer existing data',
  _AppText.restoreOrTransferDescription:
      'Restore a portable backup or connect OneDrive before creating a profile.',
  _AppText.startFresh: 'Start fresh',
  _AppText.startFreshDescription: 'Create the first private health profile.',
  _AppText.setupExistingData: 'Set up existing data',
  _AppText.initialSetup: 'Initial setup',
  _AppText.initialSetupDescription:
      'Complete imports, cloud sync, and the advisor when you are ready. Optional steps can be skipped.',
  _AppText.finishSetup: 'Finish setting up SuperHealth',
  _AppText.finishSetupDescription:
      'A few optional steps remain. You can return to them from Settings.',
  _AppText.setupProfile: 'Profile',
  _AppText.setupLegacyJson: 'Legacy JSON data',
  _AppText.setupPdfs: 'Legacy PDF files',
  _AppText.setupCloud: 'OneDrive backup and sync',
  _AppText.setupAdvisor: 'AI advisor',
  _AppText.done: 'Done',
  _AppText.importData: 'Import',
  _AppText.attachPdfs: 'Attach',
  _AppText.skipForNow: 'Skip for now',
  _AppText.setUp: 'Set up',
  _AppText.restoreSyncDecisionTitle:
      'Choose how restored data reaches OneDrive',
  _AppText.restoreSyncDecisionDescription:
      'Sync remains paused until you choose. Nothing will upload automatically.',
  _AppText.resumeAndMerge: 'Resume and merge',
  _AppText.resumeAndMergeDescription:
      'Run the normal conflict-aware sync and review any differences.',
  _AppText.publishRestoredData: 'Publish restored data',
  _AppText.publishRestoredDataDescription:
      'Replace the cloud snapshot with this restored device record. This can overwrite shared data.',
  _AppText.confirmPublishTitle: 'Publish restored data to OneDrive?',
  _AppText.confirmPublishDescription:
      'This authoritatively replaces the SuperHealth cloud snapshot. Type PUBLISH to continue.',
  _AppText.publishConfirmationLabel: 'Type PUBLISH to confirm',
  _AppText.today: 'Today',
  _AppText.supplements: 'Supplements',
  _AppText.health: 'Health',
  _AppText.advisor: 'Advisor',
  _AppText.settings: 'Settings',
  _AppText.switchProfile: 'Switch profile',
  _AppText.newProfile: 'New profile',
  _AppText.appearanceAccessibility: 'Appearance & accessibility',
  _AppText.deviceWideAppearance:
      'Display choices apply to this device, not to a profile',
  _AppText.language: 'Language',
  _AppText.themeMode: 'Theme mode',
  _AppText.savingAppearance: 'Saving appearance settings…',
  _AppText.themeModeDescription: 'Use the device setting or choose a mode.',
  _AppText.system: 'System',
  _AppText.light: 'Light',
  _AppText.dark: 'Dark',
  _AppText.colorPalette: 'Color palette',
  _AppText.mint: 'Mint',
  _AppText.midnight: 'Midnight',
  _AppText.colorVision: 'Color vision',
  _AppText.standard: 'Standard',
  _AppText.deuteranomalyFriendly: 'Deuteranomaly-friendly',
  _AppText.colorVisionExplanation:
      'Icons and text remain the source of meaning. This color mode reduces reliance on red and green.',
  _AppText.highContrast: 'High contrast',
  _AppText.highContrastDescription:
      'Increase foreground, outline, and focus contrast.',
  _AppText.todayDoses: 'Today’s doses',
  _AppText.biomarkersDue: 'Biomarkers due',
  _AppText.lowStock: 'Low stock',
  _AppText.householdInventory: 'Household inventory',
  _AppText.labPlans: 'Lab plans',
  _AppText.createFirstPlan: 'Create your first plan',
  _AppText.savedChecklists: 'Saved checklists',
  _AppText.latestBelow: 'Latest below',
  _AppText.latestAbove: 'Latest above',
  _AppText.comparisonDescription:
      'Compared with personal, stored, or lab bounds',
  _AppText.rangeUnavailable: 'Range unavailable',
  _AppText.quickTrack: 'Quick track',
  _AppText.quickTrackDescription: 'Add data while it is fresh',
  _AppText.supplementIntake: 'Supplement intake',
  _AppText.symptom: 'Symptom',
  _AppText.tag: 'Tag',
  _AppText.recentActivity: 'Recent activity',
  _AppText.noActivityYet: 'No activity yet',
  _AppText.noActivityDescription:
      'Intakes, symptoms, and tags will appear here.',
  _AppText.needsAttention: 'Needs attention',
  _AppText.needsAttentionDescription: 'The most useful next actions',
  _AppText.taken: 'Taken',
  _AppText.refill: 'Refill',
  _AppText.privacyBoundary: 'Privacy boundary',
  _AppText.privacyBoundaryDescription:
      'Designed for a private, local-first health record',
  _AppText.keysNeverSynced: 'Your keys and OneDrive tokens are never synced',
  _AppText.keysNeverSyncedDescription:
      'The AI receives only the complete active-profile snapshot for a request. It has no database connection.',
  _AppText.supplementFallback: 'Supplement',
  _AppText.whichSupplement: 'Which supplement?',
  _AppText.confirm: 'Confirm',
  _AppText.cancel: 'Cancel',
  _AppText.greetingMorning: 'Good morning, {name}',
  _AppText.greetingAfternoon: 'Good afternoon, {name}',
  _AppText.greetingEvening: 'Good evening, {name}',
  _AppText.activeProduct: 'active product',
  _AppText.activeProducts: 'active products',
  _AppText.measuredSingular: 'measured',
  _AppText.measuredPlural: 'measured',
  _AppText.unavailableSingular: 'unavailable',
  _AppText.unavailablePlural: 'unavailable',
  _AppText.neverMeasuredSingular: 'never measured',
  _AppText.neverMeasuredPlural: 'never measured',
  _AppText.neverMeasured: 'never measured',
  _AppText.score: 'Score {score}/10',
  _AppText.due: '{name} is due',
  _AppText.dayOverdue: 'day overdue',
  _AppText.daysOverdue: 'days overdue',
  _AppText.low: '{name} is low',
  _AppText.remaining: '{quantity} {unit} remaining',
  _AppText.catalog: 'Catalog',
  _AppText.stock: 'Stock',
  _AppText.history: 'History',
  _AppText.nothingScheduled: 'Nothing scheduled',
  _AppText.manual: 'Manual',
  _AppText.noDosesForThisDay: 'No doses for this day',
  _AppText.addScheduleFromCatalog:
      'Add a schedule from the supplement catalog.',
  _AppText.scheduleFreeDay: 'This is a schedule-free day.',
  _AppText.adherence30Day: '30-day adherence',
  _AppText.scheduledThroughCurrentTime:
      'Scheduled doses through the current time',
  _AppText.undoCheckIn: 'Undo check-in',
  _AppText.skipDose: 'Skip this dose',
  _AppText.markTaken: 'Mark as taken',
  _AppText.skipped: 'Skipped',
  _AppText.missed: 'Missed',
  _AppText.scheduled: 'Scheduled',
  _AppText.searchProductsOrIngredients: 'Search products or ingredients',
  _AppText.clearSearch: 'Clear search',
  _AppText.active: 'Active',
  _AppText.paused: 'Paused',
  _AppText.all: 'All',
  _AppText.addSupplement: 'Add supplement',
  _AppText.noMatchingSupplements: 'No matching supplements',
  _AppText.changeFilterOrAddProduct: 'Change the filter or add a new product.',
  _AppText.logIntake: 'Log intake',
  _AppText.addSchedule: 'Add schedule',
  _AppText.adjustStock: 'Adjust stock',
  _AppText.editProduct: 'Edit product',
  _AppText.pauseProduct: 'Pause product',
  _AppText.reactivate: 'Reactivate',
  _AppText.delete: 'Delete',
  _AppText.deleteSchedule: 'Delete schedule',
  _AppText.pastIntakeRecordsKept: 'Past intake records will be kept.',
  _AppText.householdCatalog: 'Household catalog',
  _AppText.plannedMonthlyCost: 'Planned monthly cost',
  _AppText.knownPackagePrices: 'Known package prices',
  _AppText.householdStock: 'Household stock',
  _AppText.stockProjectionDescription:
      'Consumption projection includes every profile schedule',
  _AppText.noStockToManage: 'No stock to manage',
  _AppText.addSupplementAndContainerCount:
      'Add a supplement and its current container count.',
  _AppText.noCompatibleHouseholdSchedule: 'No compatible household schedule',
  _AppText.purchase: 'Purchase',
  _AppText.historyAnalytics: 'History & analytics',
  _AppText.weeklyAdherence: 'Weekly adherence',
  _AppText.weeklyAdherenceDescription:
      'Taken, skipped and missed scheduled doses; future doses are excluded.',
  _AppText.filterSupplementsAndIngredients:
      'Filter supplements and ingredients',
  _AppText.clearFilter: 'Clear filter',
  _AppText.supplementExposure: 'Supplement exposure',
  _AppText.supplementExposureDescription:
      'Actual non-skipped check-ins, kept separate by reported unit.',
  _AppText.noSupplementExposure: 'No supplement exposure in this range',
  _AppText.logNonSkippedIntake:
      'Log a non-skipped intake to see unit-safe totals.',
  _AppText.ingredientExposure: 'Ingredient / component exposure',
  _AppText.ingredientExposureDescription:
      'Calculated from the ingredient snapshot saved with each intake.',
  _AppText.noIngredientTotals: 'No ingredient totals yet',
  _AppText.addIngredientsAndIntakes:
      'Add ingredient amounts to products and log intakes to see totals.',
  _AppText.ingredientSnapshot: 'Ingredient snapshot',
  _AppText.knownIntakeCost: 'Known intake cost',
  _AppText.knownIntakeCostDescription:
      'Actual intakes with a compatible package price and unit.',
  _AppText.temporalContext: 'Symptoms & tags: temporal context',
  _AppText.temporalContextDescription:
      'Hypothesis generation only; this does not show causation. Use Correlations for analysis.',
  _AppText.noSymptomOrTagEvents: 'No symptom or tag events in this range',
  _AppText.eventsShownAlongsideHistory:
      'Events logged in Health appear here alongside intake history.',
  _AppText.intakeHistory: 'Intake history',
  _AppText.intakeHistoryDescription:
      'All matching records are reachable. Remove an entry to reverse its linked stock deduction.',
  _AppText.noIntakeHistory: 'No intake history',
  _AppText.intakeHistoryEmptyDescription:
      'Scheduled and manual check-ins in this range appear here.',
  _AppText.deletedSupplement: 'Deleted supplement',
  _AppText.noDueScheduledDoses: 'No due scheduled doses in this range',
  _AppText.futureDosesExcluded:
      'Future doses are intentionally not counted as missed.',
  _AppText.pinComparisonSeries: 'Pin comparison series',
  _AppText.unpinComparisonSeries: 'Unpin comparison series',
  _AppText.chooseSupplement: 'Choose supplement',
  _AppText.trackingProgress: '{taken} of {total} taken',
  _AppText.scheduleSingular: 'schedule',
  _AppText.schedulePlural: 'schedules',
  _AppText.daysPerWeek: '{count} days/week',
  _AppText.deleteProductTitle: 'Delete {name}?',
  _AppText.deleteProductDescription:
      'The product and its active schedules will be removed. Historical intakes remain as evidence.',
  _AppText.deleteScheduleTitle: 'Delete schedule?',
  _AppText.deleteIntakeTitle: 'Delete intake?',
  _AppText.deleteIntakeDescription:
      'The linked stock deduction will also be reversed.',
  _AppText.daysProjected: '{count} days projected',
  _AppText.buyForWeeks: 'Buy ~{quantity} for {weeks} weeks',
  _AppText.historyRangeDays: '{days} days',
  _AppText.intakeSingular: 'intake',
  _AppText.intakePlural: 'intakes',
  _AppText.showMoreHistory: 'Show 50 more ({count} remaining)',
  _AppText.weeklyAdherenceSemantic:
      'Week starting {week}: {taken} taken, {skipped} skipped, {missed} missed, {due} due.',
  _AppText.weeklyAdherenceSummary:
      'Taken {taken} · Skipped {skipped} · Missed {missed} · Due {due}',
  _AppText.unknownCostDescription:
      '{count} intakes excluded: missing price/package size or incompatible intake unit. This is not a total cost.',
  _AppText.unknownCostSingularDescription:
      '{count} intake excluded: missing price/package size or incompatible intake unit. This is not a total cost.',
  _AppText.dailyKnownCostsSemantic: 'Daily known intake costs: {costs}',
  _AppText.eventScore: 'score {score}',
  _AppText.noNonSkippedIntakes: 'No non-skipped intakes',
  _AppText.knownCostCoverage:
      '{known} of {eligible} intakes have known compatible cost',
  _AppText.knownSubtotal: '{cost} known subtotal',
  _AppText.journal: 'Journal',
  _AppText.biomarkers: 'Biomarkers',
  _AppText.context: 'Context',
  _AppText.quickCheckIn: 'Quick check-in',
  _AppText.quickCheckInDescription:
      'Symptoms, exposures, habits, and interventions',
  _AppText.trackHealthEvent: 'Track a health event',
  _AppText.reusableCheckIns: 'Create reusable check-ins as you log',
  _AppText.reusableCheckInsExamples:
      'Examples: headache severity, energy, caffeine, alcohol, exercise, sleep quality.',
  _AppText.symptomTrend: 'Symptom trend',
  _AppText.changeDateRange: 'Change date range',
  _AppText.lastYear: 'Last year',
  _AppText.allHistory: 'All history',
  _AppText.symptoms: 'Symptoms',
  _AppText.tags: 'Tags',
  _AppText.noJournalEntries: 'No journal entries',
  _AppText.noJournalEntriesDescription:
      'Track a symptom or exposure to start the timeline.',
  _AppText.exploratoryCorrelations: 'Exploratory correlations',
  _AppText.correlationsDescription:
      'Daily exposure vs symptom scores; association is not causation',
  _AppText.analyze: 'Analyze',
  _AppText.minimumCorrelationDays: 'At least 7 overlapping days are required',
  _AppText.minimumCorrelationDaysDescription:
      'Repeated check-ins are needed. Constant exposures cannot produce a correlation.',
  _AppText.spearmanUnavailable: 'Spearman ρ unavailable',
  _AppText.adjustedQUnavailable: 'adjusted q unavailable',
  _AppText.statisticallySignificant: 'statistically significant association',
  _AppText.notStatisticallySignificant: 'not statistically significant',
  _AppText.correlationCaveat:
      'Exploratory only: daily observations can be related over time, so q-values are estimates—not causal evidence.',
  _AppText.edit: 'Edit',
  _AppText.deleteJournalEntryTitle: 'Delete journal entry?',
  _AppText.deleteJournalEntryDescription:
      'This removes the entry from future analysis.',
  _AppText.healthContext: 'Health context',
  _AppText.healthContextDescription:
      'Personal facts used by the advisor and lab planner—not shared across profiles',
  _AppText.addHealthContext: 'Add health context',
  _AppText.noHealthContext: 'No health context yet',
  _AppText.noHealthContextDescription:
      'Add conditions, medicines, goals, and family history so advice can account for them.',
  _AppText.privacy: 'Privacy',
  _AppText.privacyDescription:
      'The active profile is the AI and export boundary',
  _AppText.sharedInventoryPrivateFacts:
      'Household inventory is shared; health facts are not',
  _AppText.sharedInventoryPrivateFactsDescription:
      'Other profiles can use the same supplement stock without their conditions, biomarkers, or journal entering this profile’s AI context.',
  _AppText.journalEntrySingular: 'journal entry in the selected range',
  _AppText.journalEntryPlural: 'journal entries in the selected range',
  _AppText.lastDays: 'Last {days} days',
  _AppText.trendSemantics:
      '{name} trend with {count} points, from {min} to {max}.',
  _AppText.scoreOutOfTen: 'Score {score}/10',
  _AppText.durationMinutes: '{minutes} min',
  _AppText.correlationStrong: 'strong',
  _AppText.correlationModerate: 'moderate',
  _AppText.correlationWeak: 'weak',
  _AppText.correlationSummary:
      'Lag {lag}d · n={sample} · {strength}\n{spearman} · {q}',
  _AppText.contextConditions: 'Conditions',
  _AppText.contextMedicines: 'Medicines',
  _AppText.contextGoals: 'Goals',
  _AppText.contextFamilyHistory: 'Family history',
  _AppText.deleteNamedRecordTitle: 'Delete {name}?',
  _AppText.deleteNamedRecordDescription:
      'The record will no longer be included in advisor context.',
  _AppText.spearmanValue: 'Spearman ρ={value}',
  _AppText.adjustedQValue: 'adjusted q={value} · {significance}',
  _AppText.pearsonValue: 'Pearson r={value}',
  _AppText.configureAdvisor: 'Configure the advisor',
  _AppText.configureAdvisorDescription:
      'Add a provider API key and choose an advisor model in Settings.',
  _AppText.webSearchEnabled: 'Web search enabled',
  _AppText.codeExecutionEnabled: 'Provider sandbox code enabled',
  _AppText.proposalSafetyCopy:
      'Nothing is written until you review and confirm it.',
  _AppText.advisorFileProposals: 'Advisor file proposals',
  _AppText.advisorFileProposalsDescription:
      'Review the exact operation, path, and content. These files are separate from the health database.',
  _AppText.noPendingFileChanges: 'No pending file changes',
  _AppText.noPendingFileChangesDescription:
      'All proposals have been applied or rejected.',
  _AppText.reject: 'Reject',
  _AppText.reviewAndApply: 'Review & apply',
  _AppText.exactPath: 'Exact path',
  _AppText.completeNewContent: 'Complete new content',
  _AppText.askHealthData: 'Ask about your health data…',
  _AppText.completeProfileSent:
      'The complete active profile is sent with each request.',
  _AppText.send: 'Send',
  _AppText.advisorWelcomeTitle: 'Your health research partner',
  _AppText.advisorWelcomeDescription:
      'The advisor can reason across your complete active-profile history. It labels evidence and uncertainty, but does not replace medical care.',
  _AppText.welcomePromptSupplements:
      'Review my current supplements for possible duplications, interactions, and monitoring needs.',
  _AppText.welcomePromptPatterns:
      'What patterns in my recent symptoms and tags are worth investigating?',
  _AppText.welcomePromptBiomarkers:
      'Summarize the most important gaps in my current biomarker history.',
  _AppText.providerReasoning: '{provider} · {model} · {reasoning} reasoning',
  _AppText.pendingFileProposalSingular: 'file change awaiting approval',
  _AppText.pendingFileProposalPlural: 'file changes awaiting approval',
  _AppText.advisorConversations: 'Conversations',
  _AppText.advisorNewConversation: 'New conversation',
  _AppText.advisorUntitledConversation: 'Untitled conversation',
  _AppText.advisorNoConversations: 'No conversations yet',
  _AppText.advisorNoConversationsDescription:
      'Ask the advisor something and this conversation appears here.',
  _AppText.advisorConversationSummarySingular: '{count} message · {at}',
  _AppText.advisorConversationSummaryPlural: '{count} messages · {at}',
  _AppText.advisorDeleteConversation: 'Delete this conversation?',
  _AppText.advisorDeleteConversationDescription:
      'Its messages are removed. Your health record is not affected.',
  _AppText.lastContext: 'Last context: {size} KB (~{tokens} tokens)',
  _AppText.confirmFileOperation: '{operation} file?',
  _AppText.confirmOperation: 'Confirm {operation}',
  _AppText.updatedFile: '{path} updated.',
  _AppText.sourceNumber: 'Source {number}',
};

const _german = <_AppText, String>{
  _AppText.appName: 'SuperHealth',
  _AppText.openingRecord: 'Deine private Gesundheitsakte wird geöffnet…',
  _AppText.couldNotStart: 'SuperHealth konnte nicht gestartet werden',
  _AppText.welcome: 'Willkommen bei SuperHealth',
  _AppText.onboardingDescription:
      'Ein privater Ort für Nahrungsergänzung, Symptome, Biomarker, Laborplanung und eine KI-Beratung mit vollem Kontext.',
  _AppText.isolatedProfiles: 'Getrennte Profile',
  _AppText.isolatedProfilesDescription:
      'Nur das ausgewählte Profil wird in KI-Anfragen oder Exporte einbezogen.',
  _AppText.localFirstByok: 'Lokal zuerst und eigener Schlüssel',
  _AppText.localFirstByokDescription:
      'Keine Google-Anmeldung, keine Abrechnungskomponente und keine app-eigenen KI-Schlüssel.',
  _AppText.createFirstProfile: 'Erstes Profil erstellen',
  _AppText.restoreFromOneDrive: 'Aus OneDrive wiederherstellen',
  _AppText.additionalPhoneHint:
      'Stelle auf einem weiteren Telefon zuerst den gemeinsamen Schnappschuss wieder her, bevor du ein lokales Profil erstellst.',
  _AppText.restoreOrTransferExistingData:
      'Vorhandene Daten wiederherstellen oder übertragen',
  _AppText.restoreOrTransferDescription:
      'Stelle eine portable Sicherung wieder her oder verbinde OneDrive, bevor du ein Profil erstellst.',
  _AppText.startFresh: 'Neu beginnen',
  _AppText.startFreshDescription:
      'Erstelle das erste private Gesundheitsprofil.',
  _AppText.setupExistingData: 'Vorhandene Daten einrichten',
  _AppText.initialSetup: 'Ersteinrichtung',
  _AppText.initialSetupDescription:
      'Importe, Cloud-Synchronisierung und Beratung kannst du einrichten, wenn du bereit bist. Optionale Schritte können übersprungen werden.',
  _AppText.finishSetup: 'SuperHealth fertig einrichten',
  _AppText.finishSetupDescription:
      'Einige optionale Schritte sind noch offen. Du kannst sie jederzeit in den Einstellungen abschließen.',
  _AppText.setupProfile: 'Profil',
  _AppText.setupLegacyJson: 'Alte JSON-Daten',
  _AppText.setupPdfs: 'Alte PDF-Dateien',
  _AppText.setupCloud: 'OneDrive-Sicherung und -Synchronisierung',
  _AppText.setupAdvisor: 'KI-Beratung',
  _AppText.done: 'Erledigt',
  _AppText.importData: 'Importieren',
  _AppText.attachPdfs: 'Anhängen',
  _AppText.skipForNow: 'Vorerst überspringen',
  _AppText.setUp: 'Einrichten',
  _AppText.restoreSyncDecisionTitle:
      'Festlegen, wie wiederhergestellte Daten OneDrive erreichen',
  _AppText.restoreSyncDecisionDescription:
      'Die Synchronisierung bleibt pausiert, bis du dich entscheidest. Es wird nichts automatisch hochgeladen.',
  _AppText.resumeAndMerge: 'Fortsetzen und zusammenführen',
  _AppText.resumeAndMergeDescription:
      'Normale konfliktbewusste Synchronisierung starten und Unterschiede prüfen.',
  _AppText.publishRestoredData: 'Wiederhergestellte Daten veröffentlichen',
  _AppText.publishRestoredDataDescription:
      'Cloud-Schnappschuss durch die Daten dieses wiederhergestellten Geräts ersetzen. Dabei können gemeinsame Daten überschrieben werden.',
  _AppText.confirmPublishTitle:
      'Wiederhergestellte Daten in OneDrive veröffentlichen?',
  _AppText.confirmPublishDescription:
      'Der SuperHealth-Cloud-Schnappschuss wird verbindlich ersetzt. Tippe PUBLISH zum Fortfahren.',
  _AppText.publishConfirmationLabel: 'Zum Bestätigen PUBLISH eingeben',
  _AppText.today: 'Heute',
  _AppText.supplements: 'Ergänzungen',
  _AppText.health: 'Gesundheit',
  _AppText.advisor: 'Beratung',
  _AppText.settings: 'Einstellungen',
  _AppText.switchProfile: 'Profil wechseln',
  _AppText.newProfile: 'Neues Profil',
  _AppText.appearanceAccessibility: 'Darstellung & Barrierefreiheit',
  _AppText.deviceWideAppearance:
      'Anzeigeoptionen gelten für dieses Gerät, nicht für ein Profil',
  _AppText.language: 'Sprache',
  _AppText.themeMode: 'Darstellungsmodus',
  _AppText.savingAppearance: 'Darstellungseinstellungen werden gespeichert…',
  _AppText.themeModeDescription:
      'Geräteeinstellung verwenden oder einen Modus wählen.',
  _AppText.system: 'System',
  _AppText.light: 'Hell',
  _AppText.dark: 'Dunkel',
  _AppText.colorPalette: 'Farbpalette',
  _AppText.mint: 'Mint',
  _AppText.midnight: 'Mitternacht',
  _AppText.colorVision: 'Farbwahrnehmung',
  _AppText.standard: 'Standard',
  _AppText.deuteranomalyFriendly: 'Deuteranomalie-freundlich',
  _AppText.colorVisionExplanation:
      'Symbole und Text bleiben die Bedeutungsträger. Dieser Farbmodus verringert die Abhängigkeit von Rot und Grün.',
  _AppText.highContrast: 'Hoher Kontrast',
  _AppText.highContrastDescription:
      'Erhöht den Kontrast von Vordergrund, Umrissen und Fokus.',
  _AppText.todayDoses: 'Heutige Einnahmen',
  _AppText.biomarkersDue: 'Fällige Biomarker',
  _AppText.lowStock: 'Niedriger Bestand',
  _AppText.householdInventory: 'Haushaltsbestand',
  _AppText.labPlans: 'Laborpläne',
  _AppText.createFirstPlan: 'Ersten Plan erstellen',
  _AppText.savedChecklists: 'Gespeicherte Checklisten',
  _AppText.latestBelow: 'Zuletzt zu niedrig',
  _AppText.latestAbove: 'Zuletzt zu hoch',
  _AppText.comparisonDescription:
      'Verglichen mit persönlichen, gespeicherten oder Laborgrenzen',
  _AppText.rangeUnavailable: 'Bereich nicht verfügbar',
  _AppText.quickTrack: 'Schnell erfassen',
  _AppText.quickTrackDescription: 'Daten erfassen, solange sie frisch sind',
  _AppText.supplementIntake: 'Einnahme',
  _AppText.symptom: 'Symptom',
  _AppText.tag: 'Markierung',
  _AppText.recentActivity: 'Letzte Aktivitäten',
  _AppText.noActivityYet: 'Noch keine Aktivitäten',
  _AppText.noActivityDescription:
      'Einnahmen, Symptome und Markierungen werden hier angezeigt.',
  _AppText.needsAttention: 'Benötigt Aufmerksamkeit',
  _AppText.needsAttentionDescription: 'Die sinnvollsten nächsten Schritte',
  _AppText.taken: 'Eingenommen',
  _AppText.refill: 'Auffüllen',
  _AppText.privacyBoundary: 'Datenschutzgrenze',
  _AppText.privacyBoundaryDescription:
      'Für eine private, lokal gespeicherte Gesundheitsakte entwickelt',
  _AppText.keysNeverSynced:
      'Deine Schlüssel und OneDrive-Token werden nie synchronisiert',
  _AppText.keysNeverSyncedDescription:
      'Die KI erhält für eine Anfrage nur den vollständigen Schnappschuss des aktiven Profils. Sie hat keine Datenbankverbindung.',
  _AppText.supplementFallback: 'Nahrungsergänzung',
  _AppText.whichSupplement: 'Welche Nahrungsergänzung?',
  _AppText.confirm: 'Bestätigen',
  _AppText.cancel: 'Abbrechen',
  _AppText.greetingMorning: 'Guten Morgen, {name}',
  _AppText.greetingAfternoon: 'Guten Tag, {name}',
  _AppText.greetingEvening: 'Guten Abend, {name}',
  _AppText.activeProduct: 'aktives Produkt',
  _AppText.activeProducts: 'aktive Produkte',
  _AppText.measuredSingular: 'gemessen',
  _AppText.measuredPlural: 'gemessen',
  _AppText.unavailableSingular: 'nicht verfügbar',
  _AppText.unavailablePlural: 'nicht verfügbar',
  _AppText.neverMeasuredSingular: 'nie gemessen',
  _AppText.neverMeasuredPlural: 'nie gemessen',
  _AppText.neverMeasured: 'nie gemessen',
  _AppText.score: 'Wert {score}/10',
  _AppText.due: '{name} ist fällig',
  _AppText.dayOverdue: 'Tag überfällig',
  _AppText.daysOverdue: 'Tage überfällig',
  _AppText.low: '{name} ist fast aufgebraucht',
  _AppText.remaining: '{quantity} {unit} übrig',
  _AppText.catalog: 'Katalog',
  _AppText.stock: 'Bestand',
  _AppText.history: 'Verlauf',
  _AppText.nothingScheduled: 'Nichts geplant',
  _AppText.manual: 'Manuell',
  _AppText.noDosesForThisDay: 'Keine Einnahmen für diesen Tag',
  _AppText.addScheduleFromCatalog:
      'Füge im Ergänzungskatalog einen Einnahmeplan hinzu.',
  _AppText.scheduleFreeDay: 'An diesem Tag ist keine Einnahme geplant.',
  _AppText.adherence30Day: '30-Tage-Adhärenz',
  _AppText.scheduledThroughCurrentTime:
      'Bis zur aktuellen Uhrzeit geplante Einnahmen',
  _AppText.undoCheckIn: 'Eintragung rückgängig machen',
  _AppText.skipDose: 'Diese Einnahme überspringen',
  _AppText.markTaken: 'Als eingenommen markieren',
  _AppText.skipped: 'Übersprungen',
  _AppText.missed: 'Verpasst',
  _AppText.scheduled: 'Geplant',
  _AppText.searchProductsOrIngredients: 'Produkte oder Inhaltsstoffe suchen',
  _AppText.clearSearch: 'Suche löschen',
  _AppText.active: 'Aktiv',
  _AppText.paused: 'Pausiert',
  _AppText.all: 'Alle',
  _AppText.addSupplement: 'Nahrungsergänzung hinzufügen',
  _AppText.noMatchingSupplements: 'Keine passenden Nahrungsergänzungen',
  _AppText.changeFilterOrAddProduct:
      'Ändere den Filter oder füge ein neues Produkt hinzu.',
  _AppText.logIntake: 'Einnahme erfassen',
  _AppText.addSchedule: 'Einnahmeplan hinzufügen',
  _AppText.adjustStock: 'Bestand anpassen',
  _AppText.editProduct: 'Produkt bearbeiten',
  _AppText.pauseProduct: 'Produkt pausieren',
  _AppText.reactivate: 'Reaktivieren',
  _AppText.delete: 'Löschen',
  _AppText.deleteSchedule: 'Einnahmeplan löschen',
  _AppText.pastIntakeRecordsKept:
      'Vergangene Einnahmeaufzeichnungen bleiben erhalten.',
  _AppText.householdCatalog: 'Haushaltskatalog',
  _AppText.plannedMonthlyCost: 'Geplante Monatskosten',
  _AppText.knownPackagePrices: 'Bekannte Packungspreise',
  _AppText.householdStock: 'Haushaltsbestand',
  _AppText.stockProjectionDescription:
      'Die Verbrauchsprognose berücksichtigt alle Profile.',
  _AppText.noStockToManage: 'Kein Bestand zu verwalten',
  _AppText.addSupplementAndContainerCount:
      'Füge eine Nahrungsergänzung und ihre aktuelle Packungsanzahl hinzu.',
  _AppText.noCompatibleHouseholdSchedule:
      'Kein kompatibler Einnahmeplan im Haushalt',
  _AppText.purchase: 'Kaufen',
  _AppText.historyAnalytics: 'Verlauf & Auswertung',
  _AppText.weeklyAdherence: 'Wöchentliche Adhärenz',
  _AppText.weeklyAdherenceDescription:
      'Eingenommene, übersprungene und verpasste geplante Einnahmen; zukünftige Einnahmen sind ausgeschlossen.',
  _AppText.filterSupplementsAndIngredients:
      'Nahrungsergänzungen und Inhaltsstoffe filtern',
  _AppText.clearFilter: 'Filter löschen',
  _AppText.supplementExposure: 'Aufnahme von Nahrungsergänzungen',
  _AppText.supplementExposureDescription:
      'Tatsächliche nicht übersprungene Einträge, nach gemeldeter Einheit getrennt.',
  _AppText.noSupplementExposure:
      'Keine Aufnahme von Nahrungsergänzungen in diesem Zeitraum',
  _AppText.logNonSkippedIntake:
      'Erfasse eine nicht übersprungene Einnahme, um einheitssichere Summen zu sehen.',
  _AppText.ingredientExposure: 'Aufnahme von Inhaltsstoffen / Komponenten',
  _AppText.ingredientExposureDescription:
      'Berechnet aus dem bei jeder Einnahme gespeicherten Inhaltsstoff-Schnappschuss.',
  _AppText.noIngredientTotals: 'Noch keine Summen für Inhaltsstoffe',
  _AppText.addIngredientsAndIntakes:
      'Füge Produkten Inhaltsstoffmengen hinzu und erfasse Einnahmen, um Summen zu sehen.',
  _AppText.ingredientSnapshot: 'Inhaltsstoff-Schnappschuss',
  _AppText.knownIntakeCost: 'Bekannte Einnahmekosten',
  _AppText.knownIntakeCostDescription:
      'Tatsächliche Einnahmen mit kompatiblem Packungspreis und Einheit.',
  _AppText.temporalContext: 'Symptome & Markierungen: zeitlicher Kontext',
  _AppText.temporalContextDescription:
      'Nur zur Hypothesenbildung; dies zeigt keine Kausalität. Verwende Korrelationen zur Analyse.',
  _AppText.noSymptomOrTagEvents:
      'Keine Symptom- oder Markierungsereignisse in diesem Zeitraum',
  _AppText.eventsShownAlongsideHistory:
      'In Gesundheit erfasste Ereignisse erscheinen hier neben dem Einnahmeverlauf.',
  _AppText.intakeHistory: 'Einnahmeverlauf',
  _AppText.intakeHistoryDescription:
      'Alle passenden Einträge sind erreichbar. Das Entfernen eines Eintrags macht die verknüpfte Bestandsminderung rückgängig.',
  _AppText.noIntakeHistory: 'Kein Einnahmeverlauf',
  _AppText.intakeHistoryEmptyDescription:
      'Geplante und manuelle Einträge in diesem Zeitraum erscheinen hier.',
  _AppText.deletedSupplement: 'Gelöschte Nahrungsergänzung',
  _AppText.noDueScheduledDoses:
      'Keine fälligen geplanten Einnahmen in diesem Zeitraum',
  _AppText.futureDosesExcluded:
      'Zukünftige Einnahmen werden absichtlich nicht als verpasst gezählt.',
  _AppText.pinComparisonSeries: 'Vergleichsreihe anheften',
  _AppText.unpinComparisonSeries: 'Vergleichsreihe lösen',
  _AppText.chooseSupplement: 'Nahrungsergänzung auswählen',
  _AppText.trackingProgress: '{taken} von {total} eingenommen',
  _AppText.scheduleSingular: 'Einnahmeplan',
  _AppText.schedulePlural: 'Einnahmepläne',
  _AppText.daysPerWeek: '{count} Tage/Woche',
  _AppText.deleteProductTitle: '{name} löschen?',
  _AppText.deleteProductDescription:
      'Das Produkt und seine aktiven Einnahmepläne werden entfernt. Vergangene Einnahmen bleiben als Nachweis erhalten.',
  _AppText.deleteScheduleTitle: 'Einnahmeplan löschen?',
  _AppText.deleteIntakeTitle: 'Einnahme löschen?',
  _AppText.deleteIntakeDescription:
      'Die verknüpfte Bestandsminderung wird ebenfalls rückgängig gemacht.',
  _AppText.daysProjected: '{count} Tage prognostiziert',
  _AppText.buyForWeeks: 'Ca. {quantity} für {weeks} Wochen kaufen',
  _AppText.historyRangeDays: '{days} Tage',
  _AppText.intakeSingular: 'Einnahme',
  _AppText.intakePlural: 'Einnahmen',
  _AppText.showMoreHistory: 'Weitere 50 anzeigen ({count} verbleibend)',
  _AppText.weeklyAdherenceSemantic:
      'Woche ab {week}: {taken} eingenommen, {skipped} übersprungen, {missed} verpasst, {due} fällig.',
  _AppText.weeklyAdherenceSummary:
      'Eingenommen {taken} · Übersprungen {skipped} · Verpasst {missed} · Fällig {due}',
  _AppText.unknownCostDescription:
      '{count} Einnahmen ausgeschlossen: Preis/Packungsgröße fehlt oder Einnahmeeinheit ist inkompatibel. Dies ist kein Gesamtpreis.',
  _AppText.unknownCostSingularDescription:
      '{count} Einnahme ausgeschlossen: Preis/Packungsgröße fehlt oder Einnahmeeinheit ist inkompatibel. Dies ist kein Gesamtpreis.',
  _AppText.dailyKnownCostsSemantic: 'Tägliche bekannte Einnahmekosten: {costs}',
  _AppText.eventScore: 'Wert {score}',
  _AppText.noNonSkippedIntakes: 'Keine nicht übersprungenen Einnahmen',
  _AppText.knownCostCoverage:
      '{known} von {eligible} Einnahmen haben bekannte kompatible Kosten',
  _AppText.knownSubtotal: '{cost} bekannter Zwischensumme',
  _AppText.journal: 'Journal',
  _AppText.biomarkers: 'Biomarker',
  _AppText.context: 'Kontext',
  _AppText.quickCheckIn: 'Schneller Eintrag',
  _AppText.quickCheckInDescription:
      'Symptome, Expositionen, Gewohnheiten und Interventionen',
  _AppText.trackHealthEvent: 'Gesundheitsereignis erfassen',
  _AppText.reusableCheckIns:
      'Beim Erfassen wiederverwendbare Einträge erstellen',
  _AppText.reusableCheckInsExamples:
      'Beispiele: Kopfschmerzstärke, Energie, Koffein, Alkohol, Bewegung, Schlafqualität.',
  _AppText.symptomTrend: 'Symptomverlauf',
  _AppText.changeDateRange: 'Zeitraum ändern',
  _AppText.lastYear: 'Letztes Jahr',
  _AppText.allHistory: 'Gesamter Verlauf',
  _AppText.symptoms: 'Symptome',
  _AppText.tags: 'Markierungen',
  _AppText.noJournalEntries: 'Keine Journaleinträge',
  _AppText.noJournalEntriesDescription:
      'Erfasse ein Symptom oder eine Exposition, um die Zeitleiste zu starten.',
  _AppText.exploratoryCorrelations: 'Explorative Korrelationen',
  _AppText.correlationsDescription:
      'Tägliche Exposition im Vergleich zu Symptomwerten; Zusammenhang ist keine Kausalität',
  _AppText.analyze: 'Analysieren',
  _AppText.minimumCorrelationDays:
      'Mindestens 7 überlappende Tage sind erforderlich',
  _AppText.minimumCorrelationDaysDescription:
      'Wiederholte Einträge sind nötig. Konstante Expositionen können keine Korrelation erzeugen.',
  _AppText.spearmanUnavailable: 'Spearman-ρ nicht verfügbar',
  _AppText.adjustedQUnavailable: 'adjustiertes q nicht verfügbar',
  _AppText.statisticallySignificant: 'statistisch signifikanter Zusammenhang',
  _AppText.notStatisticallySignificant: 'nicht statistisch signifikant',
  _AppText.correlationCaveat:
      'Nur explorativ: Tägliche Beobachtungen können über die Zeit zusammenhängen; q-Werte sind daher Schätzungen und kein kausaler Nachweis.',
  _AppText.edit: 'Bearbeiten',
  _AppText.deleteJournalEntryTitle: 'Journaleintrag löschen?',
  _AppText.deleteJournalEntryDescription:
      'Der Eintrag wird aus zukünftigen Analysen entfernt.',
  _AppText.healthContext: 'Gesundheitskontext',
  _AppText.healthContextDescription:
      'Persönliche Fakten für Beratung und Laborplanung – nicht zwischen Profilen geteilt',
  _AppText.addHealthContext: 'Gesundheitskontext hinzufügen',
  _AppText.noHealthContext: 'Noch kein Gesundheitskontext',
  _AppText.noHealthContextDescription:
      'Füge Erkrankungen, Medikamente, Ziele und Familiengeschichte hinzu, damit die Beratung sie berücksichtigen kann.',
  _AppText.privacy: 'Datenschutz',
  _AppText.privacyDescription:
      'Das aktive Profil bildet die Grenze für KI und Exporte',
  _AppText.sharedInventoryPrivateFacts:
      'Der Haushaltsbestand wird geteilt, Gesundheitsdaten nicht',
  _AppText.sharedInventoryPrivateFactsDescription:
      'Andere Profile können denselben Ergänzungsbestand nutzen, ohne dass ihre Erkrankungen, Biomarker oder Journaleinträge in den KI-Kontext dieses Profils gelangen.',
  _AppText.journalEntrySingular: 'Journaleintrag im ausgewählten Zeitraum',
  _AppText.journalEntryPlural: 'Journaleinträge im ausgewählten Zeitraum',
  _AppText.lastDays: 'Letzte {days} Tage',
  _AppText.trendSemantics:
      '{name}-Verlauf mit {count} Punkten, von {min} bis {max}.',
  _AppText.scoreOutOfTen: 'Wert {score}/10',
  _AppText.durationMinutes: '{minutes} Min.',
  _AppText.correlationStrong: 'stark',
  _AppText.correlationModerate: 'moderat',
  _AppText.correlationWeak: 'schwach',
  _AppText.correlationSummary:
      'Verzögerung {lag} T. · n={sample} · {strength}\n{spearman} · {q}',
  _AppText.contextConditions: 'Erkrankungen',
  _AppText.contextMedicines: 'Medikamente',
  _AppText.contextGoals: 'Ziele',
  _AppText.contextFamilyHistory: 'Familiengeschichte',
  _AppText.deleteNamedRecordTitle: '{name} löschen?',
  _AppText.deleteNamedRecordDescription:
      'Der Eintrag wird nicht mehr in den Beratungskontext einbezogen.',
  _AppText.spearmanValue: 'Spearman-ρ={value}',
  _AppText.adjustedQValue: 'adjustiertes q={value} · {significance}',
  _AppText.pearsonValue: 'Pearson-r={value}',
  _AppText.configureAdvisor: 'Beratung einrichten',
  _AppText.configureAdvisorDescription:
      'Füge einen API-Schlüssel eines Anbieters hinzu und wähle in Einstellungen ein Beratungsmodell.',
  _AppText.webSearchEnabled: 'Websuche aktiviert',
  _AppText.codeExecutionEnabled:
      'Code-Ausführung in der Anbieter-Sandbox aktiviert',
  _AppText.proposalSafetyCopy:
      'Es wird nichts geschrieben, bevor du es geprüft und bestätigt hast.',
  _AppText.advisorFileProposals: 'Dateivorschläge der Beratung',
  _AppText.advisorFileProposalsDescription:
      'Prüfe den genauen Vorgang, Pfad und Inhalt. Diese Dateien sind von der Gesundheitsdatenbank getrennt.',
  _AppText.noPendingFileChanges: 'Keine ausstehenden Dateiänderungen',
  _AppText.noPendingFileChangesDescription:
      'Alle Vorschläge wurden übernommen oder abgelehnt.',
  _AppText.reject: 'Ablehnen',
  _AppText.reviewAndApply: 'Prüfen & übernehmen',
  _AppText.exactPath: 'Genauer Pfad',
  _AppText.completeNewContent: 'Vollständiger neuer Inhalt',
  _AppText.askHealthData: 'Frage zu deinen Gesundheitsdaten…',
  _AppText.completeProfileSent:
      'Bei jeder Anfrage wird das vollständige aktive Profil gesendet.',
  _AppText.send: 'Senden',
  _AppText.advisorWelcomeTitle: 'Dein Forschungspartner für Gesundheit',
  _AppText.advisorWelcomeDescription:
      'Die Beratung kann die vollständige Historie des aktiven Profils einbeziehen. Sie kennzeichnet Evidenz und Unsicherheit, ersetzt aber keine medizinische Versorgung.',
  _AppText.welcomePromptSupplements:
      'Prüfe meine aktuellen Nahrungsergänzungen auf mögliche Doppelungen, Wechselwirkungen und Überwachungsbedarf.',
  _AppText.welcomePromptPatterns:
      'Welche Muster in meinen jüngsten Symptomen und Markierungen sollte ich untersuchen?',
  _AppText.welcomePromptBiomarkers:
      'Fasse die wichtigsten Lücken in meinem bisherigen Biomarkerverlauf zusammen.',
  _AppText.providerReasoning: '{provider} · {model} · {reasoning}-Reasoning',
  _AppText.pendingFileProposalSingular: 'Dateiänderung wartet auf Bestätigung',
  _AppText.pendingFileProposalPlural: 'Dateiänderungen warten auf Bestätigung',
  _AppText.advisorConversations: 'Unterhaltungen',
  _AppText.advisorNewConversation: 'Neue Unterhaltung',
  _AppText.advisorUntitledConversation: 'Unterhaltung ohne Titel',
  _AppText.advisorNoConversations: 'Noch keine Unterhaltungen',
  _AppText.advisorNoConversationsDescription:
      'Stelle dem Berater eine Frage, dann erscheint die Unterhaltung hier.',
  _AppText.advisorConversationSummarySingular: '{count} Nachricht · {at}',
  _AppText.advisorConversationSummaryPlural: '{count} Nachrichten · {at}',
  _AppText.advisorDeleteConversation: 'Diese Unterhaltung löschen?',
  _AppText.advisorDeleteConversationDescription:
      'Ihre Nachrichten werden entfernt. Deine Gesundheitsakte bleibt '
      'unberührt.',
  _AppText.lastContext: 'Letzter Kontext: {size} KB (~{tokens} Token)',
  _AppText.confirmFileOperation: '{operation}-Datei?',
  _AppText.confirmOperation: '{operation} bestätigen',
  _AppText.updatedFile: '{path} aktualisiert.',
  _AppText.sourceNumber: 'Quelle {number}',
};
