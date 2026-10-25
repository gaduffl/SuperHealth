import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/design.dart';
import 'package:super_health/ui/supplement_stock_section.dart';

void main() {
  testWidgets('low stock filters the visible inventory and can be cleared', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpStock(tester, [_low, _covered]);

    expect(tester.takeException(), isNull);
    expect(find.text('Running low'), findsOneWidget);
    expect(find.text('Well stocked'), findsOneWidget);
    expect(tester.widget<StatTile>(_lowStockTile).selected, isFalse);

    await tester.tap(_lowStockTile);
    await tester.pumpAndSettle();

    expect(find.text('Running low'), findsOneWidget);
    expect(find.text('Well stocked'), findsNothing);
    expect(find.text('Clear filter'), findsOneWidget);
    expect(tester.widget<StatTile>(_lowStockTile).selected, isTrue);
    expect(
      tester.getSemantics(_lowStockTile),
      matchesSemantics(
        label: 'Low stock: 1. Low stock only',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
    expect(tester.getBottomLeft(find.text('Running low')).dy, lessThan(850));

    await tester.tap(find.text('Clear filter'));
    await tester.pumpAndSettle();

    expect(find.text('Well stocked'), findsOneWidget);
    expect(find.text('Clear filter'), findsNothing);
    expect(tester.widget<StatTile>(_lowStockTile).selected, isFalse);

    await tester.tap(_lowStockTile);
    await tester.pumpAndSettle();
    await tester.tap(_lowStockTile);
    await tester.pumpAndSettle();

    expect(find.text('Well stocked'), findsOneWidget);
  });

  testWidgets('an empty low stock filter explains the result', (tester) async {
    await _pumpStock(tester, [_covered]);
    await tester.tap(_lowStockTile);
    await tester.pumpAndSettle();

    expect(find.text('Nothing is running low'), findsOneWidget);
    expect(find.text('Well stocked'), findsNothing);
    expect(find.text('Clear filter'), findsOneWidget);
  });

  testWidgets('an incoming low stock filter is shown on arrival in German', (
    tester,
  ) async {
    await _pumpStock(
      tester,
      [_low, _covered],
      onlyLowStock: true,
      locale: const Locale('de'),
    );

    expect(find.text('Running low'), findsOneWidget);
    expect(find.text('Well stocked'), findsNothing);
    expect(find.text('Filter löschen'), findsOneWidget);
    await tester.tap(find.widgetWithText(StatTile, 'Niedriger Bestand'));
    await tester.pumpAndSettle();
    expect(find.text('Well stocked'), findsOneWidget);
  });

  testWidgets('filtered stock keeps purchase and adjustment actions', (
    tester,
  ) async {
    final purchases = <Supplement>[];
    final adjustments = <Supplement>[];
    await _pumpStock(
      tester,
      [_low, _covered],
      onlyLowStock: true,
      onPurchase: purchases.add,
      onAdjustStock: adjustments.add,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Purchase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running low'));
    await tester.pumpAndSettle();

    expect(purchases, [_low.supplement]);
    expect(adjustments, [_low.supplement]);
  });

  testWidgets('stock summary fits a phone with larger text', (tester) async {
    await _pumpStock(tester, [_low], textScale: 2);

    expect(tester.takeException(), isNull);
    await tester.tap(_lowStockTile);
    await tester.pumpAndSettle();
    expect(find.text('Clear filter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Finder get _lowStockTile => find.widgetWithText(StatTile, 'Low stock');

Future<void> _pumpStock(
  WidgetTester tester,
  List<StockProjection> projections, {
  bool onlyLowStock = false,
  Locale locale = const Locale('en'),
  double textScale = 1,
  ValueChanged<Supplement>? onPurchase,
  ValueChanged<Supplement>? onAdjustStock,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 850);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SupplementStockSection(
                allProjections: projections,
                onlyLowStock: onlyLowStock,
                onLowStockChanged: (value) =>
                    setState(() => onlyLowStock = value),
                monthlyCost: 12,
                householdMonthlyCost: true,
                onPurchase: onPurchase ?? (_) {},
                onAdjustStock: onAdjustStock ?? (_) {},
              ),
              const Text('Shopping list'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _now = DateTime(2026, 10, 25);
final _low = StockProjection(
  supplement: Supplement(
    id: 'low',
    name: 'Running low',
    createdAt: _now,
    updatedAt: _now,
  ),
  unitsOnHand: 5,
  weeklyScheduledUnits: 7,
  daysRemaining: 5,
);
final _covered = StockProjection(
  supplement: Supplement(
    id: 'covered',
    name: 'Well stocked',
    createdAt: _now,
    updatedAt: _now,
  ),
  unitsOnHand: 90,
  weeklyScheduledUnits: 7,
  daysRemaining: 90,
);
