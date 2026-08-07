import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ui/tracking_screen.dart';

void main() {
  bool matches(
    String filter, {
    required bool active,
    required bool scheduled,
  }) => catalogMatchesFilter(
    filter: filter,
    productIsActive: active,
    hasSchedule: scheduled,
  );

  test('active and paused sort by the product, ignoring schedules', () {
    expect(matches('active', active: true, scheduled: false), isTrue);
    expect(matches('active', active: false, scheduled: true), isFalse);
    expect(matches('inactive', active: false, scheduled: false), isTrue);
    expect(matches('inactive', active: true, scheduled: true), isFalse);
  });

  test('scheduled sorts by the schedule, not by the product', () {
    // A paused product with a schedule is still scheduled, and its row says so
    // — the filter has to agree with the count printed beside it.
    expect(matches('scheduled', active: false, scheduled: true), isTrue);
    // Active but never scheduled is exactly what this filter exists to hide.
    expect(matches('scheduled', active: true, scheduled: false), isFalse);
    expect(matches('scheduled', active: true, scheduled: true), isTrue);
  });

  test('all keeps everything', () {
    for (final active in [true, false]) {
      for (final scheduled in [true, false]) {
        expect(matches('all', active: active, scheduled: scheduled), isTrue);
      }
    }
  });
}
