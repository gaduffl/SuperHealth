import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/app/shell_navigation.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/ui/charts.dart';
import 'package:super_health/ui/dashboard_screen.dart';
import 'package:super_health/ui/health_screen.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // The screen formats dates and numbers through intl, which needs its
    // locale tables loaded before the first frame.
    initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('today groups scheduled doses under their part of the day', (
    tester,
  ) async {
    final controller = _seededController();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);

    expect(find.text('Magnesium'), findsOneWidget);
    expect(find.text('Morning'), findsWidgets);
    // The whole-block shortcut only appears for a block that has doses in it.
    expect(find.widgetWithText(FilledButton, 'Morning'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Bedtime'), findsNothing);
    expect(find.text('Quick actions'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Symptom'), findsNothing);
    // Both per-dose actions are offered while the dose is still open.
    expect(find.byTooltip('Mark as taken'), findsOneWidget);
    expect(find.byTooltip('Skip this dose'), findsOneWidget);
  });

  testWidgets('a recorded dose replaces its actions with an undo', (
    tester,
  ) async {
    final controller = _seededController(recordTodaysDose: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);

    expect(find.byTooltip('Mark as taken'), findsNothing);
    expect(find.byTooltip('Undo check-in'), findsOneWidget);
    expect(find.text('1/1'), findsWidgets);
  });

  testWidgets('an unplanned intake stays visible in its block', (tester) async {
    final controller = _seededController(recordUnplannedIntake: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);

    expect(find.textContaining('unplanned'), findsOneWidget);
    expect(find.text('Vitamin D'), findsOneWidget);
  });

  testWidgets('daily check-in summarizes symptoms and portion tags', (
    tester,
  ) async {
    final controller = _seededController(recordDailyCheckIn: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);

    expect(
      find.text('1 symptom score(s) and 2 tag(s) saved for this day.'),
      findsOneWidget,
    );
    expect(find.text('Energy 4/5'), findsOneWidget);
    expect(find.text('Stress 4/5'), findsOneWidget);
    expect(find.text('Coffee · 2× filter coffee · 12 g'), findsOneWidget);
  });

  testWidgets('daily check-in owns management and uses a 0-5 symptom scale', (
    tester,
  ) async {
    final controller = _seededController(recordDailyCheckIn: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);
    await tester.tap(find.widgetWithText(FilledButton, 'Edit check-in'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Manage symptoms and tags'), findsOneWidget);
    expect(find.text('New symptom'), findsNothing);
    final ratingSliders = tester.widgetList<Slider>(find.byType(Slider));
    expect(ratingSliders, hasLength(2));
    for (final slider in ratingSliders) {
      expect(slider.max, 5);
      expect(slider.divisions, 5);
    }

    await tester.tap(find.byTooltip('Manage symptoms and tags'));
    await tester.pumpAndSettle();
    expect(find.text('Symptoms and tags'), findsOneWidget);
    expect(find.byTooltip('Add symptom or tag'), findsOneWidget);
  });

  testWidgets('health journal no longer exposes the quick check-in area', (
    tester,
  ) async {
    final controller = _seededController(recordDailyCheckIn: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 3200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_healthApp(controller, navigation));
    await tester.pumpAndSettle();

    expect(find.text('Quick check-in'), findsNothing);
    expect(find.byTooltip('Manage symptoms and tags'), findsNothing);
  });

  testWidgets('health journal groups check-in events into one compact day', (
    tester,
  ) async {
    final controller = _seededController(recordDailyCheckIn: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 3200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_healthApp(controller, navigation));
    await tester.pumpAndSettle();

    expect(find.text('1 recorded day(s) · 4 entries'), findsOneWidget);
    expect(find.text('1 symptom · 2 tags'), findsOneWidget);
    expect(find.text('Energy 4/5'), findsOneWidget);
    expect(find.text('Coffee · 2× filter coffee · 12 g'), findsOneWidget);
    expect(find.text('Trends and correlations'), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);

    final today = DateTime.now();
    final dayKey = ValueKey(
      'journal-${DateTime(today.year, today.month, today.day).toIso8601String()}',
    );
    await tester.tap(find.byKey(dayKey));
    await tester.pumpAndSettle();
    expect(find.text('Edit daily check-in'), findsOneWidget);
  });

  testWidgets('biomarker tab opens with the old Biomarkers home structure', (
    tester,
  ) async {
    final controller = _seededController();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 3200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_healthApp(controller, navigation));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Biomarkers'));
    await tester.pumpAndSettle();

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Add measurement'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Biomarker lists'), findsOneWidget);
    expect(find.text('Due biomarkers'), findsOneWidget);
    expect(find.text('Latest values'), findsOneWidget);
    expect(find.text('Lab planning and biomarker management'), findsOneWidget);
  });

  testWidgets(
    'biomarker dashboard labels collapsed status and reveals every chart',
    (tester) async {
      final controller = _seededController(recordBiomarkers: true);
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });

      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 3200);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_healthApp(controller, navigation));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Biomarkers'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('Metabolic Health'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
      expect(find.text('Complete Blood Count'), findsOneWidget);
      expect(find.text('Out of range'), findsOneWidget);
      expect(
        tester
            .widget<Icon>(
              find.byKey(const ValueKey('biomarker-category-status-metabolic')),
            )
            .color,
        const Color(0xFF0072B2),
      );
      expect(
        tester
            .widget<Icon>(
              find.byKey(const ValueKey('biomarker-category-status-cbc')),
            )
            .color,
        const Color(0xFF9C6500),
      );
      expect(
        find.byKey(const ValueKey('biomarker-trend-glucose')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('biomarker-trend-wbc')), findsNothing);

      await tester.tap(find.text('Metabolic Health'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('biomarker-trend-glucose')),
        findsOneWidget,
      );
      expect(find.text('Trend · mg/dL'), findsOneWidget);
      final glucoseTrend = tester.widget<TrendChart>(
        find.byKey(const ValueKey('biomarker-trend-glucose')),
      );
      expect(glucoseTrend.rangeLow, 70);
      expect(glucoseTrend.rangeHigh, 110);
      final glucoseLineChart = tester.widget<LineChart>(
        find.descendant(
          of: find.byKey(const ValueKey('biomarker-trend-glucose')),
          matching: find.byType(LineChart),
        ),
      );
      final glucoseBand = glucoseLineChart
          .data
          .rangeAnnotations
          .horizontalRangeAnnotations
          .single;
      expect(glucoseBand.y1, 70);
      expect(glucoseBand.y2, 110);
      expect(glucoseLineChart.data.minY, lessThan(70));
      expect(glucoseLineChart.data.maxY, greaterThan(110));

      await tester.tap(find.text('Complete Blood Count'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('biomarker-trend-wbc')), findsOneWidget);
      expect(find.text('Trend · 10^9/L'), findsOneWidget);
      final wbcTrend = tester.widget<TrendChart>(
        find.byKey(const ValueKey('biomarker-trend-wbc')),
      );
      expect(wbcTrend.rangeLow, isNull);
      expect(wbcTrend.rangeHigh, 10);
      final wbcLineChart = tester.widget<LineChart>(
        find.descendant(
          of: find.byKey(const ValueKey('biomarker-trend-wbc')),
          matching: find.byType(LineChart),
        ),
      );
      final wbcBand =
          wbcLineChart.data.rangeAnnotations.horizontalRangeAnnotations.single;
      expect(wbcBand.y1, wbcLineChart.data.minY);
      expect(wbcBand.y2, 10);
    },
  );

  testWidgets('overview tiles deep-link into the section that owns them', (
    tester,
  ) async {
    final controller = _seededController();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);

    // The day's doses are on this screen already, so that tile scrolls
    // instead of navigating and leaves the shell where it is.
    await tester.tap(find.text('Today\u2019s doses'));
    await tester.pumpAndSettle();
    expect(navigation.tabIndex, 0);
    expect(navigation.request, isNull);

    await tester.tap(find.text('Low stock'));
    await tester.pumpAndSettle();
    expect(navigation.tabIndex, 1);
    expect(navigation.request?.section, AppSection.stock);
    expect(navigation.request?.filter, SectionFilter.lowStock);

    await tester.tap(find.text('Biomarkers due'));
    await tester.pumpAndSettle();
    expect(navigation.tabIndex, 2);
    expect(navigation.request?.section, AppSection.biomarkers);
    expect(navigation.request?.filter, SectionFilter.dueBiomarkers);

    await tester.tap(find.text('Latest above'));
    await tester.pumpAndSettle();
    expect(navigation.request?.filter, SectionFilter.aboveTarget);
  });

  testWidgets('analyzing the day hands a question to the advisor', (
    tester,
  ) async {
    final controller = _seededController();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pumpToday(tester, controller, navigation);

    await tester.tap(find.byTooltip('More day actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analyze day'));
    await tester.pumpAndSettle();

    expect(navigation.tabIndex, 3);
    expect(navigation.request?.section, AppSection.advisor);
    final prompt = navigation.request?.prompt ?? '';
    expect(prompt, contains('Magnesium'));
    // The components are what makes the question worth asking.
    expect(prompt, contains('Magnesium 100 mg'));
    expect(prompt, contains('planned'));
  });
}

