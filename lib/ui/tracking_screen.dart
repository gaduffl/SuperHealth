import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'dialogs.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _insights = const SupplementInsights();
  final _search = TextEditingController();
  var _selectedDay = DateTime.now();
  var _catalogFilter = 'active';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return DefaultTabController(
      length: 4,
      child: PageBody(
        child: Column(
          children: [
            const Material(
              color: Colors.transparent,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(icon: Icon(Icons.today_outlined), text: 'Today'),
                  Tab(icon: Icon(Icons.medication_outlined), text: 'Catalog'),
                  Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock'),
                  Tab(icon: Icon(Icons.analytics_outlined), text: 'History'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _today(context, controller),
                  _catalog(context, controller),
                  _stock(context, controller),
                  _history(context, controller),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _today(BuildContext context, AppController controller) {
    final doses = _insights.dosesForDay(
      day: _selectedDay,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    final now = DateTime.now();
    final adherence = _insights.adherence(
      from: now.subtract(const Duration(days: 29)),
      through: now,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    return RefreshIndicator(
      onRefresh: controller.refreshActiveData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
        children: [
          _dayStrip(context),
          SectionHeader(
            title: DateFormat('EEEE, d MMMM').format(_selectedDay),
            subtitle: doses.isEmpty
                ? 'Nothing scheduled'
                : '${doses.where((item) => item.taken).length} of ${doses.length} taken',
            action: TextButton.icon(
              onPressed: controller.supplements.isEmpty
                  ? () => showAddSupplementDialog(context, controller)
                  : () => _chooseManualIntake(context, controller),
              icon: const Icon(Icons.add),
              label: const Text('Manual'),
            ),
          ),
          if (doses.isEmpty)
            EmptyState(
              icon: Icons.event_available_outlined,
              title: 'No doses for this day',
              message: controller.schedules.isEmpty
                  ? 'Add a schedule from the supplement catalog.'
                  : 'This is a schedule-free day.',
            )
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final dose in doses)
                    _doseTile(context, controller, dose),
                ],
              ),
            ),
          const SectionHeader(
            title: '30-day adherence',
            subtitle: 'Scheduled doses through the current time',
          ),
          _adherenceCard(context, adherence),
        ],
      ),
    );
  }

  Widget _dayStrip(BuildContext context) {
    final today = DateTime.now();
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 15,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final day = DateTime(
            today.year,
            today.month,
            today.day,
          ).add(Duration(days: index - 7));
          final selected = _sameDay(day, _selectedDay);
          return Semantics(
            selected: selected,
            label: DateFormat('EEEE d MMMM').format(day),
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => setState(() => _selectedDay = day),
              label: SizedBox(
                width: 40,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(DateFormat.E().format(day).substring(0, 2)),
                    Text(
                      '${day.day}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _doseTile(
    BuildContext context,
    AppController controller,
    ScheduledDoseStatus status,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final icon = status.taken
        ? Icons.check_circle
        : status.skipped
        ? Icons.do_not_disturb_on
        : status.missed
        ? Icons.error_outline
        : Icons.schedule;
    final color = status.taken
        ? colorScheme.primary
        : status.skipped
        ? colorScheme.outline
        : status.missed
        ? colorScheme.error
        : colorScheme.secondary;
    return Column(
      children: [
        ListTile(
          leading: Icon(icon, color: color, size: 30),
          title: Text(status.supplement.name),
          subtitle: Text(
            [
              '${status.schedule.dose} ${status.schedule.unit}',
              status.schedule.timeOfDay,
              if (status.schedule.instructions.isNotEmpty)
                status.schedule.instructions,
            ].join(' · '),
          ),
          trailing: status.intake != null
              ? IconButton(
                  tooltip: 'Undo check-in',
                  onPressed: controller.busy
                      ? null
                      : () => _undoIntake(context, controller, status.intake!),
                  icon: const Icon(Icons.undo),
                )
              : Wrap(
                  spacing: 4,
                  children: [
                    IconButton.outlined(
                      tooltip: 'Skip this dose',
                      onPressed: controller.busy
                          ? null
                          : () => _recordScheduled(
                              context,
                              controller,
                              status,
                              skipped: true,
                            ),
                      icon: const Icon(Icons.close),
                    ),
                    IconButton.filled(
                      tooltip: 'Mark as taken',
                      onPressed: controller.busy
                          ? null
                          : () => _recordScheduled(
                              context,
                              controller,
                              status,
                              skipped: false,
                            ),
                      icon: const Icon(Icons.check),
                    ),
                  ],
                ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _recordScheduled(
    BuildContext context,
    AppController controller,
    ScheduledDoseStatus status, {
    required bool skipped,
  }) async {
    try {
      await controller.logIntake(
        supplement: status.supplement,
        dose: status.schedule.dose,
        unit: status.schedule.unit,
        takenAt: DateTime.now(),
        schedule: status.schedule,
        skipped: skipped,
      );
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  Future<void> _undoIntake(
    BuildContext context,
    AppController controller,
    SupplementIntake intake,
  ) async {
    try {
      await controller.deleteIntake(intake);
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  Widget _adherenceCard(BuildContext context, AdherenceSummary value) {
    final rate = value.rate;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: rate ?? 0,
                        strokeWidth: 7,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      Center(
                        child: Text(
                          rate == null ? '—' : '${(rate * 100).round()}%',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _count('Taken', value.taken),
                      _count('Skipped', value.skipped),
                      _count('Missed', value.missed),
                      _count('Scheduled', value.scheduled),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _count(String label, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(label),
    ],
  );

  Widget _catalog(BuildContext context, AppController controller) {
    final query = _search.text.trim().toLowerCase();
    final products = controller.supplements.where((item) {
      final matchesQuery =
          query.isEmpty ||
          item.name.toLowerCase().contains(query) ||
          item.brand.toLowerCase().contains(query) ||
          item.ingredients.any(
            (ingredient) =>
                '${ingredient['name']}'.toLowerCase().contains(query),
          );
      final matchesState =
          _catalogFilter == 'all' ||
          (_catalogFilter == 'active' ? item.active : !item.active);
      return matchesQuery && matchesState;
    }).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: 'Search products or ingredients',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'active', label: Text('Active')),
                ButtonSegment(value: 'inactive', label: Text('Paused')),
                ButtonSegment(value: 'all', label: Text('All')),
              ],
              selected: {_catalogFilter},
              onSelectionChanged: (value) =>
                  setState(() => _catalogFilter = value.first),
            ),
            const Spacer(),
            IconButton.filled(
              tooltip: 'Add supplement',
              onPressed: () => showAddSupplementDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          const EmptyState(
            icon: Icons.search_off,
            title: 'No matching supplements',
            message: 'Change the filter or add a new product.',
          )
        else
          for (final product in products)
            _productCard(context, controller, product),
      ],
    );
  }

  Widget _productCard(
    BuildContext context,
    AppController controller,
    Supplement product,
  ) {
    final stock = controller.stockLevels[product.id] ?? 0;
    final productSchedules = controller.schedules
        .where((item) => item.supplementId == product.id)
        .toList();
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          child: Text(
            product.name.isEmpty ? '?' : product.name.characters.first,
          ),
        ),
        title: Text(product.name),
        subtitle: Text(
          [
            if (product.brand.isNotEmpty) product.brand,
            '${stock.toStringAsFixed(1)} ${product.stockUnit}',
            '${productSchedules.length} schedule${productSchedules.length == 1 ? '' : 's'}',
          ].join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) =>
              _productAction(context, controller, product, value),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'log', child: Text('Log intake')),
            const PopupMenuItem(value: 'schedule', child: Text('Add schedule')),
            const PopupMenuItem(value: 'stock', child: Text('Adjust stock')),
            const PopupMenuItem(value: 'edit', child: Text('Edit product')),
            PopupMenuItem(
              value: 'toggle',
              child: Text(product.active ? 'Pause product' : 'Reactivate'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        children: [
          if (product.ingredients.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ingredient in product.ingredients)
                      Chip(
                        label: Text(
                          [
                                ingredient['name'],
                                ingredient['amount'],
                                ingredient['unit'],
                              ]
                              .where(
                                (item) => item != null && '$item'.isNotEmpty,
                              )
                              .join(' '),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          for (final schedule in productSchedules)
            ListTile(
              leading: Icon(
                schedule.active ? Icons.schedule : Icons.pause_circle_outline,
              ),
              title: Text(
                '${schedule.dose} ${schedule.unit} · ${schedule.timeOfDay}',
              ),
              subtitle: Text(
                '${schedule.weekdays.length} days/week'
                '${schedule.instructions.isEmpty ? '' : ' · ${schedule.instructions}'}',
              ),
              onTap: () => showAddScheduleDialog(
                context,
                controller,
                product,
                existing: schedule,
              ),
              trailing: IconButton(
                tooltip: 'Delete schedule',
                onPressed: () => _deleteSchedule(context, controller, schedule),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          if (product.notes.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes),
              title: Text(product.notes),
            ),
        ],
      ),
    );
  }

  Future<void> _productAction(
    BuildContext context,
    AppController controller,
    Supplement product,
    String action,
  ) async {
    switch (action) {
      case 'log':
        await showLogIntakeDialog(context, controller, product);
        return;
      case 'schedule':
        await showAddScheduleDialog(context, controller, product);
        return;
      case 'stock':
        await showAdjustStockDialog(context, controller, product);
        return;
      case 'edit':
        await showAddSupplementDialog(context, controller, existing: product);
        return;
      case 'toggle':
        await controller.updateSupplement(
          _supplementWithActive(product, !product.active),
        );
        return;
      case 'delete':
        if (!context.mounted) return;
        final confirmed = await showConfirmAction(
          context,
          title: 'Delete ${product.name}?',
          message:
              'The product and its active schedules will be removed. Historical intakes remain as evidence.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (confirmed) await controller.deleteSupplement(product);
        return;
    }
  }

  Supplement _supplementWithActive(Supplement value, bool active) => Supplement(
    id: value.id,
    name: value.name,
    brand: value.brand,
    form: value.form,
    ingredients: value.ingredients,
    unitsPerContainer: value.unitsPerContainer,
    containerCount: value.containerCount,
    priceEur: value.priceEur,
    bioavailability: value.bioavailability,
    notes: value.notes,
    active: active,
    lowStockAlerts: value.lowStockAlerts,
    lowStockThresholdUnits: value.lowStockThresholdUnits,
    stockUnit: value.stockUnit,
    sourceId: value.sourceId,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
  );

  Future<void> _deleteSchedule(
    BuildContext context,
    AppController controller,
    SupplementSchedule schedule,
  ) async {
    final confirmed = await showConfirmAction(
      context,
      title: 'Delete schedule?',
      message: 'Past intake records will be kept.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) await controller.deleteSchedule(schedule);
  }

  Widget _stock(BuildContext context, AppController controller) {
    final projections = _insights.stockProjections(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
      stockLevels: controller.stockLevels,
    );
    final monthlyCost = _insights.monthlyCostEstimate(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Low stock',
                value: '${projections.where((item) => item.low).length}',
                icon: Icons.inventory_outlined,
                detail: 'Household catalog',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                label: 'Planned monthly cost',
                value: '${monthlyCost.toStringAsFixed(0)} €',
                icon: Icons.euro_outlined,
                detail: 'Known package prices',
              ),
            ),
          ],
        ),
        const SectionHeader(
          title: 'Household stock',
          subtitle: 'Consumption projection includes every profile schedule',
        ),
        if (projections.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No stock to manage',
            message: 'Add a supplement and its current container count.',
          )
        else
          for (final projection in projections)
            Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: projection.low
                      ? Theme.of(context).colorScheme.errorContainer
                      : null,
                  child: Icon(
                    projection.low
                        ? Icons.warning_amber_rounded
                        : Icons.inventory_2_outlined,
                  ),
                ),
                title: Text(projection.supplement.name),
                subtitle: Text(
                  [
                    '${projection.unitsOnHand.toStringAsFixed(1)} ${projection.supplement.stockUnit}',
                    if (projection.daysRemaining != null)
                      '${projection.daysRemaining!.clamp(0, 9999).toStringAsFixed(0)} days projected'
                    else
                      'No compatible household schedule',
                    if (projection.low && projection.suggestedPurchaseUnits > 0)
                      'Buy ~${projection.suggestedPurchaseUnits.toStringAsFixed(0)} for 12 weeks',
                  ].join(' · '),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => showAdjustStockDialog(
                    context,
                    controller,
                    projection.supplement,
                    purchase: true,
                  ),
                  child: const Text('Purchase'),
                ),
                onTap: () => showAdjustStockDialog(
                  context,
                  controller,
                  projection.supplement,
                ),
              ),
            ),
      ],
    );
  }

  Widget _history(BuildContext context, AppController controller) {
    final now = DateTime.now();
    final ingredients = _insights.ingredientExposure(
      intakes: controller.intakes,
      from: now.subtract(const Duration(days: 30)),
      to: now.add(const Duration(days: 1)),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        const SectionHeader(
          title: '30-day ingredient exposure',
          subtitle: 'Calculated from the ingredient snapshot saved per intake',
        ),
        if (ingredients.isEmpty)
          const EmptyState(
            icon: Icons.science_outlined,
            title: 'No ingredient totals yet',
            message:
                'Add ingredient amounts to products and log intakes to see totals.',
          )
        else
          Card(
            child: Column(
              children: [
                for (final item in ingredients.take(20))
                  ListTile(
                    title: Text(item.name),
                    trailing: Text(
                      '${item.total.toStringAsFixed(1)} ${item.unit}',
                    ),
                  ),
              ],
            ),
          ),
        const SectionHeader(
          title: 'Intake history',
          subtitle: 'Tap an entry to edit or remove it',
        ),
        if (controller.intakes.isEmpty)
          const EmptyState(
            icon: Icons.history,
            title: 'No intake history',
            message: 'Scheduled and manual check-ins appear here.',
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final intake in controller.intakes.take(100))
                  ListTile(
                    leading: Icon(
                      intake.skipped ? Icons.close : Icons.check,
                      color: intake.skipped
                          ? Theme.of(context).colorScheme.outline
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      controller.supplements
                              .firstWhereOrNull(
                                (item) => item.id == intake.supplementId,
                              )
                              ?.name ??
                          'Deleted supplement',
                    ),
                    subtitle: Text(
                      '${intake.dose} ${intake.unit} · '
                      '${DateFormat('dd.MM.yyyy HH:mm').format(intake.takenAt)}'
                      '${intake.notes.isEmpty ? '' : ' · ${intake.notes}'}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete intake',
                      onPressed: () =>
                          _deleteHistoryIntake(context, controller, intake),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _deleteHistoryIntake(
    BuildContext context,
    AppController controller,
    SupplementIntake intake,
  ) async {
    final confirmed = await showConfirmAction(
      context,
      title: 'Delete intake?',
      message: 'The linked stock deduction will also be reversed.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed) await controller.deleteIntake(intake);
  }

  Future<void> _chooseManualIntake(
    BuildContext context,
    AppController controller,
  ) async {
    final product = await showModalBottomSheet<Supplement>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Choose supplement')),
            for (final item in controller.supplements.where(
              (value) => value.active,
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
    if (product != null && context.mounted) {
      await showLogIntakeDialog(context, controller, product);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
