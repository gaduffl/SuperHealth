import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          SectionHeader(
            title: 'Supplements',
            subtitle: 'Products, schedules, and intake history',
            action: IconButton.filledTonal(
              tooltip: 'Add supplement',
              onPressed: () => showAddSupplementDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ),
          if (controller.supplements.isEmpty)
            EmptyState(
              icon: Icons.medication_outlined,
              title: 'No supplements',
              message:
                  'Add products manually or import your Supplement Manager data.',
              action: FilledButton(
                onPressed: () => showAddSupplementDialog(context, controller),
                child: const Text('Add product'),
              ),
            )
          else
            ...controller.supplements.map(
              (supplement) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.medication_outlined),
                  ),
                  title: Text(supplement.name),
                  subtitle: Text(
                    [
                      if (supplement.brand.isNotEmpty) supplement.brand,
                      if (supplement.form.isNotEmpty) supplement.form,
                      if (supplement.ingredients.isNotEmpty)
                        '${supplement.ingredients.length} ingredients',
                    ].join(' · '),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'log') {
                        showLogIntakeDialog(context, controller, supplement);
                      } else if (value == 'schedule') {
                        showAddScheduleDialog(context, controller, supplement);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'log', child: Text('Log intake')),
                      PopupMenuItem(
                        value: 'schedule',
                        child: Text('Add schedule'),
                      ),
                    ],
                  ),
                  onTap: () =>
                      showLogIntakeDialog(context, controller, supplement),
                ),
              ),
            ),
          SectionHeader(
            title: 'Symptoms & tags',
            subtitle: 'Track symptom severity and exposures such as caffeine',
            action: IconButton.filledTonal(
              tooltip: 'Track event',
              onPressed: () => showAddEventDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ),
          if (controller.events.isEmpty)
            const EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'No tracked events',
              message:
                  'Add symptoms and tags to make correlation analysis possible.',
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final event in controller.events.take(12))
                    ListTile(
                      leading: Icon(
                        event.kind == EventKind.symptom
                            ? Icons.monitor_heart_outlined
                            : Icons.sell_outlined,
                      ),
                      title: Text(event.name),
                      subtitle: Text(
                        [
                          DateFormat(
                            'd MMM yyyy, HH:mm',
                          ).format(event.observedAt),
                          if (event.notes.isNotEmpty) event.notes,
                        ].join(' · '),
                      ),
                      trailing: event.score == null
                          ? (event.numericValue == null
                                ? null
                                : Text(
                                    '${event.numericValue} ${event.unit ?? ''}',
                                  ))
                          : CircleAvatar(child: Text('${event.score}')),
                    ),
                ],
              ),
            ),
          SectionHeader(
            title: 'Health context',
            subtitle: 'Conditions, medicines, goals, and family history',
            action: IconButton.filledTonal(
              tooltip: 'Add health context',
              onPressed: () => showAddNamedRecordDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ),
          if (controller.namedRecords.isEmpty)
            const EmptyState(
              icon: Icons.assignment_ind_outlined,
              title: 'No health context yet',
              message:
                  'This context materially improves advisor and lab-planning quality.',
            )
          else
            ..._groupedRecords(context, controller.namedRecords),
          SectionHeader(
            title: 'Exploratory correlations',
            subtitle:
                'Pearson correlation on daily aggregates; association is not causation',
            action: TextButton.icon(
              onPressed: controller.busy
                  ? null
                  : () async {
                      try {
                        await controller.analyzeCorrelations();
                      } on Object catch (error) {
                        if (context.mounted) await showAppError(context, error);
                      }
                    },
              icon: const Icon(Icons.analytics_outlined),
              label: const Text('Analyze'),
            ),
          ),
          if (controller.correlations.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('At least 7 overlapping days are required'),
                subtitle: Text(
                  'Log repeated exposures and scored symptoms. Results are hypothesis-generating only.',
                ),
              ),
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final result in controller.correlations.take(12))
                    ListTile(
                      title: Text('${result.exposure} → ${result.outcome}'),
                      subtitle: Text(
                        'Lag ${result.lagDays} day${result.lagDays == 1 ? '' : 's'} · '
                        'n=${result.sampleSize} · ${result.strength}',
                      ),
                      trailing: Text(
                        result.coefficient.toStringAsFixed(2),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: result.coefficient >= 0
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _groupedRecords(
    BuildContext context,
    List<NamedHealthRecord> records,
  ) {
    const labels = {
      'condition': 'Conditions',
      'medication': 'Medicines',
      'goal': 'Goals',
      'family_history': 'Family history',
    };
    return [
      for (final entry in labels.entries)
        if (records.any((record) => record.kind == entry.key))
          Card(
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(entry.value),
              children: [
                for (final record in records.where(
                  (item) => item.kind == entry.key,
                ))
                  ListTile(
                    title: Text(record.name),
                    subtitle: Text(
                      [
                        record.status,
                        if (record.dose != null)
                          '${record.dose} ${record.unit ?? ''}',
                        if (record.schedule?.isNotEmpty == true)
                          record.schedule!,
                        if (record.notes.isNotEmpty) record.notes,
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
          ),
    ];
  }
}
