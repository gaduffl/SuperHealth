import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
  });

  tearDown(() => database.close());

  test(
    'health context isolates clinical evidence while retaining household stock',
    () async {
      final active = await repository.createProfile(displayName: 'Active');
      final spouse = await repository.createProfile(displayName: 'Spouse');
      final now = DateTime.utc(2026, 7, 18, 10);
      final supplement = Supplement(
        id: 'supplement-magnesium',
        name: 'Household magnesium',
        stockUnit: 'capsules',
        lowStockThresholdUnits: 2.25,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveSupplement(supplement);
      await repository.saveInventoryMovement(
        InventoryMovement(
          id: 'stock-purchase',
          supplementId: supplement.id,
          quantityUnits: 2.5,
          occurredAt: now,
          reason: 'purchase',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveIntake(
        SupplementIntake(
          id: 'active-intake',
          profileId: active.id,
          supplementId: supplement.id,
          takenAt: now,
          dose: 1,
          unit: 'capsule',
          createdAt: now,
          updatedAt: now,
        ),
        inventoryUnits: 0.125,
      );
      await repository.saveIntake(
        SupplementIntake(
          id: 'spouse-intake',
          profileId: spouse.id,
          supplementId: supplement.id,
          takenAt: now,
          dose: 1,
          unit: 'capsule',
          createdAt: now,
          updatedAt: now,
        ),
        inventoryUnits: 0.25,
      );
      await repository.saveNamedRecord(
        NamedHealthRecord(
          id: 'spouse-condition',
          profileId: spouse.id,
          name: 'Private spouse condition',
          kind: 'condition',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveEvent(
        HealthEvent(
          id: 'spouse-event',
          profileId: spouse.id,
          kind: EventKind.symptom,
          name: 'Private spouse symptom',
          observedAt: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final biomarker = Biomarker(
        id: 'biomarker-apo-b',
        canonicalName: 'apo_b',
        displayName: 'ApoB',
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveBiomarker(biomarker);
      final activePlan = LabPlan(
        id: 'active-plan',
        profileId: active.id,
        title: 'Active plan',
        createdAt: now,
        updatedAt: now,
        items: [
          LabPlanItem(
            id: 'active-plan-item',
            planId: 'active-plan',
            biomarkerId: biomarker.id,
            biomarkerName: biomarker.displayName,
            tier: LabTier.core,
            priority: 1,
            rationale: 'Active',
            evidenceClass: EvidenceClass.longevity,
            createdAt: now,
            updatedAt: now,
          ),
          LabPlanItem(
            id: 'deleted-active-plan-item',
            planId: 'active-plan',
            biomarkerId: biomarker.id,
            biomarkerName: biomarker.displayName,
            tier: LabTier.core,
            priority: 2,
            rationale: 'Deleted',
            evidenceClass: EvidenceClass.longevity,
            createdAt: now,
            updatedAt: now,
            deleted: true,
          ),
        ],
      );
      await repository.saveLabPlan(activePlan);
      final deletedPlan = LabPlan(
        id: 'deleted-plan',
        profileId: active.id,
        title: 'Deleted plan',
        createdAt: now,
        updatedAt: now,
        items: [
          LabPlanItem(
            id: 'deleted-plan-item',
            planId: 'deleted-plan',
            biomarkerId: biomarker.id,
            biomarkerName: biomarker.displayName,
            tier: LabTier.core,
            priority: 1,
            rationale: 'Deleted plan item',
            evidenceClass: EvidenceClass.longevity,
            createdAt: now,
            updatedAt: now,
          ),
        ],
      );
      await repository.saveLabPlan(deletedPlan);
      final db = await database.database;
      await db.update(
        'lab_plan_items',
        {'deleted': 1},
        where: 'id = ?',
        whereArgs: ['deleted-active-plan-item'],
      );
      await db.update(
        'lab_plans',
        {'deleted': 1},
        where: 'id = ?',
        whereArgs: ['deleted-plan'],
      );

      final source = await repository.completeProfileSnapshot(active.id);
      final data = source['data']! as Map<String, Object?>;
      final rawMovements = data['inventory_movements']! as List<dynamic>;
      final stock =
          (data['household_stock_levels']! as List<dynamic>).single
              as Map<String, Object?>;

      // The raw movement ledger is stock provenance, not clinical evidence,
      // and was one of the largest tables in the context. It is no longer
      // shipped at all — including the spouse's rows, which were never
      // evidence about this profile.
      expect(rawMovements, isEmpty);
      // The derived total survives, because "am I out of this" is worth
      // answering and costs one row per catalog item.
      expect(stock['current_units'], 2.125);
      expect(
        (data['supplement_intakes']! as List<dynamic>).map((row) => row['id']),
        ['active-intake'],
      );
      expect(
        HealthRepository.stableJson(data),
        isNot(contains('Private spouse condition')),
      );
      expect(
        HealthRepository.stableJson(data),
        isNot(contains('Private spouse symptom')),
      );
      expect((data['lab_plans']! as List<dynamic>).map((row) => row['id']), [
        'active-plan',
      ]);
      expect(
        (data['lab_plan_items']! as List<dynamic>).map((row) => row['id']),
        ['active-plan-item'],
      );
      expect(
        (source['manifest']! as Map<String, Object?>)['counts']!
            as Map<String, int>,
        containsPair('household_stock_levels', 1),
      );

      final builder = HealthContextBuilder(repository);
      final first = await builder.build(active.id);
      final second = await builder.build(active.id);
      expect(second.sha256, first.sha256);
      final package = jsonDecode(first.json) as Map<String, dynamic>;
      final attention = package['attention_index'] as Map<String, dynamic>;
      final indexStock =
          (attention['household_stock'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(indexStock['current_units'], 2.125);
      expect(indexStock['is_low_stock'], isTrue);
      // The index counts what the context carries, and the context no longer
      // carries the movement ledger. The stock total above is what remains,
      // and it is derived from the full ledger in the database.
      expect(indexStock['inventory_movement_record_count'], 0);
    },
  );
}
