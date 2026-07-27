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
import 'package:super_health/ui/dashboard_screen.dart';
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

    await tester.tap(find.widgetWithText(OutlinedButton, 'Analyze'));
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
}) {
  final today = DateTime.now();
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex',
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
