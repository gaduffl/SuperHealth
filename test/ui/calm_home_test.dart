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
import 'package:super_health/ai/lab_price_service.dart';
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
import 'package:super_health/ui/calm_home_screen.dart';
import 'package:super_health/ui/design.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the day is one line, one bar, and one button per dose', (
    tester,
  ) async {
    final controller = _seeded();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    expect(find.text('Magnesium'), findsOneWidget);
    expect(find.text('0 of 1 taken'), findsOneWidget);
    expect(find.byTooltip('Mark as taken'), findsOneWidget);
    // One dose is not a list worth a bulk action.
    expect(find.text('Take all'), findsNothing);
  });

  testWidgets('the calm home leaves out the whole analysis half', (
    tester,
  ) async {
    final controller = _seeded();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    // The day strip, the tile grid, and the privacy card are the parts of
    // Today that exist to be read rather than acted on.
    expect(find.byType(DayStrip), findsNothing);
    expect(find.textContaining('Privacy'), findsNothing);
    expect(find.textContaining('Needs attention'), findsNothing);
    expect(find.byTooltip('Skip this dose'), findsNothing);
  });

  testWidgets('two actions, both of them full width', (tester) async {
    final controller = _seeded();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    for (final label in ['Ask a question', 'Add a lab report']) {
      expect(find.text(label), findsOneWidget);
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .width,
        greaterThan(600),
      );
    }
  });

  testWidgets('nothing here leads to managing supplements', (tester) async {
    // This profile does not choose its own products. A route to the catalogue
    // opens a form that assumes a decision the reader did not make.
    final controller = _seeded();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    expect(find.text('My supplements'), findsNothing);
    expect(find.text('Add a supplement'), findsNothing);
  });

  testWidgets('a recorded dose offers the way back, not a second check', (
    tester,
  ) async {
    final controller = _seeded(recorded: true);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    expect(find.byTooltip('Mark as taken'), findsNothing);
    expect(find.byTooltip('Undo check-in'), findsOneWidget);
    expect(find.text('1 of 1 taken'), findsOneWidget);
  });

  testWidgets('an empty day says so and asks for nothing', (tester) async {
    final controller = _seeded(scheduled: false);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    expect(find.text('Nothing to take today'), findsOneWidget);
    expect(find.byTooltip('Mark as taken'), findsNothing);
    // No call to action: an empty day is not a task for this reader.
    expect(find.text('Add a supplement'), findsNothing);
  });
}

/// Pumped on a tall surface so the whole page lays out at once, the same way
/// the Today tests do — the default window would leave most of it unbuilt.
Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  ShellNavigation navigation,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
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
        home: Scaffold(body: CalmHomeScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _then = DateTime(2026, 7, 27);

final _magnesium = Supplement(
  id: 'magnesium',
  name: 'Magnesium',
  stockUnit: 'capsule',
  createdAt: _then,
  updatedAt: _then,
);

final _schedule = SupplementSchedule(
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
  createdAt: _then,
  updatedAt: _then,
);

/// A controller with its in-memory state populated directly.
///
/// `testWidgets` runs inside fake async, so awaiting real database work here
/// would never complete. The screen only reads the controller's public lists.
AppController _seeded({bool recorded = false, bool scheduled = true}) {
  final today = DateTime.now();
  final profile = Profile(
    id: 'profile',
    displayName: 'Robin',
    easyMode: true,
    createdAt: _then,
    updatedAt: _then,
  );
  return _controller()
    ..initialized = true
    ..profiles = [profile]
    ..activeProfile = profile
    ..supplements = [_magnesium]
    ..schedules = [if (scheduled) _schedule]
    ..householdSchedules = [if (scheduled) _schedule]
    ..intakes = [
      if (recorded)
        SupplementIntake(
          id: 'recorded',
          profileId: profile.id,
          supplementId: _magnesium.id,
          scheduleId: _schedule.id,
          takenAt: DateTime(today.year, today.month, today.day, 8),
          dose: 2,
          unit: 'capsule',
          createdAt: _then,
          updatedAt: _then,
        ),
    ];
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
    labPriceService: LabPriceService(keyStore, clientFactory),
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
