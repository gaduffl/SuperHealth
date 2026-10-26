import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/charts.dart';
import 'package:super_health/ui/design.dart';
import 'package:super_health/ui/exposure_series_picker.dart';

void main() {
  test(
    'saved ingredient choices survive canonical names and unit spellings',
    () {
      final key = canonicalExposurePin('ingredient|B12|microgram');
      expect(key, 'ingredient|vitamin-b12|µg');
      expect(canonicalExposurePin(key), key);
      expect(canonicalExposurePin('ingredient|Vitamin B12|μg'), key);
      expect(
        canonicalExposurePin('supplement|product|capsule'),
        'supplement|product|capsule',
      );
      final unknown = canonicalExposurePin('ingredient|Unlisted extract|mg');
      expect(canonicalExposurePin(unknown), unknown);
    },
  );

  testWidgets('choosing B12 draws its complete exposure and keeps the choice', (
    tester,
  ) async {
    final day = DateTime(2026, 5, 1);
    final product = Supplement(
      id: 'b12',
      name: 'B12',
      ingredients: const [
        {'name': 'B12', 'amount': 100, 'unit': 'microgram'},
      ],
      createdAt: day,
      updatedAt: day,
    );
    final series = const SupplementInsights().weeklyIngredientSeries(
      supplements: [product],
      intakes: [
        SupplementIntake(
          id: 'old',
          profileId: 'p',
          supplementId: product.id,
          takenAt: day,
          dose: 1,
          unit: 'capsule',
          createdAt: day,
          updatedAt: day,
        ),
      ],
      from: day,
      through: day,
    );
    final available = [
      ...series,
      ExposureSeries(
        key: 'other|mg',
        name: 'Other',
        unit: 'mg',
        weeklyTotals: {DateTime(2026, 4, 27): 20},
      ),
    ];
    Set<String> pins = {};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              final shown = selectedExposureSeries(
                available,
                pins,
                category: 'ingredient',
              );
              return Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      final next = await showExposureSeriesPicker(
                        context,
                        title: 'Components',
                        series: available,
                        initialPins: pins,
                        category: 'ingredient',
                      );
                      if (next != null) setState(() => pins = next);
                    },
                    child: const Text('Choose'),
                  ),
                  WeeklySeriesChart(
                    weeks: [DateTime(2026, 4, 27)],
                    series: shown,
                    colors: seriesColors(shown.map((item) => item.key)),
                    weekLabel: (_) => 'Week',
                    valueLabel: (value) => '$value',
                    semanticLabel: 'Exposure',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vitamin B12'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    final chart = tester.widget<WeeklySeriesChart>(
      find.byType(WeeklySeriesChart),
    );
    expect(chart.series.single.key, series.single.key);
    expect(chart.series.single.total, 100);
    final line = tester.widget<LineChart>(find.byType(LineChart));
    expect(line.data.lineBarsData.single.spots.single.y, 100);

    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.widgetWithText(CheckboxListTile, 'Vitamin B12'),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing selected'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<WeeklySeriesChart>(find.byType(WeeklySeriesChart)).series,
      hasLength(2),
    );
  });
}
