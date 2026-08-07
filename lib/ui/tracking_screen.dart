import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/appearance_settings.dart';
import '../app/shell_navigation.dart';
import '../domain/entities.dart';
import '../reminders/reminder_planner.dart';
import 'charts.dart';
import 'common.dart';
import 'dashboard_screen.dart' show periodLabel;
import 'design.dart';
import 'dialogs.dart';

/// The supplements screen: the catalog, the weekly plan, stock, and history.
///
/// The day-by-day dosing workflow lives on Today, so this screen owns
/// everything about the products themselves.
class TrackingScreen extends StatefulWidget {
  const TrackingScreen({super.key});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with SingleTickerProviderStateMixin {
  static const _insights = SupplementInsights();
  static const _tabCount = 4;

  late final TabController _tabs = TabController(
    length: _tabCount,
    vsync: this,
  );
  final _search = TextEditingController();
  final _historySearch = TextEditingController();

  var _catalogFilter = 'active';
  var _historyRange = '90';
  var _historyVisible = 50;
  var _planMonths = 3;
  var _onlyLowStock = false;
  String? _historyPinsProfileId;
  var _historyPinsLoading = false;
  Set<String> _historyPins = <String>{};
  int? _handledRequestToken;

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    _historySearch.dispose();
    super.dispose();
  }

