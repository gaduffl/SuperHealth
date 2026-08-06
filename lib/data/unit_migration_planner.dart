import 'dart:convert';

import '../domain/substance_catalog.dart';
import '../domain/units.dart';
import 'app_database.dart';

/// One change the migration would like to make to stored data.
class UnitMigrationProposal {
  const UnitMigrationProposal({
    required this.table,
    required this.rowId,
    required this.field,
    required this.before,
    required this.after,
    required this.reason,
  });

  final String table;
  final String rowId;

  /// Human-readable field name, e.g. "unit of Vitamin D3".
  final String field;
  final String before;
  final String after;
  final UnitMigrationReason reason;
}

enum UnitMigrationReason {
  /// The same unit written another way. Safe to apply without asking.
  unitSpelling,

  /// The same substance written another way.
  substanceSpelling,

  /// A dosage form sitting in a unit column, where the countable equivalent is
  /// unambiguous — a capsule is a capsule.
  formToCountableUnit,

  /// A dosage form with no implied count. Powder is bought by weight and taken
  /// by scoop; only the owner knows which they meant.
  formWithoutCountableUnit,

  /// A unit the vocabulary does not recognise at all.
  unknownUnit,
}

extension UnitMigrationReasonX on UnitMigrationReason {
  /// Whether the change is mechanical enough to apply without confirmation.
  ///
  /// Spelling is mechanical: `mg/dl` and `mg/dL` are the same unit, and nobody
  /// meant two different things by them. Anything that requires knowing what
  /// the person intended is not.
  bool get isAutomatic => switch (this) {
    UnitMigrationReason.unitSpelling => true,
    UnitMigrationReason.substanceSpelling => true,
    UnitMigrationReason.formToCountableUnit => true,
    UnitMigrationReason.formWithoutCountableUnit => false,
    UnitMigrationReason.unknownUnit => false,
  };
}

/// What the migration found, split by whether it needs the owner's judgement.
class UnitMigrationPlan {
  const UnitMigrationPlan({required this.automatic, required this.needsReview});

  final List<UnitMigrationProposal> automatic;
  final List<UnitMigrationProposal> needsReview;

  bool get isEmpty => automatic.isEmpty && needsReview.isEmpty;
  int get total => automatic.length + needsReview.length;
}

/// Surveys stored rows and proposes unit and substance corrections.
///
/// Deliberately read-only. The plan is produced first and shown to the owner,
/// because rewriting somebody's health history on app start — even correctly —
/// is not a thing to do quietly.
class UnitMigrationPlanner {
  const UnitMigrationPlanner(this._database);

  final AppDatabase _database;

  static const _substances = SubstanceCatalog();

  /// Forms that have an unambiguous countable equivalent.
  static const _formToUnit = <String, String>{
    'capsule': 'capsule',
    'capsules': 'capsule',
    'kapsel': 'capsule',
    'kapseln': 'capsule',
    'tablet': 'tablet',
    'tablets': 'tablet',
    'tablette': 'tablet',
    'tabletten': 'tablet',
  };

  /// Forms that say nothing about how the thing is counted.
  static const _formsWithoutCount = <String>{
    'powder',
    'pulver',
    'liquid',
    'flüssig',
    'oil',
    'öl',
    'cream',
    'gel',
  };

  Future<UnitMigrationPlan> plan() async {
    final db = await _database.database;
    final automatic = <UnitMigrationProposal>[];
    final review = <UnitMigrationProposal>[];

    void add(UnitMigrationProposal proposal) {
      (proposal.reason.isAutomatic ? automatic : review).add(proposal);
    }

    for (final row in await db.query(
      'supplements',
      columns: ['id', 'name', 'stock_unit', 'ingredients_json'],
      where: 'deleted = 0',
    )) {
      final id = '${row['id']}';
      final name = '${row['name']}';
      final stockUnit = '${row['stock_unit'] ?? ''}'.trim();
      final folded = stockUnit.toLowerCase();
      if (_formsWithoutCount.contains(folded)) {
        add(
          UnitMigrationProposal(
            table: 'supplements',
            rowId: id,
            field: '$name — stock unit',
            before: stockUnit,
            after: 'unit',
            reason: UnitMigrationReason.formWithoutCountableUnit,
          ),
        );
      } else if (_formToUnit.containsKey(folded) &&
          stockUnit != _formToUnit[folded]) {
        add(
          UnitMigrationProposal(
            table: 'supplements',
            rowId: id,
            field: '$name — stock unit',
            before: stockUnit,
            after: _formToUnit[folded]!,
            reason: UnitMigrationReason.formToCountableUnit,
          ),
        );
      } else if (stockUnit.isNotEmpty && !CanonicalUnit.isKnown(stockUnit)) {
        add(
          UnitMigrationProposal(
            table: 'supplements',
            rowId: id,
            field: '$name — stock unit',
            before: stockUnit,
            after: stockUnit,
            reason: UnitMigrationReason.unknownUnit,
          ),
        );
      }

      for (final proposal in _ingredientProposals(
        table: 'supplements',
        rowId: id,
        owner: name,
        json: row['ingredients_json'],
      )) {
        add(proposal);
      }
    }

    for (final row in await db.query(
      'trend_dose_links',
      columns: ['id', 'ingredient_name', 'ingredient_unit'],
      where: 'deleted = 0',
    )) {
      final before = '${row['ingredient_unit'] ?? ''}'.trim();
      final after = CanonicalUnit.normalize(before);
      if (before.isNotEmpty && after != before) {
        add(
          UnitMigrationProposal(
            table: 'trend_dose_links',
            rowId: '${row['id']}',
            field: '${row['ingredient_name']} — dose underlay unit',
            before: before,
            after: after,
            reason: UnitMigrationReason.unitSpelling,
          ),
        );
      }
    }

    return UnitMigrationPlan(automatic: automatic, needsReview: review);
  }

