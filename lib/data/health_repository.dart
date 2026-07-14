import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/entities.dart';
import 'app_database.dart';

class HealthRepository {
  HealthRepository(this._database, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

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
    double? weightKg,
    String notes = '',
  }) async {
    final now = DateTime.now();
    final profile = Profile(
      id: newId(),
      displayName: displayName.trim(),
      dateOfBirth: dateOfBirth,
      sex: sex,
      weightKg: weightKg,
      notes: notes.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final db = await _database.database;
    await db.insert('profiles', profile.toMap());
    return profile;
  }

  Future<void> saveProfile(Profile profile) async {
    final db = await _database.database;
    await db.insert(
      'profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Supplement>> supplements(String profileId) async {
    final db = await _database.database;
    final rows = await db.query(
      'supplements',
      where: 'profile_id = ? AND deleted = 0',
      whereArgs: [profileId],
      orderBy: 'active DESC, name COLLATE NOCASE',
    );
    return rows.map(Supplement.fromMap).toList();
  }

  Future<void> saveSupplement(Supplement supplement) async {
    final db = await _database.database;
    await db.insert(
      'supplements',
      supplement.toMap(),
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

  Future<void> saveSchedule(SupplementSchedule schedule) async {
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

  Future<void> saveIntake(SupplementIntake intake) async {
    final db = await _database.database;
    await db.insert(
      'supplement_intakes',
      intake.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    final db = await _database.database;
    await db.insert(
      'health_events',
      event.toMap(),
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
    final db = await _database.database;
    await db.insert(
      'biomarkers',
      biomarker.toMap(),
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

  Future<void> saveDocumentBundle({
    required HealthDocument document,
    required List<Biomarker> newBiomarkers,
    required List<Measurement> measurements,
  }) async {
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
          measurement.toMap(),
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
    final db = await _database.database;
    await db.insert(
      'measurements',
      measurement.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    final db = await _database.database;
    await db.insert(
      'named_health_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<LabPlan>> labPlans(String profileId) async {
    final db = await _database.database;
    final planRows = await db.query(
      'lab_plans',
      where: 'profile_id = ?',
      whereArgs: [profileId],
      orderBy: 'created_at DESC',
    );
    final result = <LabPlan>[];
    for (final row in planRows) {
      final itemRows = await db.query(
        'lab_plan_items',
        where: 'plan_id = ?',
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
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        'lab_plans',
        plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'lab_plan_items',
        where: 'plan_id = ?',
        whereArgs: [plan.id],
      );
      for (final item in plan.items) {
        await txn.insert('lab_plan_items', item.toMap());
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
      where: 'profile_id = ? AND conversation_id = ?',
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
      'supplements': await _profileRows(db, 'supplements', profileId),
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
      'lab_plans': await _profileRows(
        db,
        'lab_plans',
        profileId,
        includeDeletedClause: false,
      ),
      'advisor_messages': await _profileRows(
        db,
        'advisor_messages',
        profileId,
        includeDeletedClause: false,
      ),
      // The full catalog is needed to choose unmeasured tests and calculate price tiers.
      'biomarker_catalog': await db.query('biomarkers', where: 'deleted = 0'),
      'biomarker_ranges': await db.query(
        'biomarker_ranges',
        where: 'deleted = 0',
      ),
    };

    final planIds = (data['lab_plans']! as List<Map<String, Object?>>)
        .map((row) => row['id'])
        .whereType<String>()
        .toList();
    data['lab_plan_items'] = planIds.isEmpty
        ? <Map<String, Object?>>[]
        : await db.query(
            'lab_plan_items',
            where: 'plan_id IN (${List.filled(planIds.length, '?').join(',')})',
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
          'other_profiles',
        ],
      },
      'data': data,
    };
  }

  Future<Map<String, Object?>> fullSyncSnapshot() async {
    final db = await _database.database;
    final tables = <String, Object?>{};
    for (final table in AppDatabase.synchronizedTables) {
      tables[table] = await db.query(table);
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
