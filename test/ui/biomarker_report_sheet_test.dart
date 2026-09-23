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
import 'package:super_health/ui/biomarker_report_sheet.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the sheet lists measured categories and the comments of the '
      'reports that feed them', (tester) async {
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _open(tester, controller);

    expect(find.text('Thyroid Function'), findsOneWidget);
    expect(find.text('tumor_markers'), findsOneWidget);
    expect(find.text('Not fasting'), findsOneWidget);
    expect(find.text('PSA follow-up advised'), findsOneWidget);
    expect(find.text('Create PDF · 2 charts'), findsOneWidget);

    // Leaving out a category also drops the comment of a report that fed
    // only that category: it could name exactly what was left out.
    await tester.tap(find.text('tumor_markers'));
    await tester.pumpAndSettle();
    expect(find.text('PSA follow-up advised'), findsNothing);
    expect(find.text('Create PDF · 1 charts'), findsOneWidget);

    // A withdrawn comment stays listed so it can be ticked again.
    await tester.tap(find.text('Not fasting'));
    await tester.pumpAndSettle();
    final box = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, 'Not fasting'),
    );
    expect(box.value, isFalse);
  });

  testWidgets('with every category left out there is nothing to create', (
    tester,
  ) async {
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _open(tester, controller);

    await tester.tap(find.text('Thyroid Function'));
    await tester.tap(find.text('tumor_markers'));
    await tester.pumpAndSettle();

    expect(find.text('Select at least one category'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Select at least one category'),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}

Future<void> _open(WidgetTester tester, AppController controller) async {
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
            onPressed: () => showBiomarkerReportSheet(context, controller),
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
  Biomarker marker(String id, String name, String category) => Biomarker(
    id: id,
    canonicalName: id,
    displayName: name,
    category: category,
    createdAt: now,
    updatedAt: now,
  );
  Measurement reading(String biomarkerId, int daysAgo, String documentId) =>
      Measurement(
        id: '$biomarkerId-reading',
        profileId: 'profile',
        biomarkerId: biomarkerId,
        documentId: documentId,
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
      marker('tsh', 'TSH', 'thyroid'),
      marker('psa', 'PSA', 'tumor_markers'),
    ]
    ..measurements = [reading('tsh', 10, 'a'), reading('psa', 400, 'b')]
    ..documents = [
      HealthDocument(
        id: 'a',
        profileId: 'profile',
        fileName: 'a.pdf',
        reportComment: 'Not fasting',
        createdAt: now,
        updatedAt: now,
      ),
      HealthDocument(
        id: 'b',
        profileId: 'profile',
        fileName: 'b.pdf',
        reportComment: 'PSA follow-up advised',
        createdAt: now,
        updatedAt: now,
      ),
    ];
}
