import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/analysis/lab_catalog_pricing.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/biomarker_merge_flow.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late HealthRepository repository;
  late Profile profile;
  final now = DateTime.utc(2026, 7, 18, 10);

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
    profile = await repository.createProfile(displayName: 'Alex');
  });

  tearDown(() => database.close());

  Biomarker biomarker(
    String id,
    String name, {
    String unit = '%',
    List<String> synonyms = const [],
    bool temporary = false,
  }) => Biomarker(
    id: id,
    canonicalName: HealthRepository.normalizeName(name),
    displayName: name,
    defaultUnit: unit,
    category: 'iron',
    synonyms: synonyms,
    isTemporary: temporary,
    createdAt: now,
    updatedAt: now,
  );

  Measurement reading(
    String id,
    String biomarkerId, {
    double value = 28,
    String unit = '%',
    String? documentId,
    int? page,
    String? rowText,
    List<String> flags = const [],
  }) => Measurement(
    id: id,
    profileId: profile.id,
    biomarkerId: biomarkerId,
    documentId: documentId,
    takenAt: now,
    value: value,
    unit: unit,
    page: page,
    rowText: rowText,
    flags: flags,
    createdAt: now,
    updatedAt: now,
  );

  Future<(Biomarker, Biomarker)> seedPair({
    String sourceUnit = '%',
    String targetUnit = '%',
  }) async {
    final source = biomarker(
      'source',
      'Transferrin-Sättigung',
      unit: sourceUnit,
      synonyms: const ['TSAT'],
    );
    final target = biomarker(
      'target',
      'Transferrinsättigung',
      unit: targetUnit,
      synonyms: const ['Transferrin saturation'],
    );
    await repository.saveBiomarker(source);
    await repository.saveBiomarker(target);
    return (source, target);
  }

  Future<Map<String, Object?>> row(String table, String id) async =>
      (await (await database.database).query(
        table,
        where: 'id = ?',
        whereArgs: [id],
      )).single;

  test(
    'merging two permanent tests keeps every result tied to its report, page and source row',
    () async {
      final (source, target) = await seedPair();
      await repository.saveDocument(
        HealthDocument(
          id: 'report',
          profileId: profile.id,
          fileName: 'labor.pdf',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveMeasurement(
        reading(
          'from-report',
          source.id,
          value: 31,
          documentId: 'report',
          page: 2,
          rowText: 'Transferrin-Sättigung 31 %',
          flags: const [Measurement.selfPaidFlag],
        ),
      );
      await repository.saveMeasurement(reading('already-there', target.id));

      final preview = await repository.previewBiomarkerMerge(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );
      expect(preview.measurements, 1);
      expect(preview.documents, 1);
      expect(preview.unconvertedMeasurements, 0);

      final result = await repository.mergeBiomarker(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );

      expect(result.movedMeasurements, 1);
      final measurements = await repository.measurements(profile.id);
      expect(measurements.map((item) => item.biomarkerId).toSet(), {target.id});
      final moved = measurements.singleWhere(
        (item) => item.id == 'from-report',
      );
      expect(moved.documentId, 'report');
      expect(moved.page, 2);
      expect(moved.rowText, 'Transferrin-Sättigung 31 %');
      expect(moved.value, 31);
      expect(moved.isSelfPaid, isTrue);

      final catalog = await repository.biomarkers();
      expect(catalog.map((item) => item.id), isNot(contains(source.id)));
      expect(
        catalog.singleWhere((item) => item.id == target.id).synonyms,
        containsAll([
          'Transferrin saturation',
          'Transferrin-Sättigung',
          'transferrin_sättigung',
          'TSAT',
        ]),
      );
      expect(await row('biomarkers', source.id), containsPair('deleted', 1));
    },
  );

  test(
    'a merged result is compared in the unit of the test that stayed',
    () async {
      // Left in the source's unit, the result's canonical unit would differ from
      // its new neighbours' and it would silently drop out of the trend.
      final (source, target) = await seedPair(
        sourceUnit: 'g/L',
        targetUnit: 'mg/dL',
      );
      await repository.saveMeasurement(
        reading('convertible', source.id, value: 1.2, unit: 'g/L'),
      );
      await repository.saveMeasurement(
        reading('incompatible', source.id, value: 40, unit: 'U/L'),
      );

      final preview = await repository.previewBiomarkerMerge(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );
      expect(preview.unconvertedMeasurements, 1);
      expect(preview.targetUnit, 'mg/dL');

      final result = await repository.mergeBiomarker(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );

      expect(result.unconvertedMeasurements, 1);
      final measurements = {
        for (final item in await repository.measurements(profile.id))
          item.id: item,
      };
      expect(measurements['convertible']!.value, 1.2);
      expect(measurements['convertible']!.unit, 'g/L');
      expect(measurements['convertible']!.canonicalUnit, 'mg/dL');
      expect(measurements['convertible']!.canonicalValue, closeTo(120, 1e-9));
      expect(measurements['incompatible']!.value, 40);
      expect(measurements['incompatible']!.canonicalValue, isNull);
      expect(measurements['incompatible']!.conversionStatus, 'unsupported');
    },
  );

  test(
    'a merge moves the current offer per lab and never overrules the target price',
    () async {
      final (source, target) = await seedPair();
      final db = await database.database;
      LabPrice price(
        String id,
        String biomarkerId,
        String lab,
        double eur,
        DateTime updatedAt, {
        bool deleted = false,
      }) => LabPrice(
        id: id,
        biomarkerId: biomarkerId,
        labName: lab,
        priceEur: eur,
        createdAt: updatedAt,
        updatedAt: updatedAt,
        deleted: deleted,
      );
      for (final item in [
        price('target-a', target.id, 'Labor A', 10, now),
        // Newer than the target's own price at the same lab: moved as it
        // stands, it would win and replace the price the target already had.
        price(
          'source-a',
          source.id,
          'labor a',
          20,
          now.add(const Duration(days: 1)),
        ),
        price('source-b-old', source.id, 'Labor B', 12, now),
        price(
          'source-b-new',
          source.id,
          'Labor B',
          15,
          now.add(const Duration(days: 2)),
        ),
        price('source-c-gone', source.id, 'Labor C', 9, now),
        price(
          'source-c-tombstone',
          source.id,
          'Labor C',
          9,
          now.add(const Duration(days: 1)),
          deleted: true,
        ),
      ]) {
        await db.insert('lab_prices', item.toMap());
      }

      await repository.mergeBiomarker(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );

      final pricing = LabCatalogPricing(prices: await repository.labPrices());
      expect(pricing.priceFor(target.id, lab: 'Labor A')?.priceEur, 10);
      expect(pricing.priceFor(target.id, lab: 'Labor B')?.priceEur, 15);
      expect(pricing.priceFor(target.id, lab: 'Labor C'), isNull);
      expect(
        (await row('lab_prices', 'source-b-old'))['biomarker_id'],
        source.id,
      );
    },
  );

  test(
    'a plan that listed both names keeps one item, in the earlier tier and ticked if either was',
    () async {
      final (source, target) = await seedPair();
      LabPlanItem item(
        String id,
        Biomarker biomarker,
        LabTier tier, {
        bool checked = false,
      }) => LabPlanItem(
        id: id,
        planId: 'plan',
        biomarkerId: biomarker.id,
        biomarkerName: biomarker.displayName,
        tier: tier,
        priority: 1,
        rationale: 'iron status',
        evidenceClass: EvidenceClass.guideline,
        checked: checked,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveLabPlan(
        LabPlan(
          id: 'plan',
          profileId: profile.id,
          title: 'Plan',
          contextHash: 'hash',
          createdAt: now,
          updatedAt: now,
          items: [
            item('source-item', source, LabTier.core),
            item('target-item', target, LabTier.advanced, checked: true),
          ],
          coverage: [
            PlanCoverage(
              id: 'cond:iron',
              kind: 'condition',
              label: 'Iron deficiency',
              verdict: PlanCoverageVerdict.addressed,
              biomarkerIds: [source.id, target.id],
              why: 'Both saturation entries',
            ),
          ],
        ),
      );

      await repository.mergeBiomarker(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );

      final plan = (await repository.labPlans(profile.id)).single;
      final kept = plan.items.single;
      expect(kept.id, 'source-item');
      expect(kept.biomarkerId, target.id);
      expect(kept.biomarkerName, target.displayName);
      expect(kept.tier, LabTier.core);
      expect(kept.checked, isTrue);
      expect(
        await row('lab_plan_items', 'target-item'),
        containsPair('deleted', 1),
      );
      expect(plan.coverage!.single.biomarkerIds, [target.id]);
      expect(plan.coverage!.single.why, 'Both saturation entries');
    },
  );

  test(
    'package memberships and dose underlays follow the merge without doubling',
    () async {
      final (source, target) = await seedPair();
      await repository.saveBiomarkerPackage(
        BiomarkerPackage(
          id: 'both',
          name: 'Eisenstatus',
          createdAt: now,
          updatedAt: now,
        ),
        {source.id, target.id},
      );
      await repository.saveBiomarkerPackage(
        BiomarkerPackage(
          id: 'source-only',
          name: 'Eisen klein',
          createdAt: now,
          updatedAt: now,
        ),
        {source.id},
      );
      await repository.saveTrendDoseLink(
        TrendDoseLink(
          id: 'underlay',
          profileId: profile.id,
          biomarkerId: source.id,
          ingredientName: 'Iron',
          ingredientUnit: 'mg',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await repository.mergeBiomarker(
        sourceBiomarkerId: source.id,
        targetBiomarkerId: target.id,
      );

      final members = await repository.biomarkerPackageMembers();
      expect(members['both'], {target.id});
      expect(members['source-only'], {target.id});
      expect(
        (await repository.trendDoseLinks(profile.id)).single.biomarkerId,
        target.id,
      );
    },
  );

  test(
    'a calculated or temporary entry is never the test that stays',
    () async {
      final (source, _) = await seedPair();
      final temporary = biomarker(
        'temporary',
        'Imported TSAT',
        temporary: true,
      );
      await repository.saveBiomarker(temporary);

      await expectLater(
        repository.mergeBiomarker(
          sourceBiomarkerId: source.id,
          targetBiomarkerId: temporary.id,
        ),
        throwsStateError,
      );
      await expectLater(
        repository.mergeBiomarker(
          sourceBiomarkerId: source.id,
          targetBiomarkerId: source.id,
        ),
        throwsArgumentError,
      );
      final homa = (await repository.biomarkers()).firstWhere(
        (item) => item.isCalculated,
      );
      await expectLater(
        repository.mergeBiomarker(
          sourceBiomarkerId: homa.id,
          targetBiomarkerId: source.id,
        ),
        throwsStateError,
      );
      expect(
        (await repository.biomarkers()).map((item) => item.id),
        containsAll([source.id, temporary.id, homa.id]),
      );
    },
  );

  test(
    'the merge picker lists entries spelled like the source first and offers only valid targets',
    () {
      final source = biomarker('source', 'Transferrin-Sättigung');
      final catalog = [
        biomarker('ferritin', 'Ferritin'),
        biomarker('imported', 'Transferrin Sättigung', temporary: true),
        source,
        biomarker('target', 'Transferrinsättigung'),
        Biomarker.fromMap({
          ...biomarker('calculated', 'HOMA1-IR').toMap(),
          'is_calculated': 1,
        }),
      ];

      expect(mergeTargetCandidates(source, catalog).map((item) => item.id), [
        'target',
        'ferritin',
      ]);
    },
  );
}
