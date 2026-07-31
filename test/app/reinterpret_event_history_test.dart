import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
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

  test('reinterpretEventHistory converts scored and old-unit entries to the '
      'new canonical unit, skips already-converted and deleted entries, and '
      'leaves other definitions untouched', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 7, 24);
    final profile = await fixture.repository.createProfile(
      displayName: 'Caffeine',
    );
    final caffeine = HealthEventDefinition(
      id: 'caffeine',
      profileId: profile.id,
      kind: EventKind.tag,
      name: 'Caffeine',
      valueMode: TagValueMode.amount,
      defaultUnit: 'g',
      createdAt: now,
      updatedAt: now,
    );
    final other = HealthEventDefinition(
      id: 'other',
      profileId: profile.id,
      kind: EventKind.tag,
      name: 'Other',
      valueMode: TagValueMode.intensity,
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveEventDefinition(caffeine);
    await fixture.repository.saveEventDefinition(other);

    Future<void> save(HealthEvent event) => fixture.repository.saveEvent(event);
    await save(_event('scored-2', profile.id, caffeine.id, now, score: 2));
    await save(_event('scored-4', profile.id, caffeine.id, now, score: 4));
    await save(
      _event(
        'already-g',
        profile.id,
        caffeine.id,
        now,
        numericValue: 18,
        unit: 'g',
      ),
    );
    await save(
      _event(
        'old-unit-cups',
        profile.id,
        caffeine.id,
        now,
        numericValue: 3,
        unit: 'cups',
      ),
    );
    await save(
      _event(
        'deleted-scored',
        profile.id,
        caffeine.id,
        now,
        score: 5,
        deleted: true,
      ),
    );
    await save(_event('other-definition', profile.id, other.id, now, score: 7));

    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await fixture.controller.refreshActiveData();

    await fixture.controller.reinterpretEventHistory(
      definition: caffeine,
      factor: 6,
      newUnit: 'g',
    );

    final db = await fixture.database.database;
    final byId = {
      for (final row in await db.query('health_events'))
        row['id'] as String: row,
    };

    expect(byId['scored-2']!['numeric_value'], 12);
    expect(byId['scored-2']!['unit'], 'g');
    expect(byId['scored-2']!['score'], isNull);

    expect(byId['scored-4']!['numeric_value'], 24);
    expect(byId['scored-4']!['unit'], 'g');
    expect(byId['scored-4']!['score'], isNull);

    // Already in the canonical unit: left exactly as-is.
    expect(byId['already-g']!['numeric_value'], 18);
    expect(byId['already-g']!['unit'], 'g');

    // A stale amount in an old unit is rewritten under the same factor.
    expect(byId['old-unit-cups']!['numeric_value'], 18);
    expect(byId['old-unit-cups']!['unit'], 'g');

    // Deleted entries and other definitions are never touched.
    expect(byId['deleted-scored']!['score'], 5);
    expect(byId['deleted-scored']!['unit'], isNull);
    expect(byId['other-definition']!['score'], 7);
    expect(byId['other-definition']!['unit'], isNull);
  });
}

HealthEvent _event(
  String id,
  String profileId,
  String definitionId,
  DateTime now, {
  int? score,
  double? numericValue,
  String? unit,
  bool deleted = false,
}) => HealthEvent(
  id: id,
  profileId: profileId,
  definitionId: definitionId,
  kind: EventKind.tag,
  name: 'Caffeine',
  observedAt: now,
  score: score,
  numericValue: numericValue,
  unit: unit,
  createdAt: now,
  updatedAt: now,
  deleted: deleted,
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
