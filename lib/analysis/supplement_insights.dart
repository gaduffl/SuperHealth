import '../domain/entities.dart';

class ScheduledDoseStatus {
  const ScheduledDoseStatus({
    required this.schedule,
    required this.supplement,
    required this.dueAt,
    required this.evaluatedAt,
    this.intake,
  });

  final SupplementSchedule schedule;
  final Supplement supplement;
  final DateTime dueAt;
  final DateTime evaluatedAt;
  final SupplementIntake? intake;

  bool get taken => intake != null && !intake!.skipped;
  bool get skipped => intake?.skipped == true;
  bool get pending => intake == null && dueAt.isAfter(evaluatedAt);
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

/// A local-calendar-day adherence bucket. Counts only doses that were due by
/// [now]; a future schedule is deliberately not treated as missed.
class DailyAdherence {
  const DailyAdherence({
    required this.day,
    required this.scheduled,
    required this.taken,
    required this.skipped,
    required this.missed,
  });

  final DateTime day;
  final int scheduled;
  final int taken;
  final int skipped;
  final int missed;

  double? get rate => scheduled == 0 ? null : taken / scheduled;
}

/// A Monday-to-Sunday local-calendar adherence bucket.
class WeeklyAdherence extends DailyAdherence {
  const WeeklyAdherence({
    required super.day,
    required super.scheduled,
    required super.taken,
    required super.skipped,
    required super.missed,
  });

  DateTime get weekStarting => day;
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

/// Exposure is intentionally separated by reported unit. The app never adds
/// e.g. milligrams and capsules as if they were interchangeable.
class SupplementExposure {
  const SupplementExposure({
    required this.supplementId,
    required this.name,
    required this.unit,
    required this.total,
    required this.intakeCount,
  });

  final String supplementId;
  final String name;
  final String unit;
  final double total;
  final int intakeCount;

  String get seriesKey => '$supplementId|${unit.trim().toLowerCase()}';
}

class DailyCost {
  const DailyCost({required this.day, required this.knownEur});

  final DateTime day;
  final double knownEur;
}

class InsightDateRange {
  const InsightDateRange({required this.from, required this.through});

  final DateTime from;
  final DateTime through;
}

/// Cost values include only intakes with a known package price, package size,
/// and a unit compatible with the product's stock unit. [unknownIntakes] is
/// always exposed so a known subtotal cannot be mistaken for a complete total.
class IntakeCostInsight {
  const IntakeCostInsight({
    required this.knownEur,
    required this.eligibleIntakes,
    required this.knownIntakes,
    required this.unknownIntakes,
    required this.daily,
  });

  final double knownEur;
  final int eligibleIntakes;
  final int knownIntakes;
  final int unknownIntakes;
  final List<DailyCost> daily;

  bool get completeCoverage => eligibleIntakes == knownIntakes;
  String get coverageLabel => eligibleIntakes == 0
      ? 'No non-skipped intakes'
      : '$knownIntakes of $eligibleIntakes intakes have known compatible cost';
}

class SupplementInsights {
  const SupplementInsights();

  /// Legacy/manual intakes do not carry a schedule ID. For exact HH:mm
  /// schedules, only treat an intake within this local-time tolerance as the
  /// scheduled dose. This allows ordinary timing drift without silently
  /// turning a much later intake into adherence.
  static const _exactScheduleFallbackWindow = Duration(minutes: 90);

  static const _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  /// Resolves the fixed history choices against local calendar dates. The end
  /// is always today, so neither a normal nor an all-history view reaches into
  /// the future.
  InsightDateRange historyRange({
    required String selection,
    required DateTime now,
    required Iterable<DateTime> historyDates,
  }) {
    final through = _calendarDay(now);
    if (selection != 'all') {
      final days = int.tryParse(selection);
      if (days == null || days <= 0) {
        throw ArgumentError.value(
          selection,
          'selection',
          'Expected day count or all',
        );
      }
      return InsightDateRange(
        from: DateTime(through.year, through.month, through.day - days + 1),
        through: through,
      );
    }
    final eligible =
        historyDates
            .map(_calendarDay)
            .where((item) => !item.isAfter(through))
            .toList()
          ..sort();
    return InsightDateRange(
      from: eligible.isEmpty ? through : eligible.first,
      through: through,
    );
  }