/// Pumps Today on a tall surface so the whole page is laid out at once.
///
/// The default 800x600 test window would leave most of the screen unbuilt,
/// which makes ordinary `find` calls miss content that a person would scroll to.
Future<void> _pumpToday(
  WidgetTester tester,
  AppController controller,
  ShellNavigation navigation,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(controller, navigation));
  await tester.pumpAndSettle();
}

Widget _app(AppController controller, ShellNavigation navigation) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: navigation),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: DashboardScreen()),
      ),
    );

Widget _healthApp(AppController controller, ShellNavigation navigation) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: navigation),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: HealthScreen()),
      ),
    );

final _now = DateTime(2026, 7, 27);

final _magnesium = Supplement(
  id: 'magnesium',
  name: 'Magnesium',
  stockUnit: 'capsule',
  unitsPerContainer: 60,
  priceEur: 12,
  lowStockThresholdUnits: 20,
  ingredients: const [
    {'name': 'Magnesium', 'amount': 100, 'unit': 'mg'},
  ],
  createdAt: _now,
  updatedAt: _now,
);

final _vitaminD = Supplement(
  id: 'vitamin-d',
  name: 'Vitamin D',
  stockUnit: 'capsule',
  createdAt: _now,
  updatedAt: _now,
);

final _morningSchedule = SupplementSchedule(
  id: 'schedule',
  profileId: 'profile',
  supplementId: _magnesium.id,
  dose: 2,
  unit: 'capsule',
  timeOfDay: 'Morning',
  weekdays: const [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ],
  createdAt: _now,
  updatedAt: _now,
);

