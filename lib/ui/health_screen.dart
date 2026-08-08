import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/shell_navigation.dart';
import '../domain/entities.dart';
import 'charts.dart';
import 'check_in_dialog.dart';
import 'common.dart';
import 'design.dart';
import 'dialogs.dart';
import 'dose_underlay.dart';
import 'labs_screen.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen>
    with SingleTickerProviderStateMixin {
  /// Easy mode leaves only Biomarkers: the journal and context panes are the
  /// symptom-and-tag half of the app. A TabController cannot change length, so
  /// this is read once and the shell rebuilds the screen on a profile switch.
  late final TabController _tabs = TabController(
    length: (context.read<AppController>().activeProfile?.easyMode ?? true)
        ? 1
        : 3,
    vsync: this,
  );
  int? _handledRequestToken;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Switches to the tab a Today tile asked for. The biomarker filter itself is
  /// applied by [LabsScreen], which owns the catalog's filter state.
  void _applyRequest(ShellNavigation navigation) {
    final request = navigation.request;
    if (request == null || request.token == _handledRequestToken) return;
    final tab = healthTabForSection(request.section);
    if (tab == null) return;
    _handledRequestToken = request.token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tabs.index = tab;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final visibility = context.watch<AppController>().visibility;
    _applyRequest(context.watch<ShellNavigation>());
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tabs,
            tabs: [
              if (visibility.symptomsAndTags)
                Tab(
                  icon: const Icon(Icons.monitor_heart_outlined),
                  text: strings.journal,
                ),
              Tab(
                icon: const Icon(Icons.science_outlined),
                text: strings.biomarkers,
              ),
              if (visibility.symptomsAndTags)
                Tab(
                  icon: const Icon(Icons.assignment_ind_outlined),
                  text: strings.context,
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              if (visibility.symptomsAndTags) const _JournalPane(),
              const LabsScreen(),
              if (visibility.symptomsAndTags) const _ContextPane(),
            ],
          ),
        ),
      ],
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
    final activeEvents = controller.events
        .where((event) => !event.deleted)
        .toList();
    final filtered =
        activeEvents
            .where(
              (event) =>
                  !event.observedAt.isBefore(cutoff) &&
                  (_kind == 'all' || event.kind.name == _kind),
            )
            .toList()
          ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final dayGroups = _groupJournalEvents(filtered);
    final trendNames =
        activeEvents
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
              : activeEvents
                    .where(
                      (event) =>
                          event.name == selectedTrend &&
                          !event.observedAt.isBefore(cutoff) &&
                          (event.score != null || event.numericValue != null),
                    )
                    .toList()
          ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return PageBody(
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          children: [
            SectionHeader(
              title: strings.journal,
              subtitle: strings.pick(
                '${dayGroups.length} recorded day(s) · '
                    '${filtered.length} entries',
                '${dayGroups.length} erfasste(r) Tag(e) · '
                    '${filtered.length} Einträge',
              ),
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
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.first),
            ),
            const SizedBox(height: 10),
            _JournalInsightsCard(
              controller: controller,
              rangeDays: _rangeDays,
              trendNames: trendNames,
              selectedTrend: selectedTrend,
              trendEvents: trendEvents,
              onTrendChanged: (value) => setState(() => _trendName = value),
            ),
            const SizedBox(height: 6),
            if (filtered.isEmpty)
              EmptyState(
                icon: Icons.monitor_heart_outlined,
                title: strings.noJournalEntries,
                message: strings.noJournalEntriesDescription,
              )
            else
              for (final group in dayGroups)
                _JournalDayCard(
                  controller: controller,
                  day: group.day,
                  events: group.events,
                ),
          ],
        ),
      ),
    );
  }
}

