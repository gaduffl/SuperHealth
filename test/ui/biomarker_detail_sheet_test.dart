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
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/ui/biomarker_detail_sheet.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an edited price appears in the sheet that edited it', (
    tester,
  ) async {
    // The regression: the sheet held the `Biomarker` it was opened with and a
    // non-listening controller, so it was frozen at open time. Its own Edit
    // action then re-seeded the form from that frozen copy — a saved price was
    // written to the database and vanished from the field, which is
    // indistinguishable from the save having failed.
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    expect(find.text('metabolic · mg/dL · No price'), findsOneWidget);

    controller.setBiomarkersForTest([_glucose(priceEur: 12.5, lab: 'Labor X')]);
    await _settleSheet(tester);

    expect(find.text('metabolic · mg/dL · 12.50 € · Labor X'), findsOneWidget);
  });

  testWidgets('a zero price is reported as no price, not as free', (
    tester,
  ) async {
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    controller.setBiomarkersForTest([_glucose(priceEur: 0)]);
    await _settleSheet(tester);

    expect(find.text('metabolic · mg/dL · No price'), findsOneWidget);
  });

  testWidgets('a biomarker deleted while the sheet is open renders nothing', (
    tester,
  ) async {
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    controller.setBiomarkersForTest([_glucose(deleted: true)]);
    await _settleSheet(tester);

    expect(find.text('Glucose'), findsNothing);
  });
}

Biomarker _glucose({double? priceEur, String? lab, bool deleted = false}) =>
    Biomarker(
      id: 'glucose',
      canonicalName: 'glucose',
      displayName: 'Glucose',
      category: 'metabolic',
      defaultUnit: 'mg/dL',
      priceEur: priceEur,
      labName: lab,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      deleted: deleted,
    );

Future<void> _openSheet(WidgetTester tester, AppController controller) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(controller));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open'));
  await _settleSheet(tester);
}

/// Bounded pumps rather than `pumpAndSettle`: the sheet draws a trend chart
/// whose entry animation never lets the tree go quiet.
Future<void> _settleSheet(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

Widget _app(AppController controller) => ChangeNotifierProvider.value(
  value: controller,
  child: MaterialApp(
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
          onPressed: () =>
              showBiomarkerDetail(context, controller.biomarkers.single),
          child: const Text('Open'),
        ),
      ),
    ),
  ),
);

/// Replaces the catalog the way a save would, without a database.
///
/// `sqflite` runs its work off the test's own clock, and a `testWidgets` body
/// drives a fake one — so a widget test here cannot await the repository. What
/// the fix turns on is only that the sheet re-reads the controller instead of
/// replaying the value it was opened with, which this exercises directly.
class _TestController extends AppController {
  _TestController({
    required super.database,
    required super.repository,
    required super.keyStore,
    required super.aiSettingsStore,
    required super.advisorService,
    required super.labPriceService,
    required super.labPlannerService,
    required super.documentParsingService,
    required super.correlationService,
    required super.importService,
    required super.oneDriveService,
    required super.workspaceService,
    required super.exportService,
    required super.clientFactory,
  });

  void setBiomarkersForTest(List<Biomarker> value) {
    biomarkers = value;
    notifyListeners();
  }
}

_TestController _seededController() {
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
  final now = DateTime(2026, 1, 1);
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex',
    createdAt: now,
    updatedAt: now,
  );
  return _TestController(
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
    ..biomarkers = [_glucose()];
}
