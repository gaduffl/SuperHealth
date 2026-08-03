import 'dart:convert';

enum LabTier { core, advanced, comprehensive }

enum EvidenceClass { guideline, longevity, experimental, unclassified }

enum EventKind { symptom, tag }

/// How a tag definition's number is interpreted for logging and correlation.
///
/// Symptoms always behave like [intensity] regardless of this field — it
/// only distinguishes the three ways a *tag* (an exposure/predictor) can be
/// quantified, so that occurrence counts, felt-strength ratings, and real
/// amounts are never summed together into one meaningless series.
enum TagValueMode {
  /// It happened or it did not. Logging needs no number; a day's exposure is
  /// how many times it was logged.
  occurrence,

  /// A 0-5 felt-strength rating with no physical unit, e.g. how strong a
  /// tremor felt. Legacy entries above 5 remain readable without being
  /// rewritten.
  intensity,

  /// A real quantity in [HealthEventDefinition.defaultUnit], e.g. grams of
  /// coffee beans. A day's exposure is the sum of that day's amounts.
  amount,
}

bool _boolFromDb(Object? value) => value == true || value == 1;

String _iso(DateTime value) => value.toUtc().toIso8601String();

DateTime _date(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '')?.toLocal() ??
    DateTime.fromMillisecondsSinceEpoch(0);

List<String> _strings(Object? value) {
  if (value is List) return value.map((item) => '$item').toList();
  if (value is! String || value.isEmpty) return const [];
  final decoded = jsonDecode(value);
  return decoded is List ? decoded.map((item) => '$item').toList() : const [];
}

const _canonicalWeekdays = <String>[
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Canonicalizes legacy English/German weekday labels and removes duplicates.
///
/// Supplement Manager exports have existed with both title-case and lower-case
/// weekday keys in the same schedule. Keeping both made a seven-day schedule
/// appear as fourteen days and prevented title-case-only plans from matching.
List<String> normalizeWeekdays(Iterable<String> values) {
  final selected = <String>{};
  for (final value in values) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-zäöü]+'),
      '',
    );
    final canonical = switch (normalized) {
      'monday' || 'mon' || 'mo' || 'montag' => 'monday',
      'tuesday' || 'tue' || 'tues' || 'tu' || 'di' || 'dienstag' => 'tuesday',
      'wednesday' || 'wed' || 'we' || 'mi' || 'mittwoch' => 'wednesday',
      'thursday' ||
      'thu' ||
      'thur' ||
      'thurs' ||
      'th' ||
      'do' ||
      'donnerstag' => 'thursday',
      'friday' || 'fri' || 'fr' || 'freitag' => 'friday',
      'saturday' || 'sat' || 'sa' || 'samstag' => 'saturday',
      'sunday' || 'sun' || 'so' || 'sonntag' => 'sunday',
      _ => null,
    };
    if (canonical != null) selected.add(canonical);
  }
  return [
    for (final weekday in _canonicalWeekdays)
      if (selected.contains(weekday)) weekday,
  ];
}

