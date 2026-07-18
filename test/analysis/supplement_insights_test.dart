import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  final service = SupplementInsights();
  final monday = DateTime(2026, 7, 13);
  final supplement = Supplement(
    id: 'magnesium',
    name: 'Magnesium',
    stockUnit: 'capsule',
    unitsPerContainer: 60,
    priceEur: 12,
    lowStockThresholdUnits: 20,
    createdAt: monday,
    updatedAt: monday,
  );
  final schedule = SupplementSchedule(
    id: 'schedule',
    profileId: 'profile',
    supplementId: supplement.id,
    dose: 2,
    unit: 'capsules',
    timeOfDay: 'Morning',
    weekdays: const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ],
    createdAt: monday,
    updatedAt: monday,
  );

  test('matches a legacy intake to a scheduled time bucket', () {
    final intake = SupplementIntake(
      id: 'intake',
      profileId: 'profile',
      supplementId: supplement.id,
      takenAt: DateTime(2026, 7, 13, 8),
      dose: 2,
      unit: 'capsules',
      createdAt: monday,
      updatedAt: monday,
    );
    final result = service.dosesForDay(
      day: monday,
      schedules: [schedule],
      supplements: [supplement],
      intakes: [intake],
    );
    expect(result.single.taken, isTrue);
  });

  test('projects household stock from all profile schedules', () {
    final projection = service
        .stockProjections(
          supplements: [supplement],
          householdSchedules: [schedule],
          stockLevels: {supplement.id: 14},
        )
        .single;
    expect(projection.weeklyScheduledUnits, 14);
    expect(projection.daysRemaining, 7);
    expect(projection.low, isTrue);
    expect(projection.suggestedPurchaseUnits, 154);
  });

  test('monthly cost uses package price and scheduled units', () {
    final cost = service.monthlyCostEstimate(
      supplements: [supplement],
      householdSchedules: [schedule],
    );
    expect(cost, closeTo(12.1333, 0.001));
  });
}