  List<ScheduledDoseStatus> dosesForDay({
    required DateTime day,
    required List<SupplementSchedule> schedules,
    required List<Supplement> supplements,
    required List<SupplementIntake> intakes,
    DateTime? now,
  }) {
    final evaluatedAt = now ?? DateTime.now();
    final catalog = {for (final item in supplements) item.id: item};
    final dayIntakes =
        intakes
            .where((item) => !item.deleted && _sameDay(item.takenAt, day))
            .toList()
          ..sort(_compareIntakes);
    final scheduled =
        schedules.where((item) => _scheduledOn(item, day)).where((item) {
          final supplement = catalog[item.supplementId];
          return supplement != null && !supplement.deleted && supplement.active;
        }).toList()..sort((a, b) {
          final due = _dueAt(
            day,
            a.timeOfDay,
          ).compareTo(_dueAt(day, b.timeOfDay));
          return due != 0 ? due : a.id.compareTo(b.id);
        });
    final consumedIntakeIds = <String>{};
    final matches = <String, SupplementIntake>{};

    // A schedule ID is authoritative. Resolve these first so legacy fallback
    // logic never replaces a precise, explicit link.
    for (final schedule in scheduled) {
      for (final intake in dayIntakes) {
        if (consumedIntakeIds.contains(intake.id)) continue;
        if (intake.scheduleId == schedule.id &&
            intake.supplementId == schedule.supplementId) {
          matches[schedule.id] = intake;
          consumedIntakeIds.add(intake.id);
          break;
        }
      }
    }

    // Exact schedules use the closest available same-supplement legacy intake
    // in a fixed window. Stable schedule and intake ordering makes ties
    // deterministic, and consumed IDs keep the relationship one-to-one.
    for (final schedule in scheduled) {
      if (matches.containsKey(schedule.id)) continue;
      final exactTime = _exactTimeOfDay(schedule.timeOfDay);
      if (exactTime == null) continue;
      final dueAt = DateTime(
        day.year,
        day.month,
        day.day,
        exactTime.$1,
        exactTime.$2,
      );
      final candidates =
          dayIntakes
              .where(
                (intake) =>
                    !consumedIntakeIds.contains(intake.id) &&
                    intake.scheduleId == null &&
                    intake.supplementId == schedule.supplementId &&
                    intake.takenAt.difference(dueAt).abs() <=
                        _exactScheduleFallbackWindow,
              )
              .toList()
            ..sort((a, b) {
              final distance = a.takenAt
                  .difference(dueAt)
                  .abs()
                  .compareTo(b.takenAt.difference(dueAt).abs());
              return distance != 0 ? distance : _compareIntakes(a, b);
            });
      if (candidates.isNotEmpty) {
        matches[schedule.id] = candidates.first;
        consumedIntakeIds.add(candidates.first.id);
      }
    }

    // Named slots intentionally retain their broad period matching for data
    // imported from older versions, after exact times have had first claim.
    for (final schedule in scheduled) {
      if (matches.containsKey(schedule.id) ||
          !_isNamedSlot(schedule.timeOfDay)) {
        continue;
      }
      for (final intake in dayIntakes) {
        if (consumedIntakeIds.contains(intake.id) ||
            intake.scheduleId != null ||
            intake.supplementId != schedule.supplementId) {
          continue;
        }
        if (_periodForHour(intake.takenAt.hour) ==
            _period(schedule.timeOfDay)) {
          matches[schedule.id] = intake;
          consumedIntakeIds.add(intake.id);
          break;
        }
      }
    }

    final result = <ScheduledDoseStatus>[];
    for (final schedule in scheduled) {
      final supplement = catalog[schedule.supplementId]!;
      result.add(
        ScheduledDoseStatus(
          schedule: schedule,
          supplement: supplement,
          dueAt: _dueAt(day, schedule.timeOfDay),
          evaluatedAt: evaluatedAt,
          intake: matches[schedule.id],
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
    DateTime? now,
  }) {
    var scheduled = 0;
    var taken = 0;
    var skipped = 0;
    var missed = 0;
    final values = dailyAdherence(
      from: from,
      through: through,
      schedules: schedules,
      supplements: supplements,
      intakes: intakes,
      now: now,
    );
    for (final value in values) {
      scheduled += value.scheduled;
      taken += value.taken;
      skipped += value.skipped;
      missed += value.missed;
    }
    return AdherenceSummary(
      scheduled: scheduled,
      taken: taken,
      skipped: skipped,
      missed: missed,
    );
  }

  List<DailyAdherence> dailyAdherence({
    required DateTime from,
    required DateTime through,
    required List<SupplementSchedule> schedules,
    required List<Supplement> supplements,
    required List<SupplementIntake> intakes,
    DateTime? now,
  }) {
    final result = <DailyAdherence>[];
    final effectiveNow = now ?? DateTime.now();
    var day = _calendarDay(from);
    final last = _calendarDay(through);
    while (!day.isAfter(last)) {
      var scheduled = 0;
      var taken = 0;
      var skipped = 0;
      var missed = 0;
      for (final dose in dosesForDay(
        day: day,
        schedules: schedules,
        supplements: supplements,
        intakes: intakes,
        now: effectiveNow,
      )) {
        if (dose.pending) continue;
        scheduled++;
        if (dose.taken) {
          taken++;
        } else if (dose.skipped) {
          skipped++;
        } else {
          missed++;
        }
      }
      result.add(
        DailyAdherence(
          day: day,
          scheduled: scheduled,
          taken: taken,
          skipped: skipped,
          missed: missed,
        ),
      );
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return result;
  }

  List<WeeklyAdherence> weeklyAdherence({
    required DateTime from,
    required DateTime through,
    required List<SupplementSchedule> schedules,
    required List<Supplement> supplements,
    required List<SupplementIntake> intakes,
    DateTime? now,
  }) {
    final buckets = <DateTime, List<int>>{};
    for (final day in dailyAdherence(
      from: from,
      through: through,
      schedules: schedules,
      supplements: supplements,
      intakes: intakes,
      now: now,
    )) {
      final date = day.day;
      final week = DateTime(date.year, date.month, date.day - date.weekday + 1);
      final totals = buckets.putIfAbsent(week, () => [0, 0, 0, 0]);
      totals[0] += day.scheduled;
      totals[1] += day.taken;
      totals[2] += day.skipped;
      totals[3] += day.missed;
    }
    final result = [
      for (final entry in buckets.entries)
        WeeklyAdherence(
          day: entry.key,
          scheduled: entry.value[0],
          taken: entry.value[1],
          skipped: entry.value[2],
          missed: entry.value[3],
        ),
    ];
    result.sort((a, b) => a.weekStarting.compareTo(b.weekStarting));
    return result;
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
          _withinLocalRange(item.takenAt, from, to),
    )) {
      for (final ingredient in intake.ingredientSnapshot) {
        final name = ingredient['name']?.toString().trim() ?? '';
        final unit = ingredient['unit']?.toString().trim() ?? '';
        final amount = _asDouble(ingredient['amount']);
        if (name.isEmpty || amount == null || !intake.dose.isFinite) continue;
        final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
        final contribution = amount * intake.dose;
        if (!contribution.isFinite) continue;
        final next = (totals[key] ?? 0) + contribution;
        if (!next.isFinite) continue;
        totals[key] = next;
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
    result.sort(_compareExposure);
    return result;
  }

  List<SupplementExposure> supplementExposure({
    required List<SupplementIntake> intakes,
    required List<Supplement> supplements,
    required DateTime from,
    required DateTime through,
  }) {
    final names = {
      for (final supplement in supplements) supplement.id: supplement.name,
    };
    final totals = <String, double>{};
    final counts = <String, int>{};
    final display = <String, (String, String, String)>{};
    for (final intake in _actualIntakesInRange(intakes, from, through)) {
      final unit = intake.unit.trim();
      final name = names[intake.supplementId] ?? 'Deleted supplement';
      final key = '${intake.supplementId}|${unit.toLowerCase()}';
      totals[key] = (totals[key] ?? 0) + intake.dose;
      counts[key] = (counts[key] ?? 0) + 1;
      display[key] = (intake.supplementId, name, unit);
    }
    final result = [
      for (final entry in totals.entries)
        SupplementExposure(
          supplementId: display[entry.key]!.$1,
          name: display[entry.key]!.$2,
          unit: display[entry.key]!.$3,
          total: entry.value,
          intakeCount: counts[entry.key]!,
        ),
    ];
    result.sort((a, b) {
      final amount = b.total.compareTo(a.total);
      if (amount != 0) return amount;
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (name != 0) return name;
      return a.unit.toLowerCase().compareTo(b.unit.toLowerCase());
    });
    return result;
  }

  IntakeCostInsight actualIntakeCost({
    required List<SupplementIntake> intakes,
    required List<Supplement> supplements,
    required DateTime from,
    required DateTime through,
  }) {
    final products = {for (final item in supplements) item.id: item};
    final daily = <DateTime, double>{};
    var known = 0.0;
    var eligible = 0;
    var knownCount = 0;
    for (final intake in _actualIntakesInRange(intakes, from, through)) {
      eligible++;
      final product = products[intake.supplementId];
      final price = product?.priceEur;
      final packageUnits = product?.unitsPerContainer;
      if (product == null ||
          price == null ||
          price < 0 ||
          packageUnits == null ||
          packageUnits <= 0 ||
          !_sameReportedUnit(intake.unit, product.stockUnit)) {
        continue;
      }
      final value = intake.dose * price / packageUnits;
      known += value;
      knownCount++;
      final day = _calendarDay(intake.takenAt);
      daily[day] = (daily[day] ?? 0) + value;
    }
    final trend = [
      for (final entry in daily.entries)
        DailyCost(day: entry.key, knownEur: entry.value),
    ]..sort((a, b) => a.day.compareTo(b.day));
    return IntakeCostInsight(
      knownEur: known,
      eligibleIntakes: eligible,
      knownIntakes: knownCount,
      unknownIntakes: eligible - knownCount,
      daily: trend,
    );
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
    final namedHour = switch (_period(value)) {
      'morning' => 8,
      'midday' => 12,
      'evening' => 18,
      'bedtime' => 22,
      _ => null,
    };
    if (namedHour != null) {
      return DateTime(day.year, day.month, day.day, namedHour);
    }
    final match = RegExp(r'^(\d{1,2})(?::(\d{2}))?').firstMatch(value.trim());
    final hour = int.tryParse(match?.group(1) ?? '') ?? 12;
    final minute = int.tryParse(match?.group(2) ?? '') ?? 0;
    return DateTime(
      day.year,
      day.month,
      day.day,
      hour.clamp(0, 23).toInt(),
      minute.clamp(0, 59).toInt(),
    );
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

  (int, int)? _exactTimeOfDay(String value) {
    final match = RegExp(
      r'^([01]\d|2[0-3]):([0-5]\d)$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  bool _isNamedSlot(String value) => switch (_period(value)) {
    'morning' || 'midday' || 'evening' || 'bedtime' => true,
    _ => false,
  };

  static int _compareIntakes(SupplementIntake a, SupplementIntake b) {
    final takenAt = a.takenAt.compareTo(b.takenAt);
    return takenAt != 0 ? takenAt : a.id.compareTo(b.id);
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

  /// Cost cannot safely use the schedule/stock projection's broad "discrete
  /// unit" equivalence. A tablet intake is not evidence that a capsule package
  /// was consumed, even though both are countable units.
  bool _sameReportedUnit(String a, String b) {
    String normalize(String value) {
      var result = value.trim().toLowerCase();
      if (result.endsWith('s') && result.length > 1) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    }

    return normalize(a) == normalize(b);
  }

  List<SupplementIntake> _actualIntakesInRange(
    List<SupplementIntake> intakes,
    DateTime from,
    DateTime through,
  ) => intakes
      .where(
        (item) =>
            !item.deleted &&
            !item.skipped &&
            _withinLocalRange(item.takenAt, from, through),
      )
      .toList();

  bool _withinLocalRange(DateTime value, DateTime from, DateTime through) {
    final day = _calendarDay(value);
    return !day.isBefore(_calendarDay(from)) &&
        !day.isAfter(_calendarDay(through));
  }

  DateTime _calendarDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  double? _asDouble(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString().replaceAll(',', '.') ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  int _compareExposure(IngredientExposure a, IngredientExposure b) {
    final amount = b.total.compareTo(a.total);
    if (amount != 0) return amount;
    final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    if (name != 0) return name;
    return a.unit.toLowerCase().compareTo(b.unit.toLowerCase());
  }
}
