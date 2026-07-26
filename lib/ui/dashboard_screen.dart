import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../biomarkers/biomarker_status_service.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';
import 'initial_setup_widgets.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    final profile = controller.activeProfile!;
    final now = DateTime.now();
    final today = now;
    const insights = SupplementInsights();
    final todayIntakes = controller.intakes
        .where((item) => _sameDay(item.takenAt, today))
        .toList();
    final latestMeasurements = <String, Measurement>{};
    for (final measurement in controller.measurements) {
      final existing = latestMeasurements[measurement.biomarkerId];
      if (existing == null || measurement.takenAt.isAfter(existing.takenAt)) {
        latestMeasurements[measurement.biomarkerId] = measurement;
      }
    }
    final statusService = BiomarkerStatusService();
    final latestStatuses = [
      for (final biomarker in controller.biomarkers)
        statusService.evaluate(
          biomarker: biomarker,
          measurement: latestMeasurements[biomarker.id],
          profile: profile,
          targets: controller.profileTargets,
          referenceRanges: controller.biomarkerRanges,
          now: now,
        ),
    ];
    final belowCount = latestStatuses.where((item) => item.isBelow).length;
    final aboveCount = latestStatuses.where((item) => item.isAbove).length;
    final unavailableCount = latestStatuses
        .where((item) => item.kind == BiomarkerStatusKind.unavailable)
        .length;
    final neverMeasuredCount = latestStatuses
        .where((item) => item.kind == BiomarkerStatusKind.neverMeasured)
        .length;
    final activeSupplements = controller.supplements
        .where((item) => item.active)
        .length;
    final recentEvents = controller.events.take(4).toList();
    final scheduledToday = insights.dosesForDay(
      day: today,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    final stock = insights.stockProjections(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
      stockLevels: controller.stockLevels,
    );
    final lowStock = stock.where((item) => item.low).toList();

    return PageBody(
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            Text(
              strings.greeting(_partOfDay(today), profile.displayName),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              strings.formatDashboardDate(today),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (!controller.initialSetupProgress.isComplete) ...[
              const SizedBox(height: 12),
              DashboardSetupPrompt(
                onOpenSettings: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(strings.settings)),
                      body: const SettingsScreen(),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 4 : 2,
              childAspectRatio: 1.35,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                MetricCard(
                  label: strings.todayDoses,
                  value: strings.doseProgress(
                    scheduledToday.where((item) => item.taken).length,
                    scheduledToday.length,
                  ),
                  icon: Icons.medication_outlined,
                  detail: strings.activeProducts(activeSupplements),
                ),
                MetricCard(
                  label: strings.biomarkersDue,
                  value: '${controller.dueBiomarkers.length}',
                  icon: Icons.science_outlined,
                  detail: strings.measured(latestMeasurements.length),
                ),
                MetricCard(
                  label: strings.lowStock,
                  value: '${lowStock.length}',
                  icon: Icons.inventory_2_outlined,
                  detail: strings.householdInventory,
                ),
                MetricCard(
                  label: strings.labPlans,
                  value: '${controller.labPlans.length}',
                  icon: Icons.checklist_outlined,
                  detail: controller.labPlans.isEmpty
                      ? strings.createFirstPlan
                      : strings.savedChecklists,
                ),
                MetricCard(
                  label: strings.latestBelow,
                  value: '$belowCount',
                  icon: Icons.arrow_downward_outlined,
                  detail: strings.comparisonDescription,
                ),
                MetricCard(
                  label: strings.latestAbove,
                  value: '$aboveCount',
                  icon: Icons.arrow_upward_outlined,
                  detail: strings.comparisonDescription,
                ),
                MetricCard(
                  label: strings.rangeUnavailable,
                  value: '${unavailableCount + neverMeasuredCount}',
                  icon: Icons.help_outline,
                  detail:
                      '${strings.unavailableCount(unavailableCount)} · '
                      '${strings.neverMeasuredCount(neverMeasuredCount)}',
                ),
              ],
            ),
            SectionHeader(
              title: strings.quickTrack,
              subtitle: strings.quickTrackDescription,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: controller.supplements.isEmpty
                      ? () => showAddSupplementDialog(context, controller)
                      : () => _chooseSupplement(context, controller),
                  icon: const Icon(Icons.add_task),
                  label: Text(strings.supplementIntake),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showAddEventDialog(context, controller),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: Text(strings.symptom),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showAddEventDialog(
                    context,
                    controller,
                    initialKind: EventKind.tag,
                  ),
                  icon: const Icon(Icons.sell_outlined),
                  label: Text(strings.tag),
                ),
              ],
            ),
            SectionHeader(title: strings.recentActivity),
            if (todayIntakes.isEmpty && recentEvents.isEmpty)
              EmptyState(
                icon: Icons.timeline,
                title: strings.noActivityYet,
                message: strings.noActivityDescription,
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final intake in todayIntakes.take(4))
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.medication_outlined),
                        ),
                        title: Text(
                          _supplementName(
                            controller,
                            intake.supplementId,
                            strings,
                          ),
                        ),
                        subtitle: Text('${intake.dose} ${intake.unit}'),
                        trailing: Text(strings.formatTime(intake.takenAt)),
                      ),
                    for (final event in recentEvents)
                      ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            event.kind == EventKind.symptom
                                ? Icons.monitor_heart_outlined
                                : Icons.sell_outlined,
                          ),
                        ),
                        title: Text(event.name),
                        subtitle: Text(
                          event.score == null
                              ? (event.kind == EventKind.symptom
                                    ? strings.symptom
                                    : strings.tag)
                              : strings.score(event.score!),
                        ),
                        trailing: Text(
                          strings.formatShortDate(event.observedAt),
                        ),
                      ),
                  ],
                ),
              ),
            if (scheduledToday.any((item) => !item.taken) ||
                controller.dueBiomarkers.isNotEmpty ||
                lowStock.isNotEmpty) ...[
              SectionHeader(
                title: strings.needsAttention,
                subtitle: strings.needsAttentionDescription,
              ),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (final dose in scheduledToday.where(
                      (item) => !item.taken && !item.skipped,
                    ))
                      ListTile(
                        leading: const Icon(Icons.schedule),
                        title: Text(dose.supplement.name),
                        subtitle: Text(
                          '${dose.schedule.dose} ${dose.schedule.unit} · ${dose.schedule.timeOfDay}',
                        ),
                        trailing: FilledButton.tonal(
                          onPressed: () async {
                            try {
                              await controller.logIntake(
                                supplement: dose.supplement,
                                dose: dose.schedule.dose,
                                unit: dose.schedule.unit,
                                schedule: dose.schedule,
                              );
                            } on Object catch (error) {
                              if (context.mounted) {
                                await showAppError(context, error);
                              }
                            }
                          },
                          child: Text(strings.taken),
                        ),
                      ),
                    for (final due in controller.dueBiomarkers.take(3))
                      ListTile(
                        leading: const Icon(Icons.event_busy_outlined),
                        title: Text(strings.due(due.biomarker.displayName)),
                        subtitle: Text(
                          due.lastMeasuredAt == null
                              ? '${due.listName} · ${strings.neverMeasured}'
                              : '${due.listName} · '
                                    '${strings.daysOverdue(due.daysOverdue)}',
                        ),
                      ),
                    for (final item in lowStock.take(3))
                      ListTile(
                        leading: Icon(
                          Icons.inventory_outlined,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(strings.low(item.supplement.name)),
                        subtitle: Text(
                          strings.remaining(
                            item.unitsOnHand,
                            item.supplement.stockUnit,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () => showAdjustStockDialog(
                            context,
                            controller,
                            item.supplement,
                            purchase: true,
                          ),
                          child: Text(strings.refill),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            SectionHeader(
              title: strings.privacyBoundary,
              subtitle: strings.privacyBoundaryDescription,
            ),
            Card(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
              child: ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(strings.keysNeverSynced),
                subtitle: Text(strings.keysNeverSyncedDescription),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static AppDayPeriod _partOfDay(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return AppDayPeriod.morning;
    if (hour < 18) return AppDayPeriod.afternoon;
    return AppDayPeriod.evening;
  }

  static String _supplementName(
    AppController controller,
    String id,
    AppLocalizations strings,
  ) =>
      controller.supplements
          .where((item) => item.id == id)
          .map((item) => item.name)
          .firstOrNull ??
      strings.supplementFallback;

  Future<void> _chooseSupplement(
    BuildContext context,
    AppController controller,
  ) async {
    final strings = AppLocalizations.of(context);
    final supplement = await showModalBottomSheet<Supplement>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(title: Text(strings.whichSupplement)),
            for (final item in controller.supplements.where(
              (item) => item.active,
            ))
              ListTile(
                leading: const Icon(Icons.medication_outlined),
                title: Text(item.name),
                subtitle: item.brand.isEmpty ? null : Text(item.brand),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    );
    if (supplement != null && context.mounted) {
      await showLogIntakeDialog(context, controller, supplement);
    }
  }
}
