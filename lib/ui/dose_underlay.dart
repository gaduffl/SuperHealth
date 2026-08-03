import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';

/// What to draw beneath one trend, and what to offer the user if nothing has
/// been chosen yet.
///
/// A suggestion is never drawn on its own. The point of the underlay is to
/// judge whether a supplement moved a number, so an unconfirmed guess sitting
/// behind the line would be the one kind of error worth avoiding entirely.
class TrendDoseUnderlay {
  const TrendDoseUnderlay({
    required this.available,
    this.series,
    this.selected,
    this.suggestion,
  });

  /// Every ingredient the profile actually takes, offered in the picker.
  final List<({String name, String unit})> available;

  /// Present only once the user has confirmed an ingredient.
  final DoseSeries? series;
  final ({String name, String unit})? selected;

  /// A guess shown as an offer while [selected] is null.
  final ({String name, String unit})? suggestion;

  bool get hasChoice => available.isNotEmpty;
}

/// Builds the underlay for a trend spanning [from]..[through].
///
/// Exactly one of [biomarkerId] and [definitionId] identifies the trend.
/// [trendNames] carries every name it is known by, so a biomarker can be
/// matched through its synonyms rather than its display name alone.
TrendDoseUnderlay resolveTrendDoseUnderlay({
  required AppController controller,
  required Iterable<String> trendNames,
  required DateTime from,
  required DateTime through,
  String? biomarkerId,
  String? definitionId,
}) {
  const insights = SupplementInsights();
  final available = insights.knownIngredients(controller.intakes);
  if (available.isEmpty) return const TrendDoseUnderlay(available: []);

  final link = controller.trendDoseLinks.firstWhereOrNull(
    (item) => biomarkerId != null
        ? item.biomarkerId == biomarkerId
        : item.definitionId == definitionId,
  );
  if (link == null) {
    return TrendDoseUnderlay(
      available: available,
      suggestion: insights.suggestIngredient(
        ingredients: available,
        trendNames: trendNames,
      ),
    );
  }

  // A linked ingredient the user no longer takes has no series to draw, but
  // the link is kept so re-adding the supplement restores the underlay.
  final selected = available.firstWhereOrNull(
    (item) =>
        item.name.toLowerCase() == link.ingredientName.toLowerCase() &&
        item.unit.toLowerCase() == link.ingredientUnit.toLowerCase(),
  );
  return TrendDoseUnderlay(
    available: available,
    selected: (name: link.ingredientName, unit: link.ingredientUnit),
    series: selected == null
        ? null
        : insights.doseSeries(
            intakes: controller.intakes,
            ingredientName: link.ingredientName,
            ingredientUnit: link.ingredientUnit,
            from: from,
            through: through,
          ),
  );
}

/// The control strip beneath a trend for choosing, changing, or removing the
/// supplement dose drawn behind it.
class DoseUnderlayPicker extends StatelessWidget {
  const DoseUnderlayPicker({
    required this.underlay,
    required this.onChanged,
    super.key,
  });

  final TrendDoseUnderlay underlay;
  final ValueChanged<({String name, String unit})?> onChanged;

  @override
  Widget build(BuildContext context) {
    if (!underlay.hasChoice) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = underlay.selected;
    final suggestion = underlay.suggestion;

    if (selected != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: InputChip(
          visualDensity: VisualDensity.compact,
          avatar: Icon(
            Icons.medication_outlined,
            color: theme.colorScheme.tertiary,
          ),
          label: Text(
            underlay.series == null
                ? strings.pick(
                    '${selected.name} — no longer taken',
                    '${selected.name} — nicht mehr eingenommen',
                  )
                : '${selected.name} (${selected.unit})',
          ),
          onPressed: () => _choose(context),
          onDeleted: () => onChanged(null),
          deleteIconColor: theme.colorScheme.onSurfaceVariant,
          tooltip: strings.pick(
            'Change the supplement shown behind this trend',
            'Nahrungsergänzung hinter diesem Verlauf ändern',
          ),
        ),
      );
    }

    if (suggestion != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          visualDensity: VisualDensity.compact,
          avatar: const Icon(Icons.add),
          label: Text(
            strings.pick(
              'Show ${suggestion.name} dose',
              '${suggestion.name}-Dosis anzeigen',
            ),
          ),
          onPressed: () => onChanged(suggestion),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _choose(context),
        icon: const Icon(Icons.add, size: 18),
        label: Text(
          strings.pick(
            'Show a supplement dose',
            'Dosis einer Ergänzung zeigen',
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final strings = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<({String name, String unit})?>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                strings.pick(
                  'Supplement shown behind the trend',
                  'Ergänzung hinter dem Verlauf',
                ),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
              subtitle: Text(
                strings.pick(
                  'Doses keep their own scale on the right. Only the unit you '
                      'actually logged is shown, never converted.',
                  'Dosen behalten rechts ihre eigene Skala. Es wird nur die '
                      'tatsächlich erfasste Einheit gezeigt, nie umgerechnet.',
                ),
              ),
            ),
            const Divider(height: 1),
            RadioGroup<({String name, String unit})>(
              groupValue: underlay.selected,
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final ingredient in underlay.available)
                    RadioListTile<({String name, String unit})>(
                      value: ingredient,
                      title: Text(ingredient.name),
                      subtitle: Text(ingredient.unit),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }
}
