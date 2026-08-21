import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/ui/charts.dart';

void main() {
  Future<LineChartData> pump(WidgetTester tester, Widget chart) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SizedBox(width: 400, child: chart)),
      ),
    );
    return tester.widget<LineChart>(find.byType(LineChart)).data;
  }

  testWidgets('points sit at their real dates, not at even spacing', (
    tester,
  ) async {
    // Two readings three days apart, then one six months later. On an
    // index-based axis all three would be equally spaced, hiding the gap.
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 1, 1), value: 20),
          (day: DateTime(2026, 1, 4), value: 25),
          (day: DateTime(2026, 7, 1), value: 60),
        ],
        dayLabel: (day) => '${day.month}/${day.year}',
        semanticLabel: 'trend',
      ),
    );

    final spots = data.lineBarsData.single.spots;
    expect(spots, hasLength(3));
    expect(spots[0].x, DateTime(2026, 1, 1).millisecondsSinceEpoch);
    expect(spots[1].x, DateTime(2026, 1, 4).millisecondsSinceEpoch);
    expect(spots[2].x, DateTime(2026, 7, 1).millisecondsSinceEpoch);

    final shortGap = spots[1].x - spots[0].x;
    final longGap = spots[2].x - spots[1].x;
    expect(longGap, greaterThan(shortGap * 20));
  });

  testWidgets('the tooltip is kept inside the plot', (tester) async {
    // The reported bug: tapping the right-most point — the newest reading, and
    // the one most worth tapping — pushed its own label off the right edge and
    // out of the rendered area. fl_chart centres the tooltip on the touched
    // point unless told to reflow.
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 1, 1), value: 20),
          (day: DateTime(2026, 1, 4), value: 25),
        ],
        dayLabel: (day) => '${day.month}/${day.year}',
        semanticLabel: 'trend',
      ),
    );

    final tooltip = data.lineTouchData.touchTooltipData;
    expect(tooltip.fitInsideHorizontally, isTrue);
    expect(tooltip.fitInsideVertically, isTrue);
  });

  testWidgets("a reading's remark rides along in its tooltip", (tester) async {
    // The remark explains the point's position — a different lab, a
    // non-fasting sample — so the chart that shows the position should be able
    // to show the reason.
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 1, 1), value: 20),
          (day: DateTime(2026, 1, 4), value: 25),
        ],
        dayLabel: (day) => '${day.month}/${day.year}',
        semanticLabel: 'trend',
        noteLabel: (day) => day.day == 4 ? 'Not fasting' : null,
      ),
    );

    List<String> tooltipFor(int index) {
      final items = data.lineTouchData.touchTooltipData.getTooltipItems([
        LineBarSpot(
          data.lineBarsData.first,
          0,
          data.lineBarsData.first.spots[index],
        ),
      ]);
      final item = items.single!;
      return [item.text, ...?item.children?.map((span) => span.toPlainText())];
    }

    expect(tooltipFor(1), ['1/2026: 25.0', '\nNot fasting']);
    // A reading with no remark keeps the bare value; an empty line under every
    // other point would be noise.
    expect(tooltipFor(0), ['1/2026: 20.0']);
  });

  testWidgets('out-of-order points are sorted onto the axis', (tester) async {
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 3, 1), value: 30),
          (day: DateTime(2026, 1, 1), value: 10),
          (day: DateTime(2026, 2, 1), value: 20),
        ],
        dayLabel: (day) => '${day.month}',
        semanticLabel: 'trend',
      ),
    );

    final spots = data.lineBarsData.single.spots;
    expect(spots.map((spot) => spot.y), [10, 20, 30]);
    expect(spots[0].x, lessThan(spots[1].x));
    expect(spots[1].x, lessThan(spots[2].x));
  });

  testWidgets('a single point still gets a drawable span', (tester) async {
    final data = await pump(
      tester,
      TrendChart(
        points: [(day: DateTime(2026, 1, 1), value: 20)],
        dayLabel: (day) => '${day.month}',
        semanticLabel: 'trend',
      ),
    );

    expect(data.minX, lessThan(data.maxX));
  });

  testWidgets('the dose underlay is drawn behind the measurement line', (
    tester,
  ) async {
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 1, 1), value: 20),
          (day: DateTime(2026, 3, 1), value: 60),
        ],
        dayLabel: (day) => '${day.month}',
        semanticLabel: 'Vitamin D trend',
        rangeLow: 30,
        rangeHigh: 70,
        doseSeries: DoseSeries(
          target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
          bucketDays: 7,
          buckets: [
            DoseBucket(
              start: DateTime(2026, 1, 1),
              end: DateTime(2026, 1, 8),
              averageDailyDose: 1000,
              tracked: true,
            ),
            DoseBucket(
              start: DateTime(2026, 1, 8),
              end: DateTime(2026, 1, 15),
              averageDailyDose: 4000,
              tracked: true,
            ),
          ],
        ),
      ),
    );

    // Two series: dose first so it paints underneath, trend second.
    expect(data.lineBarsData, hasLength(2));
    final dose = data.lineBarsData.first;
    final trend = data.lineBarsData.last;
    expect(dose.isStepLineChart, isTrue);
    expect(trend.isCurved, isTrue);

    // The dose is mapped onto the primary axis but capped well below the top,
    // so it cannot swamp the reading it sits behind.
    final peakDoseY = dose.spots
        .map((spot) => spot.y)
        .reduce((a, b) => a > b ? a : b);
    expect(peakDoseY, lessThan(data.maxY));
    expect(peakDoseY - data.minY, lessThan((data.maxY - data.minY) * 0.6));

    // A closing spot keeps the last bucket at full width.
    expect(dose.spots.last.x, DateTime(2026, 1, 15).millisecondsSinceEpoch);

    // The reference range survives the underlay.
    expect(data.rangeAnnotations.horizontalRangeAnnotations, hasLength(1));
    expect(data.rangeAnnotations.horizontalRangeAnnotations.single.y1, 30);
  });

  testWidgets('untracked spans are shaded rather than shown as zero dose', (
    tester,
  ) async {
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 1, 1), value: 20),
          (day: DateTime(2026, 2, 1), value: 30),
        ],
        dayLabel: (day) => '${day.month}',
        semanticLabel: 'trend',
        doseSeries: DoseSeries(
          target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
          bucketDays: 7,
          buckets: [
            DoseBucket(
              start: DateTime(2026, 1, 1),
              end: DateTime(2026, 1, 8),
              averageDailyDose: 1000,
              tracked: true,
            ),
            // Nothing logged at all here: a gap, not a deliberate zero.
            DoseBucket(
              start: DateTime(2026, 1, 8),
              end: DateTime(2026, 1, 15),
              averageDailyDose: 0,
              tracked: false,
            ),
          ],
        ),
      ),
    );

    final shaded = data.rangeAnnotations.verticalRangeAnnotations;
    expect(shaded, hasLength(1));
    expect(shaded.single.x1, DateTime(2026, 1, 8).millisecondsSinceEpoch);
    expect(shaded.single.x2, DateTime(2026, 1, 15).millisecondsSinceEpoch);
  });

  testWidgets('a dose series of all zeroes draws no underlay', (tester) async {
    final data = await pump(
      tester,
      TrendChart(
        points: [
          (day: DateTime(2026, 1, 1), value: 20),
          (day: DateTime(2026, 2, 1), value: 30),
        ],
        dayLabel: (day) => '${day.month}',
        semanticLabel: 'trend',
        doseSeries: DoseSeries(
          target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
          bucketDays: 7,
          buckets: [
            DoseBucket(
              start: DateTime(2026, 1, 1),
              end: DateTime(2026, 1, 8),
              averageDailyDose: 0,
              tracked: true,
            ),
          ],
        ),
      ),
    );

    // Nothing was ever taken, so there is no second series and no right axis.
    expect(data.lineBarsData, hasLength(1));
    expect(data.titlesData.rightTitles.sideTitles.showTitles, isFalse);
  });
}
