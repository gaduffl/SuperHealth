import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai/supplement_label_service.dart';
import '../app/app_controller.dart';
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

  /// Replaces every row with [ingredients].
  ///
  /// Used after reading a label: the rows stay editable, so the parse result is
  /// a starting point a person reviews rather than something stored on trust.
  void replaceAll(List<ParsedLabelIngredient> ingredients) {
    for (final row in _rows) {
      row.name.dispose();
      row.amount.dispose();
      row.unit.dispose();
    }
    _rows.clear();
    for (final ingredient in ingredients) {
      _add(
        name: ingredient.name,
        // Trailing zeros from the division would be noise in a text field.
        amount: ingredient.amount == null
            ? ''
            : _trimNumber(ingredient.amount!),
        unit: ingredient.unit,
      );
    }
    if (_rows.isEmpty) _add();
  }

  static String _trimNumber(double value) {
    final text = value.toStringAsFixed(6);
    if (!text.contains('.')) return text;
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

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
  final _labelText = TextEditingController();
  final _servingSize = TextEditingController(text: '1');
  var _readingLabel = false;
  var _labelExpanded = false;
  ParsedSupplementLabel? _lastResult;

  @override
  void dispose() {
    _labelText.dispose();
    _servingSize.dispose();
    super.dispose();
  }

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
              onPressed: () => setState(() => _labelExpanded = !_labelExpanded),
              icon: Icon(
                _labelExpanded
                    ? Icons.expand_less
                    : Icons.content_paste_outlined,
                size: 18,
              ),
              label: Text(strings.pick('Paste label', 'Etikett einfügen')),
            ),
            TextButton.icon(
              onPressed: () => setState(widget.rows.addRow),
              icon: const Icon(Icons.add, size: 18),
              label: Text(strings.pick('Add row', 'Zeile hinzufügen')),
            ),
          ],
        ),
        if (_labelExpanded) _labelReader(context, unit),
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

  /// The paste-a-label panel.
  ///
  /// Serving size is part of the input because labels state amounts per
  /// serving, and a serving is routinely several capsules — the number that
  /// decides whether a stored dose is right or four times too high.
  Widget _labelReader(BuildContext context, String? stockUnit) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final result = _lastResult;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.medium),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.pick(
                'Paste the ingredient table from the packaging. The configured '
                    'lab document parser model reads it into the rows below, '
                    'where you can correct anything before saving.',
                'Füge die Zutatentabelle von der Verpackung ein. Das '
                    'konfigurierte Modell für Labordokumente liest sie in die '
                    'Zeilen unten ein, wo du vor dem Speichern korrigieren '
                    'kannst.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _servingSize,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                isDense: true,
                labelText: strings.pick(
                  'Serving size on the label',
                  'Portionsgröße laut Etikett',
                ),
                helperText: strings.pick(
                  'How many ${stockUnit == null || stockUnit.isEmpty ? 'units' : '${stockUnit}s'} '
                      'the stated amounts cover.',
                  'Für wie viele ${stockUnit == null || stockUnit.isEmpty ? 'Einheiten' : stockUnit} '
                      'die angegebenen Mengen gelten.',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _labelText,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: strings.pick(
                  'Ingredient list from the label',
                  'Zutatenliste vom Etikett',
                ),
                alignLabelWithHint: true,
                hintText: 'Vitamin C 440 mg\nVitamin D3 26 µg (1040 IU)',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _readingLabel ? null : _readLabel,
                  icon: _readingLabel
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    _readingLabel
                        ? strings.pick('Reading…', 'Lese …')
                        : strings.pick('Read label', 'Etikett auslesen'),
                  ),
                ),
              ],
            ),
            if (result != null) ...[
              const SizedBox(height: AppSpacing.md),
              if (result.servingSizeDisagrees)
                _notice(
                  context,
                  icon: Icons.warning_amber_rounded,
                  color: colors.error,
                  text: strings.pick(
                    'The label appears to state a serving of '
                        '${result.detectedServingSize}, not ${result.servingSize}. '
                        'Check the amounts before saving.',
                    'Das Etikett scheint eine Portion von '
                        '${result.detectedServingSize} anzugeben, nicht '
                        '${result.servingSize}. Prüfe die Mengen vor dem '
                        'Speichern.',
                  ),
                ),
              for (final warning in result.warnings)
                _notice(
                  context,
                  icon: Icons.info_outline,
                  color: colors.onSurfaceVariant,
                  text: warning,
                ),
              if (result.ingredients.isEmpty)
                _notice(
                  context,
                  icon: Icons.info_outline,
                  color: colors.onSurfaceVariant,
                  text: strings.pick(
                    'Nothing readable was found in that text.',
                    'In diesem Text war nichts Lesbares zu finden.',
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _notice(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );

  Future<void> _readLabel() async {
    final strings = AppLocalizations.of(context);
    final servingSize = int.tryParse(_servingSize.text.trim());
    if (servingSize == null || servingSize < 1) {
      await showAppError(
        context,
        StateError(
          strings.pick(
            'Enter a serving size of at least 1.',
            'Gib eine Portionsgröße von mindestens 1 ein.',
          ),
        ),
      );
      return;
    }
    setState(() => _readingLabel = true);
    try {
      final parsed = await context.read<AppController>().parseSupplementLabel(
        labelText: _labelText.text,
        servingSize: servingSize,
        stockUnit: widget.stockUnitLabel?.trim().isNotEmpty == true
            ? widget.stockUnitLabel!.trim()
            : 'unit',
      );
      if (!mounted) return;
      setState(() {
        _lastResult = parsed;
        if (parsed.ingredients.isNotEmpty) {
          widget.rows.replaceAll(parsed.ingredients);
        }
      });
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    } finally {
      if (mounted) setState(() => _readingLabel = false);
    }
  }
}
