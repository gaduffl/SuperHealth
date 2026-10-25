import 'package:flutter/material.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'design.dart';

/// Stock and its filter stay together so a tap changes the visible list.
class SupplementStockSection extends StatelessWidget {
  const SupplementStockSection({
    required this.allProjections,
    required this.onlyLowStock,
    required this.onLowStockChanged,
    required this.monthlyCost,
    required this.householdMonthlyCost,
    required this.onPurchase,
    required this.onAdjustStock,
    super.key,
  });

  final List<StockProjection> allProjections;
  final bool onlyLowStock;
  final ValueChanged<bool> onLowStockChanged;
  final double monthlyCost;
  final bool householdMonthlyCost;
  final ValueChanged<Supplement> onPurchase;
  final ValueChanged<Supplement> onAdjustStock;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final projections = onlyLowStock
        ? allProjections.where((item) => item.low).toList()
        : allProjections;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: StatTile(
                  label: strings.lowStock,
                  value: strings.formatNumber(
                    allProjections.where((item) => item.low).length.toDouble(),
                    decimalDigits: 0,
                  ),
                  icon: Icons.inventory_outlined,
                  selected: onlyLowStock,
                  detail: onlyLowStock
                      ? strings.pick('Low stock only', 'Nur niedriger Bestand')
                      : strings.householdCatalog,
                  tone: allProjections.any((item) => item.low)
                      ? Theme.of(context).colorScheme.error
                      : null,
                  onTap: () => onLowStockChanged(!onlyLowStock),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  label: strings.plannedMonthlyCost,
                  value: strings.formatEur(monthlyCost, decimalDigits: 0),
                  icon: Icons.euro_outlined,
                  detail: householdMonthlyCost
                      ? strings.pick('Household', 'Haushalt')
                      : strings.pick('Personal', 'Persönlich'),
                ),
              ),
            ],
          ),
        ),
        SectionHeader(
          title: onlyLowStock ? strings.lowStock : strings.householdStock,
          subtitle: strings.stockProjectionDescription,
          action: onlyLowStock
              ? TextButton.icon(
                  onPressed: () => onLowStockChanged(false),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(strings.clearFilter),
                )
              : null,
        ),
        if (projections.isEmpty)
          EmptyState(
            icon: Icons.inventory_2_outlined,
            title: onlyLowStock
                ? strings.pick(
                    'Nothing is running low',
                    'Nichts geht zur Neige',
                  )
                : strings.noStockToManage,
            message: onlyLowStock
                ? strings.pick(
                    'No products meet their low-stock alert criteria.',
                    'Kein Produkt erfüllt die Kriterien für eine Bestandswarnung.',
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
                    if (projection.low && projection.suggestedPurchaseUnits > 0)
                      strings.buyForWeeks(
                        projection.suggestedPurchaseUnits.round(),
                        12,
                      ),
                  ].join(' · '),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => onPurchase(projection.supplement),
                  child: Text(strings.purchase),
                ),
                onTap: () => onAdjustStock(projection.supplement),
              ),
            ),
      ],
    );
  }
}
