import 'package:flutter/material.dart';

import '../app/app_localizations.dart';
import 'common.dart';
import 'design.dart';

/// The editable rows behind [IngredientEditor].
///
/// The controllers live outside the widget so the dialog that hosts the editor
/// can read the current values when it saves, and dispose them on close.
class IngredientRows {
  /// Builds the rows for [ingredients].
  ///
  /// A product with none starts with one blank row so the fields are visible
  /// rather than hidden behind an "add" button.
  IngredientRows.from(List<Map<String, Object?>> ingredients) {
    for (final ingredient in ingredients) {
      _add(
        name: ingredient['name']?.toString() ?? '',
        amount: ingredient['amount']?.toString() ?? '',
        unit: ingredient['unit']?.toString() ?? '',
      );
    }
    if (_rows.isEmpty) _add();
  }

  /// Adds a blank row.
  void addRow() => _add();

  final _rows = <IngredientRow>[];

  List<IngredientRow> get rows => List.unmodifiable(_rows);

  void _add({String name = '', String amount = '', String unit = ''}) {
    _rows.add(
      IngredientRow(
        name: TextEditingController(text: name),
        amount: TextEditingController(text: amount),
        unit: TextEditingController(text: unit),
      ),
    );
  }

  /// The stored ingredient list, or `null` when a row cannot be read.
  ///
  /// A row with a name but an unparsable amount is an error rather than a
  /// silently dropped value: losing a dose quietly is worse than refusing to
  /// save.
  List<Map<String, Object?>>? parse() {
    final result = <Map<String, Object?>>[];
    for (final row in _rows) {
      final name = row.name.text.trim();
      final amountText = row.amount.text.trim();
      final unit = row.unit.text.trim();
      if (name.isEmpty && amountText.isEmpty && unit.isEmpty) continue;
      if (name.isEmpty) return null;
      final amount = amountText.isEmpty
          ? null
          : parseOptionalDouble(amountText);
      if (amountText.isNotEmpty && amount == null) return null;
      result.add({
        'name': name,
        'amount': ?amount,
        if (unit.isNotEmpty) 'unit': unit,
      });
    }
    return result;
  }

  void dispose() {
    for (final row in _rows) {
      row.name.dispose();
      row.amount.dispose();
      row.unit.dispose();
    }
    _rows.clear();
  }
}

/// One editable ingredient line.
class IngredientRow {
  IngredientRow({required this.name, required this.amount, required this.unit});

  final TextEditingController name;
  final TextEditingController amount;
  final TextEditingController unit;
}

/// A row-per-ingredient editor.
///
/// Replaces the pipe-delimited free-text field: the amount and unit each get a
/// field of their own, so there is no separator syntax to remember and a typo
/// cannot silently merge two columns.
class IngredientEditor extends StatefulWidget {
  const IngredientEditor({required this.rows, this.stockUnitLabel, super.key});

  final IngredientRows rows;

  /// The product's stock unit, shown so it is clear that amounts are per one
  /// capsule, scoop, or whatever the product is counted in.
  final String? stockUnitLabel;

  @override
  State<IngredientEditor> createState() => _IngredientEditorState();
}

class _IngredientEditorState extends State<IngredientEditor> {
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final unit = widget.stockUnitLabel?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.pick('Ingredients', 'Inhaltsstoffe'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            TextButton.icon(
              onPressed: () => setState(widget.rows.addRow),
              icon: const Icon(Icons.add, size: 18),
              label: Text(strings.pick('Add row', 'Zeile hinzufügen')),
            ),
          ],
        ),
        Text(
          unit == null || unit.isEmpty
              ? strings.pick(
                  'Amount per stock unit.',
                  'Menge je Bestandseinheit.',
                )
              : strings.pick('Amount per $unit.', 'Menge je $unit.'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (widget.rows.rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              strings.pick(
                'No ingredients recorded. Component totals and interaction '
                    'checks need them.',
                'Keine Inhaltsstoffe erfasst. Komponentensummen und '
                    'Wechselwirkungsprüfungen brauchen sie.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          for (final (index, row) in widget.rows.rows.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: TextField(
                      controller: row.name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: strings.pick('Name', 'Name'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: row.amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: strings.pick('Amount', 'Menge'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: row.unit,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: strings.pick('Unit', 'Einheit'),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: strings.pick('Remove row', 'Zeile entfernen'),
                    onPressed: () => setState(() {
                      final removed = widget.rows._rows.removeAt(index);
                      removed.name.dispose();
                      removed.amount.dispose();
                      removed.unit.dispose();
                    }),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