  /// Applies exactly the proposals given, and nothing else.
  ///
  /// Takes a list rather than re-deriving one so that what the owner approved
  /// on screen is what gets written — a plan computed twice could differ if
  /// anything changed in between.
  Future<int> apply(List<UnitMigrationProposal> proposals) async {
    if (proposals.isEmpty) return 0;
    final db = await _database.database;
    var applied = 0;
    await db.transaction((txn) async {
      final byRow = <(String, String), List<UnitMigrationProposal>>{};
      for (final proposal in proposals) {
        byRow
            .putIfAbsent((proposal.table, proposal.rowId), () => [])
            .add(proposal);
      }
      for (final entry in byRow.entries) {
        final (table, rowId) = entry.key;
        final rows = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [rowId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final row = Map<String, Object?>.from(rows.single);
        var changed = false;

        for (final proposal in entry.value) {
          switch (proposal.reason) {
            case UnitMigrationReason.formToCountableUnit:
            case UnitMigrationReason.formWithoutCountableUnit:
              if (table == 'supplements') {
                // The form is preserved in its own column before the unit
                // column is repurposed, so nothing is lost.
                final form = '${row['form'] ?? ''}'.trim();
                if (form.isEmpty) row['form'] = proposal.before;
                row['stock_unit'] = proposal.after;
                changed = true;
              }
            case UnitMigrationReason.unitSpelling:
            case UnitMigrationReason.substanceSpelling:
              if (table == 'trend_dose_links') {
                row['ingredient_unit'] = proposal.after;
                changed = true;
              } else if (row.containsKey('ingredients_json')) {
                row['ingredients_json'] = _rewriteIngredients(
                  row['ingredients_json'],
                  proposal,
                );
                changed = true;
              }
            case UnitMigrationReason.unknownUnit:
              // Nothing to write: the proposal exists to surface the value,
              // not to change it.
              break;
          }
        }

        if (!changed) continue;
        row['updated_at'] = DateTime.now().toUtc().toIso8601String();
        await txn.update(table, row, where: 'id = ?', whereArgs: [rowId]);
        applied += entry.value.length;
      }
    });
    return applied;
  }

  Object? _rewriteIngredients(Object? json, UnitMigrationProposal proposal) {
    final Object? decoded;
    try {
      decoded = jsonDecode('${json ?? '[]'}');
    } on FormatException {
      return json;
    }
    if (decoded is! List) return json;
    return jsonEncode([
      for (final item in decoded)
        if (item is Map)
          {
            for (final entry in item.entries)
              entry.key.toString(): _rewrittenValue(entry, proposal),
          }
        else
          item,
    ]);
  }

  Object? _rewrittenValue(
    MapEntry<Object?, Object?> entry,
    UnitMigrationProposal proposal,
  ) {
    final matchesUnit =
        proposal.reason == UnitMigrationReason.unitSpelling &&
        entry.key == 'unit' &&
        '${entry.value}'.trim() == proposal.before;
    final matchesName =
        proposal.reason == UnitMigrationReason.substanceSpelling &&
        entry.key == 'name' &&
        '${entry.value}'.trim() == proposal.before;
    return matchesUnit || matchesName ? proposal.after : entry.value;
  }

  Iterable<UnitMigrationProposal> _ingredientProposals({
    required String table,
    required String rowId,
    required String owner,
    required Object? json,
  }) sync* {
    final Object? decoded;
    try {
      decoded = jsonDecode('${json ?? '[]'}');
    } on FormatException {
      return;
    }
    if (decoded is! List) return;
    for (final item in decoded) {
      if (item is! Map) continue;
      final name = '${item['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;

      final unit = item['unit'];
      if (unit != null) {
        final before = '$unit'.trim();
        final after = CanonicalUnit.normalize(before);
        if (before.isNotEmpty && after != before) {
          yield UnitMigrationProposal(
            table: table,
            rowId: rowId,
            field: '$owner — $name unit',
            before: before,
            after: after,
            reason: UnitMigrationReason.unitSpelling,
          );
        } else if (before.isNotEmpty && !CanonicalUnit.isKnown(before)) {
          yield UnitMigrationProposal(
            table: table,
            rowId: rowId,
            field: '$owner — $name unit',
            before: before,
            after: before,
            reason: UnitMigrationReason.unknownUnit,
          );
        }
      }

      final canonicalName = _substances.displayNameFor(name);
      if (canonicalName != name) {
        yield UnitMigrationProposal(
          table: table,
          rowId: rowId,
          field: '$owner — ingredient name',
          before: name,
          after: canonicalName,
          reason: UnitMigrationReason.substanceSpelling,
        );
      }
    }
  }
}
