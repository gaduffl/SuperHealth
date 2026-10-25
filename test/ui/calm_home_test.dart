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
import 'package:super_health/app/app_theme.dart';
import 'package:super_health/app/appearance_settings.dart';
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

  testWidgets('intake logging and the other main actions are full width', (
    tester,
  ) async {
    final controller = _seeded();
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    for (final label in [
      'Log supplement intake',
      'Ask a question',
      'Add a lab report',
    ]) {
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

  testWidgets('a schedule-free day still offers intake logging', (
    tester,
  ) async {
    final controller = _seeded(scheduled: false);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _pump(tester, controller, navigation);

    expect(find.text('No doses planned for today'), findsOneWidget);
    expect(find.text('Log supplement intake'), findsOneWidget);
    expect(find.byTooltip('Mark as taken'), findsNothing);
    // Logging an existing product does not open catalog management.
    expect(find.text('Add a supplement'), findsNothing);
  });

  testWidgets('manual intake logging saves the dose and undo removes it', (
    tester,
  ) async {
    final controller = _seeded(scheduled: false);
    final navigation = ShellNavigation();
    addTearDown(() async {
      controller.dispose();
      navigation.dispose();
      await controller.database.close();
    });
    await tester.runAsync(() async {
      await controller.repository.saveProfile(controller.activeProfile!);
      await controller.repository.saveSupplement(_magnesium);
    });
    await _pump(tester, controller, navigation);

    await tester.tap(find.text('Log supplement intake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Magnesium'));
    await tester.pumpAndSettle();
    expect(find.text('Log Magnesium'), findsOneWidget);
    expect(find.text('Date'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Dose *'), '1.5');
    await tester.enterText(
      find.widgetWithText(TextField, 'Notes'),
      'With lunch',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Log intake'));
    await tester.pumpAndSettle();
    await _waitForIntakes(tester, controller, 1);

    final stored = (await tester.runAsync(
      () => controller.repository.intakes(controller.activeProfile!.id),
    ))!.single;
    expect(stored.dose, 1.5);
    expect(stored.unit, 'capsule');
    expect(stored.scheduleId, isNull);
    expect(stored.notes, 'With lunch');
    expect(controller.stockLevels[_magnesium.id], -1.5);
    expect(find.byType(CalmIntakeRow), findsOneWidget);
    expect(find.text('Recorded today'), findsOneWidget);
    expect(find.text('No doses planned for today'), findsNothing);

    await tester.runAsync(() => tester.tap(find.byTooltip('Undo check-in')));
    await _waitForIntakes(tester, controller, 0);
    expect(find.byType(CalmIntakeRow), findsNothing);
    expect(controller.stockLevels[_magnesium.id] ?? 0, 0);
    expect(
      await tester.runAsync(
        () => controller.repository.intakes(controller.activeProfile!.id),
      ),
      isEmpty,
    );
  });

  testWidgets(
    'manual logging can be cancelled and only offers active products',
    (tester) async {
      final controller = _seeded(scheduled: false)
        ..supplements = [
          _magnesium,
          Supplement(
            id: 'paused',
            name: 'Paused product',
            active: false,
            createdAt: _then,
            updatedAt: _then,
          ),
          Supplement(
            id: 'deleted',
            name: 'Deleted product',
            deleted: true,
            createdAt: _then,
            updatedAt: _then,
          ),
        ];
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });
      await _pump(tester, controller, navigation, locale: const Locale('de'));

      await tester.tap(find.text('Supplement-Einnahme erfassen'));
      await tester.pumpAndSettle();
      expect(find.text('Welche Nahrungsergänzung?'), findsOneWidget);
      expect(find.text('Paused product'), findsNothing);
      expect(find.text('Deleted product'), findsNothing);
      await tester.tap(find.text('Magnesium'));
      await tester.pumpAndSettle();
      expect(find.text('Magnesium erfassen'), findsOneWidget);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(controller.intakes, isEmpty);
      expect(find.byType(CalmIntakeRow), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'today includes unmatched intakes once and stays profile scoped',
    (tester) async {
      final controller = _seeded(recorded: true);
      final today = DateTime.now();
      controller.intakes = [
        ...controller.intakes,
        _intake(id: 'manual', takenAt: today),
        _intake(id: 'retired-schedule', takenAt: today, scheduleId: 'retired'),
        _intake(
          id: 'yesterday',
          takenAt: DateTime(today.year, today.month, today.day - 1),
        ),
        _intake(id: 'deleted', takenAt: today, deleted: true),
        _intake(id: 'other-profile', takenAt: today, profileId: 'other'),
      ];
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });
      await _pump(tester, controller, navigation);

      expect(find.byType(CalmDoseRow), findsOneWidget);
      expect(
        tester
            .widgetList<CalmIntakeRow>(find.byType(CalmIntakeRow))
            .map((row) => row.intake.id),
        ['manual', 'retired-schedule'],
      );
      expect(find.text('1 of 1 taken'), findsOneWidget);
    },
  );

  testWidgets('logging with no active products explains what is missing', (
    tester,
  ) async {
    final controller = _seeded(scheduled: false)..supplements = [];
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });
    await _pump(tester, controller, navigation);
    await tester.tap(find.text('Log supplement intake'));
    await tester.pumpAndSettle();

    expect(find.text('No active supplements'), findsOneWidget);
    expect(find.textContaining('Add or activate a supplement'), findsOneWidget);
    expect(controller.intakes, isEmpty);
  });

  testWidgets(
    'a manual intake matched to a schedule shows the recorded amount',
    (tester) async {
      final today = DateTime.now();
      final controller = _seeded()
        ..intakes = [
          _intake(
            id: 'manual',
            takenAt: DateTime(today.year, today.month, today.day, 8),
            dose: 1.5,
          ),
        ];
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });
      await _pump(tester, controller, navigation);

      expect(find.byType(CalmDoseRow), findsOneWidget);
      expect(find.byType(CalmIntakeRow), findsNothing);
      expect(find.textContaining('1.5'), findsOneWidget);
      expect(find.byTooltip('Undo check-in'), findsOneWidget);
    },
  );

  testWidgets('intake logging fits a phone with larger text and a keyboard', (
    tester,
  ) async {
    final controller = _seeded(scheduled: false);
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });
    await _pump(
      tester,
      controller,
      navigation,
      viewSize: const Size(400, 800),
      textScale: 1.5,
    );
    await tester.scrollUntilVisible(find.text('Log supplement intake'), 200);
    await tester.tap(find.text('Log supplement intake'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Magnesium'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.showKeyboard(find.widgetWithText(TextField, 'Dose *'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(FilledButton, 'Log intake'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}

Future<void> _waitForIntakes(
  WidgetTester tester,
  AppController controller,
  int count,
) async {
  for (
    var attempt = 0;
    attempt < 100 && controller.intakes.length != count;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  expect(controller.intakes, hasLength(count));
}

SupplementIntake _intake({
  required String id,
  required DateTime takenAt,
  String profileId = 'profile',
  String? scheduleId,
  bool deleted = false,
  double dose = 1,
}) => SupplementIntake(
  id: id,
  profileId: profileId,
  supplementId: _magnesium.id,
  scheduleId: scheduleId,
  takenAt: takenAt,
  dose: dose,
  unit: 'capsule',
  createdAt: _then,
  updatedAt: _then,
  deleted: deleted,
);

/// Pumped on a tall surface so the whole page lays out at once, the same way
/// the Today tests do — the default window would leave most of it unbuilt.
Future<void> _pump(
  WidgetTester tester,
  AppController controller,
  ShellNavigation navigation, {
  Locale locale = const Locale('en'),
  Size viewSize = const Size(900, 3200),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = viewSize;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: navigation),
      ],
      child: MaterialApp(
        locale: locale,
        theme: buildAppTheme(
          brightness: Brightness.light,
          settings: const AppearanceSettings(),
          calm: true,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const Scaffold(body: CalmHomeScreen()),
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
