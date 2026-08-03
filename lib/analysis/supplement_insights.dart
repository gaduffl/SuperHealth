import '../domain/entities.dart';

/// The named part of the day a scheduled dose belongs to.
///
/// Schedules store a free-text slot ("morning", "08:00", "bedtime"), so the UI
/// needs one canonical bucket to group the day's doses under.
enum DosePeriod {
  morning,
  midday,
  evening,
  bedtime;

  /// The representative hour used when a dose has to be timestamped for a past
  /// day, where "now" would fall outside the block.
  int get representativeHour => switch (this) {
    DosePeriod.morning => 8,
    DosePeriod.midday => 12,
    DosePeriod.evening => 18,
    DosePeriod.bedtime => 22,
  };
}

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

  /// The block this dose is shown under on the Today screen. Exact-time slots
  /// fall back to the hour they are due at.
  DosePeriod get period =>
      const SupplementInsights().periodOfSlot(schedule.timeOfDay) ??
      const SupplementInsights().periodOfHour(dueAt.hour);

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

/// One bucket of the dose underlay drawn beneath a trend.
///
/// [averageDailyDose] divides by every calendar day in the bucket, not only the
/// days with an intake, because what moves a biomarker is sustained intake: a
/// week with one capsule must read lower than a week with seven.
class DoseBucket {
  const DoseBucket({
    required this.start,
    required this.end,
    required this.averageDailyDose,
    required this.tracked,
  });

  /// Local calendar day the bucket starts on, inclusive.
  final DateTime start;

  /// Local calendar day the bucket ends on, exclusive.
  final DateTime end;

  final double averageDailyDose;

  /// Whether any intake at all was recorded in this bucket. A bucket the user
  /// simply never logged and a bucket where they genuinely took nothing both
  /// have a zero dose, and presenting them identically would invite reading an
  /// untracked gap as a deliberate pause.
  final bool tracked;
}

/// The dose underlay for one ingredient over one span.
class DoseSeries {
  const DoseSeries({
    required this.ingredientName,
    required this.unit,
    required this.buckets,
    required this.bucketDays,
  });

  final String ingredientName;
  final String unit;
  final List<DoseBucket> buckets;

  /// Calendar days each bucket covers, so callers can label the underlay
  /// honestly ("weekly average") instead of implying daily resolution.
  final int bucketDays;

  double get peakAverageDailyDose => buckets.fold(
    0,
    (peak, bucket) =>
        bucket.averageDailyDose > peak ? bucket.averageDailyDose : peak,
  );

  bool get hasDose => peakAverageDailyDose > 0;
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

/// One chartable line: a named quantity summed into Monday-anchored weeks.
///
/// Weekly buckets are used rather than raw days because supplement schedules
/// are weekly, so a daily series is dominated by the weekday pattern instead of
/// the trend a person is trying to read.
class ExposureSeries {
  const ExposureSeries({
    required this.key,
    required this.name,
    required this.unit,
    required this.weeklyTotals,
  });

  /// A stable identity for pinning, independent of the display name.
  final String key;
  final String name;
  final String unit;

  /// Week start (local Monday) to the total recorded in that week.
  final Map<DateTime, double> weeklyTotals;

  /// The label shown in legends, which has to carry the unit because two
  /// series with the same name but different units are not comparable.
  String get label => unit.isEmpty ? name : '$name ($unit)';

  double get total => weeklyTotals.values.fold(0, (sum, item) => sum + item);
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

/// How much of a product to buy to cover a planning horizon.
class PurchaseSuggestion {
  const PurchaseSuggestion({
    required this.supplement,
    required this.requiredUnits,
    required this.unitsOnHand,
    required this.missingUnits,
    required this.containersToBuy,
    required this.estimatedCostEur,
  });

  final Supplement supplement;
  final double requiredUnits;
  final double unitsOnHand;
  final double missingUnits;

  /// `null` when the package size is unknown, so a guess is never presented as
  /// a concrete number of containers.
  final int? containersToBuy;
  final double? estimatedCostEur;

  bool get covered => missingUnits <= 0;
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

  /// The named block a schedule slot belongs to, or `null` when the slot is an
  /// exact time rather than a named part of the day.
  DosePeriod? periodOfSlot(String timeOfDay) => switch (_period(timeOfDay)) {
    'morning' => DosePeriod.morning,
    'midday' => DosePeriod.midday,
    'evening' => DosePeriod.evening,
    'bedtime' => DosePeriod.bedtime,
    _ => null,
  };

  /// The block a wall-clock hour falls into.
  DosePeriod periodOfHour(int hour) => switch (_periodForHour(hour)) {
    'morning' => DosePeriod.morning,
    'midday' => DosePeriod.midday,
    'bedtime' => DosePeriod.bedtime,
    _ => DosePeriod.evening,
  };

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

