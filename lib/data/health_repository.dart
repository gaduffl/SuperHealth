import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../biomarkers/unit_conversion_service.dart';
import '../domain/entities.dart';
import 'app_database.dart';

class _SynchronizedColumn {
  const _SynchronizedColumn(this.name, this.type, this.required);

  final String name;
  final String type;
  final bool required;
}

class _SynchronizedReference {
  const _SynchronizedReference(this.table, this.column, this.parent);

  final String table;
  final String column;
  final String parent;
}

const _instantColumns = <String>{
  'created_at',
  'updated_at',
  'occurred_at',
  'taken_at',
  'observed_at',
  'price_checked_at',
  'parsed_at',
  'verified_at',
};
const _dateColumns = <String>{
  'date_of_birth',
  'start_date',
  'end_date',
  'target_date',
  'document_date',
  'planned_for',
};
const _binaryColumns = <String>{
  'deleted',
  'active',
  'low_stock_alerts',
  'reminder_enabled',
  'skipped',
  'use_score',
  'archived',
  'is_temporary',
  'checked',
};
const _jsonListColumns = <String>{
  'ingredients_json',
  'weekdays_json',
  'synonyms_json',
  'warnings_json',
  'errors_json',
  'flags_json',
  'citations_json',
  'verification_warnings_json',
  'verification_citations_json',
};
final _isoInstantPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(?:Z|[+-](\d{2}):(\d{2}))$',
);
final _dateOnlyPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

const _synchronizedReferences = <_SynchronizedReference>[
  _SynchronizedReference('supplement_schedules', 'profile_id', 'profiles'),
  _SynchronizedReference(
    'supplement_schedules',
    'supplement_id',
    'supplements',
  ),
  _SynchronizedReference('supplement_intakes', 'profile_id', 'profiles'),
  _SynchronizedReference('supplement_intakes', 'supplement_id', 'supplements'),
  _SynchronizedReference(
    'supplement_intakes',
    'schedule_id',
    'supplement_schedules',
  ),
  _SynchronizedReference('inventory_movements', 'supplement_id', 'supplements'),
  _SynchronizedReference('inventory_movements', 'profile_id', 'profiles'),
  _SynchronizedReference(
    'inventory_movements',
    'intake_id',
    'supplement_intakes',
  ),
  _SynchronizedReference('health_event_definitions', 'profile_id', 'profiles'),
  _SynchronizedReference('health_events', 'profile_id', 'profiles'),
  _SynchronizedReference(
    'health_events',
    'definition_id',
    'health_event_definitions',
  ),
  _SynchronizedReference('biomarker_ranges', 'biomarker_id', 'biomarkers'),
  _SynchronizedReference('profile_biomarker_targets', 'profile_id', 'profiles'),
  _SynchronizedReference(
    'profile_biomarker_targets',
    'biomarker_id',
    'biomarkers',
  ),
  _SynchronizedReference('documents', 'profile_id', 'profiles'),
  _SynchronizedReference('measurements', 'profile_id', 'profiles'),
  _SynchronizedReference('measurements', 'biomarker_id', 'biomarkers'),
  _SynchronizedReference('measurements', 'document_id', 'documents'),
  _SynchronizedReference('named_health_records', 'profile_id', 'profiles'),
  _SynchronizedReference('biomarker_lists', 'profile_id', 'profiles'),
  _SynchronizedReference('biomarker_list_items', 'list_id', 'biomarker_lists'),
  _SynchronizedReference('biomarker_list_items', 'biomarker_id', 'biomarkers'),
  _SynchronizedReference('lab_plans', 'profile_id', 'profiles'),
  _SynchronizedReference('lab_plan_items', 'plan_id', 'lab_plans'),
  _SynchronizedReference('lab_plan_items', 'biomarker_id', 'biomarkers'),
  _SynchronizedReference('advisor_messages', 'profile_id', 'profiles'),
];

Future<List<_SynchronizedColumn>> _synchronizedColumns(
  Database db,
  String table,
) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  if (rows.isEmpty) throw StateError('Unknown synchronized table $table.');
  return rows
      .map(
        (row) => _SynchronizedColumn(
          row['name'] as String,
          (row['type'] as String).toUpperCase(),
          row['notnull'] == 1 || row['pk'] == 1,
        ),
      )
      .toList(growable: false);
}

bool _isIsoInstant(Object? value) {
  if (value is! String) return false;
  final match = _isoInstantPattern.firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final offsetHour = match.group(7) == null ? 0 : int.parse(match.group(7)!);
  final offsetMinute = match.group(8) == null ? 0 : int.parse(match.group(8)!);
  return year >= 1 &&
      _isCalendarDay(year, month, day) &&
      hour <= 23 &&
      minute <= 59 &&
      second <= 59 &&
      offsetHour <= 14 &&
      (offsetHour < 14 || offsetMinute == 0) &&
      offsetMinute <= 59;
}

