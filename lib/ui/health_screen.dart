import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';
import 'labs_screen.dart';

class HealthScreen extends StatelessWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              tabs: [
                Tab(
                  icon: const Icon(Icons.monitor_heart_outlined),
                  text: strings.journal,
                ),
                Tab(
                  icon: const Icon(Icons.science_outlined),
                  text: strings.biomarkers,
                ),
                Tab(
                  icon: const Icon(Icons.assignment_ind_outlined),
                  text: strings.context,
                ),
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
    final strings = AppLocalizations.of(context);
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
            title: strings.quickCheckIn,
            subtitle: strings.quickCheckInDescription,
            action: IconButton.filled(
              tooltip: strings.trackHealthEvent,
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
            Card(
              child: ListTile(
                leading: Icon(Icons.lightbulb_outline),
                title: Text(strings.reusableCheckIns),
                subtitle: Text(strings.reusableCheckInsExamples),
              ),
            ),
          if (trendEvents.isNotEmpty) ...[
            SectionHeader(
              title: strings.symptomTrend,
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
            title: strings.journal,
            subtitle: strings.journalEntries(filtered.length),
            action: PopupMenuButton<int>(
              tooltip: strings.changeDateRange,
              initialValue: _rangeDays,
              onSelected: (value) => setState(() => _rangeDays = value),
              itemBuilder: (_) => [
                PopupMenuItem(value: 30, child: Text(strings.lastDays(30))),
                PopupMenuItem(value: 90, child: Text(strings.lastDays(90))),
                PopupMenuItem(value: 365, child: Text(strings.lastYear)),
                PopupMenuItem(value: 36500, child: Text(strings.allHistory)),
              ],
              icon: const Icon(Icons.date_range_outlined),
            ),
          ),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'all', label: Text(strings.all)),
              ButtonSegment(value: 'symptom', label: Text(strings.symptoms)),
              ButtonSegment(value: 'tag', label: Text(strings.tags)),
            ],
            selected: {_kind},
            onSelectionChanged: (value) => setState(() => _kind = value.first),
          ),
          const SizedBox(height: 10),
          if (filtered.isEmpty)
            EmptyState(
              icon: Icons.monitor_heart_outlined,
              title: strings.noJournalEntries,
              message: strings.noJournalEntriesDescription,
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
            title: strings.exploratoryCorrelations,
            subtitle: strings.correlationsDescription,
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
              label: Text(strings.analyze),
            ),
          ),
          if (controller.correlations.isEmpty)
            Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text(strings.minimumCorrelationDays),
                subtitle: Text(strings.minimumCorrelationDaysDescription),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final result in controller.correlations.take(20))
                    ListTile(
                      isThreeLine: true,
                      title: Text('${result.exposure} → ${result.outcome}'),
                      subtitle: Text(
                        strings.correlationSummary(
                          lagDays: result.lagDays,
                          sampleSize: result.sampleSize,
                          strength: result.strength,
                          spearman: result.spearmanCoefficient,
                          adjustedQ: result.adjustedPValue,
                          statisticallySignificant:
                              result.isStatisticallySignificant,
                        ),
                      ),
                      trailing: Text(strings.pearson(result.coefficient)),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Text(strings.correlationCaveat),
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
            AppLocalizations.of(
              context,
            ).formatTrackingDateTime(event.observedAt),
            if (event.score != null)
              AppLocalizations.of(context).scoreOutOfTen(event.score!),
            if (event.numericValue != null)
              '${AppLocalizations.of(context).formatNumber(event.numericValue!)} ${event.unit ?? ''}',
            if (event.durationMinutes != null)
              AppLocalizations.of(
                context,
              ).durationMinutes(event.durationMinutes!),
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
                title: AppLocalizations.of(context).deleteJournalEntryTitle,
                message: AppLocalizations.of(
                  context,
                ).deleteJournalEntryDescription,
                confirmLabel: AppLocalizations.of(context).delete,
                destructive: true,
              );
              if (confirmed) await controller.deleteEvent(event);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'edit',
              child: Text(AppLocalizations.of(context).edit),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(AppLocalizations.of(context).delete),
            ),
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
      label: AppLocalizations.of(
        context,
      ).trendSemantics(events.first.name, events.length, minValue, maxValue),
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
    final strings = AppLocalizations.of(context);
    const labels = {
      'condition': Icons.healing_outlined,
      'medication': Icons.medication_liquid_outlined,
      'goal': Icons.flag_outlined,
      'family_history': Icons.family_restroom_outlined,
    };
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          SectionHeader(
            title: strings.healthContext,
            subtitle: strings.healthContextDescription,
            action: IconButton.filled(
              tooltip: strings.addHealthContext,
              onPressed: () => showAddNamedRecordDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ),
          if (controller.namedRecords.isEmpty)
            EmptyState(
              icon: Icons.assignment_ind_outlined,
              title: strings.noHealthContext,
              message: strings.noHealthContextDescription,
            )
          else
            for (final entry in labels.entries)
              if (controller.namedRecords.any(
                (record) => record.kind == entry.key,
              ))
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    leading: Icon(entry.value),
                    title: Text(strings.contextCategory(entry.key)),
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
                                '${strings.formatNumber(record.dose!)} ${record.unit ?? ''}',
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
                            tooltip: strings.deleteNamedRecordTitle(
                              record.name,
                            ),
                            onPressed: () async {
                              final confirmed = await showConfirmAction(
                                context,
                                title: strings.deleteNamedRecordTitle(
                                  record.name,
                                ),
                                message: strings.deleteNamedRecordDescription,
                                confirmLabel: strings.delete,
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
          SectionHeader(
            title: strings.privacy,
            subtitle: strings.privacyDescription,
          ),
          Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text(strings.sharedInventoryPrivateFacts),
              subtitle: Text(strings.sharedInventoryPrivateFactsDescription),
            ),
          ),
        ],
      ),
    );
  }
}
