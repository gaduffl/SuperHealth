import 'dart:convert';

/// v16 and older portable backups had no way to freeze an empty recipe.
/// Call after verifying the original backup's checksums, before row validation.
void upgradeIngredientSnapshotRows(List<Map<String, Object?>> rows) {
  for (final row in rows) {
    if (row.containsKey('ingredient_snapshot_recorded')) continue;
    final raw = row['ingredients_json'];
    if (raw is! String) continue;
    final ingredients = jsonDecode(raw);
    if (ingredients is! List) continue;
    row['ingredient_snapshot_recorded'] = ingredients.isNotEmpty ? 1 : 0;
  }
}