/// A controller with its in-memory state populated directly.
///
/// `testWidgets` runs inside fake async, so awaiting real database work here
/// would never complete. The screen only reads the controller's public lists,
/// so seeding them is enough — and keeps these tests about the UI.
AppController _seededController({
  bool recordTodaysDose = false,
  bool recordUnplannedIntake = false,
  bool recordDailyCheckIn = false,
  bool recordBiomarkers = false,
}) {
  final today = DateTime.now();
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex',
    createdAt: _now,
    updatedAt: _now,
  );
  final energyDefinition = HealthEventDefinition(
    id: 'energy',
    profileId: profile.id,
    kind: EventKind.symptom,
    name: 'Energy',
    useScore: true,
    createdAt: _now,
    updatedAt: _now,
  );
  final coffeeDefinition = HealthEventDefinition(
    id: 'coffee',
    profileId: profile.id,
    kind: EventKind.tag,
    name: 'Coffee',
    defaultUnit: 'g',
    valueMode: TagValueMode.amount,
    portionAmount: 6,
    portionLabel: 'filter coffee',
    includeInCheckIn: true,
    createdAt: _now,
    updatedAt: _now,
  );
  final stressDefinition = HealthEventDefinition(
    id: 'stress',
    profileId: profile.id,
    kind: EventKind.tag,
    name: 'Stress',
    valueMode: TagValueMode.intensity,
    includeInCheckIn: true,
    createdAt: _now,
    updatedAt: _now,
  );
  final glucose = Biomarker(
    id: 'glucose',
    canonicalName: 'glucose',
    displayName: 'Glucose',
    category: 'metabolic',
    defaultUnit: 'mg/dL',
    createdAt: _now,
    updatedAt: _now,
  );
  final whiteBloodCells = Biomarker(
    id: 'wbc',
    canonicalName: 'wbc',
    displayName: 'White blood cells',
    category: 'cbc',
    defaultUnit: '10^9/L',
    createdAt: _now,
    updatedAt: _now,
  );
  final controller = _controller()
    ..initialized = true
    ..profiles = [profile]
    ..activeProfile = profile
    ..supplements = [_magnesium, if (recordUnplannedIntake) _vitaminD]
    ..schedules = [_morningSchedule]
    ..householdSchedules = [_morningSchedule]
    ..stockLevels = {_magnesium.id: 4}
    ..biomarkers = [
      if (recordBiomarkers) glucose,
      if (recordBiomarkers) whiteBloodCells,
    ]
    ..measurements = [
      if (recordBiomarkers)
        Measurement(
          id: 'glucose-old',
          profileId: profile.id,
          biomarkerId: glucose.id,
          takenAt: DateTime(2026, 6, 1),
          value: 95,
          unit: 'mg/dL',
          labRefLow: 70,
          labRefHigh: 110,
          createdAt: _now,
          updatedAt: _now,
        ),
      if (recordBiomarkers)
        Measurement(
          id: 'glucose-latest',
          profileId: profile.id,
          biomarkerId: glucose.id,
          takenAt: DateTime(2026, 7, 1),
          value: 90,
          unit: 'mg/dL',
          labRefLow: 70,
          labRefHigh: 110,
          createdAt: _now,
          updatedAt: _now,
        ),
      if (recordBiomarkers)
        Measurement(
          id: 'wbc-latest',
          profileId: profile.id,
          biomarkerId: whiteBloodCells.id,
          takenAt: DateTime(2026, 7, 1),
          value: 14,
          unit: '10^9/L',
          labRefHigh: 10,
          createdAt: _now,
          updatedAt: _now,
        ),
    ]
    ..eventDefinitions = [
      if (recordDailyCheckIn) energyDefinition,
      if (recordDailyCheckIn) coffeeDefinition,
      if (recordDailyCheckIn) stressDefinition,
    ]
    ..events = [
      if (recordDailyCheckIn)
        HealthEvent(
          id: 'energy-event',
          profileId: profile.id,
          definitionId: energyDefinition.id,
          kind: EventKind.symptom,
          name: energyDefinition.name,
          observedAt: DateTime(today.year, today.month, today.day, 9),
          score: 4,
          createdAt: _now,
          updatedAt: _now,
        ),
      for (var index = 0; index < (recordDailyCheckIn ? 2 : 0); index++)
        HealthEvent(
          id: 'coffee-event-$index',
          profileId: profile.id,
          definitionId: coffeeDefinition.id,
          kind: EventKind.tag,
          name: coffeeDefinition.name,
          observedAt: DateTime(today.year, today.month, today.day, 10 + index),
          numericValue: 6,
          unit: 'g',
          createdAt: _now,
          updatedAt: _now,
        ),
      if (recordDailyCheckIn)
        HealthEvent(
          id: 'stress-event',
          profileId: profile.id,
          definitionId: stressDefinition.id,
          kind: EventKind.tag,
          name: stressDefinition.name,
          observedAt: DateTime(today.year, today.month, today.day, 12),
          score: 4,
          createdAt: _now,
          updatedAt: _now,
        ),
    ]
    ..intakes = [
      if (recordTodaysDose)
        SupplementIntake(
          id: 'recorded',
          profileId: profile.id,
          supplementId: _magnesium.id,
          scheduleId: _morningSchedule.id,
          takenAt: DateTime(today.year, today.month, today.day, 8),
          dose: 2,
          unit: 'capsule',
          createdAt: _now,
          updatedAt: _now,
        ),
      if (recordUnplannedIntake)
        SupplementIntake(
          id: 'unplanned',
          profileId: profile.id,
          supplementId: _vitaminD.id,
          takenAt: DateTime(today.year, today.month, today.day, 9),
          dose: 1,
          unit: 'capsule',
          createdAt: _now,
          updatedAt: _now,
        ),
    ];
  return controller;
}

AppController _controller() {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final repository = HealthRepository(database);
  final keyStore = ApiKeyStore();
  final clientFactory = AiProviderClientFactory();
  final contextBuilder = HealthContextBuilder(repository);
  final snapshot = SnapshotService(database, repository);
  final oneDrive = OneDriveService(snapshot, repository: repository);
  final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
  return AppController(
    database: database,
    repository: repository,
    keyStore: keyStore,
    aiSettingsStore: AiSettingsStore(),
    advisorService: AdvisorService(
      repository: repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: contextBuilder,
      workspaceService: workspace,
    ),
    labPlannerService: LabPlannerService(
      repository: repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: contextBuilder,
    ),
    documentParsingService: DocumentParsingService(
      repository: repository,
      keyStore: keyStore,
      oneDriveService: oneDrive,
    ),
    correlationService: CorrelationService(repository),
    importService: LegacyImportService(database, repository),
    oneDriveService: oneDrive,
    workspaceService: workspace,
    exportService: LabPlanExportService(),
    clientFactory: clientFactory,
  );
}
