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

  testWidgets('the explanation sits under the name, not past the history', (
    tester,
  ) async {
    // It explains what the number means, so it belongs where the number is
    // introduced. At the foot of the sheet it sat behind every reading ever
    // recorded, which on a well-used marker is a long way down.
    final controller = _seededController(
      description: 'Fasting blood sugar.',
      measurements: [_reading(id: 'm1', takenAt: DateTime(2026, 1, 2))],
    );
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    final explanation = find.text('Fasting blood sugar.');
    expect(explanation, findsOneWidget);
    expect(
      tester.getTopLeft(explanation).dy,
      lessThan(tester.getTopLeft(find.text('History')).dy),
    );
  });

  testWidgets('a remark is its own line rather than the tail of a chain', (
    tester,
  ) async {
    // Joined onto the end of the metadata it was the first thing an
    // overflowing row dropped, which is the opposite of what a remark is for.
    final controller = _seededController(
      measurements: [
        _reading(
          id: 'm1',
          takenAt: DateTime(2026, 1, 2),
          notes: 'Not fasting, ate at 7am',
        ),
      ],
    );
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    expect(find.text('Not fasting, ate at 7am'), findsOneWidget);
  });

  testWidgets('a reading names the report it was read from', (tester) async {
    final controller = _seededController(
      measurements: [
        _reading(
          id: 'm1',
          takenAt: DateTime(2026, 1, 2),
          documentId: 'doc',
          page: 3,
        ),
      ],
      documents: [_report()],
    );
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    expect(find.text('labor-2026-01.pdf · page 3'), findsOneWidget);
  });

  testWidgets('a reading whose report is gone says so', (tester) async {
    // The measurement outlives a deleted report. A link that goes nowhere
    // would be worse than the sentence.
    final controller = _seededController(
      measurements: [
        _reading(
          id: 'm1',
          takenAt: DateTime(2026, 1, 2),
          documentId: 'missing',
        ),
      ],
    );
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    expect(find.text('Source report is no longer available'), findsOneWidget);
  });

  testWidgets('a reading with no report shows no source line', (tester) async {
    final controller = _seededController(
      measurements: [_reading(id: 'm1', takenAt: DateTime(2026, 1, 2))],
    );
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    expect(find.textContaining('.pdf'), findsNothing);
    expect(find.text('Source report is no longer available'), findsNothing);
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

  testWidgets('add to list ticks the lists the marker is already on', (
    tester,
  ) async {
    // The lists sheet asks "what is on this list" and makes you find the
    // marker in a dropdown of the whole catalog. From the marker's own page
    // the question runs the other way, so the marker is fixed and the lists
    // are what you tick — including the ones it is already on.
    final controller = _seededController(
      lists: [
        _list(
          id: 'annual',
          name: 'Annual baseline',
          items: [_listItem(listId: 'annual', dueIntervalDays: 365)],
        ),
        _list(id: 'iron', name: 'Iron follow-up'),
      ],
    );
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await _settleSheet(tester);
    await tester.tap(find.text('Add to list').last);
    await _settleSheet(tester);

    expect(find.text('Annual baseline'), findsOneWidget);
    expect(find.text('Iron follow-up'), findsOneWidget);
    expect(find.text('Already on this list · every 365 days'), findsOneWidget);
    final boxes = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .toList();
    expect(boxes.map((box) => box.value), [true, false]);
  });

  testWidgets('with no lists the dialog offers to create one', (tester) async {
    // Otherwise a phone that has never made a list reaches a dead end here and
    // has to be sent off to find the lists sheet first.
    final controller = _seededController();
    addTearDown(controller.dispose);
    await _openSheet(tester, controller);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await _settleSheet(tester);
    await tester.tap(find.text('Add to list').last);
    await _settleSheet(tester);

    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('No lists yet'), findsOneWidget);
    expect(find.text('New list'), findsOneWidget);
  });
}

Biomarker _glucose({
  double? priceEur,
  String? lab,
  bool deleted = false,
  String description = '',
}) => Biomarker(
  id: 'glucose',
  canonicalName: 'glucose',
  displayName: 'Glucose',
  category: 'metabolic',
  defaultUnit: 'mg/dL',
  description: description,
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

_TestController _seededController({
  String description = '',
  List<Measurement> measurements = const [],
  List<HealthDocument> documents = const [],
  List<BiomarkerList> lists = const [],
}) {
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
    ..biomarkers = [_glucose(description: description)]
    ..measurements = measurements
    ..documents = documents
    ..biomarkerLists = lists;
}

BiomarkerList _list({
  required String id,
  required String name,
  List<BiomarkerListItem> items = const [],
}) => BiomarkerList(
  id: id,
  profileId: 'profile',
  name: name,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  items: items,
);

BiomarkerListItem _listItem({required String listId, int? dueIntervalDays}) =>
    BiomarkerListItem(
      id: '$listId-glucose',
      listId: listId,
      biomarkerId: 'glucose',
      dueIntervalDays: dueIntervalDays,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Measurement _reading({
  required String id,
  required DateTime takenAt,
  double value = 95,
  String notes = '',
  String? documentId,
  int? page,
}) => Measurement(
  id: id,
  profileId: 'profile',
  biomarkerId: 'glucose',
  takenAt: takenAt,
  value: value,
  unit: 'mg/dL',
  notes: notes,
  documentId: documentId,
  page: page,
  createdAt: takenAt,
  updatedAt: takenAt,
);

HealthDocument _report({String id = 'doc', String? localPath}) =>
    HealthDocument(
      id: id,
      profileId: 'profile',
      fileName: 'labor-2026-01.pdf',
      localPath: localPath,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
