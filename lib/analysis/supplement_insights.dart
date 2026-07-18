import '../domain/entities.dart';

class ScheduledDoseStatus {
  const ScheduledDoseStatus({
    required this.schedule,
    required this.supplement,
    required this.dueAt,
    this.intake,
  });

  final SupplementSchedule schedule;
  final Supplement supplement;
  final DateTime dueAt;
  final SupplementIntake? intake;

  bool get taken => intake != null && !intake!.skipped;
  bool get skipped => intake?.skipped == true;
  bool get pending => intake == null && dueAt.isAfter(DateTime.now());
  bool get missed => intake == null && !pending;
}

class AdherenceSummary {
  const AdherenceSummary({
    required this.scheduled,
    required this.taken,
    required this.skipped,
    required this.missed,
  });

  final int scheduled;
  final int taken;
  final int skipped;
  final int missed;

  double? get rate => scheduled == 0 ? null : taken / scheduled;
}

class StockProjection {
  const StockProjection({
    required this.supplement,
    required this.unitsOnHand,
    required this.weeklyScheduledUnits,
    this.daysRemaining,
  });

  final Supplement supplement;
  final double unitsOnHand;
  final double weeklyScheduledUnits;
  final double? daysRemaining;

  bool get low {
    final threshold = supplement.lowStockThresholdUnits;
    if (!supplement.lowStockAlerts) return false;
    if (threshold != null) return unitsOnHand <= threshold;
    return daysRemaining != null && daysRemaining! <= 30;
  }

  double get suggestedPurchaseUnits {
    if (weeklyScheduledUnits <= 0) return 0;
    final target = weeklyScheduledUnits * 12;
    return (target - unitsOnHand).clamp(0, double.infinity).toDouble();
  }
}

class IngredientExposure {
  const IngredientExposure({
    required this.name,
    required this.unit,
    required this.total,
  });

  final String name;
  final String unit;
  final double total;
}

class SupplementInsights {
  const SupplementInsights();

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  List<ScheduledDoseStatus> dosesForDay({
    required DateTime day,
    required List<SupplementSchedule> schedules,
    required List<Supplement> supplements,
    required List<SupplementIntake> intakes,
  }) {
    final catalog = {for (final item in supplements) item.id: item};
    final dayIntakes = intakes
        .where((item) => !item.deleted && _sameDay(item.takenAt, day))
        .toList();
    final consumedIntakeIds = <String>{};
    final result = <ScheduledDoseStatus>[];
    for (final schedule in schedules.where((item) => _scheduledOn(item, day))) {
      final supplement = catalog[schedule.supplementId];
      if (supplement == null || supplement.deleted || !supplement.active) {
        continue;
      }
      SupplementIntake? match;
      for (final intake in dayIntakes) {
        if (consumedIntakeIds.contains(intake.id)) continue;
        if (intake.scheduleId == schedule.id) {
          match = intake;
          break;
        }
      }
      if (match == null) {
        for (final intake in dayIntakes) {
          if (consumedIntakeIds.contains(intake.id) ||
              intake.scheduleId != null ||
              intake.supplementId != schedule.supplementId) {
            continue;
          }
          if (_periodForHour(intake.takenAt.hour) ==
              _period(schedule.timeOfDay)) {
            match = intake;
            break;
          }
        }
      }
      if (match != null) consumedIntakeIds.add(match.id);
      result.add(
        ScheduledDoseStatus(
          schedule: schedule,
          supplement: supplement,
          dueAt: _dueAt(day, schedule.timeOfDay),
          intake: match,
        ),
      );
    }
    result.sort((a, b) => a.dueAt.compareTo(b.dueAt));
    return result;
  }

