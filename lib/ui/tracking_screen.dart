import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
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
  final _historySearch = TextEditingController();
  var _selectedDay = DateTime.now();
  var _catalogFilter = 'active';
  var _historyRange = '30';
  var _historyVisible = 50;
  String? _historyPinsProfileId;
  bool _historyPinsLoading = false;
  Set<String> _historyPins = <String>{};

  @override
  void dispose() {
    _search.dispose();
    _historySearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    return DefaultTabController(
      length: 4,
      child: PageBody(
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    icon: const Icon(Icons.today_outlined),
                    text: strings.today,
                  ),
                  Tab(
                    icon: const Icon(Icons.medication_outlined),
                    text: strings.catalog,
                  ),
                  Tab(
                    icon: const Icon(Icons.inventory_2_outlined),
                    text: strings.stock,
                  ),
                  Tab(
                    icon: const Icon(Icons.analytics_outlined),
                    text: strings.history,
                  ),
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
    final strings = AppLocalizations.of(context);
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
            title: strings.formatTrackingDate(_selectedDay),
            subtitle: doses.isEmpty
                ? strings.nothingScheduled
                : strings.trackingProgress(
                    doses.where((item) => item.taken).length,
                    doses.length,
                  ),
            action: TextButton.icon(
              onPressed: controller.supplements.isEmpty
                  ? () => showAddSupplementDialog(context, controller)
                  : () => _chooseManualIntake(context, controller),
              icon: const Icon(Icons.add),
              label: Text(strings.manual),
            ),
          ),
          if (doses.isEmpty)
            EmptyState(
              icon: Icons.event_available_outlined,
              title: strings.noDosesForThisDay,
              message: controller.schedules.isEmpty
                  ? strings.addScheduleFromCatalog
                  : strings.scheduleFreeDay,
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
          SectionHeader(
            title: strings.adherence30Day,
            subtitle: strings.scheduledThroughCurrentTime,
          ),
          _adherenceCard(context, adherence),
        ],
      ),
    );
  }

  Widget _dayStrip(BuildContext context) {
    final strings = AppLocalizations.of(context);
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
            label: strings.formatTrackingDate(day),
            child: ChoiceChip(
              selected: selected,
              onSelected: (_) => setState(() => _selectedDay = day),
              label: SizedBox(
                width: 40,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(strings.formatTrackingWeekday(day).substring(0, 2)),
                    Text(
                      strings.formatNumber(
                        day.day.toDouble(),
                        decimalDigits: 0,
                      ),
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
    final strings = AppLocalizations.of(context);
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
              '${strings.formatNumber(status.schedule.dose)} ${status.schedule.unit}',
              status.schedule.timeOfDay,
              if (status.schedule.instructions.isNotEmpty)
                status.schedule.instructions,
            ].join(' · '),
          ),
          trailing: status.intake != null
              ? IconButton(
                  tooltip: strings.undoCheckIn,
                  onPressed: controller.busy
                      ? null
                      : () => _undoIntake(context, controller, status.intake!),
                  icon: const Icon(Icons.undo),
                )
              : Wrap(
                  spacing: 4,
                  children: [
                    IconButton.outlined(
                      tooltip: strings.skipDose,
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
                      tooltip: strings.markTaken,
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
    final strings = AppLocalizations.of(context);
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
                          rate == null ? '—' : strings.formatPercent(rate),
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
                      _count(strings, strings.taken, value.taken),
                      _count(strings, strings.skipped, value.skipped),
                      _count(strings, strings.missed, value.missed),
                      _count(strings, strings.scheduled, value.scheduled),
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

  Widget _count(AppLocalizations strings, String label, int value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        strings.formatNumber(value.toDouble(), decimalDigits: 0),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      Text(label),
    ],
  );

  Widget _catalog(BuildContext context, AppController controller) {
    final strings = AppLocalizations.of(context);
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
            labelText: strings.searchProductsOrIngredients,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: strings.clearSearch,
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'active', label: Text(strings.active)),
                ButtonSegment(value: 'inactive', label: Text(strings.paused)),
                ButtonSegment(value: 'all', label: Text(strings.all)),
              ],
              selected: {_catalogFilter},
              onSelectionChanged: (value) =>
                  setState(() => _catalogFilter = value.first),
            ),
            const Spacer(),
            IconButton.filled(
              tooltip: strings.addSupplement,
              onPressed: () => showAddSupplementDialog(context, controller),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (products.isEmpty)
          EmptyState(
            icon: Icons.search_off,
            title: strings.noMatchingSupplements,
            message: strings.changeFilterOrAddProduct,
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
    final strings = AppLocalizations.of(context);
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
            '${strings.formatNumber(stock)} ${product.stockUnit}',
            strings.scheduleCount(productSchedules.length),
          ].join(' · '),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) =>
              _productAction(context, controller, product, value),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'log', child: Text(strings.logIntake)),
            PopupMenuItem(value: 'schedule', child: Text(strings.addSchedule)),
            PopupMenuItem(value: 'stock', child: Text(strings.adjustStock)),
            PopupMenuItem(value: 'edit', child: Text(strings.editProduct)),
            PopupMenuItem(
              value: 'toggle',
              child: Text(
                product.active ? strings.pauseProduct : strings.reactivate,
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'delete', child: Text(strings.delete)),
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
                '${strings.formatNumber(schedule.dose)} ${schedule.unit} · ${schedule.timeOfDay}',
              ),
              subtitle: Text(
                '${strings.daysPerWeek(schedule.weekdays.length)}'
                '${schedule.instructions.isEmpty ? '' : ' · ${schedule.instructions}'}',
              ),
              onTap: () => showAddScheduleDialog(
                context,
                controller,
                product,
                existing: schedule,
              ),
              trailing: IconButton(
                tooltip: strings.deleteSchedule,
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
        final strings = AppLocalizations.of(context);
        final confirmed = await showConfirmAction(
          context,
          title: strings.deleteProductTitle(product.name),
          message: strings.deleteProductDescription,
          confirmLabel: strings.delete,
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
    final strings = AppLocalizations.of(context);
    final confirmed = await showConfirmAction(
      context,
      title: strings.deleteScheduleTitle,
      message: strings.pastIntakeRecordsKept,
      confirmLabel: strings.delete,
      destructive: true,
    );
    if (confirmed) await controller.deleteSchedule(schedule);
  }

  Widget _stock(BuildContext context, AppController controller) {
    final strings = AppLocalizations.of(context);
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
                label: strings.lowStock,
                value: strings.formatNumber(
                  projections.where((item) => item.low).length.toDouble(),
                  decimalDigits: 0,
                ),
                icon: Icons.inventory_outlined,
                detail: strings.householdCatalog,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                label: strings.plannedMonthlyCost,
                value: strings.formatEur(monthlyCost, decimalDigits: 0),
                icon: Icons.euro_outlined,
                detail: strings.knownPackagePrices,
              ),
            ),
          ],
        ),
        SectionHeader(
          title: strings.householdStock,
          subtitle: strings.stockProjectionDescription,
        ),
        if (projections.isEmpty)
          EmptyState(
            icon: Icons.inventory_2_outlined,
            title: strings.noStockToManage,
            message: strings.addSupplementAndContainerCount,
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
                    '${strings.formatNumber(projection.unitsOnHand)} ${projection.supplement.stockUnit}',
                    if (projection.daysRemaining != null)
                      strings.daysProjected(
                        projection.daysRemaining!.clamp(0, 9999).round(),
                      )
                    else
                      strings.noCompatibleHouseholdSchedule,
                    if (projection.low && projection.suggestedPurchaseUnits > 0)
                      strings.buyForWeeks(
                        projection.suggestedPurchaseUnits.round(),
                        12,
                      ),
                  ].join(' · '),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => showAdjustStockDialog(
                    context,
                    controller,
                    projection.supplement,
                    purchase: true,
                  ),
                  child: Text(strings.purchase),
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
    final strings = AppLocalizations.of(context);
    final profileId = controller.activeProfile?.id;
    if (profileId != null && profileId != _historyPinsProfileId) {
      _loadHistoryPins(profileId);
    }
    final window = _historyWindow(controller);
    final weekly = _insights.weeklyAdherence(
      from: window.$1,
      through: window.$2,
      schedules: controller.schedules,
      supplements: controller.supplements,
      intakes: controller.intakes,
    );
    final exposures = _insights.supplementExposure(
      intakes: controller.intakes,
      supplements: controller.supplements,
      from: window.$1,
      through: window.$2,
    );
    final ingredients = _insights.ingredientExposure(
      intakes: controller.intakes,
      from: window.$1,
      to: window.$2,
    );
    final cost = _insights.actualIntakeCost(
      intakes: controller.intakes,
      supplements: controller.supplements,
      from: window.$1,
      through: window.$2,
    );
    final query = _historySearch.text.trim().toLowerCase();
    final filteredExposures =
        exposures
            .where(
              (item) =>
                  query.isEmpty ||
                  item.name.toLowerCase().contains(query) ||
                  item.unit.toLowerCase().contains(query),
            )
            .toList()
          ..sort(
            (a, b) => _comparePinned(
              _supplementPinKey(a),
              _supplementPinKey(b),
              a.name,
              b.name,
            ),
          );
    final filteredIngredients =
        ingredients
            .where(
              (item) =>
                  query.isEmpty ||
                  item.name.toLowerCase().contains(query) ||
                  item.unit.toLowerCase().contains(query),
            )
            .toList()
          ..sort(
            (a, b) => _comparePinned(
              _ingredientPinKey(a),
              _ingredientPinKey(b),
              a.name,
              b.name,
            ),
          );
    if (profileId != null && _historyPinsProfileId == profileId) {
      final allRange = _insights.historyRange(
        selection: 'all',
        now: DateTime.now(),
        historyDates: controller.intakes
            .where((item) => !item.deleted)
            .map((item) => item.takenAt),
      );
      final existingPins = <String>{
        for (final item in _insights.supplementExposure(
          intakes: controller.intakes,
          supplements: controller.supplements,
          from: allRange.from,
          through: allRange.through,
        ))
          _supplementPinKey(item),
        for (final item in _insights.ingredientExposure(
          intakes: controller.intakes,
          from: allRange.from,
          to: allRange.through,
        ))
          _ingredientPinKey(item),
      };
      if (_historyPins.any((item) => !existingPins.contains(item))) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _pruneHistoryPins(profileId, existingPins),
        );
      }
    }
    final history =
        controller.intakes
            .where(
              (item) =>
                  !item.deleted &&
                  _withinWindow(item.takenAt, window.$1, window.$2) &&
                  (query.isEmpty ||
                      item.unit.toLowerCase().contains(query) ||
                      (controller.supplements
                              .firstWhereOrNull(
                                (product) => product.id == item.supplementId,
                              )
                              ?.name
                              .toLowerCase()
                              .contains(query) ??
                          false)),
            )
            .toList()
          ..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final eventContext =
        controller.events
            .where(
              (item) =>
                  !item.deleted &&
                  _withinWindow(item.observedAt, window.$1, window.$2),
            )
            .toList()
          ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    final visibleHistory = history.take(_historyVisible).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 110),
      children: [
        SectionHeader(
          title: strings.historyAnalytics,
          subtitle:
              '${strings.formatHistoryDate(window.$1)} – ${strings.formatHistoryDate(window.$2)}',
        ),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: '30',
              label: Text(strings.historyRangeDays(30)),
            ),
            ButtonSegment(
              value: '90',
              label: Text(strings.historyRangeDays(90)),
            ),
            ButtonSegment(
              value: '365',
              label: Text(strings.historyRangeDays(365)),
            ),
            ButtonSegment(value: 'all', label: Text(strings.all)),
          ],
          selected: {_historyRange},
          showSelectedIcon: false,
          onSelectionChanged: (value) => setState(() {
            _historyRange = value.first;
            _historyVisible = 50;
          }),
        ),
        SectionHeader(
          title: strings.weeklyAdherence,
          subtitle: strings.weeklyAdherenceDescription,
        ),
        _weeklyAdherenceCard(context, weekly),
        const SizedBox(height: 12),
        TextField(
          controller: _historySearch,
          onChanged: (_) => setState(() => _historyVisible = 50),
          decoration: InputDecoration(
            labelText: strings.filterSupplementsAndIngredients,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _historySearch.text.isEmpty
                ? null
                : IconButton(
                    tooltip: strings.clearFilter,
                    onPressed: () => setState(() {
                      _historySearch.clear();
                      _historyVisible = 50;
                    }),
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
        SectionHeader(
          title: strings.supplementExposure,
          subtitle: strings.supplementExposureDescription,
        ),
        if (filteredExposures.isEmpty)
          EmptyState(
            icon: Icons.medication_outlined,
            title: strings.noSupplementExposure,
            message: strings.logNonSkippedIntake,
          )
        else
          Card(
            child: Column(
              children: [
                for (final item in filteredExposures)
                  _exposureTile(
                    context,
                    title: item.name,
                    total: item.total,
                    unit: item.unit,
                    detail: strings.intakeCount(item.intakeCount),
                    pinKey: _supplementPinKey(item),
                  ),
              ],
            ),
          ),
        SectionHeader(
          title: strings.ingredientExposure,
          subtitle: strings.ingredientExposureDescription,
        ),
        if (filteredIngredients.isEmpty)
          EmptyState(
            icon: Icons.science_outlined,
            title: strings.noIngredientTotals,
            message: strings.addIngredientsAndIntakes,
          )
        else
          Card(
            child: Column(
              children: [
                for (final item in filteredIngredients)
                  _exposureTile(
                    context,
                    title: item.name,
                    total: item.total,
                    unit: item.unit,
                    detail: strings.ingredientSnapshot,
                    pinKey: _ingredientPinKey(item),
                  ),
              ],
            ),
          ),
        SectionHeader(
          title: strings.knownIntakeCost,
          subtitle: strings.knownIntakeCostDescription,
        ),
        _costCard(context, cost),
        SectionHeader(
          title: strings.temporalContext,
          subtitle: strings.temporalContextDescription,
        ),
        if (eventContext.isEmpty)
          EmptyState(
            icon: Icons.event_note_outlined,
            title: strings.noSymptomOrTagEvents,
            message: strings.eventsShownAlongsideHistory,
          )
        else
          Card(
            child: Column(
              children: [
                for (final event in eventContext)
                  ListTile(
                    leading: Icon(
                      event.kind == EventKind.symptom
                          ? Icons.monitor_heart_outlined
                          : Icons.sell_outlined,
                    ),
                    title: Text(event.name),
                    subtitle: Text(_eventLabel(event, strings)),
                  ),
              ],
            ),
          ),
        SectionHeader(
          title: strings.intakeHistory,
          subtitle: strings.intakeHistoryDescription,
        ),
        if (history.isEmpty)
          EmptyState(
            icon: Icons.history,
            title: strings.noIntakeHistory,
            message: strings.intakeHistoryEmptyDescription,
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final intake in visibleHistory)
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
                          strings.deletedSupplement,
                    ),
                    subtitle: Text(
                      '${strings.formatNumber(intake.dose)} ${intake.unit} · '
                      '${strings.formatTrackingDateTime(intake.takenAt)}'
                      '${intake.notes.isEmpty ? '' : ' · ${intake.notes}'}',
                    ),
                    trailing: IconButton(
                      tooltip: strings.delete,
                      onPressed: () =>
                          _deleteHistoryIntake(context, controller, intake),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                if (visibleHistory.length < history.length)
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _historyVisible += 50),
                      icon: const Icon(Icons.expand_more),
                      label: Text(
                        strings.showMoreHistory(
                          history.length - visibleHistory.length,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  (DateTime, DateTime) _historyWindow(AppController controller) {
    final now = DateTime.now();
    final dates = [
      ...controller.intakes
          .where((item) => !item.deleted)
          .map((item) => item.takenAt),
      ...controller.events
          .where((item) => !item.deleted)
          .map((item) => item.observedAt),
    ];
    final range = _insights.historyRange(
      selection: _historyRange,
      now: now,
      historyDates: dates,
    );
    return (range.from, range.through);
  }

  Widget _weeklyAdherenceCard(
    BuildContext context,
    List<WeeklyAdherence> values,
  ) {
    final strings = AppLocalizations.of(context);
    if (values.isEmpty || values.every((item) => item.scheduled == 0)) {
      return EmptyState(
        icon: Icons.calendar_today_outlined,
        title: strings.noDueScheduledDoses,
        message: strings.futureDosesExcluded,
      );
    }
    final maximum = values.fold<int>(
      1,
      (value, item) => item.scheduled > value ? item.scheduled : value,
    );
    return Card(
      child: Column(
        children: [
          for (final value in values)
            Semantics(
              label: strings.weeklyAdherenceSemantic(
                value.weekStarting,
                value.taken,
                value.skipped,
                value.missed,
                value.scheduled,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 84,
                          child: Text(
                            strings.formatShortDate(value.weekStarting),
                          ),
                        ),
                        Expanded(
                          child: _stackedAdherenceBar(context, value, maximum),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 84, top: 4),
                      child: Text(
                        strings.weeklyAdherenceSummary(
                          value.taken,
                          value.skipped,
                          value.missed,
                          value.scheduled,
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stackedAdherenceBar(
    BuildContext context,
    WeeklyAdherence value,
    int maximum,
  ) {
    final colors = Theme.of(context).colorScheme;
    Widget segment(int count, Color color) => count == 0
        ? const SizedBox.shrink()
        : Expanded(
            flex: count,
            child: Container(height: 12, color: color),
          );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          segment(value.taken, colors.primary),
          segment(value.skipped, colors.outline),
          segment(value.missed, colors.error),
          segment(maximum - value.scheduled, colors.surfaceContainerHighest),
        ],
      ),
    );
  }

  Widget _exposureTile(
    BuildContext context, {
    required String title,
    required double total,
    required String unit,
    required String detail,
    required String pinKey,
  }) {
    final strings = AppLocalizations.of(context);
    final pinned =
        _historyPinsProfileId ==
            context.read<AppController>().activeProfile?.id &&
        _historyPins.contains(pinKey);
    return ListTile(
      leading: Icon(pinned ? Icons.push_pin : Icons.medication_outlined),
      title: Text(title),
      subtitle: Text(detail),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${strings.formatNumber(total)} $unit'),
          IconButton(
            tooltip: pinned
                ? strings.unpinComparisonSeries
                : strings.pinComparisonSeries,
            onPressed: () => _toggleHistoryPin(pinKey),
            icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
          ),
        ],
      ),
    );
  }

  Widget _costCard(BuildContext context, IntakeCostInsight value) {
    final strings = AppLocalizations.of(context);
    final color = Theme.of(context).colorScheme;
    final maximum = value.daily.fold<double>(
      0,
      (total, item) => item.knownEur > total ? item.knownEur : total,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.knownSubtotal(value.knownEur),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              strings.knownCostCoverage(
                value.knownIntakes,
                value.eligibleIntakes,
              ),
            ),
            if (!value.completeCoverage) ...[
              const SizedBox(height: 6),
              Text(
                strings.unknownCostDescription(value.unknownIntakes),
                style: TextStyle(color: color.error),
              ),
            ],
            if (value.daily.isNotEmpty) ...[
              const SizedBox(height: 12),
              Semantics(
                label: strings.dailyKnownCostsSemantic(
                  value.daily.map((item) => (item.day, item.knownEur)),
                ),
                child: SizedBox(
                  height: 52,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final item in value.daily)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1),
                            child: Tooltip(
                              message: strings.dailyKnownCostTooltip(
                                item.day,
                                item.knownEur,
                              ),
                              child: Container(
                                height: maximum == 0
                                    ? 0
                                    : 48 * item.knownEur / maximum,
                                color: color.primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _loadHistoryPins(String profileId) async {
    if (_historyPinsLoading) return;
    _historyPinsLoading = true;
    final preferences = await SharedPreferences.getInstance();
    final stored = preferences.getStringList(
      _historyPinPreferenceKey(profileId),
    );
    if (!mounted) return;
    setState(() {
      _historyPinsProfileId = profileId;
      _historyPins = {...?stored};
      _historyPinsLoading = false;
    });
  }

  Future<void> _toggleHistoryPin(String pinKey) async {
    final profileId = context.read<AppController>().activeProfile?.id;
    if (profileId == null) return;
    final next = {..._historyPins};
    if (!next.add(pinKey)) next.remove(pinKey);
    setState(() {
      _historyPinsProfileId = profileId;
      _historyPins = next;
    });
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _historyPinPreferenceKey(profileId),
      next.toList()..sort(),
    );
  }

  Future<void> _pruneHistoryPins(
    String profileId,
    Set<String> existingPins,
  ) async {
    if (!mounted || _historyPinsProfileId != profileId) return;
    final next = _historyPins.intersection(existingPins);
    if (next.length == _historyPins.length) return;
    setState(() => _historyPins = next);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _historyPinPreferenceKey(profileId),
      next.toList()..sort(),
    );
  }

  String _historyPinPreferenceKey(String profileId) =>
      'supplement_history_pins_v1_$profileId';

  String _supplementPinKey(SupplementExposure item) =>
      'supplement|${item.seriesKey}';

  String _ingredientPinKey(IngredientExposure item) =>
      'ingredient|${item.name.trim().toLowerCase()}|${item.unit.trim().toLowerCase()}';

  int _comparePinned(String aKey, String bKey, String aName, String bName) {
    final aPinned = _historyPins.contains(aKey);
    final bPinned = _historyPins.contains(bKey);
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    return aName.toLowerCase().compareTo(bName.toLowerCase());
  }

  String _eventLabel(HealthEvent event, AppLocalizations strings) {
    final details = <String>[
      strings.formatTrackingDateTime(event.observedAt),
      if (event.score != null) strings.eventScore(event.score!),
      if (event.numericValue != null)
        '${strings.formatNumber(event.numericValue!)} ${event.unit ?? ''}'
            .trim(),
      if (event.notes.isNotEmpty) event.notes,
    ];
    return details.join(' · ');
  }

  bool _withinWindow(DateTime value, DateTime from, DateTime through) {
    final day = DateTime(value.year, value.month, value.day);
    return !day.isBefore(DateTime(from.year, from.month, from.day)) &&
        !day.isAfter(DateTime(through.year, through.month, through.day));
  }

  Future<void> _deleteHistoryIntake(
    BuildContext context,
    AppController controller,
    SupplementIntake intake,
  ) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showConfirmAction(
      context,
      title: strings.deleteIntakeTitle,
      message: strings.deleteIntakeDescription,
      confirmLabel: strings.delete,
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
            ListTile(
              title: Text(AppLocalizations.of(context).chooseSupplement),
            ),
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
