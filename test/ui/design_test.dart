import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/app_theme.dart';
import 'package:super_health/app/appearance_settings.dart';
import 'package:super_health/ui/design.dart';

void main() {
  test('series colours do not depend on the caller\'s ordering', () {
    final a = seriesColors(['zinc', 'magnesium', 'omega-3']);
    final b = seriesColors(['omega-3', 'magnesium', 'zinc']);
    expect(b, a);
  });

  test('most series keep their colour when another is filtered out', () {
    const names = [
      'zinc',
      'magnesium',
      'omega-3',
      'vitamin d',
      'creatine',
      'iron',
    ];
    final all = seriesColors(names);
    var moved = 0;
    var compared = 0;
    for (final removed in names) {
      final fewer = seriesColors(names.where((item) => item != removed));
      for (final kept in fewer.keys) {
        compared++;
        if (fewer[kept] != all[kept]) moved++;
      }
    }
    // Only a key whose slot was contested can move. Positional assignment
    // would instead shift every key after the removed one.
    expect(moved / compared, lessThan(0.1));
  });

  test('colours within one chart stay distinct', () {
    const shown = 12;
    final assigned = seriesColors([
      for (var index = 0; index < shown; index++) 'series$index',
    ]);
    expect(assigned.values.toSet(), hasLength(shown));
  });

  test('the deuteranomaly-friendly palette is used when selected', () {
    final standard = seriesColors(['a', 'b'], colorMode: AppColorMode.standard);
    final friendly = seriesColors([
      'a',
      'b',
    ], colorMode: AppColorMode.deuteranomalyFriendly);
    expect(standard.values, isNot(friendly.values));
    // Single-label accents stay on the base hues.
    expect(
      seriesColorFor('a', colorMode: AppColorMode.deuteranomalyFriendly),
      isIn(deuteranomalySafeSeries),
    );
  });

  test('series labels stay readable on every palette entry', () {
    final everyColor = {
      ...seriesColors([
        for (var index = 0; index < 40; index++) 's$index',
      ]).values,
      ...seriesColors([
        for (var index = 0; index < 40; index++) 's$index',
      ], colorMode: AppColorMode.deuteranomalyFriendly).values,
    };
    for (final color in everyColor) {
      final contrast = colorContrastRatio(onSeriesColor(color), color);
      // WCAG AA for the large, bold numbers drawn on a series colour.
      expect(
        contrast,
        greaterThanOrEqualTo(3.0),
        reason: 'contrast on ${color.toARGB32().toRadixString(16)}',
      );
    }
  });

  testWidgets('the progress ring reads as no target when nothing is due', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ProgressRing(value: null, label: '—')),
      ),
    );
    await tester.pumpAndSettle();

    final indicators = tester
        .widgetList<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        )
        .toList();
    // Only the track is drawn, so an empty day never reads as 0% adherence.
    expect(indicators, hasLength(1));
    expect(find.text('—'), findsOneWidget);
  });
}
