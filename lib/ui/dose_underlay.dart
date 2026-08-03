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

  /// Everything the profile takes that could be drawn, offered in the picker.
  final List<DoseTarget> available;

  /// Present only once the user has confirmed a target.
  final DoseSeries? series;
  final DoseTarget? selected;

  /// A guess shown as an offer while [selected] is null.
  final DoseTarget? suggestion;

  bool get hasChoice => available.isNotEmpty;

  /// True when a target is chosen but produced no dose at all — worth saying
  /// out loud, since an empty chart otherwise looks like the feature failed.
  bool get selectedButEmpty => selected != null && series?.hasDose != true;
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
  final available = insights.knownDoseTargets(
    intakes: controller.intakes,
    supplements: controller.supplements,
  );
  if (available.isEmpty) return const TrendDoseUnderlay(available: []);

  final link = controller.trendDoseLinks.firstWhereOrNull(
    (item) => biomarkerId != null
        ? item.biomarkerId == biomarkerId
        : item.definitionId == definitionId,
  );
  if (link == null) {
    return TrendDoseUnderlay(
      available: available,
      suggestion: insights.suggestDoseTarget(
        targets: available,
        trendNames: trendNames,
      ),
    );
  }

  final selected = link.supplementId != null
      ? DoseTarget.supplement(
          supplementId: link.supplementId!,
          name: link.ingredientName,
          unit: link.ingredientUnit,
        )
      : DoseTarget.ingredient(
          name: link.ingredientName,
          unit: link.ingredientUnit,
        );

  // Supplementation often starts after the last measurement or ends before
  // the first, and clipping the underlay to the measured period then drew
  // nothing at all — which reads as a broken feature rather than as "no
  // overlap". Widening to cover the doses keeps the comparison visible.
  final doseSpan = insights.doseSpan(
    intakes: controller.intakes,
    target: selected,
    supplements: controller.supplements,
  );
  final windowFrom = doseSpan == null || doseSpan.from.isAfter(from)
      ? from
      : doseSpan.from;
  final windowThrough = doseSpan == null || doseSpan.through.isBefore(through)
      ? through
      : doseSpan.through;

  return TrendDoseUnderlay(
    available: available,
    selected: selected,
    series: insights.doseSeries(
      intakes: controller.intakes,
      target: selected,
      supplements: controller.supplements,
      from: windowFrom,
      through: windowThrough,
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
  final ValueChanged<DoseTarget?> onChanged;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InputChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(
                Icons.medication_outlined,
                color: theme.colorScheme.tertiary,
              ),
              label: Text(selected.label),
              onPressed: () => _choose(context),
              onDeleted: () => onChanged(null),
              deleteIconColor: theme.colorScheme.onSurfaceVariant,
              tooltip: strings.pick(
                'Change the supplement shown behind this trend',
                'Nahrungsergänzung hinter diesem Verlauf ändern',
              ),
            ),
            // Without this, picking something with no recorded intake looks
            // exactly like the feature doing nothing.
            if (underlay.selectedButEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  strings.pick(
                    'No intake recorded for this, so there is nothing to draw.',
                    'Dafür ist keine Einnahme erfasst, also gibt es nichts '
                        'anzuzeigen.',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
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
    final products = underlay.available
        .where((target) => target.isSupplement)
        .toList();
    final ingredients = underlay.available
        .where((target) => !target.isSupplement)
        .toList();
    final picked = await showModalBottomSheet<DoseTarget?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
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
            RadioGroup<DoseTarget>(
              groupValue: underlay.selected,
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final section in [
                    (
                      label: strings.pick('Products', 'Produkte'),
                      targets: products,
                    ),
                    (
                      label: strings.pick('Ingredients', 'Inhaltsstoffe'),
                      targets: ingredients,
                    ),
                  ])
                    if (section.targets.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            section.label,
                            style: Theme.of(sheetContext).textTheme.labelMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    sheetContext,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                      for (final target in section.targets)
                        RadioListTile<DoseTarget>(
                          value: target,
                          title: Text(target.name),
                          subtitle: target.unit.isEmpty
                              ? null
                              : Text(target.unit),
                        ),
                    ],
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