/// The dose underlay for the currently selected symptom or tag trend.
///
/// Legacy events carry no definition id, and a link has to point at a
/// definition, so those trends simply get no underlay rather than a link that
/// could not be stored.
TrendDoseUnderlay _trendUnderlay(
  AppController controller,
  List<HealthEvent> trendEvents,
) {
  final definitionId = trendEvents.firstOrNull?.definitionId;
  if (definitionId == null || trendEvents.isEmpty) {
    return const TrendDoseUnderlay(available: []);
  }
  final days = trendEvents.map((event) => event.observedAt).toList()..sort();
  return resolveTrendDoseUnderlay(
    controller: controller,
    definitionId: definitionId,
    trendNames: [trendEvents.first.name],
    from: days.first,
    through: days.last,
  );
}

class _JournalInsightsCard extends StatelessWidget {
  const _JournalInsightsCard({
    required this.controller,
    required this.rangeDays,
    required this.trendNames,
    required this.selectedTrend,
    required this.trendEvents,
    required this.onTrendChanged,
  });

  final AppController controller;
  final int rangeDays;
  final List<String> trendNames;
  final String? selectedTrend;
  final List<HealthEvent> trendEvents;
  final ValueChanged<String?> onTrendChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          leading: const Icon(Icons.insights_outlined),
          title: Text(
            strings.pick('Trends and correlations', 'Trends und Korrelationen'),
          ),
          subtitle: Text(
            strings.pick(
              'Open insights only when you need them.',
              'Öffne Auswertungen nur bei Bedarf.',
            ),
          ),
          children: [
            if (trendEvents.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    strings.pick(
                      'Record symptom scores to display a trend.',
                      'Erfasse Symptombewertungen, um einen Trend anzuzeigen.',
                    ),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.symptomTrend,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        DropdownButton<String>(
                          value: selectedTrend,
                          underline: const SizedBox.shrink(),
                          items: [
                            for (final name in trendNames)
                              DropdownMenuItem(value: name, child: Text(name)),
                          ],
                          onChanged: onTrendChanged,
                        ),
                      ],
                    ),
                    Text(
                      strings.lastDays(rangeDays),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TrendChart(
                      points: [
                        for (final event in trendEvents)
                          (
                            day: event.observedAt,
                            value:
                                event.score?.toDouble() ??
                                event.numericValue ??
                                0,
                          ),
                      ],
                      dayLabel: strings.formatShortDate,
                      doseSeries: _trendUnderlay(
                        controller,
                        trendEvents,
                      ).series,
                      minY: trendEvents.every((event) => event.score != null)
                          ? 0
                          : null,
                      maxY: trendEvents.every((event) => event.score != null)
                          ? trendEvents.any((event) => (event.score ?? 0) > 5)
                                ? 10
                                : 5
                          : null,
                      semanticLabel: strings.trendSemantics(
                        trendEvents.first.name,
                        trendEvents.length,
                        trendEvents
                            .map(
                              (event) =>
                                  event.score?.toDouble() ??
                                  event.numericValue ??
                                  0,
                            )
                            .reduce((a, b) => a < b ? a : b),
                        trendEvents
                            .map(
                              (event) =>
                                  event.score?.toDouble() ??
                                  event.numericValue ??
                                  0,
                            )
                            .reduce((a, b) => a > b ? a : b),
                      ),
                    ),
                    if (_trendUnderlay(controller, trendEvents).hasChoice) ...[
                      const SizedBox(height: 4),
                      DoseUnderlayPicker(
                        underlay: _trendUnderlay(controller, trendEvents),
                        onChanged: (target) => controller.setTrendDoseLink(
                          definitionId: trendEvents.first.definitionId,
                          target: target,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.exploratoryCorrelations,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          strings.correlationsDescription,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () async {
                            try {
                              await controller.analyzeCorrelations();
                            } on Object catch (error) {
                              if (context.mounted) {
                                await showAppError(context, error);
                              }
                            }
                          },
                    icon: const Icon(Icons.analytics_outlined),
                    label: Text(strings.analyze),
                  ),
                ],
              ),
            ),
            if (controller.correlations.isEmpty)
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(strings.minimumCorrelationDays),
                subtitle: Text(strings.minimumCorrelationDaysDescription),
              )
            else ...[
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
          ],
        ),
      ),
    );
  }
}

