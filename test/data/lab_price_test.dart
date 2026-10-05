import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/analysis/lab_catalog_pricing.dart';
import 'package:super_health/analysis/lab_plan_pricing.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/sync/snapshot_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  final stamp = DateTime.utc(2026, 1, 1);
  late AppDatabase database;
  late HealthRepository repository;

  Biomarker marker(String id, {String? lab = 'Lab A', double? price = 20}) =>
      Biomarker(
        id: id,
        canonicalName: id,
        displayName: id,
        labName: lab,
        priceEur: price,
        createdAt: stamp,
        updatedAt: stamp,
      );
  LabPrice offer(String id, String lab, double price, {bool package = false}) =>
      LabPrice(
        id: repository.newId(),
        labName: lab,
        priceEur: price,
        biomarkerId: package ? null : id,
        packageId: package ? id : null,
        createdAt: stamp,
        updatedAt: stamp,
        sourceUrl: 'https://example.com/prices',
        quote: '$id $price EUR',
        checkedAt: stamp,
      );

  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
    await repository.saveProfile(
      Profile(
        id: 'profile',
        displayName: 'Fixture',
        createdAt: stamp,
        updatedAt: stamp,
      ),
    );
    await repository.saveBiomarker(marker('a'));
    await repository.saveBiomarker(marker('b'));
    await repository.saveBiomarkerPackage(
      BiomarkerPackage(
        id: 'bundle',
        name: 'Bundle',
        labName: 'Lab A',
        priceEur: 30,
        createdAt: stamp,
        updatedAt: stamp,
      ),
      {'a', 'b'},
    );
  });
  tearDown(() => database.close());

  test(
    'another lab adds offers without replacing the existing test or bundle price',
    () async {
      await repository.saveLabPrices([
        offer('a', 'Lab B', 12),
        offer('bundle', 'Lab B', 18, package: true),
      ]);
      final prices = await repository.labPrices();
      final a = LabCatalogPricing(prices: prices, labName: 'Lab A');
      final b = LabCatalogPricing(prices: prices, labName: 'lab b');
      expect(
        a
            .catalog(await repository.biomarkers())
            .firstWhere((item) => item.id == 'a')
            .priceEur,
        20,
      );
      expect(
        b
            .catalog(await repository.biomarkers())
            .firstWhere((item) => item.id == 'a')
            .priceEur,
        12,
      );
      expect(
        b
            .catalog(await repository.biomarkers())
            .firstWhere((item) => item.id == 'b')
            .priceEur,
        isNull,
      );
      expect(
        a.packages(await repository.biomarkerPackages()).single.priceEur,
        30,
      );
      expect(
        b.packages(await repository.biomarkerPackages()).single.priceEur,
        18,
      );
      expect(
        (await repository.biomarkers())
            .firstWhere((item) => item.id == 'a')
            .priceEur,
        20,
      );
      expect(LabCatalogPricing.labNames(prices), ['Lab A', 'Lab B']);
    },
  );

  test(
    'case and whitespace variants update the same lab offer and preserve its source',
    () async {
      await repository.saveLabPrices([offer('a', '  LAB   A  ', 22)]);
      final prices = (await repository.labPrices())
          .where((item) => item.biomarkerId == 'a')
          .toList();
      expect(prices, hasLength(1));
      expect(prices.single.priceEur, 22);
      expect(prices.single.sourceUrl, 'https://example.com/prices');
      final original = marker('a');
      // Editing catalog metadata must not restore a stale legacy price over the lab offer.
      await repository.saveBiomarker(
        Biomarker.fromMap({...original.toMap(), 'description': 'Edited'}),
      );
      expect(
        (await repository.labPrices())
            .firstWhere((item) => item.biomarkerId == 'a')
            .priceEur,
        22,
      );
    },
  );

  test(
    'clearing a named catalog price tombstones its offer without borrowing another lab price',
    () async {
      await repository.saveLabPrices([offer('a', 'Lab B', 12)]);
      await repository.saveBiomarker(marker('a', price: null));
      final pricing = LabCatalogPricing(
        prices: await repository.labPrices(),
        labName: 'Lab A',
      );
      expect(
        pricing
            .catalog(await repository.biomarkers())
            .singleWhere((row) => row.id == 'a')
            .priceEur,
        isNull,
      );
      expect(
        LabCatalogPricing(
              prices: await repository.labPrices(),
              labName: 'Lab B',
            )
            .catalog(await repository.biomarkers())
            .singleWhere((row) => row.id == 'a')
            .priceEur,
        12,
      );
    },
  );

  test('invalid prices roll the entire batch back', () async {
    final before = await repository.labPrices();
    await expectLater(
      repository.saveLabPrices([
        offer('a', 'Lab B', 10),
        offer('missing', 'Lab B', 10),
      ]),
      throwsArgumentError,
    );
    expect((await repository.labPrices()).length, before.length);
    for (final price in [0.0, -1.0, double.infinity, double.nan]) {
      await expectLater(
        repository.saveLabPrices([offer('a', 'Lab B', price)]),
        throwsArgumentError,
      );
    }
  });

  test(
    'lab offers survive snapshot sync and invalid references or keys are rejected',
    () async {
      await repository.saveLabPrices([offer('a', 'Lab B', 12)]);
      final otherDatabase = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(otherDatabase.close);
      final otherRepository = HealthRepository(otherDatabase);
      final service = SnapshotService(otherDatabase, otherRepository);
      final snapshot = await repository.fullSyncSnapshot();
      await service.merge(snapshot);
      expect((await otherRepository.labPrices()).length, 4);
      final bad = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
      (bad['tables']['lab_prices'] as List).first['lab_key'] = 'wrong';
      await expectLater(
        service.merge(Map<String, Object?>.from(bad)),
        throwsFormatException,
      );
      (bad['tables']['lab_prices'] as List).first['lab_key'] = 'lab a';
      (bad['tables']['lab_prices'] as List).first['package_id'] = 'bundle';
      await expectLater(
        service.merge(Map<String, Object?>.from(bad)),
        throwsFormatException,
      );
    },
  );

  test(
    'lab selection changes the context receipt even with identical offers',
    () async {
      await repository.saveLabPrices([
        offer('a', 'Lab B', 20),
        offer('b', 'Lab B', 20),
      ]);
      final prices = await repository.labPrices();
      final builder = HealthContextBuilder(repository);
      final a = await builder.build(
        'profile',
        pricing: LabCatalogPricing(prices: prices, labName: 'Lab A'),
      );
      final b = await builder.build(
        'profile',
        pricing: LabCatalogPricing(prices: prices, labName: 'Lab B'),
      );
      expect(a.sha256, isNot(b.sha256));
      expect(b.json, contains('Lab B'));
    },
  );

  test(
    'saved lab plans and all exports retain their package offers after a price update',
    () async {
      await repository.saveLabPrices([
        offer('a', 'Lab B', 12),
        offer('b', 'Lab B', 15),
        offer('bundle', 'Lab B', 18, package: true),
      ]);
      final prices = LabCatalogPricing(
        prices: await repository.labPrices(),
        labName: 'Lab B',
      );
      final catalog = {
        for (final item in prices.catalog(await repository.biomarkers()))
          item.id: item,
      };
      final plan = LabPlan(
        id: 'plan',
        profileId: 'profile',
        title: 'Fixture',
        createdAt: stamp,
        updatedAt: stamp,
        pricingSnapshot: LabPricingSnapshot(
          labName: 'Lab B',
          packages: prices.packages(await repository.biomarkerPackages()),
          members: await repository.biomarkerPackageMembers(),
        ),
        items: [
          for (final id in ['a', 'b'])
            LabPlanItem(
              id: 'item-$id',
              planId: 'plan',
              biomarkerId: id,
              biomarkerName: id,
              tier: LabTier.core,
              priority: 1,
              rationale: 'Fixture',
              evidenceClass: EvidenceClass.guideline,
              priceEur: catalog[id]!.priceEur,
            ),
        ],
      );
      await repository.saveLabPlan(plan);
      await repository.saveLabPrices([
        offer('bundle', 'Lab B', 99, package: true),
      ]);
      final saved = (await repository.labPlans('profile')).single;
      expect(saved.labName, 'Lab B');
      expect(
        saved.copyWith(title: 'Renamed').pricingSnapshot,
        same(saved.pricingSnapshot),
      );
      final cost = const LabPlanPricing().cost(
        items: saved.itemsThrough(LabTier.core),
        packages: saved.pricingSnapshot!.packages,
        membersByPackageId: saved.pricingSnapshot!.members,
      );
      expect(cost.totalEur, 18);
      final exports = LabPlanExportService();
      final json =
          jsonDecode(
                utf8.decode(
                  (await exports.build(saved, LabPlanExportFormat.json)).bytes,
                ),
              )
              as Map;
      expect(json['tiers']['core']['known_total_eur'], 18);
      expect(json['tiers']['core']['packages'], hasLength(1));
      final csv = utf8.decode(
        (await exports.build(saved, LabPlanExportFormat.csv)).bytes,
      );
      expect(csv, contains('Lab B'));
      expect(csv, contains('Bundle'));
      expect(
        (await exports.build(saved, LabPlanExportFormat.pdf)).bytes.take(4),
        [37, 80, 68, 70],
      );
    },
  );

  test(
    'v16 migrates named legacy offers and leaves existing plans without a fabricated pricing snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lab-prices-v15-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/ledger.db';
      final old = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
      final oldRepository = HealthRepository(old);
      await oldRepository.saveBiomarker(marker('named'));
      await oldRepository.saveBiomarker(marker('unnamed', lab: null));
      await oldRepository.saveBiomarker(marker('unpriced', price: 0));
      await oldRepository.saveBiomarkerPackage(
        BiomarkerPackage(
          id: 'legacy-bundle',
          name: 'Legacy bundle',
          labName: 'Lab A',
          priceEur: 25,
          createdAt: stamp,
          updatedAt: stamp,
        ),
        {'named'},
      );
      final db = await old.database;
      await db.execute('DROP TABLE lab_prices');
      await db.execute(
        'ALTER TABLE lab_plans DROP COLUMN pricing_snapshot_json',
      );
      await db.execute('PRAGMA user_version = 15');
      await old.close();
      final upgraded = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(upgraded.close);
      final migrated = HealthRepository(upgraded);
      final offers = await migrated.labPrices();
      expect(offers, hasLength(2));
      expect(
        offers.singleWhere((row) => row.biomarkerId != null).biomarkerId,
        'named',
      );
      expect(offers.singleWhere((row) => row.packageId != null).priceEur, 25);
      expect(
        (await migrated.biomarkers())
            .where((row) => row.id == 'unnamed')
            .single
            .priceEur,
        20,
      );
      expect((await upgraded.database).getVersion(), completion(16));
    },
  );
}
