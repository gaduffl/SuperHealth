import 'package:flutter_test/flutter_test.dart';
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
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a marker is added to the ticked lists and to nothing else', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final ferritin = fixture.biomarker('ferritin');

    final result = await fixture.controller.setBiomarkerListMemberships(
      biomarker: ferritin,
      listIds: {'annual', 'iron'},
      dueIntervalDays: 365,
    );

    expect(result.added, 2);
    expect(result.removed, 0);
    expect(fixture.listsHolding('ferritin'), {'annual', 'iron'});
    expect(fixture.interval('annual', 'ferritin'), 365);
    // The third list was never ticked, so it stays empty.
    expect(fixture.list('quarterly').items, isEmpty);
  });

  test('unticking a list removes only that membership', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final ferritin = fixture.biomarker('ferritin');
    await fixture.controller.setBiomarkerListMemberships(
      biomarker: ferritin,
      listIds: {'annual', 'iron'},
      dueIntervalDays: 365,
    );

    final result = await fixture.controller.setBiomarkerListMemberships(
      biomarker: ferritin,
      listIds: {'annual'},
      dueIntervalDays: 365,
    );

    expect(result.added, 0);
    expect(result.removed, 1);
    expect(fixture.listsHolding('ferritin'), {'annual'});
  });

  test('a membership that stays keeps the interval it was given', () async {
    // The dialog carries one interval field for the whole edit. Applying it to
    // memberships that already exist would silently overwrite a retest
    // schedule the owner chose per marker, which is not what ticking an
    // already-ticked box asks for.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();
    final ferritin = fixture.biomarker('ferritin');
    await fixture.controller.setBiomarkerListItem(
      list: fixture.list('annual'),
      biomarker: ferritin,
      dueIntervalDays: 90,
      notes: 'after the infusion course',
    );

    final result = await fixture.controller.setBiomarkerListMemberships(
      biomarker: ferritin,
      listIds: {'annual', 'iron'},
      dueIntervalDays: 365,
    );

    expect(result.added, 1);
    expect(fixture.interval('annual', 'ferritin'), 90);
    expect(
      fixture.list('annual').items.single.notes,
      'after the infusion course',
    );
    // Only the new membership takes the interval from the dialog.
    expect(fixture.interval('iron', 'ferritin'), 365);
  });

  test('an empty interval stores a membership without due alerts', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();

    await fixture.controller.setBiomarkerListMemberships(
      biomarker: fixture.biomarker('ferritin'),
      listIds: {'annual'},
    );

    expect(fixture.interval('annual', 'ferritin'), isNull);
  });

  test('other markers on the same list are untouched', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.controller.setBiomarkerListItem(
      list: fixture.list('annual'),
      biomarker: fixture.biomarker('tsh'),
      dueIntervalDays: 180,
    );

    await fixture.controller.setBiomarkerListMemberships(
      biomarker: fixture.biomarker('ferritin'),
      listIds: const <String>{},
    );

    expect(fixture.listsHolding('tsh'), {'annual'});
    expect(fixture.interval('annual', 'tsh'), 180);
  });

  test('a non-positive interval is refused rather than stored', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();

    await expectLater(
      fixture.controller.setBiomarkerListMemberships(
        biomarker: fixture.biomarker('ferritin'),
        listIds: {'annual'},
        dueIntervalDays: 0,
      ),
      throwsA(isA<StateError>()),
    );
    expect(fixture.list('annual').items, isEmpty);
  });

  test('changing nothing writes nothing', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.seed();
    await fixture.controller.setBiomarkerListMemberships(
      biomarker: fixture.biomarker('ferritin'),
      listIds: {'annual'},
      dueIntervalDays: 365,
    );
    final before = fixture.list('annual').items.single.updatedAt;

    final result = await fixture.controller.setBiomarkerListMemberships(
      biomarker: fixture.biomarker('ferritin'),
      listIds: {'annual'},
      dueIntervalDays: 30,
    );

    expect(result.added, 0);
    expect(result.removed, 0);
    // An unchanged row keeps its timestamp, so a no-op edit does not
    // manufacture sync work for every device.
    expect(fixture.list('annual').items.single.updatedAt, before);
  });
}

class _Fixture {
  _Fixture({
    required this.database,
    required this.repository,
    required this.controller,
  });

  final AppDatabase database;
  final HealthRepository repository;
  final AppController controller;

  Biomarker biomarker(String id) =>
      controller.biomarkers.firstWhere((item) => item.id == id);

  BiomarkerList list(String id) =>
      controller.biomarkerLists.firstWhere((item) => item.id == id);

  Set<String> listsHolding(String biomarkerId) => {
    for (final item in controller.biomarkerLists)
      if (item.items.any((entry) => entry.biomarkerId == biomarkerId)) item.id,
  };

  int? interval(String listId, String biomarkerId) => list(
    listId,
  ).items.firstWhere((item) => item.biomarkerId == biomarkerId).dueIntervalDays;

  Future<void> seed() async {
    final now = DateTime(2026, 8, 21);
    final profile = await repository.createProfile(displayName: 'A');
    for (final id in ['ferritin', 'tsh']) {
      await repository.saveBiomarker(
        Biomarker(
          id: id,
          canonicalName: id,
          displayName: id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    for (final entry in {
      'annual': 'Annual baseline',
      'iron': 'Iron follow-up',
      'quarterly': 'Quarterly',
    }.entries) {
      await repository.saveBiomarkerList(
        BiomarkerList(
          id: entry.key,
          profileId: profile.id,
          name: entry.value,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await controller.refreshActiveData();
  }

  static Future<_Fixture> create() async {
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
    final controller = AppController(
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
    );
    return _Fixture(
      database: database,
      repository: repository,
      controller: controller,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await database.close();
  }
}
