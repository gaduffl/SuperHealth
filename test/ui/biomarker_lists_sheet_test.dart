import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/lab_price_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/ui/biomarker_lists_sheet.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'each list shows its schedule, where every item’s interval comes from, '
    'and what is due',
    (tester) async {
      final controller = _seededController();
      addTearDown(controller.dispose);
      await _openSheet(tester, controller);

      expect(find.text('Every year · 2 biomarkers · 1 due'), findsOneWidget);
      expect(find.text('No schedule · 1 biomarkers'), findsOneWidget);

      await tester.tap(find.text('Annual'));
      await tester.pumpAndSettle();
      expect(find.text('Retest schedule: every year'), findsOneWidget);
      // The list schedule is changed from a labelled button, not only from
      // the overflow menu.
      expect(find.widgetWithText(TextButton, 'Change'), findsOneWidget);
      expect(
        find.textContaining('Every year (list) · Due since'),
        findsOneWidget,
      );
      expect(find.textContaining('Every 2 years (own) · Next'), findsOneWidget);

      await tester.tap(find.text('Checklist'));
      await tester.pumpAndSettle();
      expect(find.text('No retest schedule'), findsOneWidget);
      expect(
        find.textContaining('No schedule, never due · Never measured'),
        findsOneWidget,
      );
    },
  );

  testWidgets('changing the schedule offers to apply it to every biomarker', (
    tester,
  ) async {
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    await tester.tap(find.text('Annual'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Change'));
    await tester.pumpAndSettle();

    expect(find.text('Edit list'), findsOneWidget);
    expect(find.text('Retest schedule'), findsOneWidget);
    expect(find.text('Apply to every biomarker'), findsOneWidget);
    expect(find.textContaining('1 biomarker(s)'), findsOneWidget);
  });
}

Future<void> _openSheet(WidgetTester tester, AppController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showBiomarkerListsSheet(context, controller),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

AppController _seededController() {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final repository = HealthRepository(database);
  final snapshot = SnapshotService(database, repository);
  final oneDrive = OneDriveService(snapshot);
  final keyStore = ApiKeyStore();
  final clientFactory = AiProviderClientFactory();
  final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
  final now = DateTime.now();
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex',
    createdAt: now,
    updatedAt: now,
  );
  Biomarker marker(String id, String name) => Biomarker(
    id: id,
    canonicalName: id,
    displayName: name,
    createdAt: now,
    updatedAt: now,
  );
  BiomarkerListItem item(String listId, String biomarkerId, {int? days}) =>
      BiomarkerListItem(
        id: '$listId-$biomarkerId',
        listId: listId,
        biomarkerId: biomarkerId,
        dueIntervalDays: days,
        createdAt: now,
        updatedAt: now,
      );
  Measurement reading(String biomarkerId, int daysAgo) => Measurement(
    id: '$biomarkerId-reading',
    profileId: 'profile',
    biomarkerId: biomarkerId,
    takenAt: now.subtract(Duration(days: daysAgo)),
    value: 1,
    unit: 'ng/mL',
    createdAt: now,
    updatedAt: now,
  );
  return AppController(
      database: database,
      repository: repository,
      keyStore: keyStore,
      aiSettingsStore: AiSettingsStore(),
      advisorService: AdvisorService(
        repository: repository,
        keyStore: keyStore,
        clientFactory: clientFactory,
        contextBuilder: HealthContextBuilder(repository),
        workspaceService: workspace,
      ),
      labPriceService: LabPriceService(keyStore, clientFactory),
      labPlannerService: LabPlannerService(
        repository: repository,
        keyStore: keyStore,
        clientFactory: clientFactory,
        contextBuilder: HealthContextBuilder(repository),
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
    )
    ..profiles = [profile]
    ..activeProfile = profile
    ..biomarkers = [
      marker('psa', 'PSA'),
      marker('tsh', 'TSH'),
      marker('lipase', 'Lipase'),
    ]
    ..measurements = [reading('tsh', 10), reading('psa', 400)]
    ..biomarkerLists = [
      BiomarkerList(
        id: 'annual',
        profileId: 'profile',
        name: 'Annual',
        dueIntervalDays: 365,
        createdAt: now,
        updatedAt: now,
        items: [item('annual', 'psa'), item('annual', 'tsh', days: 730)],
      ),
      BiomarkerList(
        id: 'checklist',
        profileId: 'profile',
        name: 'Checklist',
        createdAt: now,
        updatedAt: now,
        items: [item('checklist', 'lipase')],
      ),
    ];
}