class _JournalDayGroup {
  const _JournalDayGroup({required this.day, required this.events});

  final DateTime day;
  final List<HealthEvent> events;
}

List<_JournalDayGroup> _groupJournalEvents(List<HealthEvent> events) {
  final grouped = <DateTime, List<HealthEvent>>{};
  for (final event in events) {
    final day = DateTime(
      event.observedAt.year,
      event.observedAt.month,
      event.observedAt.day,
    );
    grouped.putIfAbsent(day, () => []).add(event);
  }
  final result = [
    for (final entry in grouped.entries)
      _JournalDayGroup(day: entry.key, events: entry.value),
  ]..sort((a, b) => b.day.compareTo(a.day));
  return result;
}

class _JournalDayCard extends StatelessWidget {
  const _JournalDayCard({
    required this.controller,
    required this.day,
    required this.events,
  });

  final AppController controller;
  final DateTime day;
  final List<HealthEvent> events;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final summaries = _journalDaySummaries(controller, events, strings);
    final symptomCount = summaries
        .where((entry) => entry.kind == EventKind.symptom)
        .length;
    final tagCount = summaries.length - symptomCount;
    final notes = <String>[];
    for (final event in events) {
      final note = event.notes.trim();
      if (note.isNotEmpty && !notes.contains(note)) notes.add(note);
    }

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: ValueKey('journal-${day.toIso8601String()}'),
          leading: const Icon(Icons.calendar_today_outlined),
          title: Text(strings.formatTrackingDate(day)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_journalDayCount(strings, symptomCount, tagCount)),
              if (summaries.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final summary in summaries.take(3))
                      Chip(
                        label: Text(summary.label),
                        visualDensity: VisualDensity.compact,
                      ),
                    if (summaries.length > 3)
                      Chip(
                        label: Text('+${summaries.length - 3}'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ],
          ),
          children: [
            if (notes.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notes.length == 1
                          ? strings.pick('Day note', 'Tagesnotiz')
                          : strings.pick('Notes', 'Notizen'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    for (final note in notes) Text(note),
                  ],
                ),
              ),
            for (final event in events)
              _JournalEventRow(controller: controller, event: event),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      showDailyCheckInDialog(context, controller, day: day),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(
                    strings.pick('Edit daily check-in', 'Check-in bearbeiten'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalEventRow extends StatelessWidget {
  const _JournalEventRow({required this.controller, required this.event});

  final AppController controller;
  final HealthEvent event;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final details = <String>[
      strings.formatTime(event.observedAt),
      if (event.score != null) _scoreLabel(strings, event),
      if (event.numericValue != null)
        '${strings.formatNumber(event.numericValue!)} ${event.unit ?? ''}'
            .trim(),
      if (event.durationMinutes != null)
        strings.durationMinutes(event.durationMinutes!),
    ];
    return Column(
      children: [
        ListTile(
          dense: true,
          leading: Icon(
            event.kind == EventKind.symptom
                ? Icons.monitor_heart_outlined
                : Icons.sell_outlined,
            size: 21,
          ),
          title: Text(event.name),
          subtitle: Text(details.join(' · ')),
          trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                await showAddEventDialog(context, controller, existing: event);
              } else if (value == 'delete') {
                final confirmed = await showConfirmAction(
                  context,
                  title: strings.deleteJournalEntryTitle,
                  message: strings.deleteJournalEntryDescription,
                  confirmLabel: strings.delete,
                  destructive: true,
                );
                if (confirmed) await controller.deleteEvent(event);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(strings.pick('Edit details', 'Details bearbeiten')),
              ),
              PopupMenuItem(value: 'delete', child: Text(strings.delete)),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

class _JournalDaySummary {
  const _JournalDaySummary({required this.kind, required this.label});

  final EventKind kind;
  final String label;
}

List<_JournalDaySummary> _journalDaySummaries(
  AppController controller,
  List<HealthEvent> events,
  AppLocalizations strings,
) {
  final definitions = {
    for (final definition in controller.eventDefinitions)
      definition.id: definition,
  };
  final grouped = <String, List<HealthEvent>>{};
  for (final event in events) {
    final key =
        event.definitionId ??
        '${event.kind.name}:${event.name.trim().toLowerCase()}';
    grouped.putIfAbsent(key, () => []).add(event);
  }

  final result = <_JournalDaySummary>[];
  for (final entry in grouped.values) {
    entry.sort((a, b) => a.observedAt.compareTo(b.observedAt));
    final latest = entry.last;
    final definition = definitions[latest.definitionId];
    if (latest.kind == EventKind.symptom) {
      final score = latest.score ?? latest.numericValue?.round();
      final repeat = entry.length > 1 ? ' · ${entry.length}×' : '';
      result.add(
        _JournalDaySummary(
          kind: EventKind.symptom,
          label: score == null
              ? '${latest.name}$repeat'
              : score > 5
              ? strings.pick(
                  '${latest.name} $score/10 (legacy)$repeat',
                  '${latest.name} $score/10 (alt)$repeat',
                )
              : '${latest.name} $score/5$repeat',
        ),
      );
      continue;
    }

    final label = switch (definition?.valueMode ?? TagValueMode.occurrence) {
      TagValueMode.occurrence =>
        entry.length == 1 ? latest.name : '${latest.name} · ${entry.length}×',
      TagValueMode.intensity =>
        latest.score == null
            ? latest.name
            : latest.score! > 5
            ? strings.pick(
                '${latest.name} ${latest.score}/10 (legacy)',
                '${latest.name} ${latest.score}/10 (alt)',
              )
            : '${latest.name} ${latest.score}/5',
      TagValueMode.amount => _journalAmountSummary(strings, definition, entry),
    };
    result.add(_JournalDaySummary(kind: EventKind.tag, label: label));
  }
  result.sort((a, b) {
    if (a.kind != b.kind) return a.kind == EventKind.symptom ? -1 : 1;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return result;
}

String _journalAmountSummary(
  AppLocalizations strings,
  HealthEventDefinition? definition,
  List<HealthEvent> events,
) {
  final name = definition?.name ?? events.last.name;
  final unit = definition?.defaultUnit ?? events.last.unit ?? '';
  final total = events.fold<double>(
    0,
    (sum, event) => sum + (event.numericValue ?? 0),
  );
  final parts = <String>[name];
  final portion = definition?.portionAmount;
  final portionLabel = definition?.portionLabel?.trim();
  if (portion != null &&
      portion > 0 &&
      portionLabel != null &&
      portionLabel.isNotEmpty) {
    parts.add('${_journalNumber(strings, total / portion)}× $portionLabel');
  }
  parts.add('${_journalNumber(strings, total)} $unit'.trim());
  return parts.join(' · ');
}

String _journalNumber(AppLocalizations strings, double value) =>
    strings.formatNumber(
      value,
      decimalDigits: value == value.truncateToDouble() ? 0 : 1,
    );

String _journalDayCount(
  AppLocalizations strings,
  int symptomCount,
  int tagCount,
) {
  final parts = <String>[];
  if (symptomCount > 0) {
    parts.add(
      strings.pick(
        symptomCount == 1 ? '1 symptom' : '$symptomCount symptoms',
        symptomCount == 1 ? '1 Symptom' : '$symptomCount Symptome',
      ),
    );
  }
  if (tagCount > 0) {
    parts.add(
      strings.pick(
        tagCount == 1 ? '1 tag' : '$tagCount tags',
        tagCount == 1 ? '1 Tag' : '$tagCount Tags',
      ),
    );
  }
  return parts.join(' · ');
}

String _scoreLabel(AppLocalizations strings, HealthEvent event) {
  final score = event.score!;
  if (score > 5) {
    return strings.pick('Score $score/10 (legacy)', 'Wert $score/10 (alt)');
  }
  return strings.pick('Score $score/5', 'Wert $score/5');
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