bool _isDateOnly(Object? value) {
  if (value is! String) return false;
  final match = _dateOnlyPattern.firstMatch(value);
  if (match == null) return false;
  return _isCalendarDay(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

bool _isCalendarDay(int year, int month, int day) {
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return false;
  }
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

bool _isJsonList(Object? value) {
  if (value is! String) return false;
  try {
    return jsonDecode(value) is List;
  } on FormatException {
    return false;
  }
}

void _validateJsonListContents(String table, String column, String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List) {
    throw FormatException('$table.$column must contain a JSON list.');
  }
  final expectsObjects = column == 'ingredients_json';
  final valid = expectsObjects
      ? decoded.every((item) => item is Map)
      : decoded.every((item) => item is String);
  if (!valid) {
    throw FormatException('$table.$column contains invalid list entries.');
  }
}

class HealthRepository {
  HealthRepository(
    this._database, {
    Uuid? uuid,
    UnitConversionService? unitConversionService,
  }) : _uuid = uuid ?? const Uuid(),
       _unitConversion = unitConversionService ?? UnitConversionService();

  final AppDatabase _database;
  final Uuid _uuid;
  final UnitConversionService _unitConversion;

  String newId() => _uuid.v4();

  Future<List<Profile>> profiles() async {
    final db = await _database.database;
    final rows = await db.query(
      'profiles',
      where: 'deleted = 0',
      orderBy: 'display_name COLLATE NOCASE',
    );
    return rows.map(Profile.fromMap).toList();
  }

  Future<Profile> createProfile({
    required String displayName,
    DateTime? dateOfBirth,
    String? sex,
    double? heightCm,
    double? weightKg,
    String notes = '',
  }) async {
    final now = DateTime.now();
    final profile = Profile(
      id: newId(),
      displayName: displayName.trim(),
      dateOfBirth: dateOfBirth,
      sex: sex,
      heightCm: heightCm,
      weightKg: weightKg,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _validateProfile(profile);
    final db = await _database.database;
    await db.insert('profiles', profile.toMap());
    return profile;
  }

  Future<void> saveProfile(Profile profile) async {
    _validateProfile(profile);
    final db = await _database.database;
    await db.insert(
      'profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String table, String id) async {
    if (!AppDatabase.synchronizedTables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Table is not synchronized.');
    }
    final db = await _database.database;
    final changed = await db.update(
      table,
      {'deleted': 1, 'updated_at': DateTime.now().toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw StateError('The record no longer exists. Refresh and try again.');
    }
  }

  Future<List<Supplement>> supplements([String? profileId]) async {
    final db = await _database.database;
    final rows = await db.query(
      'supplements',
      where: 'deleted = 0',
      orderBy: 'active DESC, name COLLATE NOCASE',
    );
    return rows.map(Supplement.fromMap).toList();
  }

  Future<void> saveSupplement(Supplement supplement) async {
    _validateSupplement(supplement);
    final db = await _database.database;
    await db.insert(
      'supplements',
      supplement.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<InventoryMovement>> inventoryMovements({
    String? supplementId,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'inventory_movements',
      where: supplementId == null
          ? 'deleted = 0'
          : 'supplement_id = ? AND deleted = 0',
      whereArgs: supplementId == null ? null : [supplementId],
      orderBy: 'occurred_at DESC, created_at DESC',
    );
    return rows.map(InventoryMovement.fromMap).toList();
  }

  Future<Map<String, double>> stockLevels() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT supplement_id, COALESCE(SUM(quantity_units), 0) AS stock
      FROM inventory_movements
      WHERE deleted = 0
      GROUP BY supplement_id
    ''');
    return {
      for (final row in rows)
        '${row['supplement_id']}': (row['stock'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<void> saveInventoryMovement(InventoryMovement movement) async {
    _validateInventoryMovement(movement);
    final db = await _database.database;
    await db.insert(
      'inventory_movements',
      movement.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SupplementSchedule>> schedules(String profileId) async {
    final db = await _database.database;
    final rows = await db.query(
      'supplement_schedules',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'time_of_day, supplement_id',
    );
    return rows.map(SupplementSchedule.fromMap).toList();
  }

  Future<List<SupplementSchedule>> householdSchedules() async {
    final db = await _database.database;
    final rows = await db.query(
      'supplement_schedules',
      where: 'active = 1 AND deleted = 0',
      orderBy: 'profile_id, time_of_day, supplement_id',
    );
    return rows.map(SupplementSchedule.fromMap).toList();
  }

  /// Returns every live schedule that references a shared supplement.
  ///
  /// This deliberately includes inactive schedules: deleting a household
  /// supplement must not leave an archived schedule pointing at it for a
  /// different profile.
  Future<List<SupplementSchedule>> schedulesForSupplement(
    String supplementId,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      'supplement_schedules',
      where: 'supplement_id = ? AND deleted = 0',
      whereArgs: [supplementId],
      orderBy: 'profile_id, time_of_day, id',
    );
    return rows.map(SupplementSchedule.fromMap).toList();
  }

  /// Tombstones a household supplement and every schedule that references it
  /// as one atomic ledger change. Historical intakes and inventory movements
  /// remain available as evidence.
  Future<void> deleteSupplementWithSchedules(String supplementId) async {
    final db = await _database.database;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final changed = await txn.update(
        'supplements',
        {'deleted': 1, 'updated_at': updatedAt},
        where: 'id = ? AND deleted = 0',
        whereArgs: [supplementId],
      );
      if (changed != 1) {
        throw StateError(
          'The supplement no longer exists. Refresh and try again.',
        );
      }
      await txn.update(
        'supplement_schedules',
        {'deleted': 1, 'updated_at': updatedAt},
        where: 'supplement_id = ? AND deleted = 0',
        whereArgs: [supplementId],
      );
    });
  }

  Future<void> saveSchedule(SupplementSchedule schedule) async {
    _validateSchedule(schedule);
    final db = await _database.database;
    await db.insert(
      'supplement_schedules',
      schedule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SupplementIntake>> intakes(
    String profileId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _database.database;
    final where = <String>['profile_id = ?', 'deleted = 0'];
    final args = <Object?>[profileId];
    if (from != null) {
      where.add('taken_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.add('taken_at < ?');
      args.add(to.toUtc().toIso8601String());
    }
    final rows = await db.query(
      'supplement_intakes',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'taken_at DESC',
    );
    return rows.map(SupplementIntake.fromMap).toList();
  }

  Future<void> saveIntake(
    SupplementIntake intake, {
    double? inventoryUnits,
  }) async {
    _validateIntake(intake);
    if (inventoryUnits != null) {
      _requireNonNegativeFinite(inventoryUnits, 'Inventory units');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        'supplement_intakes',
        intake.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final existing = await txn.query(
        'inventory_movements',
        where: 'intake_id = ?',
        whereArgs: [intake.id],
        limit: 1,
      );
      if (intake.deleted || intake.skipped || inventoryUnits == null) {
        if (existing.isNotEmpty) {
          await txn.update(
            'inventory_movements',
            {
              'deleted': 1,
              'updated_at': intake.updatedAt.toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [existing.single['id']],
          );
        }
        return;
      }
      final now = intake.updatedAt;
      final movement = InventoryMovement(
        id: existing.isEmpty ? newId() : '${existing.single['id']}',
        supplementId: intake.supplementId,
        profileId: intake.profileId,
        intakeId: intake.id,
        quantityUnits: -inventoryUnits.abs(),
        occurredAt: intake.takenAt,
        reason: 'intake',
        createdAt: existing.isEmpty
            ? intake.createdAt
            : DateTime.tryParse('${existing.single['created_at']}') ?? now,
        updatedAt: now,
      );
      await txn.insert(
        'inventory_movements',
        movement.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<HealthEvent>> events(
    String profileId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final db = await _database.database;
    final where = <String>['profile_id = ?', 'deleted = 0'];
    final args = <Object?>[profileId];
    if (from != null) {
      where.add('observed_at >= ?');
      args.add(from.toUtc().toIso8601String());
    }
    if (to != null) {
      where.add('observed_at < ?');
      args.add(to.toUtc().toIso8601String());
    }
    final rows = await db.query(
      'health_events',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'observed_at DESC',
    );
    return rows.map(HealthEvent.fromMap).toList();
  }

  Future<void> saveEvent(HealthEvent event) async {
    _validateEvent(event);
    final db = await _database.database;
    await db.insert(
      'health_events',
      event.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HealthEventDefinition>> eventDefinitions(
    String profileId, {
    bool includeArchived = false,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'health_event_definitions',
      where: includeArchived
          ? 'profile_id = ? AND deleted = 0'
          : 'profile_id = ? AND archived = 0 AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'kind, name COLLATE NOCASE',
    );
    return rows.map(HealthEventDefinition.fromMap).toList();
  }

  Future<void> saveEventDefinition(HealthEventDefinition definition) async {
    final db = await _database.database;
    await db.insert(
      'health_event_definitions',
      definition.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Biomarker>> biomarkers() async {
    final db = await _database.database;
    final rows = await db.query(
      'biomarkers',
      where: 'deleted = 0',
      orderBy: 'category, display_name COLLATE NOCASE',
    );
    return rows.map(Biomarker.fromMap).toList();
  }

  Future<void> saveBiomarker(Biomarker biomarker) async {
    _validateBiomarker(biomarker);
    final db = await _database.database;
    await db.insert(
      'biomarkers',
      biomarker.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BiomarkerReferenceRange>> biomarkerRanges({
    String? biomarkerId,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'biomarker_ranges',
      where: biomarkerId == null
          ? 'deleted = 0'
          : 'biomarker_id = ? AND deleted = 0',
      whereArgs: biomarkerId == null ? null : [biomarkerId],
      orderBy: 'biomarker_id, range_type, sex, age_min',
    );
    return rows.map(BiomarkerReferenceRange.fromMap).toList();
  }

  Future<void> saveBiomarkerRange(BiomarkerReferenceRange range) async {
    _validateBiomarkerRange(range);
    final db = await _database.database;
    await db.insert(
      'biomarker_ranges',
      range.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveBiomarkerRanges(
    Iterable<BiomarkerReferenceRange> ranges,
  ) async {
    final values = ranges.toList(growable: false);
    for (final range in values) {
      _validateBiomarkerRange(range);
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      for (final range in values) {
        await txn.insert(
          'biomarker_ranges',
          range.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  void _validateBiomarkerRange(BiomarkerReferenceRange range) {
    _requireOptionalFinite(range.low, 'Reference low bound');
    _requireOptionalFinite(range.high, 'Reference high bound');
    _requireOptionalFinite(range.optimalLow, 'Optimal low bound');
    _requireOptionalFinite(range.optimalHigh, 'Optimal high bound');
    if (range.deleted) return;
    if (range.rangeType.trim().isEmpty || range.unit.trim().isEmpty) {
      throw ArgumentError('A range type and unit are required.');
    }
    if (range.low == null &&
        range.high == null &&
        range.optimalLow == null &&
        range.optimalHigh == null) {
      throw ArgumentError(
        'At least one reference or optimal bound is required.',
      );
    }
    if ((range.ageMin != null && (range.ageMin! < 0 || range.ageMin! > 150)) ||
        (range.ageMax != null && (range.ageMax! < 0 || range.ageMax! > 150)) ||
        (range.ageMin != null &&
            range.ageMax != null &&
            range.ageMin! > range.ageMax!) ||
        (range.low != null && range.high != null && range.low! > range.high!) ||
        (range.optimalLow != null &&
            range.optimalHigh != null &&
            range.optimalLow! > range.optimalHigh!)) {
      throw ArgumentError('Range bounds must be ordered low to high.');
    }
    final url = range.evidenceUrl;
    if (url != null && url.trim().isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !uri.hasAuthority ||
          uri.host.isEmpty ||
          (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw ArgumentError('Evidence URL must use http or https.');
      }
    }
  }

  /// Merges a temporary parser-created biomarker into an existing catalog entry.
  ///
  /// The operation is intentionally one transaction: a crash cannot leave a
  /// measurement pointing at a soft-deleted temporary entry.  Conflicting
  /// target/list/range links are retained as tombstones rather than discarded.
  Future<TemporaryBiomarkerResolution> mergeTemporaryBiomarker({
    required String temporaryBiomarkerId,
    required String canonicalBiomarkerId,
  }) async {
    if (temporaryBiomarkerId == canonicalBiomarkerId) {
      throw ArgumentError('Choose a different canonical biomarker.');
    }
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final counts = <String, int>{};
    await db.transaction((txn) async {
      final temporary = await txn.query(
        'biomarkers',
        where: 'id = ? AND deleted = 0',
        whereArgs: [temporaryBiomarkerId],
        limit: 1,
      );
      final canonical = await txn.query(
        'biomarkers',
        where: 'id = ? AND deleted = 0',
        whereArgs: [canonicalBiomarkerId],
        limit: 1,
      );
      if (temporary.length != 1 ||
          canonical.length != 1 ||
          (temporary.single['is_temporary'] as num?)?.toInt() != 1 ||
          (canonical.single['is_temporary'] as num?)?.toInt() == 1) {
        throw StateError(
          'The selected temporary or canonical biomarker is unavailable.',
        );
      }

      counts['measurements'] = await txn.update(
        'measurements',
        {'biomarker_id': canonicalBiomarkerId, 'updated_at': now},
        where: 'biomarker_id = ?',
        whereArgs: [temporaryBiomarkerId],
      );
      counts['lab_plan_items'] = await txn.update(
        'lab_plan_items',
        {
          'biomarker_id': canonicalBiomarkerId,
          'biomarker_name': '${canonical.single['display_name']}',
          'updated_at': now,
        },
        where: 'biomarker_id = ?',
        whereArgs: [temporaryBiomarkerId],
      );
      counts['targets'] = await _moveConstrainedRelations(
        txn,
        table: 'profile_biomarker_targets',
        temporaryBiomarkerId: temporaryBiomarkerId,
        canonicalBiomarkerId: canonicalBiomarkerId,
        constraintColumns: const ['profile_id'],
        now: now,
      );
      counts['list_items'] = await _moveConstrainedRelations(
        txn,
        table: 'biomarker_list_items',
        temporaryBiomarkerId: temporaryBiomarkerId,
        canonicalBiomarkerId: canonicalBiomarkerId,
        constraintColumns: const ['list_id'],
        now: now,
      );
      counts['ranges'] = await _moveRanges(
        txn,
        temporaryBiomarkerId: temporaryBiomarkerId,
        canonicalBiomarkerId: canonicalBiomarkerId,
        now: now,
      );
      final temporaryBiomarker = Biomarker.fromMap(temporary.single);
      final canonicalBiomarker = Biomarker.fromMap(canonical.single);
      final synonyms = _mergedSynonyms(temporaryBiomarker, canonicalBiomarker);
      await txn.update(
        'biomarkers',
        {'synonyms_json': jsonEncode(synonyms), 'updated_at': now},
        where: 'id = ?',
        whereArgs: [canonicalBiomarkerId],
      );
      await txn.update(
        'biomarkers',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ? AND deleted = 0',
        whereArgs: [temporaryBiomarkerId],
      );
    });
    return TemporaryBiomarkerResolution(
      temporaryBiomarkerId: temporaryBiomarkerId,
      canonicalBiomarkerId: canonicalBiomarkerId,
      movedMeasurements: counts['measurements'] ?? 0,
      movedTargets: counts['targets'] ?? 0,
      movedListItems: counts['list_items'] ?? 0,
      movedRanges: counts['ranges'] ?? 0,
      movedLabPlanItems: counts['lab_plan_items'] ?? 0,
    );
  }

  List<String> _mergedSynonyms(Biomarker temporary, Biomarker canonical) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in [
      ...canonical.synonyms,
      temporary.displayName,
      temporary.canonicalName,
      ...temporary.synonyms,
    ]) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (key.isEmpty || !seen.add(key)) continue;
      result.add(trimmed);
    }
    return result;
  }

  /// Keeps the temporary row and all its evidence, changing only its catalog
  /// status.  A caller may subsequently edit its regular catalog metadata.
  Future<void> makeTemporaryBiomarkerPermanent(String biomarkerId) async {
    final db = await _database.database;
    final changed = await db.update(
      'biomarkers',
      {
        'is_temporary': 0,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ? AND is_temporary = 1 AND deleted = 0',
      whereArgs: [biomarkerId],
    );
    if (changed != 1) {
      throw StateError('The temporary biomarker is no longer available.');
    }
  }

  Future<int> _moveConstrainedRelations(
    Transaction txn, {
    required String table,
    required String temporaryBiomarkerId,
    required String canonicalBiomarkerId,
    required List<String> constraintColumns,
    required String now,
  }) async {
    final rows = await txn.query(
      table,
      where: 'biomarker_id = ?',
      whereArgs: [temporaryBiomarkerId],
    );
    var moved = 0;
    for (final row in rows) {
      final id = '${row['id']}';
      if ((row['deleted'] as num?)?.toInt() == 1) {
        await txn.update(
          table,
          {'biomarker_id': canonicalBiomarkerId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        moved++;
        continue;
      }
      final where = <String>['biomarker_id = ?', 'deleted = 0'];
      final args = <Object?>[canonicalBiomarkerId];
      for (final column in constraintColumns) {
        where.add('$column = ?');
        args.add(row[column]);
      }
      final duplicate = await txn.query(
        table,
        columns: const ['id'],
        where: where.join(' AND '),
        whereArgs: args,
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        await txn.update(
          table,
          {
            'biomarker_id': canonicalBiomarkerId,
            'deleted': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.update(
          table,
          {'biomarker_id': canonicalBiomarkerId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        moved++;
      }
    }
    return moved;
  }

  Future<int> _moveRanges(
    Transaction txn, {
    required String temporaryBiomarkerId,
    required String canonicalBiomarkerId,
    required String now,
  }) async {
    final rows = await txn.query(
      'biomarker_ranges',
      where: 'biomarker_id = ?',
      whereArgs: [temporaryBiomarkerId],
    );
    var moved = 0;
    const fields = [
      'range_type',
      'sex',
      'age_min',
      'age_max',
      'low',
      'high',
      'optimal_low',
      'optimal_high',
      'unit',
      'evidence_label',
      'evidence_url',
      'notes',
    ];
    for (final row in rows) {
      final id = '${row['id']}';
      if ((row['deleted'] as num?)?.toInt() == 1) {
        await txn.update(
          'biomarker_ranges',
          {'biomarker_id': canonicalBiomarkerId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        moved++;
        continue;
      }
      final where = <String>['biomarker_id = ?', 'deleted = 0'];
      final args = <Object?>[canonicalBiomarkerId];
      for (final field in fields) {
        where.add('$field IS ?');
        args.add(row[field]);
      }
      final duplicate = await txn.query(
        'biomarker_ranges',
        columns: const ['id'],
        where: where.join(' AND '),
        whereArgs: args,
        limit: 1,
      );
      if (duplicate.isNotEmpty) {
        await txn.update(
          'biomarker_ranges',
          {
            'biomarker_id': canonicalBiomarkerId,
            'deleted': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.update(
          'biomarker_ranges',
          {'biomarker_id': canonicalBiomarkerId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
        moved++;
      }
    }
    return moved;
  }

  Future<List<ProfileBiomarkerTarget>> profileTargets(
    String profileId, {
    String? biomarkerId,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'profile_biomarker_targets',
      where: biomarkerId == null
          ? 'profile_id = ? AND deleted = 0'
          : 'profile_id = ? AND biomarker_id = ? AND deleted = 0',
      whereArgs: biomarkerId == null ? [profileId] : [profileId, biomarkerId],
      orderBy: 'biomarker_id',
    );
    return rows.map(ProfileBiomarkerTarget.fromMap).toList();
  }

  Future<void> saveProfileTarget(ProfileBiomarkerTarget target) async {
    _validateProfileTarget(target);
    final db = await _database.database;
    await db.insert(
      'profile_biomarker_targets',
      target.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HealthDocument>> documents(String profileId) async {
    final db = await _database.database;
    final rows = await db.query(
      'documents',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'COALESCE(document_date, created_at) DESC',
    );
    return rows.map(HealthDocument.fromMap).toList();
  }

  Future<void> saveDocument(HealthDocument document) async {
    final db = await _database.database;
    await db.insert(
      'documents',
      document.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDocumentWithMeasurements(String documentId) async {
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final changed = await txn.update(
        'documents',
        {'deleted': 1, 'updated_at': now},
        where: 'id = ? AND deleted = 0',
        whereArgs: [documentId],
      );
      if (changed != 1) {
        throw StateError('The document no longer exists.');
      }
      await txn.update(
        'measurements',
        {'deleted': 1, 'updated_at': now},
        where: 'document_id = ? AND deleted = 0',
        whereArgs: [documentId],
      );
    });
  }

  Future<HealthDocument?> documentByHash(String profileId, String hash) async {
    final db = await _database.database;
    final rows = await db.query(
      'documents',
      where: 'profile_id = ? AND sha256 = ? AND deleted = 0',
      whereArgs: [profileId, hash],
      limit: 1,
    );
    return rows.isEmpty ? null : HealthDocument.fromMap(rows.first);
  }

  Future<List<HealthDocument>> documentsPendingCloudUpload() async {
    final db = await _database.database;
    final rows = await db.query(
      'documents',
      where:
          'deleted = 0 AND local_path IS NOT NULL AND local_path != ? '
          'AND (one_drive_item_id IS NULL OR one_drive_item_id = ?)',
      whereArgs: ['', ''],
    );
    return rows.map(HealthDocument.fromMap).toList();
  }

  Future<List<HealthDocument>> documentsWithCloudCopies() async {
    final db = await _database.database;
    final rows = await db.query(
      'documents',
      where:
          'deleted = 0 AND one_drive_item_id IS NOT NULL '
          'AND one_drive_item_id != ?',
      whereArgs: [''],
    );
    return rows.map(HealthDocument.fromMap).toList();
  }

  Future<void> setDocumentCloudItem(
    String documentId,
    String oneDriveItemId,
  ) async {
    final db = await _database.database;
    await db.update(
      'documents',
      {
        'one_drive_item_id': oneDriveItemId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> setDocumentLocalPath(String documentId, String localPath) async {
    final db = await _database.database;
    // Device-local paths are deliberately not synchronization metadata.
    await db.update(
      'documents',
      {'local_path': localPath},
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  Future<void> saveDocumentBundle({
    required HealthDocument document,
    required List<Biomarker> newBiomarkers,
    required List<Measurement> measurements,
  }) async {
    for (final biomarker in newBiomarkers) {
      _validateBiomarker(biomarker);
    }
    for (final measurement in measurements) {
      _validateMeasurement(measurement);
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      for (final biomarker in newBiomarkers) {
        await txn.insert(
          'biomarkers',
          biomarker.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.insert(
        'documents',
        document.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final measurement in measurements) {
        await txn.insert(
          'measurements',
          await measurementMapWithCanonicalUnits(txn, measurement),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<Biomarker?> biomarkerByCanonicalName(String name) async {
    final db = await _database.database;
    final normalized = normalizeName(name);
    final rows = await db.query(
      'biomarkers',
      where: 'canonical_name = ? AND deleted = 0',
      whereArgs: [normalized],
      limit: 1,
    );
    return rows.isEmpty ? null : Biomarker.fromMap(rows.first);
  }

  Future<List<Measurement>> measurements(String profileId) async {
    final db = await _database.database;
    final rows = await db.query(
      'measurements',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'taken_at DESC',
    );
    return rows.map(Measurement.fromMap).toList();
  }

  Future<void> saveMeasurement(Measurement measurement) async {
    _validateMeasurement(measurement);
    final db = await _database.database;
    await db.insert(
      'measurements',
      await measurementMapWithCanonicalUnits(db, measurement),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, Object?>> measurementMapWithCanonicalUnits(
    DatabaseExecutor db,
    Measurement measurement,
  ) async {
    _validateMeasurement(measurement);
    final map = measurement.toMap();
    final rows = await db.query(
      'biomarkers',
      where: 'id = ? AND deleted = 0',
      whereArgs: [measurement.biomarkerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      map['conversion_status'] = 'missing_biomarker';
      map['canonical_value'] = null;
      map['canonical_unit'] = null;
      return map;
    }
    final biomarker = Biomarker.fromMap(rows.single);
    final preferredUnit = _unitConversion.normalizeUnit(
      biomarker.defaultUnit.isEmpty ? measurement.unit : biomarker.defaultUnit,
    );
    final reportedUnit = _unitConversion.normalizeUnit(measurement.unit);
    map['unit_reported'] = reportedUnit;
    map['canonical_unit'] = preferredUnit;
    if (reportedUnit == preferredUnit) {
      map['canonical_value'] = measurement.value;
      map['conversion_status'] = 'not_required';
      return map;
    }
    final converted = _unitConversion.convertValueForBiomarkerKeys(
      measurement.value,
      reportedUnit,
      preferredUnit,
      _biomarkerConversionKeys(biomarker),
    );
    // A finite reported measurement can still overflow during a unit
    // conversion.  Do not let that derived value bypass the persistence
    // boundary: retain the source result and mark its canonical form as
    // unavailable instead.
    final canonicalValue = converted?.isFinite == true ? converted : null;
    map['canonical_value'] = canonicalValue;
    map['conversion_status'] = canonicalValue == null
        ? 'unsupported'
        : 'converted';
    return map;
  }

  /// Recomputes only derived canonical values that an older converter could
  /// not resolve. Reported values, provenance, and timestamps remain intact.
  Future<int> repairUnsupportedMeasurementConversions() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT
        m.id AS measurement_id,
        m.value AS reported_value,
        m.unit_reported,
        m.canonical_unit,
        b.id AS biomarker_id,
        b.canonical_name,
        b.display_name,
        b.default_unit,
        b.synonyms_json,
        b.created_at AS biomarker_created_at,
        b.updated_at AS biomarker_updated_at,
        b.deleted AS biomarker_deleted
      FROM measurements m
      INNER JOIN biomarkers b ON b.id = m.biomarker_id
      WHERE m.deleted = 0
        AND b.deleted = 0
        AND m.conversion_status = 'unsupported'
    ''');
    if (rows.isEmpty) return 0;

    var repaired = 0;
    await db.transaction((txn) async {
      for (final row in rows) {
        final value = (row['reported_value'] as num?)?.toDouble();
        final reportedUnit = row['unit_reported']?.toString() ?? '';
        final preferredUnit = _unitConversion.normalizeUnit(
          row['canonical_unit']?.toString().trim().isNotEmpty == true
              ? row['canonical_unit'].toString()
              : row['default_unit']?.toString() ?? '',
        );
        if (value == null ||
            !value.isFinite ||
            reportedUnit.trim().isEmpty ||
            preferredUnit.isEmpty) {
          continue;
        }
        final biomarker = Biomarker.fromMap({
          'id': row['biomarker_id'],
          'canonical_name': row['canonical_name'],
          'display_name': row['display_name'],
          'default_unit': row['default_unit'],
          'synonyms_json': row['synonyms_json'],
          'created_at': row['biomarker_created_at'],
          'updated_at': row['biomarker_updated_at'],
          'deleted': row['biomarker_deleted'],
        });
        final normalizedReported = _unitConversion.normalizeUnit(reportedUnit);
        final notRequired = normalizedReported == preferredUnit;
        final converted = notRequired
            ? value
            : _unitConversion.convertValueForBiomarkerKeys(
                value,
                normalizedReported,
                preferredUnit,
                _biomarkerConversionKeys(biomarker),
              );
        if (converted?.isFinite != true) continue;
        await txn.update(
          'measurements',
          {
            'canonical_value': converted,
            'canonical_unit': preferredUnit,
            'conversion_status': notRequired ? 'not_required' : 'converted',
          },
          where: 'id = ?',
          whereArgs: [row['measurement_id']],
        );
        repaired++;
      }
    });
    return repaired;
  }

  Iterable<String> _biomarkerConversionKeys(Biomarker biomarker) sync* {
    yield biomarker.canonicalName;
    yield* biomarker.synonyms;
    yield biomarker.id;
  }

  Future<List<NamedHealthRecord>> namedRecords(
    String profileId, {
    String? kind,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'named_health_records',
      where: kind == null
          ? 'profile_id = ? AND deleted = 0'
          : 'profile_id = ? AND kind = ? AND deleted = 0',
      whereArgs: kind == null ? [profileId] : [profileId, kind],
      orderBy: 'kind, name COLLATE NOCASE',
    );
    return rows.map(NamedHealthRecord.fromMap).toList();
  }

  Future<void> saveNamedRecord(NamedHealthRecord record) async {
    _validateNamedRecord(record);
    final db = await _database.database;
    await db.insert(
      'named_health_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<BiomarkerList>> biomarkerLists(String profileId) async {
    final db = await _database.database;
    final listRows = await db.query(
      'biomarker_lists',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'name COLLATE NOCASE',
    );
    final result = <BiomarkerList>[];
    for (final row in listRows) {
      final itemRows = await db.query(
        'biomarker_list_items',
        where: 'list_id = ? AND deleted = 0',
        whereArgs: [row['id']],
        orderBy: 'biomarker_id',
      );
      result.add(
        BiomarkerList.fromMap(
          row,
          itemRows.map(BiomarkerListItem.fromMap).toList(),
        ),
      );
    }
    return result;
  }

  Future<void> saveBiomarkerList(BiomarkerList list) async {
    for (final item in list.items) {
      _validateBiomarkerListItem(item);
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        'biomarker_lists',
        list.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      for (final item in list.items) {
        await txn.insert(
          'biomarker_list_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> saveBiomarkerListItem(BiomarkerListItem item) async {
    _validateBiomarkerListItem(item);
    final db = await _database.database;
    await db.insert(
      'biomarker_list_items',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<DueBiomarker>> dueBiomarkers(String profileId) async {
    final lists = await biomarkerLists(profileId);
    final catalog = {for (final item in await biomarkers()) item.id: item};
    final latest = <String, DateTime>{};
    for (final measurement in await measurements(profileId)) {
      latest.putIfAbsent(measurement.biomarkerId, () => measurement.takenAt);
    }
    final now = DateTime.now();
    // Collapsed per biomarker: a marker on three lists is still one blood
    // draw, so it must count and read as one due item.
    final byBiomarker = <String, DueBiomarker>{};
    final listNames = <String, Set<String>>{};
    for (final list in lists) {
      for (final item in list.items) {
        final interval = item.dueIntervalDays;
        final biomarker = catalog[item.biomarkerId];
        if (interval == null || interval <= 0 || biomarker == null) continue;
        final measured = latest[item.biomarkerId];
        final dueDate =
            measured?.add(Duration(days: interval)) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (dueDate.isAfter(now)) continue;
        listNames.putIfAbsent(biomarker.id, () => <String>{}).add(list.name);
        final existing = byBiomarker[biomarker.id];
        // Keep the most demanding list's schedule: the earliest due date, and
        // on a tie the shorter interval.
        if (existing == null ||
            dueDate.isBefore(existing.dueDate) ||
            (dueDate == existing.dueDate && interval < existing.intervalDays)) {
          byBiomarker[biomarker.id] = DueBiomarker(
            biomarker: biomarker,
            listNames: const [],
            lastMeasuredAt: measured,
            dueDate: dueDate,
            intervalDays: interval,
          );
        }
      }
    }
    final result = [
      for (final entry in byBiomarker.entries)
        DueBiomarker(
          biomarker: entry.value.biomarker,
          listNames: listNames[entry.key]!.toList()..sort(),
          lastMeasuredAt: entry.value.lastMeasuredAt,
          dueDate: entry.value.dueDate,
          intervalDays: entry.value.intervalDays,
        ),
    ];
    result.sort((a, b) {
      final due = a.dueDate.compareTo(b.dueDate);
      return due != 0
          ? due
          : a.biomarker.displayName.toLowerCase().compareTo(
              b.biomarker.displayName.toLowerCase(),
            );
    });
    return result;
  }

  Future<List<LabPlan>> labPlans(String profileId) async {
    final db = await _database.database;
    final planRows = await db.query(
      'lab_plans',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    final result = <LabPlan>[];
    for (final row in planRows) {
      final itemRows = await db.query(
        'lab_plan_items',
        where: 'plan_id = ? AND deleted = 0',
        whereArgs: [row['id']],
        orderBy: 'tier, priority, biomarker_name',
      );
      result.add(
        LabPlan.fromMap(row, itemRows.map(LabPlanItem.fromMap).toList()),
      );
    }
    return result;
  }

  Future<void> saveLabPlan(LabPlan plan) async {
    _validateLabPlan(plan);
    final itemIds = <String>{};
    final biomarkerIds = <String>{};
    for (final item in plan.items) {
      _validateLabPlanItem(item);
      if (item.planId != plan.id) {
        throw ArgumentError(
          'Every lab-plan item must belong to the plan being saved.',
        );
      }
      if (!itemIds.add(item.id)) {
        throw ArgumentError('A lab plan cannot contain duplicate item IDs.');
      }
      if (!item.deleted && !biomarkerIds.add(item.biomarkerId)) {
        throw ArgumentError(
          'A biomarker can appear only once in a cumulative lab plan.',
        );
      }
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      final updated = await txn.update(
        'lab_plans',
        plan.toMap(),
        where: 'id = ?',
        whereArgs: [plan.id],
      );
      if (updated == 0) {
        await txn.insert(
          'lab_plans',
          plan.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
      final incomingIds = plan.items.map((item) => item.id).toSet();
      final existing = await txn.query(
        'lab_plan_items',
        where: 'plan_id = ? AND deleted = 0',
        whereArgs: [plan.id],
      );
      for (final row in existing) {
        final id = '${row['id']}';
        if (!incomingIds.contains(id)) {
          await txn.update(
            'lab_plan_items',
            {
              'deleted': 1,
              'updated_at': plan.updatedAt.toUtc().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
      for (final item in plan.items) {
        final map = item.toMap();
        map['created_at'] = (item.createdAt ?? plan.createdAt)
            .toUtc()
            .toIso8601String();
        map['updated_at'] = (item.updatedAt ?? plan.updatedAt)
            .toUtc()
            .toIso8601String();
        await txn.insert(
          'lab_plan_items',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<AdvisorMessage>> messages(
    String profileId,
    String conversationId,
  ) async {
    final db = await _database.database;
    final rows = await db.query(
      'advisor_messages',
      where: 'profile_id = ? AND conversation_id = ? AND deleted = 0',
      whereArgs: [profileId, conversationId],
      orderBy: 'created_at',
    );
    return rows.map(AdvisorMessage.fromMap).toList();
  }

  Future<void> saveMessage(AdvisorMessage message) async {
    final db = await _database.database;
    await db.insert(
      'advisor_messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Validates a complete synchronized ledger before a sync or portable
  /// restore is allowed to write a single row.  This is intentionally more
  /// strict than SQLite's affinity rules: a snapshot is an external trust
  /// boundary, so omitted columns, special floating point values, malformed
  /// dates, and unknown enum values must not be silently coerced into health
  /// data.
  ///
  /// Portable backups deliberately omit both device-local document metadata
  /// columns. OneDrive snapshots omit only [local_path], because the remote
  /// item id is synchronization metadata shared between devices.
  Future<void> validateSynchronizedRows(
    Map<String, List<Map<String, Object?>>> tables, {
    required bool portableBackup,
  }) async {
    if (tables.keys.toSet().length != AppDatabase.synchronizedTables.length ||
        !tables.keys.toSet().containsAll(AppDatabase.synchronizedTables)) {
      throw const FormatException(
        'Synchronized data has an unexpected table set.',
      );
    }

    final db = await _database.database;
    final knownIds = <String, Set<String>>{};
    for (final table in AppDatabase.synchronizedTables) {
      final columns = await _synchronizedColumns(db, table);
      final excluded = table == 'documents'
          ? portableBackup
                ? const {'local_path', 'one_drive_item_id'}
                : const {'local_path'}
          : const <String>{};
      final expected = {
        for (final column in columns)
          if (!excluded.contains(column.name)) column.name,
      };
      final ids = <String>{};
      for (final row in tables[table]!) {
        _validateSynchronizedRowShape(table, row, columns, expected, excluded);
        final id = row['id'] as String;
        if (!ids.add(id)) {
          throw FormatException('$table contains duplicate id $id.');
        }
        _validateSynchronizedRowSemantics(table, row);
      }
      knownIds[table] = ids;
    }
    _validateSynchronizedReferences(tables, knownIds);
  }

  void _validateSynchronizedRowShape(
    String table,
    Map<String, Object?> row,
    List<_SynchronizedColumn> columns,
    Set<String> expected,
    Set<String> excluded,
  ) {
    if (row.keys.toSet().length != expected.length ||
        !row.keys.toSet().containsAll(expected)) {
      throw FormatException('$table row has an unexpected field set.');
    }
    if (row['id'] is! String || (row['id'] as String).trim().isEmpty) {
      throw FormatException('$table row has invalid id.');
    }
    for (final column in columns) {
      if (excluded.contains(column.name)) continue;
      final value = row[column.name];
      if (value == null) {
        if (column.required) {
          throw FormatException('$table.${column.name} is required.');
        }
        continue;
      }
      final valid = switch (column.type) {
        final type when type.contains('INT') => value is int,
        final type
            when type.contains('REAL') ||
                type.contains('DOUBLE') ||
                type.contains('FLOAT') =>
          value is num && value.isFinite,
        final type when type.contains('TEXT') => value is String,
        _ => value is String || value is num,
      };
      if (!valid) {
        throw FormatException('$table.${column.name} has the wrong type.');
      }
      if (value is num && !value.isFinite) {
        throw FormatException('$table.${column.name} must be finite.');
      }
    }

    for (final column in _instantColumns) {
      final value = row[column];
      if (value != null && !_isIsoInstant(value)) {
        throw FormatException('$table.$column has an invalid timestamp.');
      }
    }
    for (final column in _dateColumns) {
      final value = row[column];
      if (value != null && !_isDateOnly(value)) {
        throw FormatException('$table.$column has an invalid date.');
      }
    }
    for (final column in _binaryColumns) {
      final value = row[column];
      if (value != null && value != 0 && value != 1) {
        throw FormatException('$table.$column must be 0 or 1.');
      }
    }
    for (final column in _jsonListColumns) {
      final value = row[column];
      if (value != null && !_isJsonList(value)) {
        throw FormatException('$table.$column must contain a JSON list.');
      }
      if (value is String) {
        _validateJsonListContents(table, column, value);
      }
    }
  }

  void _validateSynchronizedRowSemantics(
    String table,
    Map<String, Object?> row,
  ) {
    try {
      switch (table) {
        case 'profiles':
          _validateOptionalEnum(table, 'sex', row['sex'], const {
            'female',
            'male',
            'intersex',
            'other',
          });
          _validateProfile(Profile.fromMap(row));
        case 'supplements':
          _validateSupplement(Supplement.fromMap(row));
        case 'supplement_schedules':
          _validateSchedule(SupplementSchedule.fromMap(row));
        case 'supplement_intakes':
          _validateIntake(SupplementIntake.fromMap(row));
        case 'inventory_movements':
          _validateInventoryMovement(InventoryMovement.fromMap(row));
        case 'health_event_definitions':
          _validateEnum(table, 'kind', row['kind'], const {'symptom', 'tag'});
        case 'health_events':
          _validateEnum(table, 'kind', row['kind'], const {'symptom', 'tag'});
          _validateEvent(HealthEvent.fromMap(row));
        case 'biomarkers':
          _validateBiomarker(Biomarker.fromMap(row));
        case 'biomarker_ranges':
          _validateBiomarkerRange(BiomarkerReferenceRange.fromMap(row));
        case 'profile_biomarker_targets':
          _validateProfileTarget(ProfileBiomarkerTarget.fromMap(row));
        case 'measurements':
          _validateEnum(
            table,
            'conversion_status',
            row['conversion_status'],
            const {
              'not_required',
              'converted',
              'unsupported',
              'missing_biomarker',
            },
          );
          _validateMeasurement(Measurement.fromMap(row));
        case 'named_health_records':
          _validateEnum(table, 'kind', row['kind'], const {
            'condition',
            'medication',
            'goal',
            'family_history',
          });
          _validateEnum(table, 'status', row['status'], const {
            'active',
            'monitoring',
            'resolved',
            'paused',
          });
          _validateNamedRecord(NamedHealthRecord.fromMap(row));
        case 'biomarker_list_items':
          _validateBiomarkerListItem(BiomarkerListItem.fromMap(row));
        case 'lab_plan_items':
          _validateEnum(table, 'tier', row['tier'], const {
            'core',
            'advanced',
            'comprehensive',
          });
          _validateEnum(table, 'evidence_class', row['evidence_class'], const {
            'guideline',
            'longevity',
            'experimental',
            'unclassified',
          });
          _validateLabPlanItem(LabPlanItem.fromMap(row));
        case 'documents':
          _validateEnum(table, 'parse_status', row['parse_status'], const {
            'saved',
            'imported',
          });
        case 'biomarker_lists':
          break;
        case 'lab_plans':
          _validateEnum(table, 'status', row['status'], const {
            'draft',
            'verified',
          });
          _validateLabPlan(LabPlan.fromMap(row, const []));
        case 'advisor_messages':
          _validateEnum(table, 'role', row['role'], const {
            'user',
            'assistant',
          });
      }
    } on ArgumentError catch (error) {
      throw FormatException('$table row violates health-data limits: $error');
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('$table row is invalid: $error');
    }
    if (table == 'inventory_movements') {
      _validateEnum(table, 'reason', row['reason'], const {
        'initial',
        'purchase',
        'intake',
        'correction',
        'discard',
        'import',
      });
    }
  }

  void _validateSynchronizedReferences(
    Map<String, List<Map<String, Object?>>> tables,
    Map<String, Set<String>> knownIds,
  ) {
    for (final reference in _synchronizedReferences) {
      for (final row in tables[reference.table]!) {
        final value = row[reference.column];
        if (value != null &&
            (value is! String ||
                !knownIds[reference.parent]!.contains(value))) {
          throw FormatException(
            '${reference.table}.${reference.column} references a missing ${reference.parent} row.',
          );
        }
      }
    }
    final schedules = _rowsById(tables['supplement_schedules']!);
    final intakes = _rowsById(tables['supplement_intakes']!);
    final definitions = _rowsById(tables['health_event_definitions']!);
    final documents = _rowsById(tables['documents']!);

    for (final intake in tables['supplement_intakes']!) {
      final scheduleId = intake['schedule_id'];
      if (scheduleId == null) continue;
      final schedule = schedules[scheduleId]!;
      if (schedule['profile_id'] != intake['profile_id'] ||
          schedule['supplement_id'] != intake['supplement_id']) {
        throw const FormatException(
          'Supplement intake does not match its schedule profile and supplement.',
        );
      }
    }
    for (final movement in tables['inventory_movements']!) {
      final intakeId = movement['intake_id'];
      if (intakeId == null) continue;
      final intake = intakes[intakeId]!;
      if (intake['supplement_id'] != movement['supplement_id'] ||
          (movement['profile_id'] != null &&
              intake['profile_id'] != movement['profile_id'])) {
        throw const FormatException(
          'Inventory movement does not match its intake provenance.',
        );
      }
    }
    for (final event in tables['health_events']!) {
      final definitionId = event['definition_id'];
      if (definitionId == null) continue;
      final definition = definitions[definitionId]!;
      if (definition['profile_id'] != event['profile_id'] ||
          definition['kind'] != event['kind']) {
        throw const FormatException(
          'Health event does not match its definition profile and kind.',
        );
      }
    }
    for (final measurement in tables['measurements']!) {
      final documentId = measurement['document_id'];
      if (documentId == null) continue;
      final document = documents[documentId]!;
      if (document['profile_id'] != measurement['profile_id']) {
        throw const FormatException(
          'Measurement does not match its document profile.',
        );
      }
    }
  }

  Map<Object?, Map<String, Object?>> _rowsById(
    List<Map<String, Object?>> rows,
  ) => {for (final row in rows) row['id']: row};

  void _validateEnum(
    String table,
    String column,
    Object? value,
    Set<String> allowed,
  ) {
    if (value is! String || !allowed.contains(value)) {
      throw FormatException('$table.$column has an invalid value.');
    }
  }

  void _validateOptionalEnum(
    String table,
    String column,
    Object? value,
    Set<String> allowed,
  ) {
    if (value != null) _validateEnum(table, column, value, allowed);
  }

  // SQLite accepts IEEE special values on some platforms. Reject them at the
  // one boundary shared by UI, parser, sync, and future callers so invalid
  // numeric data cannot silently enter a health record.
  void _validateProfile(Profile profile) {
    _requireOptionalFinite(profile.heightCm, 'Height');
    _requireOptionalFinite(profile.weightKg, 'Weight');
    if (profile.deleted) return;
    _requireSensiblePositive(
      profile.heightCm,
      'Height',
      minimum: 30,
      maximum: 300,
    );
    _requireSensiblePositive(
      profile.weightKg,
      'Weight',
      minimum: 1,
      maximum: 1000,
    );
  }

  void _validateSupplement(Supplement supplement) {
    _validateIngredientAmounts(
      supplement.ingredients,
      deleted: supplement.deleted,
    );
    _requireOptionalFinite(supplement.containerCount, 'Container count');
    _requireOptionalFinite(supplement.priceEur, 'Supplement price');
    _requireOptionalFinite(
      supplement.lowStockThresholdUnits,
      'Low-stock threshold',
    );
    if (supplement.deleted) return;
    if (supplement.unitsPerContainer != null &&
        supplement.unitsPerContainer! < 0) {
      throw ArgumentError('Units per container must not be negative.');
    }
    _requireOptionalNonNegative(supplement.containerCount, 'Container count');
    _requireOptionalNonNegative(supplement.priceEur, 'Supplement price');
    _requireOptionalNonNegative(
      supplement.lowStockThresholdUnits,
      'Low-stock threshold',
    );
  }

  void _validateInventoryMovement(InventoryMovement movement) {
    _requireFinite(movement.quantityUnits, 'Inventory quantity');
  }

  void _validateSchedule(SupplementSchedule schedule) {
    _requireFinite(schedule.dose, 'Supplement schedule dose');
    if (!schedule.deleted) {
      _requirePositive(schedule.dose, 'Supplement schedule dose');
    }
  }

  void _validateIntake(SupplementIntake intake) {
    _validateIngredientAmounts(
      intake.ingredientSnapshot,
      deleted: intake.deleted,
    );
    _requireFinite(intake.dose, 'Supplement intake dose');
    if (!intake.deleted) {
      _requirePositive(intake.dose, 'Supplement intake dose');
    }
  }

  void _validateEvent(HealthEvent event) {
    _requireOptionalFinite(event.numericValue, 'Event numeric value');
    if (event.deleted) return;
    if (event.score != null && (event.score! < 0 || event.score! > 10)) {
      throw ArgumentError('Event score must be between 0 and 10.');
    }
    if (event.durationMinutes != null && event.durationMinutes! < 0) {
      throw ArgumentError('Event duration must not be negative.');
    }
  }

  void _validateBiomarker(Biomarker biomarker) {
    _requireOptionalFinite(biomarker.priceEur, 'Biomarker price');
    if (!biomarker.deleted) {
      _requireOptionalNonNegative(biomarker.priceEur, 'Biomarker price');
    }
  }

  void _validateProfileTarget(ProfileBiomarkerTarget target) {
    _requireOptionalFinite(target.low, 'Target low bound');
    _requireOptionalFinite(target.high, 'Target high bound');
    _requireOptionalFinite(target.borderlineLow, 'Borderline low bound');
    _requireOptionalFinite(target.borderlineHigh, 'Borderline high bound');
    if (target.deleted) return;
    _requireOrdered(target.low, target.high, 'Target low and high bounds');
    _requireOrdered(
      target.borderlineLow,
      target.borderlineHigh,
      'Borderline low and high bounds',
    );
  }

  void _validateMeasurement(Measurement measurement) {
    _requireFinite(measurement.value, 'Measurement value');
    _requireOptionalFinite(
      measurement.canonicalValue,
      'Canonical measurement value',
    );
    _requireOptionalFinite(measurement.labRefLow, 'Lab reference low bound');
    _requireOptionalFinite(measurement.labRefHigh, 'Lab reference high bound');
    _requireOptionalFinite(
      measurement.extractionConfidence,
      'Extraction confidence',
    );
    if (measurement.deleted) return;
    _requireOrdered(
      measurement.labRefLow,
      measurement.labRefHigh,
      'Lab reference low and high bounds',
    );
    final confidence = measurement.extractionConfidence;
    if (confidence != null && (confidence < 0 || confidence > 1)) {
      throw ArgumentError('Extraction confidence must be between 0 and 1.');
    }
    if (measurement.page != null && measurement.page! < 1) {
      throw ArgumentError('Measurement page must be at least 1.');
    }
  }

  void _validateNamedRecord(NamedHealthRecord record) {
    _requireOptionalFinite(record.dose, 'Health record dose');
    if (record.deleted) return;
    _requireOptionalPositive(record.dose, 'Health record dose');
    if (record.priority != null && record.priority! < 0) {
      throw ArgumentError('Health record priority must not be negative.');
    }
  }

  void _validateBiomarkerListItem(BiomarkerListItem item) {
    if (!item.deleted &&
        item.dueIntervalDays != null &&
        item.dueIntervalDays! <= 0) {
      throw ArgumentError('Retest interval must be a positive number of days.');
    }
  }

  void _validateLabPlanItem(LabPlanItem item) {
    _requireOptionalFinite(item.priceEur, 'Lab-plan item price');
    if (item.deleted) return;
    _requireOptionalNonNegative(item.priceEur, 'Lab-plan item price');
    if (item.priority < 1) {
      throw ArgumentError('Lab-plan item priority must be at least 1.');
    }
  }

  void _validateLabPlan(LabPlan plan) {
    if (plan.status != 'draft' && plan.status != 'verified') {
      throw ArgumentError('Lab-plan status is invalid.');
    }
    if (plan.status == 'verified') {
      final provider = plan.provider?.trim();
      final model = plan.model?.trim();
      if (plan.contextHash.trim().isEmpty ||
          provider == null ||
          provider.isEmpty ||
          model == null ||
          model.isEmpty ||
          plan.verificationSummary.trim().isEmpty ||
          plan.verifiedAt == null) {
        throw ArgumentError(
          'A verified lab plan requires its provider, model, context hash, review summary, and verification time.',
        );
      }
    }
  }

  void _validateIngredientAmounts(
    Iterable<Map<String, Object?>> ingredients, {
    required bool deleted,
  }) {
    for (final ingredient in ingredients) {
      final rawAmount = ingredient['amount'];
      if (rawAmount is! num) continue;
      final amount = rawAmount.toDouble();
      _requireFinite(amount, 'Ingredient amount');
      if (!deleted) _requirePositive(amount, 'Ingredient amount');
    }
  }

  void _requireFinite(double value, String field) {
    if (!value.isFinite) {
      throw ArgumentError('$field must be a finite number.');
    }
  }

  void _requireOptionalFinite(double? value, String field) {
    if (value != null) _requireFinite(value, field);
  }

  void _requirePositive(double value, String field) {
    if (value <= 0) {
      throw ArgumentError('$field must be greater than zero.');
    }
  }

  void _requireOptionalPositive(double? value, String field) {
    if (value != null) _requirePositive(value, field);
  }

  void _requireNonNegativeFinite(double value, String field) {
    _requireFinite(value, field);
    if (value < 0) {
      throw ArgumentError('$field must not be negative.');
    }
  }

  void _requireOptionalNonNegative(double? value, String field) {
    if (value != null) _requireNonNegativeFinite(value, field);
  }

  void _requireSensiblePositive(
    double? value,
    String field, {
    required double minimum,
    required double maximum,
  }) {
    if (value == null) return;
    if (value < minimum || value > maximum) {
      throw ArgumentError('$field must be between $minimum and $maximum.');
    }
  }

  void _requireOrdered(double? low, double? high, String field) {
    if (low != null && high != null && low > high) {
      throw ArgumentError('$field must be ordered low to high.');
    }
  }

  Future<Map<String, Object?>> completeProfileSnapshot(String profileId) async {
    final db = await _database.database;
    final profileRows = await db.query(
      'profiles',
      where: 'id = ? AND deleted = 0',
      whereArgs: [profileId],
    );
    if (profileRows.isEmpty) throw StateError('Active profile not found');

    final data = <String, Object?>{
      'profile': profileRows.single,
      'supplements': await db.query('supplements', where: 'deleted = 0'),
      'supplement_schedules': await _profileRows(
        db,
        'supplement_schedules',
        profileId,
      ),
      'supplement_intakes': await _profileRows(
        db,
        'supplement_intakes',
        profileId,
      ),
      'inventory_movements': await db.query(
        'inventory_movements',
        // Inventory is household-shared. `profile_id` is only provenance for
        // a stock change; it is not evidence that the active profile took a
        // supplement. Personal intake evidence remains in
        // `supplement_intakes`, which is scoped above.
        where: 'deleted = 0',
      ),
      'health_event_definitions': await _profileRows(
        db,
        'health_event_definitions',
        profileId,
      ),
      'health_events': await _profileRows(db, 'health_events', profileId),
      'documents': (await _profileRows(db, 'documents', profileId))
          .map(
            (row) => Map<String, Object?>.from(row)
              ..remove('local_path')
              ..remove('one_drive_item_id'),
          )
          .toList(),
      'measurements': await _profileRows(db, 'measurements', profileId),
      'conditions_medications_goals_history': await _profileRows(
        db,
        'named_health_records',
        profileId,
      ),
      'profile_biomarker_targets': await _profileRows(
        db,
        'profile_biomarker_targets',
        profileId,
      ),
      'biomarker_lists': await _profileRows(db, 'biomarker_lists', profileId),
      'lab_plans': await _profileRows(db, 'lab_plans', profileId),
      // Advisor messages are not health evidence. The active conversation is
      // supplied separately in conversational order by AdvisorService so old
      // model output cannot be mistaken for a measured fact.
      // The full catalog is needed to choose unmeasured tests and calculate price tiers.
      'biomarker_catalog': await db.query('biomarkers', where: 'deleted = 0'),
      'biomarker_ranges': await db.query(
        'biomarker_ranges',
        where: 'deleted = 0',
      ),
    };

    // This derived navigation evidence complements, rather than replaces, the
    // complete household movement ledger. Keep one row for every active
    // catalog item, including zero-stock items, so the advisor can verify the
    // exact sum and detect a depleted household item.
    data['household_stock_levels'] = await db
        .rawQuery('''
      SELECT
        supplements.id AS supplement_id,
        supplements.name AS supplement_name,
        supplements.stock_unit AS stock_unit,
        supplements.low_stock_threshold_units AS low_stock_threshold_units,
        COALESCE(SUM(inventory_movements.quantity_units), 0.0) AS current_units
      FROM supplements
      LEFT JOIN inventory_movements
        ON inventory_movements.supplement_id = supplements.id
        AND inventory_movements.deleted = 0
      WHERE supplements.deleted = 0
      GROUP BY supplements.id, supplements.name, supplements.stock_unit,
        supplements.low_stock_threshold_units
      ORDER BY supplements.name COLLATE NOCASE, supplements.id
    ''')
        .then(
          (rows) => rows
              .map(
                (row) => <String, Object?>{
                  'id': 'household-stock:${row['supplement_id']}',
                  'supplement_id': row['supplement_id'],
                  'name': row['supplement_name'],
                  'stock_unit': row['stock_unit'],
                  'low_stock_threshold_units': row['low_stock_threshold_units'],
                  // SQFlite returns a numeric SQLite SUM as num. Retain its
                  // double representation rather than converting to an int.
                  'current_units':
                      (row['current_units'] as num?)?.toDouble() ?? 0.0,
                },
              )
              .toList(),
        );

    final listIds = (data['biomarker_lists']! as List<Map<String, Object?>>)
        .map((row) => row['id'])
        .whereType<String>()
        .toList();
    data['biomarker_list_items'] = listIds.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'biomarker_list_items',
            where:
                'list_id IN (${List.filled(listIds.length, '?').join(',')}) '
                'AND deleted = 0',
            whereArgs: listIds,
          );

    final planIds = (data['lab_plans']! as List<Map<String, Object?>>)
        .map((row) => row['id'])
        .whereType<String>()
        .toList();
    data['lab_plan_items'] = planIds.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'lab_plan_items',
            where:
                'plan_id IN (${List.filled(planIds.length, '?').join(',')}) '
                'AND deleted = 0',
            whereArgs: planIds,
          );

    final counts = <String, int>{};
    for (final entry in data.entries) {
      if (entry.value is List) {
        counts[entry.key] = (entry.value! as List).length;
      }
    }

    return {
      'schema': 'superhealth.health_context',
      'schema_version': 1,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'active_profile_id': profileId,
      'manifest': {
        'complete': true,
        'counts': counts,
        'excluded': [
          'api_keys',
          'onedrive_tokens',
          'sync_metadata',
          'other_profiles_clinical_records',
          'other_profiles_schedules_and_intakes',
          'advisor_messages_outside_active_conversation',
        ],
        'scope': {
          'clinical_evidence': 'active_profile_only',
          'shared_supplement_catalog_and_inventory': 'household_wide',
          'inventory_movement_profile_id': 'provenance_only',
        },
      },
      'data': data,
    };
  }

  Future<Map<String, Object?>> fullSyncSnapshot() async {
    final db = await _database.database;
    final tables = <String, Object?>{};
    for (final table in AppDatabase.synchronizedTables) {
      final rows = await db.query(table);
      tables[table] = table == 'documents'
          ? [
              for (final row in rows)
                Map<String, Object?>.from(row)..remove('local_path'),
            ]
          : rows;
    }
    return {
      'schema': 'superhealth.snapshot',
      'schema_version': AppDatabase.schemaVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    };
  }

  Future<List<Map<String, Object?>>> _profileRows(
    Database db,
    String table,
    String profileId, {
    bool includeDeletedClause = true,
  }) => db.query(
    table,
    where: includeDeletedClause
        ? 'profile_id = ? AND deleted = 0'
        : 'profile_id = ?',
    whereArgs: [profileId],
  );

  static String normalizeName(String input) => input
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  static String stableJson(Object? value) {
    Object? sort(Object? input) {
      if (input is Map) {
        final keys = input.keys.map((key) => '$key').toList()..sort();
        return {for (final key in keys) key: sort(input[key])};
      }
      if (input is List) return input.map(sort).toList();
      return input;
    }

    return jsonEncode(sort(value));
  }
}

class TemporaryBiomarkerResolution {
  const TemporaryBiomarkerResolution({
    required this.temporaryBiomarkerId,
    required this.canonicalBiomarkerId,
    required this.movedMeasurements,
    required this.movedTargets,
    required this.movedListItems,
    required this.movedRanges,
    required this.movedLabPlanItems,
  });

  final String temporaryBiomarkerId;
  final String canonicalBiomarkerId;
  final int movedMeasurements;
  final int movedTargets;
  final int movedListItems;
  final int movedRanges;
  final int movedLabPlanItems;
}
