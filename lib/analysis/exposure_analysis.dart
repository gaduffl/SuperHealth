import '../domain/entities.dart';
import '../domain/medication_catalog.dart';
import '../domain/substance_catalog.dart';

/// One ingredient delivered by one logged intake.
///
/// The unit of everything downstream: interaction rules test thresholds and
/// timing against these, and the advisor digest summarises them. Built once
/// from the ledger so that every consumer agrees on what was taken when.
class DoseEvent {
  const DoseEvent({
    required this.at,
    required this.intakeId,
    required this.supplementId,
    required this.name,
    this.amount,
    this.unit,
    this.fromProductName = false,
  });

  final DateTime at;
  final String intakeId;
  final String supplementId;

  /// The ingredient's name, or the product's when the product has no
  /// ingredients recorded (see [fromProductName]).
  final String name;

  /// Ingredient amount times the number of units taken. Null when either is
  /// missing — an unknown dose, never a zero one.
  final double? amount;
  final String? unit;

  /// True when the product has no ingredient rows, so [name] is the product
  /// name and the actual contents are unknown.
  final bool fromProductName;
}

/// A substance the person takes or took, grouped by identity rather than by
/// spelling, with amounts kept per unit and never summed across units.
class SubstanceExposure {
  const SubstanceExposure({
    required this.id,
    required this.key,
    required this.displayName,
    required this.ingredientsRecorded,
    required this.supplementIds,
    required this.recentDailyAmountByUnit,
    required this.recentDaysTaken,
    required this.current,
    required this.plannedOnly,
    required this.amountMissing,
    this.substanceId,
    this.firstTakenAt,
    this.lastTakenAt,
    this.plannedDailyAmountByUnit = const {},
  });

  /// Stable id used by the advisor's review, e.g. `exp:biotin`.
  final String id;

  /// [SubstanceCatalog.groupingKeyFor] for an ingredient, or
  /// `product:<supplement id>` for a product with no ingredients.
  final String key;
  final String? substanceId;
  final String displayName;

  /// False when this entry stands for a whole product whose ingredients were
  /// never entered: the substances in it are unknown, not absent.
  final bool ingredientsRecorded;
  final Set<String> supplementIds;

  /// Mean amount per day *on days it was taken* within the recent window,
  /// per unit.
  final Map<String, double> recentDailyAmountByUnit;
  final int recentDaysTaken;
  final DateTime? firstTakenAt;
  final DateTime? lastTakenAt;

  /// Taken within the recent window, or on a schedule in force today.
  final bool current;

  /// Current only because a schedule says so — nothing logged recently.
  final bool plannedOnly;

  /// Some doses in the window had no amount or no ingredient amount.
  final bool amountMissing;

  /// What active schedules plan per scheduled day, per unit.
  final Map<String, double> plannedDailyAmountByUnit;
}

/// A medication from the health record.
class MedicationExposure {
  const MedicationExposure({
    required this.id,
    required this.record,
    required this.classIds,
    required this.current,
  });

  /// Stable id used by the advisor's review, e.g. `med:<record id>`.
  final String id;
  final NamedHealthRecord record;
  final Set<String> classIds;
  final bool current;
}

/// Everything the person takes, derived deterministically from the record.
class ExposureAnalysis {
  const ExposureAnalysis({
    required this.events,
    required this.substances,
    required this.medications,
    required this.now,
    required this.plannedToday,
  });

  /// Every non-skipped dose, oldest first.
  final List<DoseEvent> events;
  final List<SubstanceExposure> substances;
  final List<MedicationExposure> medications;
  final DateTime now;

  /// Doses active schedules plan for one day, for products with nothing
  /// logged in the recent window. Stamped at [now].
  final List<DoseEvent> plannedToday;

  /// How far back "currently taking" reaches. Four weeks covers a product
  /// taken every other day or weekly without calling a paused one current.
  static const recentWindow = Duration(days: 28);

  static const _substances = SubstanceCatalog();
  static const _medications = MedicationCatalog();

