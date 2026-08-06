import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/unit_migration_planner.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late UnitMigrationPlanner planner;

  setUp(() {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    planner = UnitMigrationPlanner(database);
  });

  tearDown(() => database.close());

  /// Writes rows straight to SQLite, bypassing the repository, because the
  /// repository now normalises on write and the planner exists precisely for
  /// rows written before it did.
  Future<void> seedSupplement({
    required String id,
    required String name,
    required String stockUnit,
    String form = '',
    List<Map<String, Object?>> ingredients = const [],
  }) async {
    final db = await database.database;
    await db.insert('supplements', {
      'id': id,
      'name': name,
      'form': form,
      'stock_unit': stockUnit,
      'ingredients_json': jsonEncode(ingredients),
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'deleted': 0,
    });
  }

  test('a spelling difference is proposed as a safe correction', () async {
    await seedSupplement(
      id: 's',
      name: 'D3 drops',
      stockUnit: 'capsule',
      ingredients: const [
        {'name': 'Vitamin D3', 'unit': 'IE', 'amount': 1000},
        {'name': 'B12', 'unit': 'microgram', 'amount': 500},
      ],
    );

    final plan = await planner.plan();
    final units = plan.automatic
        .where((p) => p.reason == UnitMigrationReason.unitSpelling)
        .map((p) => '${p.before}->${p.after}')
        .toSet();
    expect(units, {'IE->IU', 'microgram->µg'});
    expect(plan.needsReview, isEmpty);
  });

  test('a substance spelling is proposed separately from its unit', () async {
    await seedSupplement(
      id: 's',
      name: 'C',
      stockUnit: 'capsule',
      ingredients: const [
        {'name': 'Vitamin c', 'unit': 'mg', 'amount': 500},
      ],
    );

    final plan = await planner.plan();
    final rename = plan.automatic.singleWhere(
      (p) => p.reason == UnitMigrationReason.substanceSpelling,
    );
    expect(rename.before, 'Vitamin c');
    expect(rename.after, 'Vitamin C');
  });

  test(
    'a countable form converts, an uncountable one needs a decision',
    () async {
      await seedSupplement(id: 'caps', name: 'Caps', stockUnit: 'Capsule');
      await seedSupplement(id: 'powder', name: 'Protein', stockUnit: 'Powder');

      final plan = await planner.plan();
      expect(
        plan.automatic
            .singleWhere(
              (p) => p.reason == UnitMigrationReason.formToCountableUnit,
            )
            .after,
        'capsule',
      );
      // Powder is bought by weight and taken by scoop; guessing either would be
      // inventing a number.
      expect(
        plan.needsReview.single.reason,
        UnitMigrationReason.formWithoutCountableUnit,
      );
    },
  );

  test('an unrecognised unit is surfaced but cannot be auto-changed', () async {
    await seedSupplement(
      id: 's',
      name: 'Odd',
      stockUnit: 'capsule',
      ingredients: const [
        {'name': 'Mystery', 'unit': 'bananas', 'amount': 1},
      ],
    );

    final plan = await planner.plan();
    final unknown = plan.needsReview.single;
    expect(unknown.reason, UnitMigrationReason.unknownUnit);
    // It proposes no change — it exists to tell the owner to go fix the entry.
    expect(unknown.before, unknown.after);
  });

  test('applying writes only the approved proposals', () async {
    await seedSupplement(
      id: 's',
      name: 'Mixed',
      stockUnit: 'Powder',
      ingredients: const [
        {'name': 'Vitamin D3', 'unit': 'IE', 'amount': 1000},
      ],
    );

    final plan = await planner.plan();
    // Approve the unit spelling, decline the powder decision.
    final approved = plan.automatic
        .where((p) => p.reason == UnitMigrationReason.unitSpelling)
        .toList();
    expect(await planner.apply(approved), 1);

    final db = await database.database;
    final row = (await db.query('supplements')).single;
    expect((jsonDecode(row['ingredients_json']! as String) as List).single, {
      'name': 'Vitamin D3',
      'unit': 'IU',
      'amount': 1000,
    });
    // Untouched, because it was not approved.
    expect(row['stock_unit'], 'Powder');
  });

  test('converting a form preserves it in the form column first', () async {
    await seedSupplement(id: 's', name: 'Caps', stockUnit: 'Capsule');

    final plan = await planner.plan();
    await planner.apply(plan.automatic);

    final db = await database.database;
    final row = (await db.query('supplements')).single;
    expect(row['stock_unit'], 'capsule');
    // The form was empty and is now populated, so nothing was lost by
    // repurposing the unit column.
    expect(row['form'], 'Capsule');
  });

  test('a clean library proposes nothing', () async {
    await seedSupplement(
      id: 's',
      name: 'Tidy',
      form: 'Capsule',
      stockUnit: 'capsule',
      ingredients: const [
        {'name': 'Magnesium', 'unit': 'mg', 'amount': 300},
      ],
    );

    expect((await planner.plan()).isEmpty, isTrue);
  });
}