  /// Average daily dose of one ingredient, bucketed across [from]..[through]
  /// so a multi-year span stays readable instead of collapsing into hundreds
  /// of one-pixel bars.
  ///
  /// [ingredientUnit] is part of the lookup, never converted: an ingredient
  /// recorded in IU and one recorded in µg are separate series.
  DoseSeries doseSeries({
    required List<SupplementIntake> intakes,
    required String ingredientName,
    required String ingredientUnit,
    required DateTime from,
    required DateTime through,
    int targetBuckets = 40,
  }) {
    final start = _calendarDay(from);
    final end = _calendarDay(through);
    final spanDays = end.difference(start).inDays + 1;
    final safeSpan = spanDays < 1 ? 1 : spanDays;
    final safeTarget = targetBuckets < 1 ? 1 : targetBuckets;
    final bucketDays = (safeSpan / safeTarget).ceil().clamp(1, safeSpan);
    final key =
        '${ingredientName.toLowerCase()}|${ingredientUnit.toLowerCase()}';

    final totals = <int, double>{};
    final tracked = <int>{};
    for (final intake in intakes) {
      if (intake.deleted) continue;
      final day = _calendarDay(intake.takenAt);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      final index = day.difference(start).inDays ~/ bucketDays;
      // A skipped intake still proves the user was tracking that day, so it
      // marks the bucket as tracked while contributing no dose.
      tracked.add(index);
      if (intake.skipped || !intake.dose.isFinite) continue;
      for (final ingredient in intake.ingredientSnapshot) {
        final name = ingredient['name']?.toString().trim() ?? '';
        final unit = ingredient['unit']?.toString().trim() ?? '';
        if ('${name.toLowerCase()}|${unit.toLowerCase()}' != key) continue;
        final amount = _asDouble(ingredient['amount']);
        if (amount == null) continue;
        final contribution = amount * intake.dose;
        if (!contribution.isFinite) continue;
        final next = (totals[index] ?? 0) + contribution;
        if (!next.isFinite) continue;
        totals[index] = next;
      }
    }

    final bucketCount = (safeSpan / bucketDays).ceil();
    final buckets = <DoseBucket>[];
    for (var index = 0; index < bucketCount; index++) {
      // Step through the calendar rather than adding Durations, so a bucket
      // boundary crossing a DST change still lands on local midnight.
      final bucketStart = DateTime(
        start.year,
        start.month,
        start.day + index * bucketDays,
      );
      final rawEnd = DateTime(
        start.year,
        start.month,
        start.day + (index + 1) * bucketDays,
      );
      final exclusiveEnd = DateTime(end.year, end.month, end.day + 1);
      final bucketEnd = rawEnd.isAfter(exclusiveEnd) ? exclusiveEnd : rawEnd;
      final days = bucketEnd.difference(bucketStart).inDays;
      final total = totals[index] ?? 0;
      buckets.add(
        DoseBucket(
          start: bucketStart,
          end: bucketEnd,
          averageDailyDose: days > 0 ? total / days : 0,
          tracked: tracked.contains(index),
        ),
      );
    }

    return DoseSeries(
      ingredientName: ingredientName,
      unit: ingredientUnit,
      buckets: buckets,
      bucketDays: bucketDays,
    );
  }

  /// Every ingredient the profile actually takes, as name/unit pairs, for
  /// offering a dose underlay the user can pick from.
  List<({String name, String unit})> knownIngredients(
    List<SupplementIntake> intakes,
  ) {
    final seen = <String, ({String name, String unit})>{};
    for (final intake in intakes.where((item) => !item.deleted)) {
      for (final ingredient in intake.ingredientSnapshot) {
        final name = ingredient['name']?.toString().trim() ?? '';
        final unit = ingredient['unit']?.toString().trim() ?? '';
        if (name.isEmpty || unit.isEmpty) continue;
        seen['${name.toLowerCase()}|${unit.toLowerCase()}'] ??= (
          name: name,
          unit: unit,
        );
      }
    }
    final result = seen.values.toList()
      ..sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : a.unit.compareTo(b.unit);
      });
    return result;
  }