class Profile {
  const Profile({
    required this.id,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.dateOfBirth,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String displayName;
  final DateTime? dateOfBirth;
  final String? sex;
  final double? heightCm;
  final double? weightKg;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  int? get age {
    final dob = dateOfBirth;
    if (dob == null) return null;
    final now = DateTime.now();
    var result = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      result--;
    }
    return result;
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'display_name': displayName,
    'date_of_birth': dateOfBirth?.toIso8601String().split('T').first,
    'sex': sex,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory Profile.fromMap(Map<String, Object?> map) => Profile(
    id: '${map['id']}',
    displayName: '${map['display_name']}',
    dateOfBirth: map['date_of_birth'] == null
        ? null
        : DateTime.tryParse('${map['date_of_birth']}'),
    sex: map['sex']?.toString(),
    heightCm: (map['height_cm'] as num?)?.toDouble(),
    weightKg: (map['weight_kg'] as num?)?.toDouble(),
    notes: map['notes']?.toString() ?? '',
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class Supplement {
  const Supplement({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.brand = '',
    this.form = '',
    this.ingredients = const [],
    this.unitsPerContainer,
    this.containerCount,
    this.priceEur,
    this.bioavailability = '',
    this.notes = '',
    this.active = true,
    this.lowStockAlerts = true,
    this.lowStockThresholdUnits,
    this.stockUnit = 'unit',
    this.sourceId,
    this.deleted = false,
  });

  final String id;
  final String name;
  final String brand;
  final String form;
  final List<Map<String, Object?>> ingredients;
  final int? unitsPerContainer;
  final double? containerCount;
  final double? priceEur;
  final String bioavailability;
  final String notes;
  final bool active;
  final bool lowStockAlerts;
  final double? lowStockThresholdUnits;
  final String stockUnit;
  final String? sourceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'brand': brand,
    'form': form,
    'ingredients_json': jsonEncode(ingredients),
    'units_per_container': unitsPerContainer,
    'container_count': containerCount,
    'price_eur': priceEur,
    'bioavailability': bioavailability,
    'notes': notes,
    'active': active ? 1 : 0,
    'low_stock_alerts': lowStockAlerts ? 1 : 0,
    'low_stock_threshold_units': lowStockThresholdUnits,
    'stock_unit': stockUnit,
    'source_id': sourceId,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory Supplement.fromMap(Map<String, Object?> map) {
    final decoded = jsonDecode(map['ingredients_json']?.toString() ?? '[]');
    return Supplement(
      id: '${map['id']}',
      name: '${map['name']}',
      brand: map['brand']?.toString() ?? '',
      form: map['form']?.toString() ?? '',
      ingredients: decoded is List
          ? decoded
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList()
          : const [],
      unitsPerContainer: (map['units_per_container'] as num?)?.toInt(),
      containerCount: (map['container_count'] as num?)?.toDouble(),
      priceEur: (map['price_eur'] as num?)?.toDouble(),
      bioavailability: map['bioavailability']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      active: _boolFromDb(map['active']),
      lowStockAlerts: _boolFromDb(map['low_stock_alerts']),
      lowStockThresholdUnits: (map['low_stock_threshold_units'] as num?)
          ?.toDouble(),
      stockUnit: map['stock_unit']?.toString() ?? 'unit',
      sourceId: map['source_id']?.toString(),
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
      deleted: _boolFromDb(map['deleted']),
    );
  }
}

class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.supplementId,
    required this.quantityUnits,
    required this.occurredAt,
    required this.reason,
    required this.createdAt,
    required this.updatedAt,
    this.profileId,
    this.intakeId,
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String supplementId;
  final String? profileId;
  final String? intakeId;
  final double quantityUnits;
  final DateTime occurredAt;
  final String reason;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'supplement_id': supplementId,
    'profile_id': profileId,
    'intake_id': intakeId,
    'quantity_units': quantityUnits,
    'occurred_at': _iso(occurredAt),
    'reason': reason,
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory InventoryMovement.fromMap(Map<String, Object?> map) =>
      InventoryMovement(
        id: '${map['id']}',
        supplementId: '${map['supplement_id']}',
        profileId: map['profile_id']?.toString(),
        intakeId: map['intake_id']?.toString(),
        quantityUnits: (map['quantity_units'] as num).toDouble(),
        occurredAt: _date(map['occurred_at']),
        reason: '${map['reason']}',
        notes: map['notes']?.toString() ?? '',
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

class SupplementSchedule {
  const SupplementSchedule({
    required this.id,
    required this.profileId,
    required this.supplementId,
    required this.dose,
    required this.unit,
    required this.timeOfDay,
    required this.weekdays,
    required this.createdAt,
    required this.updatedAt,
    this.instructions = '',
    this.startDate,
    this.endDate,
    this.active = true,
    this.reminderEnabled = false,
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String supplementId;
  final double dose;
  final String unit;
  final String timeOfDay;
  final List<String> weekdays;
  final String instructions;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool active;
  final bool reminderEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'supplement_id': supplementId,
    'dose': dose,
    'unit': unit,
    'time_of_day': timeOfDay,
    'weekdays_json': jsonEncode(normalizeWeekdays(weekdays)),
    'instructions': instructions,
    'start_date': startDate?.toIso8601String().split('T').first,
    'end_date': endDate?.toIso8601String().split('T').first,
    'active': active ? 1 : 0,
    'reminder_enabled': reminderEnabled ? 1 : 0,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory SupplementSchedule.fromMap(Map<String, Object?> map) =>
      SupplementSchedule(
        id: '${map['id']}',
        profileId: '${map['profile_id']}',
        supplementId: '${map['supplement_id']}',
        dose: (map['dose'] as num).toDouble(),
        unit: '${map['unit']}',
        timeOfDay: '${map['time_of_day']}',
        weekdays: normalizeWeekdays(_strings(map['weekdays_json'])),
        instructions: map['instructions']?.toString() ?? '',
        startDate: map['start_date'] == null
            ? null
            : DateTime.tryParse('${map['start_date']}'),
        endDate: map['end_date'] == null
            ? null
            : DateTime.tryParse('${map['end_date']}'),
        active: _boolFromDb(map['active']),
        reminderEnabled: _boolFromDb(map['reminder_enabled']),
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

class HealthEventDefinition {
  const HealthEventDefinition({
    required this.id,
    required this.profileId,
    required this.kind,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.defaultUnit,
    this.useScore = false,
    this.valueMode = TagValueMode.occurrence,
    this.portionAmount,
    this.portionLabel,
    this.includeInCheckIn = false,
    this.colorValue,
    this.archived = false,
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final EventKind kind;
  final String name;

  /// For a tag in [TagValueMode.amount], the one fixed unit every entry for
  /// this definition is stored in, e.g. "g" or "ml". A free-text unit per
  /// entry is what made correlation impossible, so the unit is now a
  /// per-definition contract rather than a per-entry suggestion.
  final String? defaultUnit;
  final bool useScore;
  final TagValueMode valueMode;

  /// One portion in [defaultUnit] — e.g. 6 for "6 g of beans" — powering the
  /// quick +1-portion logging shortcut. Null means no shortcut has been
  /// defined yet; exact-amount entry still works.
  final double? portionAmount;

  /// Free-text description of what one portion means, e.g. "filter coffee".
  final String? portionLabel;

  /// Whether this tag is asked about in the daily check-in. Symptoms are
  /// always asked about and ignore this field.
  final bool includeInCheckIn;

  final int? colorValue;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'kind': kind.name,
    'name': name,
    'default_unit': defaultUnit,
    'use_score': useScore ? 1 : 0,
    'value_mode': valueMode.name,
    'portion_amount': portionAmount,
    'portion_label': portionLabel,
    'include_in_check_in': includeInCheckIn ? 1 : 0,
    'color_value': colorValue,
    'archived': archived ? 1 : 0,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory HealthEventDefinition.fromMap(Map<String, Object?> map) =>
      HealthEventDefinition(
        id: '${map['id']}',
        profileId: '${map['profile_id']}',
        kind: EventKind.values.firstWhere(
          (value) => value.name == map['kind'],
          orElse: () => EventKind.tag,
        ),
        name: '${map['name']}',
        defaultUnit: map['default_unit']?.toString(),
        useScore: _boolFromDb(map['use_score']),
        valueMode: TagValueMode.values.firstWhere(
          (value) => value.name == map['value_mode'],
          orElse: () => TagValueMode.occurrence,
        ),
        portionAmount: (map['portion_amount'] as num?)?.toDouble(),
        portionLabel: map['portion_label']?.toString(),
        includeInCheckIn: _boolFromDb(map['include_in_check_in']),
        colorValue: (map['color_value'] as num?)?.toInt(),
        archived: _boolFromDb(map['archived']),
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

class SupplementIntake {
  const SupplementIntake({
    required this.id,
    required this.profileId,
    required this.supplementId,
    required this.takenAt,
    required this.dose,
    required this.unit,
    required this.createdAt,
    required this.updatedAt,
    this.scheduleId,
    this.skipped = false,
    this.notes = '',
    this.ingredientSnapshot = const [],
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String supplementId;
  final String? scheduleId;
  final DateTime takenAt;
  final double dose;
  final String unit;
  final bool skipped;
  final String notes;
  final List<Map<String, Object?>> ingredientSnapshot;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'supplement_id': supplementId,
    'schedule_id': scheduleId,
    'taken_at': _iso(takenAt),
    'dose': dose,
    'unit': unit,
    'skipped': skipped ? 1 : 0,
    'notes': notes,
    'ingredients_json': jsonEncode(ingredientSnapshot),
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory SupplementIntake.fromMap(Map<String, Object?> map) {
    final decoded = jsonDecode(map['ingredients_json']?.toString() ?? '[]');
    return SupplementIntake(
      id: '${map['id']}',
      profileId: '${map['profile_id']}',
      supplementId: '${map['supplement_id']}',
      scheduleId: map['schedule_id']?.toString(),
      takenAt: _date(map['taken_at']),
      dose: (map['dose'] as num).toDouble(),
      unit: '${map['unit']}',
      skipped: _boolFromDb(map['skipped']),
      notes: map['notes']?.toString() ?? '',
      ingredientSnapshot: decoded is List
          ? decoded
                .whereType<Map>()
                .map((item) => Map<String, Object?>.from(item))
                .toList()
          : const [],
      createdAt: _date(map['created_at']),
      updatedAt: _date(map['updated_at']),
      deleted: _boolFromDb(map['deleted']),
    );
  }
}

class HealthEvent {
  const HealthEvent({
    required this.id,
    required this.profileId,
    required this.kind,
    required this.name,
    required this.observedAt,
    required this.createdAt,
    required this.updatedAt,
    this.score,
    this.definitionId,
    this.numericValue,
    this.unit,
    this.durationMinutes,
    this.notes = '',
    this.colorValue,
    this.archived = false,
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String? definitionId;
  final EventKind kind;
  final String name;
  final DateTime observedAt;
  final int? score;
  final double? numericValue;
  final String? unit;
  final int? durationMinutes;
  final String notes;
  final int? colorValue;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'definition_id': definitionId,
    'kind': kind.name,
    'name': name,
    'observed_at': _iso(observedAt),
    'score': score,
    'numeric_value': numericValue,
    'unit': unit,
    'duration_minutes': durationMinutes,
    'notes': notes,
    'color_value': colorValue,
    'archived': archived ? 1 : 0,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory HealthEvent.fromMap(Map<String, Object?> map) => HealthEvent(
    id: '${map['id']}',
    profileId: '${map['profile_id']}',
    definitionId: map['definition_id']?.toString(),
    kind: EventKind.values.firstWhere(
      (value) => value.name == map['kind'],
      orElse: () => EventKind.tag,
    ),
    name: '${map['name']}',
    observedAt: _date(map['observed_at']),
    score: (map['score'] as num?)?.toInt(),
    numericValue: (map['numeric_value'] as num?)?.toDouble(),
    unit: map['unit']?.toString(),
    durationMinutes: (map['duration_minutes'] as num?)?.toInt(),
    notes: map['notes']?.toString() ?? '',
    colorValue: (map['color_value'] as num?)?.toInt(),
    archived: _boolFromDb(map['archived']),
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class Biomarker {
  const Biomarker({
    required this.id,
    required this.canonicalName,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
    this.category = '',
    this.defaultUnit = '',
    this.priceEur,
    this.labName,
    this.priceCheckedAt,
    this.description = '',
    this.synonyms = const [],
    this.isTemporary = false,
    this.deleted = false,
  });

  final String id;
  final String canonicalName;
  final String displayName;
  final String category;
  final String defaultUnit;
  final double? priceEur;
  final String? labName;
  final DateTime? priceCheckedAt;
  final String description;
  final List<String> synonyms;
  final bool isTemporary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'canonical_name': canonicalName,
    'display_name': displayName,
    'category': category,
    'default_unit': defaultUnit,
    'price_eur': priceEur,
    'lab_name': labName,
    'price_checked_at': priceCheckedAt == null ? null : _iso(priceCheckedAt!),
    'description': description,
    'synonyms_json': jsonEncode(synonyms),
    'is_temporary': isTemporary ? 1 : 0,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory Biomarker.fromMap(Map<String, Object?> map) => Biomarker(
    id: '${map['id']}',
    canonicalName: '${map['canonical_name']}',
    displayName: '${map['display_name']}',
    category: map['category']?.toString() ?? '',
    defaultUnit: map['default_unit']?.toString() ?? '',
    priceEur: (map['price_eur'] as num?)?.toDouble(),
    labName: map['lab_name']?.toString(),
    priceCheckedAt: map['price_checked_at'] == null
        ? null
        : _date(map['price_checked_at']),
    description: map['description']?.toString() ?? '',
    synonyms: _strings(map['synonyms_json']),
    isTemporary: _boolFromDb(map['is_temporary']),
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class BiomarkerReferenceRange {
  const BiomarkerReferenceRange({
    required this.id,
    required this.biomarkerId,
    required this.rangeType,
    required this.unit,
    required this.createdAt,
    required this.updatedAt,
    this.sex,
    this.ageMin,
    this.ageMax,
    this.low,
    this.high,
    this.optimalLow,
    this.optimalHigh,
    this.evidenceLabel,
    this.evidenceUrl,
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String biomarkerId;
  final String rangeType;
  final String? sex;
  final int? ageMin;
  final int? ageMax;
  final double? low;
  final double? high;
  final double? optimalLow;
  final double? optimalHigh;
  final String unit;
  final String? evidenceLabel;
  final String? evidenceUrl;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'biomarker_id': biomarkerId,
    'range_type': rangeType,
    'sex': sex,
    'age_min': ageMin,
    'age_max': ageMax,
    'low': low,
    'high': high,
    'optimal_low': optimalLow,
    'optimal_high': optimalHigh,
    'unit': unit,
    'evidence_label': evidenceLabel,
    'evidence_url': evidenceUrl,
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory BiomarkerReferenceRange.fromMap(Map<String, Object?> map) =>
      BiomarkerReferenceRange(
        id: '${map['id']}',
        biomarkerId: '${map['biomarker_id']}',
        rangeType: '${map['range_type']}',
        sex: map['sex']?.toString(),
        ageMin: (map['age_min'] as num?)?.toInt(),
        ageMax: (map['age_max'] as num?)?.toInt(),
        low: (map['low'] as num?)?.toDouble(),
        high: (map['high'] as num?)?.toDouble(),
        optimalLow: (map['optimal_low'] as num?)?.toDouble(),
        optimalHigh: (map['optimal_high'] as num?)?.toDouble(),
        unit: '${map['unit']}',
        evidenceLabel: map['evidence_label']?.toString(),
        evidenceUrl: map['evidence_url']?.toString(),
        notes: map['notes']?.toString() ?? '',
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

class ProfileBiomarkerTarget {
  const ProfileBiomarkerTarget({
    required this.id,
    required this.profileId,
    required this.biomarkerId,
    required this.unit,
    required this.createdAt,
    required this.updatedAt,
    this.low,
    this.high,
    this.borderlineLow,
    this.borderlineHigh,
    this.source = 'personal',
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String biomarkerId;
  final double? low;
  final double? high;
  final double? borderlineLow;
  final double? borderlineHigh;
  final String unit;
  final String source;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'biomarker_id': biomarkerId,
    'low': low,
    'high': high,
    'borderline_low': borderlineLow,
    'borderline_high': borderlineHigh,
    'unit': unit,
    'source': source,
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory ProfileBiomarkerTarget.fromMap(Map<String, Object?> map) =>
      ProfileBiomarkerTarget(
        id: '${map['id']}',
        profileId: '${map['profile_id']}',
        biomarkerId: '${map['biomarker_id']}',
        low: (map['low'] as num?)?.toDouble(),
        high: (map['high'] as num?)?.toDouble(),
        borderlineLow: (map['borderline_low'] as num?)?.toDouble(),
        borderlineHigh: (map['borderline_high'] as num?)?.toDouble(),
        unit: '${map['unit']}',
        source: map['source']?.toString() ?? 'personal',
        notes: map['notes']?.toString() ?? '',
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

/// Ties one trend — either a biomarker or a health event definition — to the
/// supplement ingredient drawn underneath it.
///
/// The ingredient is stored as the name/unit pair the intake snapshots already
/// use, not as a supplement id, because the same ingredient usually arrives
/// through several products and the exposure aggregate is keyed the same way.
/// Exactly one of [biomarkerId] and [definitionId] is set; the unit is part of
/// the identity because an ingredient recorded in IU and one recorded in µg are
/// different series that must never be added together.
class TrendDoseLink {
  const TrendDoseLink({
    required this.id,
    required this.profileId,
    required this.ingredientName,
    required this.ingredientUnit,
    required this.createdAt,
    required this.updatedAt,
    this.biomarkerId,
    this.definitionId,
    this.deleted = false,
  });

  final String id;
  final String profileId;

  /// Set when this link belongs to a biomarker trend.
  final String? biomarkerId;

  /// Set when this link belongs to a symptom or tag trend.
  final String? definitionId;

  final String ingredientName;
  final String ingredientUnit;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  /// Key matching how [ingredientExposure] aggregates, so a link resolves to a
  /// dose series without a second naming convention.
  String get exposureKey =>
      '${ingredientName.toLowerCase()}|${ingredientUnit.toLowerCase()}';

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'biomarker_id': biomarkerId,
    'definition_id': definitionId,
    'ingredient_name': ingredientName,
    'ingredient_unit': ingredientUnit,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory TrendDoseLink.fromMap(Map<String, Object?> map) => TrendDoseLink(
    id: '${map['id']}',
    profileId: '${map['profile_id']}',
    biomarkerId: map['biomarker_id']?.toString(),
    definitionId: map['definition_id']?.toString(),
    ingredientName: '${map['ingredient_name']}',
    ingredientUnit: '${map['ingredient_unit']}',
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class Measurement {
  const Measurement({
    required this.id,
    required this.profileId,
    required this.biomarkerId,
    required this.takenAt,
    required this.value,
    required this.unit,
    required this.createdAt,
    required this.updatedAt,
    this.documentId,
    this.canonicalValue,
    this.canonicalUnit,
    this.conversionStatus = 'not_required',
    this.labRefLow,
    this.labRefHigh,
    this.page,
    this.rowText,
    this.extractionConfidence,
    this.flags = const [],
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String biomarkerId;
  final String? documentId;
  final DateTime takenAt;
  final double value;
  final String unit;
  final double? canonicalValue;
  final String? canonicalUnit;
  final String conversionStatus;
  final double? labRefLow;
  final double? labRefHigh;
  final int? page;
  final String? rowText;
  final double? extractionConfidence;
  final List<String> flags;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'biomarker_id': biomarkerId,
    'document_id': documentId,
    'taken_at': _iso(takenAt),
    'value': value,
    'unit_reported': unit,
    'canonical_value': canonicalValue,
    'canonical_unit': canonicalUnit,
    'conversion_status': conversionStatus,
    'lab_ref_low': labRefLow,
    'lab_ref_high': labRefHigh,
    'page': page,
    'row_text': rowText,
    'extraction_confidence': extractionConfidence,
    'flags_json': jsonEncode(flags),
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory Measurement.fromMap(Map<String, Object?> map) => Measurement(
    id: '${map['id']}',
    profileId: '${map['profile_id']}',
    biomarkerId: '${map['biomarker_id']}',
    documentId: map['document_id']?.toString(),
    takenAt: _date(map['taken_at']),
    value: (map['value'] as num).toDouble(),
    unit: '${map['unit_reported']}',
    canonicalValue: (map['canonical_value'] as num?)?.toDouble(),
    canonicalUnit: map['canonical_unit']?.toString(),
    conversionStatus: map['conversion_status']?.toString() ?? 'not_required',
    labRefLow: (map['lab_ref_low'] as num?)?.toDouble(),
    labRefHigh: (map['lab_ref_high'] as num?)?.toDouble(),
    page: (map['page'] as num?)?.toInt(),
    rowText: map['row_text']?.toString(),
    extractionConfidence: (map['extraction_confidence'] as num?)?.toDouble(),
    flags: _strings(map['flags_json']),
    notes: map['notes']?.toString() ?? '',
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class HealthDocument {
  const HealthDocument({
    required this.id,
    required this.profileId,
    required this.fileName,
    required this.createdAt,
    required this.updatedAt,
    this.mimeType = 'application/pdf',
    this.sha256,
    this.localPath,
    this.oneDriveItemId,
    this.documentDate,
    this.parsedAt,
    this.parserProvider,
    this.parserModel,
    this.labName,
    this.reportComment = '',
    this.parseStatus = 'saved',
    this.warnings = const [],
    this.errors = const [],
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String fileName;
  final String mimeType;
  final String? sha256;
  final String? localPath;
  final String? oneDriveItemId;
  final DateTime? documentDate;
  final DateTime? parsedAt;
  final String? parserProvider;
  final String? parserModel;
  final String? labName;
  final String reportComment;
  final String parseStatus;
  final List<String> warnings;
  final List<String> errors;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'file_name': fileName,
    'mime_type': mimeType,
    'sha256': sha256,
    'local_path': localPath,
    'one_drive_item_id': oneDriveItemId,
    'document_date': documentDate?.toIso8601String().split('T').first,
    'parsed_at': parsedAt == null ? null : _iso(parsedAt!),
    'parser_provider': parserProvider,
    'parser_model': parserModel,
    'lab_name': labName,
    'report_comment': reportComment,
    'parse_status': parseStatus,
    'warnings_json': jsonEncode(warnings),
    'errors_json': jsonEncode(errors),
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory HealthDocument.fromMap(Map<String, Object?> map) => HealthDocument(
    id: '${map['id']}',
    profileId: '${map['profile_id']}',
    fileName: '${map['file_name']}',
    mimeType: map['mime_type']?.toString() ?? 'application/pdf',
    sha256: map['sha256']?.toString(),
    localPath: map['local_path']?.toString(),
    oneDriveItemId: map['one_drive_item_id']?.toString(),
    documentDate: map['document_date'] == null
        ? null
        : DateTime.tryParse('${map['document_date']}'),
    parsedAt: map['parsed_at'] == null ? null : _date(map['parsed_at']),
    parserProvider: map['parser_provider']?.toString(),
    parserModel: map['parser_model']?.toString(),
    labName: map['lab_name']?.toString(),
    reportComment: map['report_comment']?.toString() ?? '',
    parseStatus: map['parse_status']?.toString() ?? 'saved',
    warnings: _strings(map['warnings_json']),
    errors: _strings(map['errors_json']),
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class NamedHealthRecord {
  const NamedHealthRecord({
    required this.id,
    required this.profileId,
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.status = 'active',
    this.dose,
    this.unit,
    this.schedule,
    this.startDate,
    this.endDate,
    this.priority,
    this.targetDate,
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String name;
  final String kind;
  final String status;
  final double? dose;
  final String? unit;
  final String? schedule;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? priority;
  final DateTime? targetDate;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'name': name,
    'kind': kind,
    'status': status,
    'dose': dose,
    'unit': unit,
    'schedule': schedule,
    'start_date': startDate?.toIso8601String().split('T').first,
    'end_date': endDate?.toIso8601String().split('T').first,
    'priority': priority,
    'target_date': targetDate?.toIso8601String().split('T').first,
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory NamedHealthRecord.fromMap(Map<String, Object?> map) =>
      NamedHealthRecord(
        id: '${map['id']}',
        profileId: '${map['profile_id']}',
        name: '${map['name']}',
        kind: '${map['kind']}',
        status: map['status']?.toString() ?? 'active',
        dose: (map['dose'] as num?)?.toDouble(),
        unit: map['unit']?.toString(),
        schedule: map['schedule']?.toString(),
        startDate: map['start_date'] == null
            ? null
            : DateTime.tryParse('${map['start_date']}'),
        endDate: map['end_date'] == null
            ? null
            : DateTime.tryParse('${map['end_date']}'),
        priority: (map['priority'] as num?)?.toInt(),
        targetDate: map['target_date'] == null
            ? null
            : DateTime.tryParse('${map['target_date']}'),
        notes: map['notes']?.toString() ?? '',
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

class BiomarkerList {
  const BiomarkerList({
    required this.id,
    required this.profileId,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.items = const [],
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<BiomarkerListItem> items;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'name': name,
    'description': description,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory BiomarkerList.fromMap(
    Map<String, Object?> map,
    List<BiomarkerListItem> items,
  ) => BiomarkerList(
    id: '${map['id']}',
    profileId: '${map['profile_id']}',
    name: '${map['name']}',
    description: map['description']?.toString() ?? '',
    createdAt: _date(map['created_at']),
    updatedAt: _date(map['updated_at']),
    items: items,
    deleted: _boolFromDb(map['deleted']),
  );
}

class BiomarkerListItem {
  const BiomarkerListItem({
    required this.id,
    required this.listId,
    required this.biomarkerId,
    required this.createdAt,
    required this.updatedAt,
    this.dueIntervalDays,
    this.notes = '',
    this.deleted = false,
  });

  final String id;
  final String listId;
  final String biomarkerId;
  final int? dueIntervalDays;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'list_id': listId,
    'biomarker_id': biomarkerId,
    'due_interval_days': dueIntervalDays,
    'notes': notes,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'deleted': deleted ? 1 : 0,
  };

  factory BiomarkerListItem.fromMap(Map<String, Object?> map) =>
      BiomarkerListItem(
        id: '${map['id']}',
        listId: '${map['list_id']}',
        biomarkerId: '${map['biomarker_id']}',
        dueIntervalDays: (map['due_interval_days'] as num?)?.toInt(),
        notes: map['notes']?.toString() ?? '',
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        deleted: _boolFromDb(map['deleted']),
      );
}

/// A biomarker that is due for measurement.
///
/// One entry per biomarker, never one per list: the same marker often sits on
/// several lists, and counting it once per membership made "biomarkers due"
/// report a number far higher than the number of tests actually needed.
class DueBiomarker {
  const DueBiomarker({
    required this.biomarker,
    required this.listNames,
    required this.dueDate,
    required this.intervalDays,
    this.lastMeasuredAt,
  });

  final Biomarker biomarker;

  /// Every list that asks for this biomarker, sorted for a stable display.
  final List<String> listNames;

  final DateTime? lastMeasuredAt;

  /// The earliest date any of those lists wants it by — the shortest interval
  /// wins, because meeting that one satisfies the others too.
  final DateTime dueDate;

  /// The interval behind [dueDate].
  final int intervalDays;

  int get daysOverdue => DateTime.now().difference(dueDate).inDays;
}

class LabPlanItem {
  const LabPlanItem({
    required this.id,
    required this.planId,
    required this.biomarkerId,
    required this.biomarkerName,
    required this.tier,
    required this.priority,
    required this.rationale,
    required this.evidenceClass,
    this.priceEur,
    this.preparation = '',
    this.checked = false,
    this.createdAt,
    this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String planId;
  final String biomarkerId;
  final String biomarkerName;
  final LabTier tier;
  final int priority;
  final String rationale;
  final EvidenceClass evidenceClass;
  final double? priceEur;
  final String preparation;
  final bool checked;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'plan_id': planId,
    'biomarker_id': biomarkerId,
    'biomarker_name': biomarkerName,
    'tier': tier.name,
    'priority': priority,
    'rationale': rationale,
    'evidence_class': evidenceClass.name,
    'price_eur': priceEur,
    'preparation': preparation,
    'checked': checked ? 1 : 0,
    'created_at': _iso(createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    'updated_at': _iso(
      updatedAt ?? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    ),
    'deleted': deleted ? 1 : 0,
  };

  factory LabPlanItem.fromMap(Map<String, Object?> map) => LabPlanItem(
    id: '${map['id']}',
    planId: '${map['plan_id']}',
    biomarkerId: '${map['biomarker_id']}',
    biomarkerName: '${map['biomarker_name']}',
    tier: LabTier.values.byName('${map['tier']}'),
    priority: (map['priority'] as num).toInt(),
    rationale: '${map['rationale']}',
    evidenceClass: EvidenceClass.values.byName('${map['evidence_class']}'),
    priceEur: (map['price_eur'] as num?)?.toDouble(),
    preparation: map['preparation']?.toString() ?? '',
    checked: _boolFromDb(map['checked']),
    createdAt: map['created_at'] == null ? null : _date(map['created_at']),
    updatedAt: map['updated_at'] == null ? null : _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}

class LabPlan {
  const LabPlan({
    required this.id,
    required this.profileId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.items,
    this.plannedFor,
    this.currency = 'EUR',
    this.contextHash = '',
    this.provider,
    this.model,
    this.status = 'draft',
    this.verificationSummary = '',
    this.verificationWarnings = const [],
    this.verificationCitations = const [],
    this.verifiedAt,
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? plannedFor;
  final String currency;
  final String contextHash;
  final String? provider;
  final String? model;
  final String status;
  final String verificationSummary;
  final List<String> verificationWarnings;
  final List<String> verificationCitations;
  final DateTime? verifiedAt;
  final bool deleted;
  final List<LabPlanItem> items;

  List<LabPlanItem> itemsThrough(LabTier tier) => items
      .where((item) => item.tier.index <= tier.index)
      .toList(growable: false);

  double knownTotal(LabTier tier) =>
      itemsThrough(tier).fold(0, (total, item) => total + (item.priceEur ?? 0));

  int missingPriceCount(LabTier tier) =>
      itemsThrough(tier).where((item) => item.priceEur == null).length;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'title': title,
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt),
    'planned_for': plannedFor?.toIso8601String().split('T').first,
    'currency': currency,
    'context_hash': contextHash,
    'provider': provider,
    'model': model,
    'status': status,
    'verification_summary': verificationSummary,
    'verification_warnings_json': jsonEncode(verificationWarnings),
    'verification_citations_json': jsonEncode(verificationCitations),
    'verified_at': verifiedAt == null ? null : _iso(verifiedAt!),
    'deleted': deleted ? 1 : 0,
  };

  factory LabPlan.fromMap(Map<String, Object?> map, List<LabPlanItem> items) =>
      LabPlan(
        id: '${map['id']}',
        profileId: '${map['profile_id']}',
        title: '${map['title']}',
        createdAt: _date(map['created_at']),
        updatedAt: _date(map['updated_at']),
        plannedFor: map['planned_for'] == null
            ? null
            : DateTime.tryParse('${map['planned_for']}'),
        currency: map['currency']?.toString() ?? 'EUR',
        contextHash: map['context_hash']?.toString() ?? '',
        provider: map['provider']?.toString(),
        model: map['model']?.toString(),
        status: map['status']?.toString() ?? 'draft',
        verificationSummary: map['verification_summary']?.toString() ?? '',
        verificationWarnings: _strings(map['verification_warnings_json']),
        verificationCitations: _strings(map['verification_citations_json']),
        verifiedAt: map['verified_at'] == null
            ? null
            : _date(map['verified_at']),
        deleted: _boolFromDb(map['deleted']),
        items: items,
      );
}

class AdvisorMessage {
  const AdvisorMessage({
    required this.id,
    required this.profileId,
    required this.conversationId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.citations = const [],
    this.updatedAt,
    this.deleted = false,
  });

  final String id;
  final String profileId;
  final String conversationId;
  final String role;
  final String content;
  final List<String> citations;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool deleted;

  Map<String, Object?> toMap() => {
    'id': id,
    'profile_id': profileId,
    'conversation_id': conversationId,
    'role': role,
    'content': content,
    'citations_json': jsonEncode(citations),
    'created_at': _iso(createdAt),
    'updated_at': _iso(updatedAt ?? createdAt),
    'deleted': deleted ? 1 : 0,
  };

  factory AdvisorMessage.fromMap(Map<String, Object?> map) => AdvisorMessage(
    id: '${map['id']}',
    profileId: '${map['profile_id']}',
    conversationId: '${map['conversation_id']}',
    role: '${map['role']}',
    content: '${map['content']}',
    citations: _strings(map['citations_json']),
    createdAt: _date(map['created_at']),
    updatedAt: map['updated_at'] == null ? null : _date(map['updated_at']),
    deleted: _boolFromDb(map['deleted']),
  );
}
