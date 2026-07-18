import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';
import 'labs_screen.dart';

class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Column(
      children: [
        const Material(
          color: Colors.transparent,
          child: TabBar(
            tabs: [
              Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'Journal'),
              Tab(icon: Icon(Icons.science_outlined), text: 'Biomarkers'),
              Tab(icon: Icon(Icons.assignment_ind_outlined), text: 'Context'),
            ],
          ),
        ),
        const Expanded(
          child: TabBarView(
            children: [_JournalPane(), LabsScreen(), _ContextPane()],
          ),
        ),
      ],
    ),
  );
}

class _JournalPane extends StatefulWidget {
  const _JournalPane();

  @override
  State<_JournalPane> createState() => _JournalPaneState();
}

class _JournalPaneState extends State<_JournalPane> {
  var _rangeDays = 30;
  var _kind = 'all';
  String? _trendName;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final cutoff = DateTime.now().subtract(Duration(days: _rangeDays));
    final filtered = controller.events
        .where(
          (event) =>
              !event.observedAt.isBefore(cutoff) &&
              (_kind == 'all' || event.kind.name == _kind),
        )
        .toList();
    final trendNames =
        controller.events
            .where(
              (event) =>
                  event.kind == EventKind.symptom &&
                  (event.score != null || event.numericValue != null),
            )
            .map((event) => event.name)
            .toSet()
            .toList()
          ..sort();
    final selectedTrend = trendNames.contains(_trendName)
        ? _trendName
        : trendNames.firstOrNull;
    final trendEvents =
        selectedTrend == null
              ? <HealthEvent>[]
              : controller.events
                    .where(
                      (event) =>
                          event.name == selectedTrend &&
                          !event.observedAt.isBefore(cutoff) &&
                          (event.score != null || event.numericValue != null),
                    )
                    .toList()
          ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          SectionHeader(
            title: 'Quick check-in',
            subtitle: 'Symptoms, exposures, habits, and interventions',
            action: IconButton.filled(
              tooltip: 'Track a health event',
              onPressed: () => showAddEventDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ),
          if (controller.eventDefinitions.isNotEmpty)
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final definition in controller.eventDefinitions.take(16))
                  ActionChip(
                    avatar: Icon(
                      definition.kind == EventKind.symptom
                          ? Icons.monitor_heart_outlined
                          : Icons.sell_outlined,
                      size: 18,
                    ),
                    label: Text(definition.name),
                    onPressed: () => showAddEventDialog(
                      context,
                      controller,
                      initialKind: definition.kind,
                    ),
                  ),
              ],
            )
          else
            const Card(
              child: ListTile(
                leading: Icon(Icons.lightbulb_outline),
                title: Text('Create reusable check-ins as you log'),
                subtitle: Text(
                  'Examples: headache severity, energy, caffeine, alcohol, exercise, sleep quality.',
                ),
              ),
            ),
          if (trendEvents.isNotEmpty) ...[
            SectionHeader(
              title: 'Symptom trend',
              action: DropdownButton<String>(
                value: selectedTrend,
                items: [
                  for (final name in trendNames)
                    DropdownMenuItem(value: name, child: Text(name)),
                ],
                onChanged: (value) => setState(() => _trendName = value),
              ),
            ),
            _TrendCard(events: trendEvents),
          ],
          SectionHeader(
            title: 'Journal',
            subtitle: '${filtered.length} entries in the selected range',
            action: PopupMenuButton<int>(
              tooltip: 'Change date range',
              initialValue: _rangeDays,
              onSelected: (value) => setState(() => _rangeDays = value),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 30, child: Text('Last 30 days')),
                PopupMenuItem(value: 90, child: Text('Last 90 days')),
                PopupMenuItem(value: 365, child: Text('Last year')),
                PopupMenuItem(value: 36500, child: Text('All history')),
              ],
              icon: const Icon(Icons.date_range_outlined),
            ),
          ),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'all', label: Text('All')),
              ButtonSegment(value: 'symptom', label: Text('Symptoms')),
              ButtonSegment(value: 'tag', label: Text('Tags')),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            const EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: 'No journal entries',
              message: 'Track a symptom or exposure to start the timeline.',
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final event in filtered)
                    _eventTile(context, controller, event),
                ],
              ),
            ),
          SectionHeader(
            title: 'Exploratory correlations',
            subtitle:
                'Daily exposure vs symptom scores; association is not causation',
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
                  'Repeated check-ins are needed. Constant exposures cannot produce a correlation.',
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final result in controller.correlations.take(20))
                    ListTile(
                      title: Text('${result.exposure} → ${result.outcome}'),
                      subtitle: Text(
                        'Lag ${result.lagDays}d · n=${result.sampleSize} · ${result.strength}',
                      ),
                      trailing: Text(result.coefficient.toStringAsFixed(2)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _eventTile(
    BuildContext context,
    AppController controller,
    HealthEvent event,
  ) => Column(
    children: [
      ListTile(
        leading: Icon(
          event.kind == EventKind.symptom
              ? Icons.monitor_heart_outlined
              : Icons.sell_outlined,
        ),
        title: Text(event.name),
        subtitle: Text(
          [
            DateFormat('dd.MM.yyyy HH:mm').format(event.observedAt),
            if (event.score != null) 'Score ${event.score}/10',
            if (event.numericValue != null)
              '${event.numericValue} ${event.unit ?? ''}',
            if (event.durationMinutes != null) '${event.durationMinutes} min',
            if (event.notes.isNotEmpty) event.notes,
          ].join(' · '),
        ),
        onTap: () => showAddEventDialog(context, controller, existing: event),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await showAddEventDialog(context, controller, existing: event);
            } else if (value == 'delete') {
              final confirmed = await showConfirmAction(
                context,
                title: 'Delete journal entry?',
                message: 'This removes the entry from future analysis.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (confirmed) await controller.deleteEvent(event);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Edit')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
      const Divider(height: 1),
    ],
  );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.events});

  final List<HealthEvent> events;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final event in events)
        event.score?.toDouble() ?? event.numericValue ?? 0,
    ];
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);
    return Semantics(
      label:
          '${events.first.name} trend with ${events.length} points, from ${minValue.toStringAsFixed(1)} to ${maxValue.toStringAsFixed(1)}.',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            child: CustomPaint(
              painter: _LineChartPainter(
                values: values,
                lineColor: Theme.of(context).colorScheme.primary,
                gridColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
  });

  final List<double> values;
  final Color lineColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var row = 0; row <= 4; row++) {
      final y = size.height * row / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (values.isEmpty) return;
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final spread = high == low ? 1.0 : high - low;
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final y = size.height - ((values[index] - low) / spread * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.gridColor != gridColor;
}

class _ContextPane extends StatelessWidget {
  const _ContextPane();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    const labels = {
      'condition': ('Conditions', Icons.healing_outlined),
      'medication': ('Medicines', Icons.medication_liquid_outlined),
      'goal': ('Goals', Icons.flag_outlined),
      'family_history': ('Family history', Icons.family_restroom_outlined),
    };
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          SectionHeader(
            title: 'Health context',
            subtitle:
                'Personal facts used by the advisor and lab planner—not shared across profiles',
            action: IconButton.filled(
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
                  'Add conditions, medicines, goals, and family history so advice can account for them.',
            )
          else
            for (final entry in labels.entries)
              if (controller.namedRecords.any(
                (record) => record.kind == entry.key,
              ))
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    leading: Icon(entry.value.$2),
                    title: Text(entry.value.$1),
                    children: [
                      for (final record in controller.namedRecords.where(
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
                          onTap: () => showAddNamedRecordDialog(
                            context,
                            controller,
                            existing: record,
                          ),
                          trailing: IconButton(
                            tooltip: 'Delete ${record.name}',
                            onPressed: () async {
                              final confirmed = await showConfirmAction(
                                context,
                                title: 'Delete ${record.name}?',
                                message:
                                    'The record will no longer be included in advisor context.',
                                confirmLabel: 'Delete',
                                destructive: true,
                              );
                              if (confirmed) {
                                await controller.deleteNamedRecord(record);
                              }
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ),
                    ],
                  ),
                ),
          const SectionHeader(
            title: 'Privacy',
            subtitle: 'The active profile is the AI and export boundary',
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text(
                'Household inventory is shared; health facts are not',
              ),
              subtitle: Text(
                'Other profiles can use the same supplement stock without their conditions, biomarkers, or journal entering this profile’s AI context.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