  /// Best guess at which ingredient belongs under a trend, given every name
  /// that trend is known by (a biomarker's canonical name, display name and
  /// synonyms, or an event definition's name).
  ///
  /// Deliberately conservative: every token of the shorter name has to match,
  /// so "Vitamin D (25-OH)" finds "Vitamin D3" while "Vitamin B12" never
  /// matches "Vitamin B6". A wrong confident guess is worse than none, because
  /// the whole point of the underlay is to judge whether a supplement moved a
  /// number.
  ({String name, String unit})? suggestIngredient({
    required List<({String name, String unit})> ingredients,
    required Iterable<String> trendNames,
  }) {
    final trendTokenSets = [
      for (final name in trendNames)
        if (_nameTokens(name).isNotEmpty) _nameTokens(name),
    ];
    if (trendTokenSets.isEmpty) return null;
    for (final ingredient in ingredients) {
      final ingredientTokens = _nameTokens(ingredient.name);
      if (ingredientTokens.isEmpty) continue;
      for (final trendTokens in trendTokenSets) {
        if (_tokensAgree(trendTokens, ingredientTokens)) return ingredient;
      }
    }
    return null;
  }

  /// Assay descriptors that say how a marker was measured rather than what it
  /// is, and so must not decide a match.
  static const _nameNoise = <String>{
    'total',
    'free',
    'serum',
    'plasma',
    'blood',
    'level',
    'levels',
    'oh',
    'hydroxy',
    '25',
    'active',
  };