  static ExposureAnalysis build({
    required List<Supplement> supplements,
    required List<SupplementSchedule> schedules,
    required List<SupplementIntake> intakes,
    required List<NamedHealthRecord> records,
    required DateTime now,
  }) {
    final byId = {for (final item in supplements) item.id: item};
    final events = <DoseEvent>[];
    for (final intake in intakes) {
      if (intake.deleted || intake.skipped) continue;
      events.addAll(_eventsFor(intake, byId[intake.supplementId]));
    }
    events.sort((a, b) => a.at.compareTo(b.at));

    final recentFrom = now.subtract(recentWindow);
    final loggedRecently = {
      for (final event in events)
        if (!event.at.isBefore(recentFrom) && !event.at.isAfter(now))
          event.supplementId,
    };
    final plannedToday = <DoseEvent>[];
    for (final schedule in schedules) {
      if (!_inForce(schedule, now)) continue;
      if (loggedRecently.contains(schedule.supplementId)) continue;
      final supplement = byId[schedule.supplementId];
      if (supplement == null || supplement.deleted || !supplement.active) {
        continue;
      }
      plannedToday.addAll(
        _eventsFor(
          SupplementIntake(
            id: 'schedule:${schedule.id}',
            profileId: schedule.profileId,
            supplementId: schedule.supplementId,
            scheduleId: schedule.id,
            takenAt: now,
            dose: schedule.dose,
            unit: schedule.unit,
            createdAt: now,
            updatedAt: now,
          ),
          supplement,
        ),
      );
    }

    return ExposureAnalysis(
      events: events,
      substances: _summarise(events, plannedToday, byId, now),
      medications: [
        for (final record in records)
          if (!record.deleted && record.kind == 'medication')
            MedicationExposure(
              id: 'med:${record.id}',
              record: record,
              classIds: _medications.classIdsFor(record.name),
              current: isCurrentMedication(record, now),
            ),
      ],
      now: now,
      plannedToday: plannedToday,
    );
  }

  static bool isCurrentMedication(NamedHealthRecord record, DateTime now) =>
      isCurrentRecord(record, now);

  /// `active` and `monitoring` are ongoing; `resolved` and `paused` are not.
  /// An end date in the past overrides a status nobody updated. The same rule
  /// for every kind of record, so a condition is current exactly when a
  /// medicine with the same status and dates would be.
  static bool isCurrentRecord(NamedHealthRecord record, DateTime now) {
    final status = record.status.trim().toLowerCase();
    if (status != 'active' && status != 'monitoring') return false;
    final end = record.endDate;
    if (end == null) return true;
    final today = DateTime(now.year, now.month, now.day);
    return !DateTime(end.year, end.month, end.day).isBefore(today);
  }

  static bool _inForce(SupplementSchedule schedule, DateTime now) {
    if (!schedule.active || schedule.deleted || schedule.weekdays.isEmpty) {
      return false;
    }
    final today = DateTime(now.year, now.month, now.day);
    final start = schedule.startDate;
    final end = schedule.endDate;
    if (start != null &&
        today.isBefore(DateTime(start.year, start.month, start.day))) {
      return false;
    }
    if (end != null && today.isAfter(DateTime(end.year, end.month, end.day))) {
      return false;
    }
    return true;
  }

  /// The ingredients one intake delivered.
  ///
  /// The snapshot taken at log time wins; an empty snapshot means the product
  /// had not been broken down yet, so the product's current ingredients stand
  /// in — in one real library that fallback covers 94% of intakes. A product
  /// with no ingredients at all becomes one event under its own name, so it
  /// stays visible as "contents unknown" instead of disappearing.
  static List<DoseEvent> _eventsFor(
    SupplementIntake intake,
    Supplement? supplement,
  ) {
    final ingredients = intake.ingredientSnapshot.isNotEmpty
        ? intake.ingredientSnapshot
        : supplement?.ingredients ?? const <Map<String, Object?>>[];
    final named = [
      for (final ingredient in ingredients)
        if ((ingredient['name']?.toString().trim() ?? '').isNotEmpty)
          ingredient,
    ];
    if (named.isEmpty) {
      return [
        DoseEvent(
          at: intake.takenAt,
          intakeId: intake.id,
          supplementId: intake.supplementId,
          name: supplement?.name ?? intake.supplementId,
          fromProductName: true,
        ),
      ];
    }
    return [
      for (final ingredient in named)
        DoseEvent(
          at: intake.takenAt,
          intakeId: intake.id,
          supplementId: intake.supplementId,
          name: ingredient['name'].toString().trim(),
          amount: _amount(ingredient['amount'], intake.dose),
          unit: _unit(ingredient['unit']),
        ),
    ];
  }

