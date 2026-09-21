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

  test(
    'deleting a shared supplement tombstones schedules for every profile',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime(2026, 7, 24);
      final alpha = await fixture.repository.createProfile(
        displayName: 'Alpha',
      );
      final beta = await fixture.repository.createProfile(displayName: 'Beta');
      final removed = Supplement(
        id: 'removed-supplement',
        name: 'Shared magnesium',
        createdAt: now,
        updatedAt: now,
      );
      final retained = Supplement(
        id: 'retained-supplement',
        name: 'Shared omega-3',
        createdAt: now,
        updatedAt: now,
      );
      await fixture.repository.saveSupplement(removed);
      await fixture.repository.saveSupplement(retained);
      await fixture.repository.saveSchedule(
        _schedule('alpha-active', alpha.id, removed.id, now),
      );
      await fixture.repository.saveSchedule(
        _schedule('beta-inactive', beta.id, removed.id, now, active: false),
      );
      await fixture.repository.saveSchedule(
        _schedule('beta-retained', beta.id, retained.id, now),
      );
      fixture.controller
        ..profiles = [alpha, beta]
        ..activeProfile = alpha;

      await fixture.controller.deleteSupplement(removed);

      final db = await fixture.database.database;
      final rows = await db.query(
        'supplement_schedules',
        columns: ['id', 'deleted'],
        orderBy: 'id',
      );
      expect(rows, [
        {'id': 'alpha-active', 'deleted': 1},
        {'id': 'beta-inactive', 'deleted': 1},
        {'id': 'beta-retained', 'deleted': 0},
      ]);
      expect(
        await fixture.repository.schedulesForSupplement(removed.id),
        isEmpty,
      );
      expect((await fixture.repository.supplements()).map((item) => item.id), [
        retained.id,
      ]);
    },
  );

  test('logging an intake reloads only intake and inventory state', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final profile = await fixture.repository.createProfile(displayName: 'Alex');
    final now = DateTime(2026, 7, 24);
    final supplement = Supplement(
      id: 'supplement',
      name: 'Magnesium',
      stockUnit: 'unit',
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveSupplement(supplement);
    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await fixture.controller.refreshActiveData();
    expect(fixture.repository.biomarkerReads, 1);
    fixture.repository.resetReadCounts();
    final biomarkersBefore = fixture.controller.biomarkers;
    final documentsBefore = fixture.controller.documents;

    await fixture.controller.logIntake(
      supplement: supplement,
      dose: 1,
      unit: 'unit',
      takenAt: now,
    );

    expect(fixture.repository.intakeReads, 1);
    expect(fixture.repository.inventoryMovementReads, 1);
    expect(fixture.repository.stockLevelReads, 1);
    expect(fixture.repository.biomarkerReads, 0);
    expect(fixture.repository.documentReads, 0);
    expect(identical(fixture.controller.biomarkers, biomarkersBefore), isTrue);
    expect(identical(fixture.controller.documents, documentsBefore), isTrue);
    expect(fixture.controller.intakes, hasLength(1));
    expect(fixture.controller.stockLevels[supplement.id], -1);
  });
}

SupplementSchedule _schedule(
  String id,
  String profileId,
  String supplementId,
  DateTime now, {
  bool active = true,
}) => SupplementSchedule(
  id: id,
  profileId: profileId,
  supplementId: supplementId,
  dose: 1,
  unit: 'capsule',
  timeOfDay: '08:00',
  weekdays: const ['monday'],
  active: active,
  createdAt: now,
  updatedAt: now,
);

class _Fixture {
  _Fixture({
    required this.database,
    required this.repository,
    required this.controller,
  });

  final AppDatabase database;
  final _CountingHealthRepository repository;
  final AppController controller;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = _CountingHealthRepository(database);
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

class _CountingHealthRepository extends HealthRepository {
  _CountingHealthRepository(super.database);

  int intakeReads = 0;
  int inventoryMovementReads = 0;
  int stockLevelReads = 0;
  int biomarkerReads = 0;
  int documentReads = 0;

  void resetReadCounts() {
    intakeReads = 0;
    inventoryMovementReads = 0;
    stockLevelReads = 0;
    biomarkerReads = 0;
    documentReads = 0;
  }

  @override
  Future<List<SupplementIntake>> intakes(
    String profileId, {
    DateTime? from,
    DateTime? to,
  }) {
    intakeReads++;
    return super.intakes(profileId, from: from, to: to);
  }

  @override
  Future<List<InventoryMovement>> inventoryMovements({String? supplementId}) {
    inventoryMovementReads++;
    return super.inventoryMovements(supplementId: supplementId);
  }

  @override
  Future<Map<String, double>> stockLevels() {
    stockLevelReads++;
    return super.stockLevels();
  }

  @override
  Future<List<Biomarker>> biomarkers() {
    biomarkerReads++;
    return super.biomarkers();
  }

  @override
  Future<List<HealthDocument>> documents(String profileId) {
    documentReads++;
    return super.documents(profileId);
  }
}
