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

  test('findings follow the loaded record, and are not recomputed until it '
      'changes', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final repository = fixture.repository;
    final profile = await repository.createProfile(displayName: 'Alex');
    final now = DateTime.now();
    final supplement = Supplement(
      id: 'hair',
      name: 'Haut, Haare & Nägel',
      ingredients: const [
        {'name': 'Biotin', 'amount': 10, 'unit': 'mg'},
      ],
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveSupplement(supplement);
    await repository.saveBiomarker(
      Biomarker(
        id: 'tsh',
        canonicalName: 'tsh',
        displayName: 'TSH',
        createdAt: now,
        updatedAt: now,
      ),
    );
    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await fixture.controller.refreshActiveData();
    expect(fixture.controller.interactionFindings, isEmpty);

    await fixture.controller.logIntake(
      supplement: supplement,
      dose: 1,
      unit: 'capsule',
      takenAt: now.subtract(const Duration(hours: 1)),
    );

    final findings = fixture.controller.interactionFindings;
    expect(
      findings.map((finding) => finding.id),
      contains('finding:biotin-streptavidin-immunoassay'),
    );
    // The biomarker sheet asks by biomarker; TSH is among the tests affected.
    expect(fixture.controller.findingsForBiomarker('tsh'), isNotEmpty);
    // A rebuild must not re-run every rule.
    expect(identical(fixture.controller.interactionFindings, findings), isTrue);
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
