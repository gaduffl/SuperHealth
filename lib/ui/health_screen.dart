import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/shell_navigation.dart';
import '../domain/entities.dart';
import 'charts.dart';
import 'common.dart';
import 'dialogs.dart';
import 'labs_screen.dart';
import 'manage_check_ins_dialog.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
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
    _applyRequest(context.watch<ShellNavigation>());
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tabs,
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
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [_JournalPane(), LabsScreen(), _ContextPane()],
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
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
          children: [
            SectionHeader(
              title: strings.quickCheckIn,
              subtitle: strings.quickCheckInDescription,
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.outlined(
                    tooltip: strings.pick(
                      'Manage symptoms and tags',
                      'Symptome und Tags verwalten',
                    ),
                    onPressed: () =>
                        showManageCheckInsDialog(context, controller),
                    icon: const Icon(Icons.tune),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    tooltip: strings.trackHealthEvent,
                    onPressed: () => showAddEventDialog(context, controller),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ),
            if (controller.eventDefinitions.any(
              (item) => !item.archived && !item.deleted,
            ))
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final definition
                      in controller.eventDefinitions
                          .where((item) => !item.archived && !item.deleted)
                          .take(16))
                    ActionChip(
                      avatar: Icon(
                        definition.kind == EventKind.symptom
                            ? Icons.monitor_heart_outlined
                            : Icons.sell_outlined,
                        size: 18,
                      ),
                      label: Text(definition.name),
                      onPressed: () =>
                          _quickTrack(context, controller, definition),
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
            if (trendEvents.isNotEmpty)
              ChartCard(
                title: strings.symptomTrend,
                subtitle: strings.lastDays(_rangeDays),
                trailing: DropdownButton<String>(
                  value: selectedTrend,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final name in trendNames)
                      DropdownMenuItem(value: name, child: Text(name)),
                  ],
                  onChanged: (value) => setState(() => _trendName = value),
                ),
                child: TrendChart(
                  points: [
                    for (final event in trendEvents)
                      (
                        day: event.observedAt,
                        value:
                            event.score?.toDouble() ?? event.numericValue ?? 0,
                      ),
                  ],
                  dayLabel: strings.formatShortDate,
                  // Scores are on a fixed 0-10 scale, so pinning the axis keeps
                  // a flat week from looking like dramatic swings.
                  minY: trendEvents.every((event) => event.score != null)
                      ? 0
                      : null,
                  maxY: trendEvents.every((event) => event.score != null)
                      ? 10
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
              ),
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
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.first),
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
                          if (context.mounted) {
                            await showAppError(context, error);
                          }
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
      ),
    );
  }

  /// A tap on a quick check-in chip.
  ///
  /// An occurrence tag has nothing to ask about — it either happened or it
  /// did not — so it is recorded straight away with an undo. An amount tag
  /// with a defined portion logs one portion the same way, matching how a
  /// quick coffee tap used to work. A symptom needs its 0-10 rating, an
  /// intensity tag needs the same rating, and an amount tag with no portion
  /// defined yet has no shortcut to take, so all three open the dialog with
  /// the name already filled in.
  Future<void> _quickTrack(
    BuildContext context,
    AppController controller,
    HealthEventDefinition definition,
  ) async {
    final strings = AppLocalizations.of(context);
    final portion = definition.portionAmount;
    final hasPortionShortcut =
        definition.valueMode == TagValueMode.amount &&
        portion != null &&
        portion > 0;
    final needsRating =
        definition.kind == EventKind.symptom ||
        definition.valueMode == TagValueMode.intensity ||
        (definition.valueMode == TagValueMode.amount && !hasPortionShortcut);
    if (needsRating) {
      await showAddEventDialog(
        context,
        controller,
        initialKind: definition.kind,
        initialName: definition.name,
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    try {
      await controller.addEvent(
        kind: definition.kind,
        name: definition.name,
        definition: definition,
        value: hasPortionShortcut ? portion : null,
        unit: hasPortionShortcut ? definition.defaultUnit : null,
      );
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
      return;
    }
    final recorded = controller.events.firstWhereOrNull(
      (event) => !event.deleted && event.definitionId == definition.id,
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          hasPortionShortcut
              ? strings.pick(
                  '${definition.name} recorded ($portion '
                      '${definition.defaultUnit}).',
                  '${definition.name} erfasst ($portion '
                      '${definition.defaultUnit}).',
                )
              : strings.pick(
                  '${definition.name} recorded.',
                  '${definition.name} erfasst.',
                ),
        ),
        action: recorded == null
            ? null
            : SnackBarAction(
                label: strings.pick('Undo', 'Rückgängig'),
                onPressed: () => controller.deleteEvent(recorded),
              ),
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
