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
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/ui/dose_underlay.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a suggested ingredient is offered but never drawn until confirmed, and '
      'choosing it replaces any earlier choice', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 6, 1);
    final profile = await fixture.repository.createProfile(
      displayName: 'Underlay',
    );
    final biomarker = Biomarker(
      id: 'vitamin-d',
      canonicalName: 'vitamin d',
      displayName: 'Vitamin D (25-OH)',
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveBiomarker(biomarker);
    final supplement = Supplement(
      id: 'supplement',
      name: 'D3 drops',
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveSupplement(supplement);
    for (var day = 0; day < 20; day++) {
      await fixture.repository.saveIntake(
        SupplementIntake(
          id: 'intake-$day',
          profileId: profile.id,
          supplementId: supplement.id,
          takenAt: DateTime(2026, 5, 1 + day),
          dose: 1,
          unit: 'drop',
          ingredientSnapshot: const [
            {'name': 'Vitamin D3', 'unit': 'IU', 'amount': 1000},
            {'name': 'Vitamin K2', 'unit': 'µg', 'amount': 50},
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await fixture.controller.refreshActiveData();

    TrendDoseUnderlay underlay() => resolveTrendDoseUnderlay(
      controller: fixture.controller,
      biomarkerId: biomarker.id,
      trendNames: [biomarker.displayName, biomarker.canonicalName],
      from: DateTime(2026, 5, 1),
      through: DateTime(2026, 5, 20),
    );

    // Nothing confirmed yet: the guess is offered, not drawn.
    final offered = underlay();
    expect(
      offered.suggestion,
      const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
    );
    expect(offered.selected, isNull);
    expect(offered.series, isNull);
    // Two ingredients plus the product they came in: a supplement whose
    // ingredients are not broken down must still be selectable.
    expect(offered.available, hasLength(3));
    expect(
      offered.available.where((target) => target.isSupplement).single.name,
      'D3 drops',
    );

    await fixture.controller.setTrendDoseLink(
      biomarkerId: biomarker.id,
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
    );

    final confirmed = underlay();
    expect(
      confirmed.selected,
      const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
    );
    expect(confirmed.series?.ingredientName, 'Vitamin D3');
    expect(confirmed.series?.unit, 'IU');
    expect(confirmed.series?.hasDose, isTrue);

    // Switching keeps exactly one link rather than accumulating rows.
    await fixture.controller.setTrendDoseLink(
      biomarkerId: biomarker.id,
      target: const DoseTarget.ingredient(name: 'Vitamin K2', unit: 'µg'),
    );
    expect(fixture.controller.trendDoseLinks, hasLength(1));
    expect(
      underlay().selected,
      const DoseTarget.ingredient(name: 'Vitamin K2', unit: 'µg'),
    );

    // Clearing removes the underlay entirely.
    await fixture.controller.setTrendDoseLink(biomarkerId: biomarker.id);
    expect(fixture.controller.trendDoseLinks, isEmpty);
    expect(underlay().series, isNull);

    await fixture.dispose();
  });

  test('a link to an ingredient no longer taken draws nothing', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 6, 1);
    final profile = await fixture.repository.createProfile(
      displayName: 'Stale',
    );
    final biomarker = Biomarker(
      id: 'ferritin',
      canonicalName: 'ferritin',
      displayName: 'Ferritin',
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveBiomarker(biomarker);
    final supplement = Supplement(
      id: 'supplement',
      name: 'Magnesium',
      createdAt: now,
      updatedAt: now,
    );
    await fixture.repository.saveSupplement(supplement);
    await fixture.repository.saveIntake(
      SupplementIntake(
        id: 'intake',
        profileId: profile.id,
        supplementId: supplement.id,
        takenAt: DateTime(2026, 5, 2),
        dose: 1,
        unit: 'capsule',
        ingredientSnapshot: const [
          {'name': 'Magnesium', 'unit': 'mg', 'amount': 400},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await fixture.repository.saveTrendDoseLink(
      TrendDoseLink(
        id: 'stale-link',
        profileId: profile.id,
        biomarkerId: biomarker.id,
        ingredientName: 'Iron bisglycinate',
        ingredientUnit: 'mg',
        createdAt: now,
        updatedAt: now,
      ),
    );
    fixture.controller
      ..profiles = [profile]
      ..activeProfile = profile;
    await fixture.controller.refreshActiveData();

    final underlay = resolveTrendDoseUnderlay(
      controller: fixture.controller,
      biomarkerId: biomarker.id,
      trendNames: [biomarker.displayName],
      from: DateTime(2026, 5, 1),
      through: DateTime(2026, 5, 20),
    );

    // The choice is remembered and shown, but nothing was ever taken of it,
    // so the chart must stay empty rather than fall back to another
    // ingredient's dose — and must say so rather than looking broken.
    expect(underlay.selected?.name, 'Iron bisglycinate');
    expect(underlay.series?.hasDose, isFalse);
    expect(underlay.selectedButEmpty, isTrue);

    await fixture.dispose();
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
  var _disposed = false;

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
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    await database.close();
  }
}
