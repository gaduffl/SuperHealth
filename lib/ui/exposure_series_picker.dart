import 'package:flutter/material.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_localizations.dart';
import '../domain/units.dart';

/// Keeps selections saved under older ingredient names and unit spellings.
String canonicalExposurePin(String pin) {
  if (!pin.startsWith('ingredient|')) return pin;
  final separator = pin.lastIndexOf('|');
  if (separator <= 'ingredient|'.length) return pin;
  final name = pin.substring('ingredient|'.length, separator);
  final unit = pin.substring(separator + 1);
  final key = name.startsWith('name:')
      ? '$name|${CanonicalUnit.normalize(unit).toLowerCase()}'
      : SupplementInsights.ingredientSeriesKey(name, unit);
  return 'ingredient|$key';
}

List<ExposureSeries> selectedExposureSeries(
  List<ExposureSeries> series,
  Set<String> pins, {
  required String category,
}) {
  final selected = series
      .where((item) => pins.contains('$category|${item.key}'))
      .toList();
  return selected.isNotEmpty ? selected : series.take(6).toList();
}

Future<Set<String>?> showExposureSeriesPicker(
  BuildContext context, {
  required String title,
  required List<ExposureSeries> series,
  required Set<String> initialPins,
  required String category,
}) {
  final strings = AppLocalizations.of(context);
  final ordered = [...series]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final pins = initialPins.map(canonicalExposurePin).toSet();
  String keyOf(ExposureSeries item) => '$category|${item.key}';
  return showModalBottomSheet<Set<String>>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.8,
      child: StatefulBuilder(
        builder: (context, setState) {
          final selected = ordered
              .where((item) => pins.contains(keyOf(item)))
              .length;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      selected == 0
                          ? strings.pick(
                              'Nothing selected — the chart shows the largest series.',
                              'Nichts ausgewählt — das Diagramm zeigt die größten Reihen.',
                            )
                          : strings.pick(
                              '$selected selected',
                              '$selected ausgewählt',
                            ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  children: [
                    for (final item in ordered)
                      CheckboxListTile(
                        value: pins.contains(keyOf(item)),
                        title: Text(item.name),
                        subtitle: Text(
                          '${strings.formatNumber(item.total)} ${item.unit}',
                        ),
                        onChanged: (checked) => setState(() {
                          if (checked == true) {
                            pins.add(keyOf(item));
                          } else {
                            pins.remove(keyOf(item));
                          }
                        }),
                      ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: selected == 0
                            ? null
                            : () => setState(
                                () => pins.removeAll(ordered.map(keyOf)),
                              ),
                        child: Text(strings.pick('Clear', 'Zurücksetzen')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(sheetContext, Set<String>.of(pins)),
                        child: Text(strings.pick('Done', 'Fertig')),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