  static double? _amount(Object? perUnit, double dose) {
    final parsed = perUnit is num
        ? perUnit.toDouble()
        : double.tryParse(perUnit?.toString().replaceAll(',', '.') ?? '');
    if (parsed == null || !parsed.isFinite || !dose.isFinite) return null;
    final total = parsed * dose;
    return total.isFinite ? total : null;
  }

  static String? _unit(Object? raw) {
    final unit = raw?.toString().trim() ?? '';
    return unit.isEmpty ? null : unit;
  }

  static String keyFor(DoseEvent event) => event.fromProductName
      ? 'product:${event.supplementId}'
      : _substances.groupingKeyFor(event.name);

  static List<SubstanceExposure> _summarise(
    List<DoseEvent> events,
    List<DoseEvent> planned,
    Map<String, Supplement> supplements,
    DateTime now,
  ) {
    final recentFrom = now.subtract(recentWindow);
    final byKey = <String, List<DoseEvent>>{};
    for (final event in events) {
      byKey.putIfAbsent(keyFor(event), () => []).add(event);
    }
    final plannedByKey = <String, List<DoseEvent>>{};
    for (final event in planned) {
      plannedByKey.putIfAbsent(keyFor(event), () => []).add(event);
    }
    final result = <SubstanceExposure>[];
    for (final key in {...byKey.keys, ...plannedByKey.keys}) {
      final all = byKey[key] ?? const <DoseEvent>[];
      final plannedEvents = plannedByKey[key] ?? const <DoseEvent>[];
      final recent = [
        for (final event in all)
          if (!event.at.isBefore(recentFrom) && !event.at.isAfter(now)) event,
      ];
      final perDayPerUnit = <String, Map<String, double>>{};
      var amountMissing = false;
      for (final event in recent) {
        final day = localDayKey(event.at);
        final bucket = perDayPerUnit.putIfAbsent(day, () => {});
        final unit = event.unit;
        final amount = event.amount;
        if (amount == null || unit == null) {
          amountMissing = true;
          continue;
        }
        bucket[unit] = (bucket[unit] ?? 0) + amount;
      }
      final perUnitTotals = <String, double>{};
      final perUnitDays = <String, int>{};
      for (final day in perDayPerUnit.values) {
        for (final entry in day.entries) {
          perUnitTotals[entry.key] =
              (perUnitTotals[entry.key] ?? 0) + entry.value;
          perUnitDays[entry.key] = (perUnitDays[entry.key] ?? 0) + 1;
        }
      }
      final plannedPerUnit = <String, double>{};
      for (final event in plannedEvents) {
        final unit = event.unit;
        final amount = event.amount;
        if (amount == null || unit == null) continue;
        plannedPerUnit[unit] = (plannedPerUnit[unit] ?? 0) + amount;
      }
      final sample = all.isNotEmpty ? all.first : plannedEvents.first;
      final productIds = {
        for (final event in all) event.supplementId,
        for (final event in plannedEvents) event.supplementId,
      };
      final substanceId = sample.fromProductName
          ? null
          : _substances.idFor(sample.name);
      result.add(
        SubstanceExposure(
          id: 'exp:$key',
          key: key,
          substanceId: substanceId,
          displayName: sample.fromProductName
              ? supplements[sample.supplementId]?.name ?? sample.name
              : _substances.displayNameFor(sample.name),
          ingredientsRecorded: !sample.fromProductName,
          supplementIds: productIds,
          recentDailyAmountByUnit: {
            for (final entry in perUnitTotals.entries)
              entry.key: entry.value / perUnitDays[entry.key]!,
          },
          recentDaysTaken: perDayPerUnit.length,
          firstTakenAt: all.isEmpty ? null : all.first.at,
          lastTakenAt: all.isEmpty ? null : all.last.at,
          current: recent.isNotEmpty || plannedEvents.isNotEmpty,
          plannedOnly: recent.isEmpty && plannedEvents.isNotEmpty,
          amountMissing: amountMissing,
          plannedDailyAmountByUnit: plannedPerUnit,
        ),
      );
    }
    result.sort((a, b) {
      if (a.current != b.current) return a.current ? -1 : 1;
      final byName = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
      return byName != 0 ? byName : a.key.compareTo(b.key);
    });
    return result;
  }
}

/// A local calendar day as `YYYY-MM-DD`, the bucket for "per day" amounts.
///
/// Local rather than UTC: a dose taken at 00:30 belongs to the day the person
/// lived it, and a UTC bucket would split one evening across two days.
String localDayKey(DateTime at) {
  final local = at.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