  AdherenceSummary adherence({
    required DateTime from,
    required DateTime through,
    required List<SupplementSchedule> schedules,
    required List<Supplement> supplements,
    required List<SupplementIntake> intakes,
  }) {
    var scheduled = 0;
    var taken = 0;
    var skipped = 0;
    var missed = 0;
    var day = DateTime(from.year, from.month, from.day);
    final last = DateTime(through.year, through.month, through.day);
    while (!day.isAfter(last)) {
      for (final dose in dosesForDay(
        day: day,
        schedules: schedules,
        supplements: supplements,
        intakes: intakes,
      )) {
        if (dose.dueAt.isAfter(DateTime.now())) continue;
        scheduled++;
        if (dose.taken) {
          taken++;
        } else if (dose.skipped) {
          skipped++;
        } else {
          missed++;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return AdherenceSummary(
      scheduled: scheduled,
      taken: taken,
      skipped: skipped,
      missed: missed,
    );
  }

  List<StockProjection> stockProjections({
    required List<Supplement> supplements,
    required List<SupplementSchedule> householdSchedules,
    required Map<String, double> stockLevels,
  }) {
    final result = <StockProjection>[];
    for (final supplement in supplements.where((item) => !item.deleted)) {
      var weekly = 0.0;
      for (final schedule in householdSchedules.where(
        (item) => item.supplementId == supplement.id && item.active,
      )) {
        if (!_sameStockUnit(schedule.unit, supplement.stockUnit)) continue;
        weekly += schedule.dose * schedule.weekdays.length;
      }
      final stock = stockLevels[supplement.id] ?? 0;
      result.add(
        StockProjection(
          supplement: supplement,
          unitsOnHand: stock,
          weeklyScheduledUnits: weekly,
          daysRemaining: weekly <= 0 ? null : stock / (weekly / 7),
        ),
      );
    }
    result.sort((a, b) {
      if (a.low != b.low) return a.low ? -1 : 1;
      return a.supplement.name.toLowerCase().compareTo(
        b.supplement.name.toLowerCase(),
      );
    });
    return result;
  }

  List<IngredientExposure> ingredientExposure({
    required List<SupplementIntake> intakes,
    required DateTime from,
    required DateTime to,
  }) {
    final totals = <String, double>{};
    final display = <String, (String, String)>{};
    for (final intake in intakes.where(
      (item) =>
          !item.deleted &&
          !item.skipped &&
          !item.takenAt.isBefore(from) &&
          item.takenAt.isBefore(to),
    )) {
      for (final ingredient in intake.ingredientSnapshot) {
        final name = ingredient['name']?.toString().trim() ?? '';
        final unit = ingredient['unit']?.toString().trim() ?? '';
        final amount = (ingredient['amount'] as num?)?.toDouble();
        if (name.isEmpty || amount == null) continue;
        final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
        totals[key] = (totals[key] ?? 0) + amount * intake.dose;
        display[key] = (name, unit);
      }
    }
    final result = [
      for (final entry in totals.entries)
        IngredientExposure(
          name: display[entry.key]!.$1,
          unit: display[entry.key]!.$2,
          total: entry.value,
        ),
    ];
    result.sort((a, b) => b.total.compareTo(a.total));
    return result;
  }

  double monthlyCostEstimate({
    required List<Supplement> supplements,
    required List<SupplementSchedule> householdSchedules,
  }) {
    var total = 0.0;
    for (final supplement in supplements) {
      final price = supplement.priceEur;
      final packageUnits = supplement.unitsPerContainer;
      if (price == null || packageUnits == null || packageUnits <= 0) continue;
      var weeklyUnits = 0.0;
      for (final schedule in householdSchedules.where(
        (item) => item.supplementId == supplement.id && item.active,
      )) {
        if (!_sameStockUnit(schedule.unit, supplement.stockUnit)) continue;
        weeklyUnits += schedule.dose * schedule.weekdays.length;
      }
      total += weeklyUnits * 52 / 12 * price / packageUnits;
    }
    return total;
  }

  bool _scheduledOn(SupplementSchedule schedule, DateTime day) {
    if (!schedule.active || schedule.deleted) return false;
    final date = DateTime(day.year, day.month, day.day);
    final start = schedule.startDate;
    final end = schedule.endDate;
    if (start != null &&
        date.isBefore(DateTime(start.year, start.month, start.day))) {
      return false;
    }
    if (end != null && date.isAfter(DateTime(end.year, end.month, end.day))) {
      return false;
    }
    return schedule.weekdays.contains(_weekdays[date.weekday - 1]);
  }

  DateTime _dueAt(DateTime day, String value) {
    final hour = switch (_period(value)) {
      'morning' => 8,
      'midday' => 12,
      'evening' => 18,
      'bedtime' => 22,
      _ => int.tryParse(RegExp(r'^\d{1,2}').stringMatch(value) ?? '') ?? 12,
    };
    return DateTime(day.year, day.month, day.day, hour);
  }

  String _period(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('morn') || normalized == 'am') return 'morning';
    if (normalized.contains('mid') || normalized.contains('noon')) {
      return 'midday';
    }
    if (normalized.contains('bed') || normalized.contains('night')) {
      return 'bedtime';
    }
    if (normalized.contains('even') || normalized == 'pm') return 'evening';
    return normalized;
  }

  String _periodForHour(int hour) {
    if (hour < 11) return 'morning';
    if (hour < 16) return 'midday';
    if (hour < 21) return 'evening';
    return 'bedtime';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _sameStockUnit(String a, String b) {
    String normalize(String value) {
      var result = value.trim().toLowerCase();
      if (result.endsWith('s') && result.length > 1) {
        result = result.substring(0, result.length - 1);
      }
      const discrete = {
        'unit',
        'capsule',
        'tablet',
        'softgel',
        'scoop',
        'drop',
        'packet',
      };
      return discrete.contains(result) ? 'unit' : result;
    }

    return normalize(a) == normalize(b);
  }
}