  List<String> _nameTokens(String value) => [
    for (final token in value.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
      if (token.isNotEmpty && !_nameNoise.contains(token)) token,
  ];

  bool _tokensAgree(List<String> left, List<String> right) {
    final shorter = left.length <= right.length ? left : right;
    final longer = left.length <= right.length ? right : left;
    if (shorter.isEmpty) return false;
    return shorter.every(
      (token) => longer.any((other) => _tokenMatches(token, other)),
    );
  }

  /// Equal, or the same name carrying a form number — "d" matches "d3", but
  /// "b12" never matches "b6".
  bool _tokenMatches(String left, String right) {
    if (left == right) return true;
    final (shorter, longer) = left.length <= right.length
        ? (left, right)
        : (right, left);
    if (!longer.startsWith(shorter)) return false;
    final suffix = longer.substring(shorter.length);
    return suffix.isNotEmpty && RegExp(r'^\d+$').hasMatch(suffix);
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

  /// The Monday-anchored weeks covered by a range, oldest first.
  List<DateTime> weeksIn({required DateTime from, required DateTime through}) {
    final result = <DateTime>[];
    var week = _weekStart(from);
    final last = _weekStart(through);
    while (!week.isAfter(last)) {
      result.add(week);
      week = DateTime(week.year, week.month, week.day + 7);
    }
    return result;
  }

  /// Weekly totals per supplement and reported unit, for the intake chart.
  List<ExposureSeries> weeklySupplementSeries({
    required List<SupplementIntake> intakes,
    required List<Supplement> supplements,
    required DateTime from,
    required DateTime through,
  }) {
    final names = {
      for (final supplement in supplements) supplement.id: supplement.name,
    };
    final totals = <String, Map<DateTime, double>>{};
    final display = <String, (String, String)>{};
    for (final intake in _actualIntakesInRange(intakes, from, through)) {
      final unit = intake.unit.trim();
      final key = '${intake.supplementId}|${unit.toLowerCase()}';
      final week = _weekStart(intake.takenAt);
      final bucket = totals.putIfAbsent(key, () => <DateTime, double>{});
      bucket[week] = (bucket[week] ?? 0) + intake.dose;
      display[key] = (names[intake.supplementId] ?? 'Deleted supplement', unit);
    }
    return _sortedSeries(totals, display);
  }

  /// Weekly totals per ingredient and unit, for the component chart.
  List<ExposureSeries> weeklyIngredientSeries({
    required List<SupplementIntake> intakes,
    required DateTime from,
    required DateTime through,
  }) {
    final totals = <String, Map<DateTime, double>>{};
    final display = <String, (String, String)>{};
    for (final intake in _actualIntakesInRange(intakes, from, through)) {
      if (!intake.dose.isFinite) continue;
      final week = _weekStart(intake.takenAt);
      for (final ingredient in intake.ingredientSnapshot) {
        final name = ingredient['name']?.toString().trim() ?? '';
        final unit = ingredient['unit']?.toString().trim() ?? '';
        final amount = _asDouble(ingredient['amount']);
        if (name.isEmpty || amount == null) continue;
        final contribution = amount * intake.dose;
        if (!contribution.isFinite) continue;
        final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
        final bucket = totals.putIfAbsent(key, () => <DateTime, double>{});
        final next = (bucket[week] ?? 0) + contribution;
        if (!next.isFinite) continue;
        bucket[week] = next;
        display[key] = (name, unit);
      }
    }
    return _sortedSeries(totals, display);
  }

  List<ExposureSeries> _sortedSeries(
    Map<String, Map<DateTime, double>> totals,
    Map<String, (String, String)> display,
  ) {
    final result = [
      for (final entry in totals.entries)
        ExposureSeries(
          key: entry.key,
          name: display[entry.key]!.$1,
          unit: display[entry.key]!.$2,
          weeklyTotals: Map.unmodifiable(entry.value),
        ),
    ];
    result.sort((a, b) {
      final amount = b.total.compareTo(a.total);
      if (amount != 0) return amount;
      final name = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return name != 0 ? name : a.unit.compareTo(b.unit);
    });
    return result;
  }

  /// How many containers of each product to buy to cover [months] ahead.
  ///
  /// Ports Supplement Manager's shopping list: projected consumption minus what
  /// is on hand, rounded up to whole packages.
  List<PurchaseSuggestion> purchasePlan({
    required List<Supplement> supplements,
    required List<SupplementSchedule> householdSchedules,
    required Map<String, double> stockLevels,
    required int months,
  }) {
    final result = <PurchaseSuggestion>[];
    for (final supplement in supplements.where(
      (item) => !item.deleted && item.active,
    )) {
      var weeklyUnits = 0.0;
      for (final schedule in householdSchedules.where(
        (item) => item.supplementId == supplement.id && item.active,
      )) {
        if (!_sameStockUnit(schedule.unit, supplement.stockUnit)) continue;
        weeklyUnits += schedule.dose * schedule.weekdays.length;
      }
      if (weeklyUnits <= 0) continue;
      // 52 weeks over 12 months, so a month is not silently treated as four
      // weeks and the plan does not come up short over a year.
      final requiredUnits = weeklyUnits * 52 / 12 * months;
      final onHand = stockLevels[supplement.id] ?? 0;
      final deficit = (requiredUnits - onHand).clamp(0, double.infinity);
      final packageUnits = supplement.unitsPerContainer;
      final containers = packageUnits == null || packageUnits <= 0
          ? null
          : (deficit / packageUnits).ceil();
      result.add(
        PurchaseSuggestion(
          supplement: supplement,
          requiredUnits: requiredUnits.toDouble(),
          unitsOnHand: onHand,
          missingUnits: deficit.toDouble(),
          containersToBuy: containers,
          estimatedCostEur: containers == null || supplement.priceEur == null
              ? null
              : containers * supplement.priceEur!,
        ),
      );
    }
    result.sort((a, b) {
      final missing = b.missingUnits.compareTo(a.missingUnits);
      if (missing != 0) return missing;
      return a.supplement.name.toLowerCase().compareTo(
        b.supplement.name.toLowerCase(),
      );
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
  }) => monthlyCostByProduct(
    supplements: supplements,
    householdSchedules: householdSchedules,
  ).fold(0, (total, item) => total + item.eur);

  /// The planned monthly cost broken down per product, largest first.
  ///
  /// Products with no price, no package size, or no compatible schedule are
  /// omitted rather than counted as free.
  List<({Supplement supplement, double eur})> monthlyCostByProduct({
    required List<Supplement> supplements,
    required List<SupplementSchedule> householdSchedules,
  }) {
    final result = <({Supplement supplement, double eur})>[];
    for (final supplement in supplements.where((item) => !item.deleted)) {
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
      if (weeklyUnits <= 0) continue;
      result.add((
        supplement: supplement,
        eur: weeklyUnits * 52 / 12 * price / packageUnits,
      ));
    }
    result.sort((a, b) => b.eur.compareTo(a.eur));
    return result;
  }

  /// What an active weekly plan is designed to deliver per component.
  ///
  /// This reads the schedule rather than the history, so it answers "what
  /// should I be getting each week" independently of adherence — the question
  /// Supplement Manager's intake analysis existed to answer.
  List<IngredientExposure> plannedWeeklyIngredients({
    required List<Supplement> supplements,
    required List<SupplementSchedule> schedules,
  }) {
    final catalog = {for (final item in supplements) item.id: item};
    final totals = <String, double>{};
    final display = <String, (String, String)>{};
    for (final schedule in schedules.where(
      (item) => item.active && !item.deleted,
    )) {
      final supplement = catalog[schedule.supplementId];
      if (supplement == null || supplement.deleted || !supplement.active) {
        continue;
      }
      final weeklyUnits = schedule.dose * schedule.weekdays.length;
      if (weeklyUnits <= 0 || !weeklyUnits.isFinite) continue;
      for (final ingredient in supplement.ingredients) {
        final name = ingredient['name']?.toString().trim() ?? '';
        final unit = ingredient['unit']?.toString().trim() ?? '';
        final amount = _asDouble(ingredient['amount']);
        if (name.isEmpty || amount == null) continue;
        final contribution = amount * weeklyUnits;
        if (!contribution.isFinite) continue;
        final key = '${name.toLowerCase()}|${unit.toLowerCase()}';
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

  /// The local Monday that starts the week containing [value].
  DateTime _weekStart(DateTime value) =>
      DateTime(value.year, value.month, value.day - value.weekday + 1);

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
