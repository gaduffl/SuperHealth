import 'package:flutter/material.dart';

import '../app/app_localizations.dart';

class LabSelfPaidSelection extends StatelessWidget {
  const LabSelfPaidSelection({
    required this.total,
    required this.selected,
    required this.onMarkAll,
    required this.onClear,
    this.savedReport = false,
    super.key,
  });

  final int total;
  final int selected;
  final VoidCallback? onMarkAll;
  final VoidCallback? onClear;
  final bool savedReport;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.pick('Self-paid (IGeL)', 'Selbst bezahlt (IGeL)'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l.pick(
                '$selected of $total marked',
                '$selected von $total markiert',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.pick(
                'Tick the results you paid for yourself. Unmarked results have no payment information.',
                'Markiere die Ergebnisse, die du selbst bezahlt hast. Nicht markierte Ergebnisse haben keine Zahlungsangabe.',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              savedReport
                  ? l.pick(
                      'Changes are saved immediately.',
                      'Änderungen werden sofort gespeichert.',
                    )
                  : l.pick(
                      'Marks are saved with the reviewed report.',
                      'Die Markierungen werden mit dem geprüften Bericht gespeichert.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: selected == total ? null : onMarkAll,
                  child: Text(
                    l.pick('Mark all IGeL', 'Alle als IGeL markieren'),
                  ),
                ),
                TextButton(
                  onPressed: selected == 0 ? null : onClear,
                  child: Text(
                    l.pick('Clear IGeL marks', 'IGeL-Markierungen entfernen'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class LabSelfPaidCheckbox extends StatelessWidget {
  const LabSelfPaidCheckbox({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CheckboxListTile(
    value: value,
    onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
    controlAffinity: ListTileControlAffinity.leading,
    contentPadding: EdgeInsets.zero,
    dense: true,
    title: Text(
      AppLocalizations.of(
        context,
      ).pick('Self-paid (IGeL)', 'Selbst bezahlt (IGeL)'),
    ),
  );
}
