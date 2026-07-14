import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final profile = controller.activeProfile!;
    final today = DateTime.now();
    final todayIntakes = controller.intakes
        .where((item) => _sameDay(item.takenAt, today))
        .toList();
    final latestMeasurements = <String, Measurement>{};
    for (final measurement in controller.measurements) {
      latestMeasurements.putIfAbsent(
        measurement.biomarkerId,
        () => measurement,
      );
    }
    final activeSupplements = controller.supplements
        .where((item) => item.active)
        .length;
    final recentEvents = controller.events.take(4).toList();

    return PageBody(
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 110),
          children: [
            Text(
              'Good ${_partOfDay()}, ${profile.displayName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('EEEE, d MMMM', 'en').format(today),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
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
                  label: 'Today’s intakes',
                  value: '${todayIntakes.length}',
                  icon: Icons.medication_outlined,
                  detail: '$activeSupplements active products',
                ),
                MetricCard(
                  label: 'Biomarkers',
                  value: '${latestMeasurements.length}',
                  icon: Icons.science_outlined,
                  detail: '${controller.biomarkers.length} in catalog',
                ),
                MetricCard(
                  label: 'Health events',
                  value: '${controller.events.length}',
                  icon: Icons.monitor_heart_outlined,
                  detail: 'Symptoms and tags',
                ),
                MetricCard(
                  label: 'Lab plans',
                  value: '${controller.labPlans.length}',
                  icon: Icons.checklist_outlined,
                  detail: controller.labPlans.isEmpty
                      ? 'Create your first plan'
                      : 'Saved checklists',
                ),
              ],
            ),
            SectionHeader(
              title: 'Quick track',
              subtitle: 'Add data while it is fresh',
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
                  label: const Text('Supplement intake'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showAddEventDialog(context, controller),
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Symptom'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => showAddEventDialog(
                    context,
                    controller,
                    initialKind: EventKind.tag,
                  ),
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Tag'),
                ),
              ],
            ),
            const SectionHeader(title: 'Recent activity'),
            if (todayIntakes.isEmpty && recentEvents.isEmpty)
              const EmptyState(
                icon: Icons.timeline,
                title: 'No activity yet',
                message: 'Intakes, symptoms, and tags will appear here.',
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
                          _supplementName(controller, intake.supplementId),
                        ),
                        subtitle: Text('${intake.dose} ${intake.unit}'),
                        trailing: Text(DateFormat.Hm().format(intake.takenAt)),
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
                              ? event.kind.name
                              : 'Score ${event.score}/10',
                        ),
                        trailing: Text(
                          DateFormat.MMMd().format(event.observedAt),
                        ),
                      ),
                  ],
                ),
              ),
            const SectionHeader(
              title: 'Privacy boundary',
              subtitle: 'Designed for a private, local-first health record',
            ),
            Card(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.55),
              child: const ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Your keys and OneDrive tokens are never synced'),
                subtitle: Text(
                  'The AI receives only the complete active-profile snapshot for a request. '
                  'It has no database connection.',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _partOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 18) return 'afternoon';
    return 'evening';
  }

  static String _supplementName(AppController controller, String id) =>
      controller.supplements
          .where((item) => item.id == id)
          .map((item) => item.name)
          .firstOrNull ??
      'Supplement';

  Future<void> _chooseSupplement(
    BuildContext context,
    AppController controller,
  ) async {
    final supplement = await showModalBottomSheet<Supplement>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Which supplement?')),
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
