import 'dart:convert';

import 'substance_catalog.dart';
import 'units.dart';

enum SupplementHistoryUpdate { startingNow, correctHistory }

/// Presentation changes and row order do not change a product's recipe.
bool ingredientRecipesEqual(
  List<Map<String, Object?>> before,
  List<Map<String, Object?>> after,
) {
  const substances = SubstanceCatalog();
  List<String> keys(List<Map<String, Object?>> rows) => [
    for (final row in rows)
      jsonEncode([
        substances.groupingKeyFor('${row['name'] ?? ''}'),
        num.tryParse('${row['amount']}')?.toDouble() ?? row['amount'],
        CanonicalUnit.normalize('${row['unit'] ?? ''}'),
      ]),
  ]..sort();
  final left = keys(before);
  final right = keys(after);
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
