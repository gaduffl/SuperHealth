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

  final reportDay = DateTime(2025, 11, 4);

  Future<(_Fixture, Profile)> storedDifferential() async {
    final fixture = await _Fixture.create();
    final profile = await fixture.repository.createProfile(displayName: 'Alex');
    for (final biomarker in [
      _marker('leuko', 'Leukozyten', unit: '10^9/L', category: 'Blutbild'),
      _marker('neut-share', 'Neutrophile %', unit: '%'),
    ]) {
      await fixture.repository.saveBiomarker(biomarker);
    }
    for (final measurement in [
      _result('total', profile.id, 'leuko', 6.5, '/nl', reportDay),
      _result('share', profile.id, 'neut-share', 58.2, '%', reportDay),
    ]) {
      await fixture.repository.saveMeasurement(measurement);
    }
    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    return (fixture, profile);
  }

  List<Measurement> calculated(AppController controller) => [
    for (final measurement in controller.measurements)
      if (measurement.isCalculated) measurement,
  ];

  test(
    'a stored differential gains its absolute counts on the next load, once',
    () async {
      final (fixture, _) = await storedDifferential();
      addTearDown(fixture.dispose);

      await fixture.controller.refreshActiveData();
      await fixture.controller.refreshActiveData();

      final series = fixture.controller.biomarkers.where(
        (item) => item.id == 'neut',
      );
      expect(series, hasLength(1));
      expect(series.single.displayName, 'Neutrophile (absolut)');
      expect(series.single.category, 'Blutbild');
      final derived = calculated(fixture.controller);
      expect(derived, hasLength(1));
      expect(derived.single.biomarkerId, 'neut');
      expect(derived.single.value, 3.78);
      expect(derived.single.takenAt, reportDay);

      final total = fixture.controller.measurements.singleWhere(
        (item) => item.id == 'total',
      );
      await fixture.controller.deleteMeasurement(total);

      expect(calculated(fixture.controller), isEmpty);
    },
  );

  test('an absolute series the owner deleted is not brought back', () async {
    final (fixture, _) = await storedDifferential();
    addTearDown(fixture.dispose);
    await fixture.controller.refreshActiveData();
    await fixture.repository.softDelete('biomarkers', 'neut');

    await fixture.controller.refreshActiveData();

    expect(
      fixture.controller.biomarkers.map((item) => item.id),
      isNot(contains('neut')),
    );
    expect(calculated(fixture.controller), isEmpty);
  });
}

Biomarker _marker(
  String id,
  String displayName, {
  required String unit,
  String category = '',
}) => Biomarker(
  id: id,
  canonicalName: id,
  displayName: displayName,
  defaultUnit: unit,
  category: category,
  createdAt: DateTime(2025),
  updatedAt: DateTime(2025),
);

Measurement _result(
  String id,
  String profileId,
  String biomarkerId,
  double value,
  String unit,
  DateTime takenAt,
) => Measurement(
  id: id,
  profileId: profileId,
  biomarkerId: biomarkerId,
  documentId: null,
  takenAt: takenAt,
  value: value,
  unit: unit,
  createdAt: takenAt,
  updatedAt: takenAt,
);

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
