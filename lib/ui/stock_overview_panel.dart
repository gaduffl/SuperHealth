import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../analysis/supplement_insights.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/shell_navigation.dart';
import 'common.dart';
import 'design.dart';

/// The at-a-glance stock drawer.
///
/// Ports the Supplement Manager stock sidebar: every product with a household
/// schedule, ordered so the ones about to run out are read first.
class StockOverviewPanel extends StatelessWidget {
  const StockOverviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    const insights = SupplementInsights();
    final projections = insights.stockProjections(
      supplements: controller.supplements,
      householdSchedules: controller.householdSchedules,
      stockLevels: controller.stockLevels,
    );
    final tracked = projections
        .where((item) => item.daysRemaining != null)
        .toList();
    final untracked = projections
        .where((item) => item.daysRemaining == null)
        .toList();
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.pick('Stock overview', 'Bestandsübersicht'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      strings.pick(
                        'Projected from every schedule in this household.',
                        'Hochgerechnet aus allen Plänen dieses Haushalts.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: strings.pick('Close', 'Schließen'),
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Expanded(
          child: projections.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: strings.noStockToManage,
                    message: strings.addSupplementAndContainerCount,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    for (final item in tracked)
                      _StockRow(projection: item, strings: strings),
                    if (untracked.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
                        child: Text(
                          strings.pick('No schedule yet', 'Noch kein Plan'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ),
                      for (final item in untracked)
                        _StockRow(projection: item, strings: strings),
                    ],
                  ],
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.of(context).maybePop();
                context.read<ShellNavigation>().go(AppSection.stock);
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(strings.pick('Open stock', 'Bestand öffnen')),
            ),
          ),
        ),
      ],
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({required this.projection, required this.strings});

  final StockProjection projection;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final days = projection.daysRemaining;
    // 90 days of cover reads as a full bar; beyond that the exact number
    // matters less than the fact that there is plenty left.
    final fill = days == null ? null : (days / 90).clamp(0.0, 1.0);
    final accent = projection.low ? colors.error : colors.primary;
    return SurfaceCard(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  projection.supplement.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (projection.low)
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: colors.error,
                ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fill ?? 0,
              minHeight: 6,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              formatAmountWithUnit(
                strings,
                amount: projection.unitsOnHand,
                unit: projection.supplement.stockUnit,
                form: projection.supplement.form,
              ),
              if (days != null)
                strings.daysProjected(days.clamp(0, 9999).round())
              else
                strings.noCompatibleHouseholdSchedule,
            ].join(' · '),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
