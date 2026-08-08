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

  test('adding a package to a list expands it into its members', () async {
    // Expanded rather than stored as one entry: "due" is a per-marker
    // question, so a bundle-level interval would throw away what the list
    // already holds.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 8, 8);
    final profile = await fixture.repository.createProfile(displayName: 'A');
    for (final id in ['hb', 'wbc', 'plt']) {
      await fixture.repository.saveBiomarker(
        Biomarker(
          id: id,
          canonicalName: id,
          displayName: id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await fixture.repository.saveBiomarkerPackage(
      BiomarkerPackage(
        id: 'blutbild',
        name: 'Kleines Blutbild',
        priceEur: 15,
        createdAt: now,
        updatedAt: now,
      ),
      {'hb', 'wbc', 'plt'},
    );
    final list = BiomarkerList(
      id: 'list',
      profileId: profile.id,
      name: 'Routine',
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveBiomarkerList(list);
    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await fixture.controller.refreshActiveData();

    // One member is already on the list, with an interval the owner chose.
    await fixture.controller.setBiomarkerListItem(
      list: fixture.controller.biomarkerLists.single,
      biomarker: fixture.controller.biomarkers.firstWhere(
        (item) => item.id == 'hb',
      ),
      dueIntervalDays: 180,
    );

    final result = await fixture.controller.addPackageToBiomarkerList(
      list: fixture.controller.biomarkerLists.single,
      package: fixture.controller.biomarkerPackages.single,
    );

    expect(result.added, 2);
    expect(result.alreadyPresent, 1);

    final items = fixture.controller.biomarkerLists.single.items;
    expect(items.map((item) => item.biomarkerId).toSet(), {'hb', 'wbc', 'plt'});
    // The pre-existing entry keeps the interval it was given; a bulk add is
    // not the place to overwrite a deliberate choice.
    expect(
      items.firstWhere((item) => item.biomarkerId == 'hb').dueIntervalDays,
      180,
    );

    // Running it again adds nothing and says so.
    final again = await fixture.controller.addPackageToBiomarkerList(
      list: fixture.controller.biomarkerLists.single,
      package: fixture.controller.biomarkerPackages.single,
    );
    expect(again.added, 0);
    expect(again.alreadyPresent, 3);
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