  /// Applies a pending deep link from a Today tile.
  void _applyRequest(ShellNavigation navigation) {
    final request = navigation.request;
    if (request == null || request.token == _handledRequestToken) return;
    final tab = supplementsTabForSection(request.section);
    if (tab == null) return;
    _handledRequestToken = request.token;
    final wantsLowStock = request.filter == SectionFilter.lowStock;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tabs.index = tab;
      if (wantsLowStock != _onlyLowStock) {
        setState(() => _onlyLowStock = wantsLowStock);
      }
      navigation.completeRequest(request.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final navigation = context.watch<ShellNavigation>();
    final strings = AppLocalizations.of(context);
    _applyRequest(navigation);
    return PageBody(
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(
                  icon: const Icon(Icons.medication_outlined),
                  text: strings.catalog,
                ),
                Tab(
                  icon: const Icon(Icons.calendar_view_week_outlined),
                  text: strings.pick('Plan', 'Plan'),
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
              controller: _tabs,
              children: [
                _catalog(context, controller),
                _weeklyPlan(context, controller),
                _stock(context, controller),
                _history(context, controller),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- catalog

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
    return RefreshIndicator(
      onRefresh: controller.refreshActiveData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: 'active',
                        label: Text(strings.active),
                      ),
                      ButtonSegment(
                        value: 'inactive',
                        label: Text(strings.paused),
                      ),
                      ButtonSegment(value: 'all', label: Text(strings.all)),
                    ],
                    selected: {_catalogFilter},
                    onSelectionChanged: (value) =>
                        setState(() => _catalogFilter = value.first),
                  ),
                ),
              ),
              const SizedBox(width: 8),
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
              action: FilledButton.tonalIcon(
                onPressed: () => showAddSupplementDialog(context, controller),
                icon: const Icon(Icons.add),
                label: Text(strings.addSupplement),
              ),
            )
          else
            for (final product in products)
              _productCard(context, controller, product),
        ],
      ),
    );
  }

  Widget _productCard(
    BuildContext context,
    AppController controller,
    Supplement product,
  ) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final stock = controller.stockLevels[product.id] ?? 0;
    final productSchedules = controller.schedules
        .where((item) => item.supplementId == product.id)
        .toList();
    final accent = seriesColorFor(
      product.name,
      colorMode: controller.colorMode,
    );
    // Days of cover is the number that decides whether to reorder, so it
    // belongs on the row rather than only in the stock tab.
    final projection = _insights
        .stockProjections(
          supplements: [product],
          householdSchedules: controller.householdSchedules,
          stockLevels: controller.stockLevels,
        )
        .firstOrNull;
    final daysRemaining = projection?.daysRemaining;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.18),
          child: Text(
            product.name.isEmpty ? '?' : product.name.characters.first,
            style: TextStyle(fontWeight: FontWeight.w700, color: accent),
          ),
        ),
        title: Text(product.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              [
                if (product.brand.isNotEmpty) product.brand,
                formatAmountWithUnit(
                  strings,
                  amount: stock,
                  unit: product.stockUnit,
                  form: product.form,
                ),
                strings.scheduleCount(productSchedules.length),
                if (!product.active) strings.paused,
              ].join(' · '),
            ),
            if (daysRemaining != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  // 90 days of cover fills the bar; past that the exact figure
                  // matters less than there being plenty.
                  value: (daysRemaining / 90).clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: colors.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                    projection!.low ? colors.error : colors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                strings.daysProjected(daysRemaining.clamp(0, 9999).round()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
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
                        visualDensity: VisualDensity.compact,
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
                color: schedule.active ? colors.primary : colors.outline,
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatAmountWithUnit(strings, amount: schedule.dose, unit: schedule.unit, form: product.form)} · '
                      '${schedule.timeOfDay}',
                    ),
                  ),
                  // Whether a schedule reminds is invisible until its dialog is
                  // opened, so a library of them cannot be checked at a glance
                  // and a forgotten switch reads as broken notifications.
                  _ScheduleReminderBadge(schedule: schedule),
                ],
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
          if (productSchedules.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () =>
                      showAddScheduleDialog(context, controller, product),
                  icon: const Icon(Icons.add),
                  label: Text(strings.addSchedule),
                ),
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

  // ------------------------------------------------------------ weekly plan

  /// The weekly pillbox: what to lay out for each day of the week.
  Widget _weeklyPlan(BuildContext context, AppController controller) {
    final strings = AppLocalizations.of(context);
    final scheduled =
        controller.supplements
            .where(
              (product) =>
                  !product.deleted &&
                  controller.schedules.any(
                    (schedule) =>
                        schedule.supplementId == product.id &&
                        schedule.active &&
                        !schedule.deleted &&
                        schedule.weekdays.isNotEmpty,
                  ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final plannedComponents = _insights.plannedWeeklyIngredients(
      supplements: controller.supplements,
      schedules: controller.schedules,
    );
    return RefreshIndicator(
      onRefresh: controller.refreshActiveData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        children: [
          SectionHeader(
            title: strings.pick('Weekly plan', 'Wochenplan'),
            subtitle: strings.pick(
              'What to lay out in a pill box for each day of the week.',
              'Was für jeden Wochentag in die Pillendose gehört.',
            ),
          ),
          if (scheduled.isEmpty)
            EmptyState(
              icon: Icons.calendar_view_week_outlined,
              title: strings.pick(
                'No weekly schedule yet',
                'Noch kein Wochenplan',
              ),
              message: strings.addScheduleFromCatalog,
              action: FilledButton.tonalIcon(
                onPressed: () => _tabs.index = 0,
                icon: const Icon(Icons.medication_outlined),
                label: Text(strings.catalog),
              ),
            )
          else
            for (final product in scheduled)
              _WeeklyPlanCard(
                product: product,
                schedules: controller.schedules
                    .where(
                      (item) =>
                          item.supplementId == product.id &&
                          item.active &&
                          !item.deleted,
                    )
                    .toList(),
                onEditSchedule: (schedule) => showAddScheduleDialog(
                  context,
                  controller,
                  product,
                  existing: schedule,
                ),
                colorMode: controller.colorMode,
              ),
          if (plannedComponents.isNotEmpty) ...[
            SectionHeader(
              title: strings.pick(
                'Planned components per week',
                'Geplante Komponenten pro Woche',
              ),
              subtitle: strings.pick(
                'What the active plan is designed to deliver, before adherence.',
                'Was der aktive Plan liefern soll, unabhängig von der Einnahme.',
              ),
            ),
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final item in plannedComponents.take(30))
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.science_outlined),
                      title: Text(item.name),
                      trailing: Text(
                        '${strings.formatNumber(item.total)} ${item.unit}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ stock

  Widget _stock(BuildContext context, AppController controller) {
    final strings = AppLocalizations.of(context);
    final allProjections = _insights.stockProjections(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
      stockLevels: controller.stockLevels,
    );
    final projections = _onlyLowStock
        ? allProjections.where((item) => item.low).toList()
        : allProjections;
    final costByProduct = _insights.monthlyCostByProduct(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
    );
    final monthlyCost = costByProduct.fold<double>(
      0,
      (total, item) => total + item.eur,
    );
    final plan = _insights.purchasePlan(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
      stockLevels: controller.stockLevels,
      months: _planMonths,
    );
    final toBuy = plan.where((item) => !item.covered).toList();
    final knownPlanCost = toBuy
        .map((item) => item.estimatedCostEur)
        .whereType<double>()
        .fold<double>(0, (sum, item) => sum + item);
    final unknownPlanPrices = toBuy
        .where((item) => item.estimatedCostEur == null)
        .length;

    return RefreshIndicator(
      onRefresh: controller.refreshActiveData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        children: [
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: strings.lowStock,
                  value: strings.formatNumber(
                    allProjections.where((item) => item.low).length.toDouble(),
                    decimalDigits: 0,
                  ),
                  icon: Icons.inventory_outlined,
                  detail: strings.householdCatalog,
                  tone: allProjections.any((item) => item.low)
                      ? Theme.of(context).colorScheme.error
                      : null,
                  onTap: () => setState(() => _onlyLowStock = !_onlyLowStock),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: strings.plannedMonthlyCost,
                  value: strings.formatEur(monthlyCost, decimalDigits: 0),
                  icon: Icons.euro_outlined,
                  detail: strings.knownPackagePrices,
                ),
              ),
            ],
          ),
          if (costByProduct.isNotEmpty)
            ChartCard(
              title: strings.plannedMonthlyCost,
              subtitle: strings.pick(
                'Per product, from package prices and the active plan.',
                'Pro Produkt, aus Packungspreisen und dem aktiven Plan.',
              ),
              child: Column(
                children: [
                  for (final item in costByProduct.take(10))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              item.supplement.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: costByProduct.first.eur <= 0
                                    ? 0
                                    : item.eur / costByProduct.first.eur,
                                minHeight: 10,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation(
                                  seriesColorFor(
                                    item.supplement.name,
                                    colorMode: controller.colorMode,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            strings.formatEur(item.eur),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          SectionHeader(
            title: strings.pick('Shopping list', 'Einkaufsliste'),
            subtitle: strings.pick(
              'Containers to buy so the plan is covered for the horizon below.',
              'Packungen, damit der Plan über den gewählten Zeitraum reicht.',
            ),
          ),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        strings.pick('Plan ahead', 'Vorausplanen'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        for (final months in [1, 3, 6, 12])
                          ButtonSegment(
                            value: months,
                            label: Text(
                              strings.pick('${months}m', '$months M'),
                            ),
                          ),
                      ],
                      selected: {_planMonths},
                      onSelectionChanged: (value) =>
                          setState(() => _planMonths = value.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (toBuy.isEmpty)
                  Text(
                    plan.isEmpty
                        ? strings.pick(
                            'Add a schedule and a package size to plan '
                                'purchases.',
                            'Lege Plan und Packungsgröße an, um Einkäufe zu '
                                'planen.',
                          )
                        : strings.pick(
                            'Nothing to buy for this horizon.',
                            'Für diesen Zeitraum ist nichts zu kaufen.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else ...[
                  for (final item in toBuy)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.shopping_cart_outlined),
                      title: Text(item.supplement.name),
                      subtitle: Text(
                        [
                          strings.pick(
                            'need ${formatAmountWithUnit(strings, amount: item.missingUnits, unit: item.supplement.stockUnit, form: item.supplement.form)}',
                            'Bedarf ${formatAmountWithUnit(strings, amount: item.missingUnits, unit: item.supplement.stockUnit, form: item.supplement.form)}',
                          ),
                          if (item.estimatedCostEur != null)
                            strings.formatEur(item.estimatedCostEur!),
                        ].join(' · '),
                      ),
                      trailing: Text(
                        item.containersToBuy == null
                            ? strings.pick('size?', 'Größe?')
                            : strings.pick(
                                '${item.containersToBuy}×',
                                '${item.containersToBuy}×',
                              ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  const Divider(),
                  Text(
                    unknownPlanPrices == 0
                        ? strings.pick(
                            'Estimated total ${strings.formatEur(knownPlanCost)}.',
                            'Geschätzte Summe ${strings.formatEur(knownPlanCost)}.',
                          )
                        : strings.pick(
                            'Known subtotal ${strings.formatEur(knownPlanCost)}; '
                                '$unknownPlanPrices product(s) have no price.',
                            'Bekannte Zwischensumme ${strings.formatEur(knownPlanCost)}; '
                                'für $unknownPlanPrices Produkt(e) fehlt der Preis.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          SectionHeader(
            title: strings.householdStock,
            subtitle: strings.stockProjectionDescription,
            action: _onlyLowStock
                ? TextButton.icon(
                    onPressed: () => setState(() => _onlyLowStock = false),
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: Text(strings.clearFilter),
                  )
                : null,
          ),
          if (projections.isEmpty)
            EmptyState(
              icon: Icons.inventory_2_outlined,
              title: _onlyLowStock
                  ? strings.pick(
                      'Nothing is running low',
                      'Nichts geht zur Neige',
                    )
                  : strings.noStockToManage,
              message: _onlyLowStock
                  ? strings.pick(
                      'Every tracked product has more than a month of cover.',
                      'Jedes erfasste Produkt reicht noch über einen Monat.',
                    )
                  : strings.addSupplementAndContainerCount,
            )
          else
            for (final projection in projections)
              SurfaceCard(
                padding: EdgeInsets.zero,
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
                      formatAmountWithUnit(
                        strings,
                        amount: projection.unitsOnHand,
                        unit: projection.supplement.stockUnit,
                        form: projection.supplement.form,
                      ),
                      if (projection.daysRemaining != null)
                        strings.daysProjected(
                          projection.daysRemaining!.clamp(0, 9999).round(),
                        )
                      else
                        strings.noCompatibleHouseholdSchedule,
                      if (projection.low &&
                          projection.suggestedPurchaseUnits > 0)
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
      ),
    );
  }

  // ---------------------------------------------------------------- history

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
      supplements: controller.supplements,
      from: window.$1,
      to: window.$2,
    );
    final cost = _insights.actualIntakeCost(
      intakes: controller.intakes,
      supplements: controller.supplements,
      from: window.$1,
      through: window.$2,
    );
    final weeks = _insights.weeksIn(from: window.$1, through: window.$2);
    final supplementSeries = _insights.weeklySupplementSeries(
      intakes: controller.intakes,
      supplements: controller.supplements,
      from: window.$1,
      through: window.$2,
    );
    final ingredientSeries = _insights.weeklyIngredientSeries(
      intakes: controller.intakes,
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
          supplements: controller.supplements,
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
    final visibleHistoryByDay = <DateTime, List<SupplementIntake>>{};
    for (final intake in visibleHistory) {
      final day = DateTime(
        intake.takenAt.year,
        intake.takenAt.month,
        intake.takenAt.day,
      );
      visibleHistoryByDay.putIfAbsent(day, () => []).add(intake);
    }

    // Charts only draw the pinned series, so a catalog of thirty products does
    // not turn into thirty overlapping lines.
    final pinnedSupplementSeries = _pinnedOrTop(
      supplementSeries,
      (item) => 'supplement|${item.key}',
    );
    final pinnedIngredientSeries = _pinnedOrTop(
      ingredientSeries,
      (item) => 'ingredient|${item.key}',
    );
    final supplementColors = seriesColors(
      pinnedSupplementSeries.map((item) => item.key),
      colorMode: controller.colorMode,
    );
    final ingredientColors = seriesColors(
      pinnedIngredientSeries.map((item) => item.key),
      colorMode: controller.colorMode,
    );

    return RefreshIndicator(
      onRefresh: controller.refreshActiveData,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
        children: [
          SectionHeader(
            title: strings.historyAnalytics,
            subtitle:
                '${strings.formatHistoryDate(window.$1)} – '
                '${strings.formatHistoryDate(window.$2)}',
            action: IconButton.outlined(
              tooltip: strings.pick('Export CSV', 'CSV exportieren'),
              onPressed: history.isEmpty
                  ? null
                  : () => _exportHistoryCsv(context, controller, history),
              icon: const Icon(Icons.table_view_outlined),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<String>(
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
          ),
          const SizedBox(height: 12),
          if (weekly.any((item) => item.scheduled > 0))
            ChartCard(
              title: strings.weeklyAdherence,
              subtitle: strings.weeklyAdherenceDescription,
              legend: SeriesLegend(
                entries: {
                  strings.taken: Theme.of(context).colorScheme.primary,
                  strings.skipped: Theme.of(context).colorScheme.outline,
                  strings.missed: Theme.of(context).colorScheme.error,
                },
              ),
              child: AdherenceChart(
                values: weekly,
                weekLabel: strings.formatShortDate,
                semanticLabel: weekly
                    .map(
                      (item) => strings.weeklyAdherenceSemantic(
                        item.weekStarting,
                        item.taken,
                        item.skipped,
                        item.missed,
                        item.scheduled,
                      ),
                    )
                    .join('. '),
              ),
            )
          else
            EmptyState(
              icon: Icons.calendar_today_outlined,
              title: strings.noDueScheduledDoses,
              message: strings.futureDosesExcluded,
            ),
          if (supplementSeries.isNotEmpty)
            ChartCard(
              title: strings.supplementExposure,
              subtitle: _seriesSubtitle(
                strings,
                shown: pinnedSupplementSeries.length,
                available: supplementSeries.length,
                pinned: supplementSeries.any(
                  (item) => _historyPins.contains('supplement|${item.key}'),
                ),
              ),
              trailing: TextButton.icon(
                onPressed: () => _chooseSeries(
                  context,
                  title: strings.supplementExposure,
                  series: supplementSeries,
                  pinKey: (item) => 'supplement|${item.key}',
                ),
                icon: const Icon(Icons.tune, size: 18),
                label: Text(strings.pick('Choose', 'Auswählen')),
              ),
              legend: SeriesLegend(
                entries: {
                  for (final item in pinnedSupplementSeries)
                    item.label: supplementColors[item.key]!,
                },
                onTap: (label) => _toggleHistoryPin(
                  'supplement|'
                  '${pinnedSupplementSeries.firstWhere((item) => item.label == label).key}',
                ),
              ),
              child: WeeklySeriesChart(
                weeks: weeks,
                series: pinnedSupplementSeries,
                colors: supplementColors,
                weekLabel: strings.formatShortDate,
                valueLabel: (value) => strings.formatNumber(value),
                semanticLabel: pinnedSupplementSeries
                    .map(
                      (item) =>
                          '${item.label}: ${strings.formatNumber(item.total)}',
                    )
                    .join('. '),
              ),
            ),
          if (ingredientSeries.isNotEmpty)
            ChartCard(
              title: strings.ingredientExposure,
              subtitle: _seriesSubtitle(
                strings,
                shown: pinnedIngredientSeries.length,
                available: ingredientSeries.length,
                pinned: ingredientSeries.any(
                  (item) => _historyPins.contains('ingredient|${item.key}'),
                ),
              ),
              trailing: TextButton.icon(
                onPressed: () => _chooseSeries(
                  context,
                  title: strings.ingredientExposure,
                  series: ingredientSeries,
                  pinKey: (item) => 'ingredient|${item.key}',
                ),
                icon: const Icon(Icons.tune, size: 18),
                label: Text(strings.pick('Choose', 'Auswählen')),
              ),
              legend: SeriesLegend(
                entries: {
                  for (final item in pinnedIngredientSeries)
                    item.label: ingredientColors[item.key]!,
                },
                onTap: (label) => _toggleHistoryPin(
                  'ingredient|'
                  '${pinnedIngredientSeries.firstWhere((item) => item.label == label).key}',
                ),
              ),
              child: WeeklySeriesChart(
                weeks: weeks,
                series: pinnedIngredientSeries,
                colors: ingredientColors,
                weekLabel: strings.formatShortDate,
                valueLabel: (value) => strings.formatNumber(value),
                semanticLabel: pinnedIngredientSeries
                    .map(
                      (item) =>
                          '${item.label}: ${strings.formatNumber(item.total)}',
                    )
                    .join('. '),
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
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final day in visibleHistoryByDay.entries) ...[
                    ListTile(
                      dense: true,
                      tileColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      title: Text(
                        strings.formatTrackingDate(day.key),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      trailing: Text(
                        strings.intakeCount(day.value.length),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    for (final intake in day.value)
                      _historyIntakeTile(context, controller, intake),
                  ],
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
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final item in filteredExposures)
                    _exposureTile(
                      context,
                      title: item.name,
                      total: item.total,
                      unit: item.unit,
                      form: controller.supplements
                          .firstWhereOrNull(
                            (product) => product.id == item.supplementId,
                          )
                          ?.form,
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
            SurfaceCard(
              padding: EdgeInsets.zero,
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
            SurfaceCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final event in eventContext.take(40))
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
        ],
      ),
    );
  }

  /// Explains what the chart is currently drawing.
  String _seriesSubtitle(
    AppLocalizations strings, {
    required int shown,
    required int available,
    required bool pinned,
  }) => pinned
      ? strings.pick(
          'Weekly totals for $shown of $available selected.',
          'Wochensummen für $shown von $available ausgewählten.',
        )
      : strings.pick(
          'Weekly totals for the $shown largest of $available. Choose to pick '
              'your own.',
          'Wochensummen der $shown größten von $available. Wähle eigene aus.',
        );

  /// Picks which series the chart draws.
  ///
  /// Writes to the same pins the exposure lists below use, so a series pinned
  /// here shows as pinned there and the two never disagree.
  Future<void> _chooseSeries(
    BuildContext context, {
    required String title,
    required List<ExposureSeries> series,
    required String Function(ExposureSeries item) pinKey,
  }) async {
    final strings = AppLocalizations.of(context);
    final ordered = [...series]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.8,
        child: StatefulBuilder(
          builder: (builderContext, setSheetState) {
            final selected = ordered
                .where((item) => _historyPins.contains(pinKey(item)))
                .length;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(builderContext).textTheme.titleLarge,
                      ),
                      Text(
                        selected == 0
                            ? strings.pick(
                                'Nothing selected — the chart shows the '
                                    'largest series.',
                                'Nichts ausgewählt — das Diagramm zeigt die '
                                    'größten Reihen.',
                              )
                            : strings.pick(
                                '$selected selected',
                                '$selected ausgewählt',
                              ),
                        style: Theme.of(builderContext).textTheme.bodySmall
                            ?.copyWith(
                              color: Theme.of(
                                builderContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                    children: [
                      for (final item in ordered)
                        CheckboxListTile(
                          value: _historyPins.contains(pinKey(item)),
                          title: Text(item.name),
                          subtitle: Text(
                            '${strings.formatNumber(item.total)} ${item.unit}',
                          ),
                          onChanged: (_) async {
                            await _toggleHistoryPin(pinKey(item));
                            setSheetState(() {});
                          },
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: selected == 0
                              ? null
                              : () async {
                                  await _clearHistoryPins(
                                    ordered.map(pinKey).toSet(),
                                  );
                                  setSheetState(() {});
                                },
                          child: Text(strings.pick('Clear', 'Zurücksetzen')),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: Text(strings.pick('Done', 'Fertig')),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Pinned series if any are pinned, otherwise the six largest.
  List<ExposureSeries> _pinnedOrTop(
    List<ExposureSeries> series,
    String Function(ExposureSeries item) pinKey,
  ) {
    final pinned = series
        .where((item) => _historyPins.contains(pinKey(item)))
        .toList();
    // An explicit choice is drawn in full. Only the unselected default is
    // capped, so a large catalog does not open as an unreadable tangle.
    return pinned.isNotEmpty ? pinned : series.take(6).toList();
  }

  Future<void> _exportHistoryCsv(
    BuildContext context,
    AppController controller,
    List<SupplementIntake> history,
  ) async {
    final strings = AppLocalizations.of(context);
    final names = {
      for (final item in controller.supplements) item.id: item.name,
    };
    final rows = <List<Object?>>[
      ['taken_at', 'supplement', 'dose', 'unit', 'skipped', 'notes'],
      for (final intake in history)
        [
          intake.takenAt.toIso8601String(),
          names[intake.supplementId] ?? '',
          intake.dose,
          intake.unit,
          intake.skipped,
          intake.notes,
        ],
    ];
    final bytes = Uint8List.fromList(
      utf8.encode(const ListToCsvConverter().convert(rows)),
    );
    final fileName =
        'superhealth-intake-history-'
        '${DateTime.now().toIso8601String().split('T').first}.csv';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: strings.pick('Save $fileName', '$fileName speichern'),
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        bytes: bytes,
      );
      if (path == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.pick('CSV saved.', 'CSV gespeichert.'))),
      );
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  Widget _historyIntakeTile(
    BuildContext context,
    AppController controller,
    SupplementIntake intake,
  ) {
    final strings = AppLocalizations.of(context);
    final supplement = controller.supplements.firstWhereOrNull(
      (item) => item.id == intake.supplementId,
    );
    return ListTile(
      leading: Icon(
        intake.skipped ? Icons.close : Icons.check,
        color: intake.skipped
            ? Theme.of(context).colorScheme.outline
            : Theme.of(context).colorScheme.primary,
      ),
      title: Text(supplement?.name ?? strings.deletedSupplement),
      subtitle: Text(
        '${formatAmountWithUnit(strings, amount: intake.dose, unit: intake.unit, form: supplement?.form)} · '
        '${strings.formatTrackingDateTime(intake.takenAt)}'
        '${intake.notes.isEmpty ? '' : ' · ${intake.notes}'}',
      ),
      onTap: supplement == null
          ? null
          : () => showLogIntakeDialog(
              context,
              controller,
              supplement,
              existing: intake,
            ),
      trailing: Wrap(
        spacing: 0,
        children: [
          IconButton(
            tooltip: strings.edit,
            onPressed: supplement == null
                ? null
                : () => showLogIntakeDialog(
                    context,
                    controller,
                    supplement,
                    existing: intake,
                  ),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: strings.delete,
            onPressed: () => _deleteHistoryIntake(context, controller, intake),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
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

  Widget _exposureTile(
    BuildContext context, {
    required String title,
    required double total,
    required String unit,
    required String detail,
    required String pinKey,
    String? form,
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
          Text(
            formatAmountWithUnit(
              strings,
              amount: total,
              unit: unit,
              form: form,
            ),
          ),
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
    return SurfaceCard(
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
            const SizedBox(height: 14),
            DailyValueChart(
              points: [
                for (final item in value.daily)
                  (day: item.day, value: item.knownEur),
              ],
              dayLabel: strings.formatShortDate,
              valueLabel: strings.formatEur,
              semanticLabel: strings.dailyKnownCostsSemantic(
                value.daily.map((item) => (item.day, item.knownEur)),
              ),
            ),
          ],
        ],
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

  Future<void> _clearHistoryPins(Set<String> keys) async {
    final profileId = context.read<AppController>().activeProfile?.id;
    if (profileId == null) return;
    final next = _historyPins.difference(keys);
    setState(() => _historyPins = next);
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
}

/// One product's week: a dose count per weekday and part of the day.
class _WeeklyPlanCard extends StatelessWidget {
  const _WeeklyPlanCard({
    required this.product,
    required this.schedules,
    required this.onEditSchedule,
    required this.colorMode,
  });

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  final Supplement product;
  final List<SupplementSchedule> schedules;
  final ValueChanged<SupplementSchedule> onEditSchedule;
  final AppColorMode colorMode;

  @override
  Widget build(BuildContext context) {
    const insights = SupplementInsights();
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final accent = seriesColorFor(product.name, colorMode: colorMode);

    // Sum the dose per weekday and block, and remember one schedule per cell so
    // tapping a filled cell opens the plan that produced it.
    final totals = <(DosePeriod, int), double>{};
    final owners = <(DosePeriod, int), SupplementSchedule>{};
    final units = <String>{};
    for (final schedule in schedules) {
      final period =
          insights.periodOfSlot(schedule.timeOfDay) ??
          insights.periodOfHour(
            int.tryParse(schedule.timeOfDay.split(':').first.trim()) ?? 12,
          );
      units.add(schedule.unit.trim());
      for (final weekday in schedule.weekdays) {
        final index = _weekdays.indexOf(weekday);
        if (index < 0) continue;
        final cell = (period, index);
        totals[cell] = (totals[cell] ?? 0) + schedule.dose;
        owners[cell] ??= schedule;
      }
    }
    final blocks = DosePeriod.values
        .where((period) => totals.keys.any((cell) => cell.$1 == period))
        .toList();
    if (blocks.isEmpty) return const SizedBox.shrink();

    // A reference Monday, used only to render localized weekday initials.
    final today = DateTime.now();
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  product.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                units.length == 1
                    ? unitLabel(strings, unit: units.first, form: product.form)
                    : strings.pick('mixed', 'gemischt'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 64),
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: Center(
                    child: Text(
                      strings
                          .formatTrackingWeekday(
                            monday.add(Duration(days: index)),
                          )
                          .substring(0, 2)
                          .toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (final period in blocks) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 64,
                  child: Text(
                    periodLabel(strings, period),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                for (var index = 0; index < 7; index++)
                  Expanded(
                    child: _PlanCell(
                      dose: totals[(period, index)],
                      accent: accent,
                      label: totals[(period, index)] == null
                          ? null
                          : strings.formatNumber(totals[(period, index)]!),
                      semanticLabel:
                          '${product.name}, '
                          '${periodLabel(strings, period)}, '
                          '${strings.formatTrackingWeekday(monday.add(Duration(days: index)))}: '
                          '${totals[(period, index)] == null ? '—' : strings.formatNumber(totals[(period, index)]!)}',
                      onTap: owners[(period, index)] == null
                          ? null
                          : () => onEditSchedule(owners[(period, index)]!),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCell extends StatelessWidget {
  const _PlanCell({
    required this.dose,
    required this.accent,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final double? dose;
  final Color accent;
  final String? label;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final filled = dose != null && dose! > 0;
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Material(
          color: filled ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Ink(
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: filled
                    ? null
                    : Border.all(color: colors.outlineVariant),
              ),
              child: Center(
                child: filled
                    ? Text(
                        label!,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: onSeriesColor(accent),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Says at a glance whether a schedule reminds, and whether it actually can.
///
/// The third state is the one that matters: a reminder switched on against a
/// time the planner cannot read produces nothing and, before this, said
/// nothing either.
class _ScheduleReminderBadge extends StatelessWidget {
  const _ScheduleReminderBadge({required this.schedule});

  final SupplementSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    if (!schedule.reminderEnabled) {
      return Tooltip(
        message: strings.pick('No reminder', 'Keine Erinnerung'),
        child: Icon(
          Icons.notifications_off_outlined,
          size: 18,
          color: colors.outline,
        ),
      );
    }
    if (!ReminderPlanner.canScheduleReminder(schedule.timeOfDay)) {
      return Tooltip(
        message: strings.pick(
          'Reminder is on, but "\${schedule.timeOfDay}" is not a time this app '
              'can schedule. Use Morning, Midday, Evening, Bedtime or HH:mm.',
          'Erinnerung ist aktiv, aber „\${schedule.timeOfDay}" ist keine Zeit, '
              'die diese App planen kann. Nutze Morning, Midday, Evening, '
              'Bedtime oder HH:mm.',
        ),
        child: Icon(
          Icons.notification_important_outlined,
          size: 18,
          color: colors.error,
        ),
      );
    }
    return Tooltip(
      message: strings.pick('Reminder is on', 'Erinnerung ist aktiv'),
      child: Icon(
        Icons.notifications_active_outlined,
        size: 18,
        color: colors.primary,
      ),
    );
  }
}
