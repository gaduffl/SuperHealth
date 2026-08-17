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

  test('a package ticks every test it covers as one edit', () async {
    // A package covers several planned tests at once. Saving the plan per test
    // would rewrite it N times and reload between each, so the whole selection
    // has to land in a single edit.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final plan = await fixture.seedPlan();

    await fixture.controller.setLabPlanItemsChecked(plan, {
      'ferritin',
      'transferrin',
    }, true);

    final saved = fixture.controller.labPlans.single;
    expect(fixture.checkedIds(saved), {'ferritin', 'transferrin'});
  });

  test('unticking a package clears exactly its own tests', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final plan = await fixture.seedPlan();
    await fixture.controller.setLabPlanItemsChecked(plan, {
      'ferritin',
      'transferrin',
      'tsh',
    }, true);

    await fixture.controller.setLabPlanItemsChecked(
      fixture.controller.labPlans.single,
      {'ferritin', 'transferrin'},
      false,
    );

    expect(fixture.checkedIds(fixture.controller.labPlans.single), {'tsh'});
  });

  test('a single test still toggles on its own', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final plan = await fixture.seedPlan();

    await fixture.controller.setLabPlanItemChecked(
      plan,
      plan.items.firstWhere((item) => item.id == 'tsh'),
      true,
    );

    expect(fixture.checkedIds(fixture.controller.labPlans.single), {'tsh'});
  });

  test('a row already in the wanted state is not rewritten', () async {
    // Every synchronized row is compared by updated_at, so touching rows that
    // did not actually change would manufacture sync work and, on a second
    // device, conflicts over edits nobody made.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final plan = await fixture.seedPlan();
    await fixture.controller.setLabPlanItemsChecked(plan, {'ferritin'}, true);
    final before = {
      for (final item in fixture.controller.labPlans.single.items)
        item.id: item.updatedAt,
    };

    await fixture.controller.setLabPlanItemsChecked(
      fixture.controller.labPlans.single,
      {'ferritin', 'transferrin'},
      true,
    );

    final after = {
      for (final item in fixture.controller.labPlans.single.items)
        item.id: item.updatedAt,
    };
    expect(after['ferritin'], before['ferritin']);
    expect(after['tsh'], before['tsh']);
    expect(after['transferrin'], isNot(before['transferrin']));
  });

  test('an empty selection is a no-op', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final plan = await fixture.seedPlan();
    final before = fixture.controller.labPlans.single.updatedAt;

    await fixture.controller.setLabPlanItemsChecked(plan, const {}, true);

    expect(fixture.controller.labPlans.single.updatedAt, before);
    expect(fixture.checkedIds(fixture.controller.labPlans.single), isEmpty);
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

  Set<String> checkedIds(LabPlan plan) => {
    for (final item in plan.items)
      if (item.checked) item.id,
  };

  /// A three-test plan where a package would cover the first two.
  Future<LabPlan> seedPlan() async {
    final now = DateTime(2026, 8, 8);
    final profile = await repository.createProfile(displayName: 'A');
    for (final id in ['ferritin', 'transferrin', 'tsh']) {
      await repository.saveBiomarker(
        Biomarker(
          id: 'bio-$id',
          canonicalName: id,
          displayName: id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    LabPlanItem item(String id) => LabPlanItem(
      id: id,
      planId: 'plan',
      biomarkerId: 'bio-$id',
      biomarkerName: id,
      tier: LabTier.core,
      priority: 1,
      rationale: 'Because',
      evidenceClass: EvidenceClass.guideline,
      priceEur: 20,
      createdAt: now,
      updatedAt: now,
    );
    final plan = LabPlan(
      id: 'plan',
      profileId: profile.id,
      title: 'Iron and thyroid',
      createdAt: now,
      updatedAt: now,
      items: [item('ferritin'), item('transferrin'), item('tsh')],
    );
    await repository.saveLabPlan(plan);
    controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await controller.refreshActiveData();
    return controller.labPlans.single;
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
