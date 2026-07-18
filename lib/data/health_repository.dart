import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../biomarkers/unit_conversion_service.dart';
import '../domain/entities.dart';
import 'app_database.dart';

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

  Future<void> saveIntake(
    SupplementIntake intake, {
    double? inventoryUnits,
  }) async {
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
    final db = await _database.database;
    await db.insert(
      'biomarker_ranges',
      range.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    final map = measurement.toMap();
    final rows = await db.query(
      'biomarkers',
      columns: ['canonical_name', 'default_unit'],
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
    final biomarker = rows.single;
    final canonicalName = biomarker['canonical_name']?.toString() ?? '';
    final preferredUnit = _unitConversion.normalizeUnit(
      biomarker['default_unit']?.toString() ?? measurement.unit,
    );
    final reportedUnit = _unitConversion.normalizeUnit(measurement.unit);
    map['unit_reported'] = reportedUnit;
    map['canonical_unit'] = preferredUnit;
    if (reportedUnit == preferredUnit) {
      map['canonical_value'] = measurement.value;
      map['conversion_status'] = 'not_required';
      return map;
    }
    final converted = _unitConversion.convertValue(
      measurement.value,
      reportedUnit,
      preferredUnit,
      canonicalName,
    );
    map['canonical_value'] = converted;
    map['conversion_status'] = converted == null ? 'unsupported' : 'converted';
    return map;
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
    final result = <DueBiomarker>[];
    for (final list in lists) {
      for (final item in list.items) {
        final interval = item.dueIntervalDays;
        final biomarker = catalog[item.biomarkerId];
        if (interval == null || interval <= 0 || biomarker == null) continue;
        final measured = latest[item.biomarkerId];
        final dueDate =
            measured?.add(Duration(days: interval)) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (!dueDate.isAfter(now)) {
          result.add(
            DueBiomarker(
              biomarker: biomarker,
              listName: list.name,
              lastMeasuredAt: measured,
              dueDate: dueDate,
              intervalDays: interval,
            ),
          );
        }
      }
    }
    result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
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
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        'lab_plans',
        plan.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
        where: '(profile_id IS NULL OR profile_id = ?) AND deleted = 0',
        whereArgs: [profileId],
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
      'lab_plans': await _profileRows(
        db,
        'lab_plans',
        profileId,
        includeDeletedClause: false,
      ),
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
          'other_profiles_intakes_and_events',
          'advisor_messages_outside_active_conversation',
        ],
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
