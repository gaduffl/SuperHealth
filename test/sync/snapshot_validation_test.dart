import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/sync/snapshot_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'rejects missing tables and keeps the current ledger unchanged',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();
      final tables = snapshot['tables'] as Map<String, Object?>;
      tables.remove('profiles');

      await expectLater(
        fixture.service.merge(snapshot),
        throwsA(isA<FormatException>()),
      );
      expect(await fixture.profileName(), 'Current local profile');
    },
  );

  test(
    'rejects duplicate ids, invalid timestamps, and invalid numeric domains',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final duplicate = await fixture.snapshot();
      final duplicateRows = _rows(duplicate, 'profiles');
      duplicateRows.add(Map<String, Object?>.from(duplicateRows.single));
      await expectLater(
        fixture.service.merge(duplicate),
        throwsA(isA<FormatException>()),
      );

      final invalidTimestamp = await fixture.snapshot();
      _rows(invalidTimestamp, 'profiles').single['updated_at'] = 'not-a-time';
      await expectLater(
        fixture.service.merge(invalidTimestamp),
        throwsA(isA<FormatException>()),
      );

      final invalidCalendarDate = await fixture.snapshot();
      _rows(invalidCalendarDate, 'profiles').single['date_of_birth'] =
          '2026-02-30';
      await expectLater(
        fixture.service.merge(invalidCalendarDate),
        throwsA(isA<FormatException>()),
      );

      final invalidClockTime = await fixture.snapshot();
      _rows(invalidClockTime, 'profiles').single['updated_at'] =
          '2026-01-01T24:00:00Z';
      await expectLater(
        fixture.service.merge(invalidClockTime),
        throwsA(isA<FormatException>()),
      );

      final invalidDomain = await fixture.snapshot();
      _rows(invalidDomain, 'profiles').single['height_cm'] = 301.0;
      await expectLater(
        fixture.service.merge(invalidDomain),
        throwsA(isA<FormatException>()),
      );

      final nonFinite = await fixture.snapshot();
      _rows(nonFinite, 'profiles').single['height_cm'] = double.infinity;
      await expectLater(
        fixture.service.merge(nonFinite),
        throwsA(isA<FormatException>()),
      );
      expect(await fixture.profileName(), 'Current local profile');
    },
  );

  test(
    'rejects broken synchronized references before applying any rows',
    () async {
      final fixture = await _Fixture.create(withSchedule: true);
      addTearDown(fixture.dispose);
      final snapshot = await fixture.snapshot();
      _rows(snapshot, 'supplement_schedules').single['supplement_id'] =
          'missing-supplement';

      await expectLater(
        fixture.service.merge(snapshot),
        throwsA(isA<FormatException>()),
      );
      expect(await fixture.profileName(), 'Current local profile');
    },
  );

  test(
    'rejects rows whose linked records disagree on profile, supplement, or kind',
    () async {
      final fixture = await _Fixture.create(withRelations: true);
      addTearDown(fixture.dispose);

      final intakeMismatch = await fixture.snapshot();
      _rows(intakeMismatch, 'supplement_intakes').single['profile_id'] =
          'profile-2';
      await expectLater(
        fixture.service.merge(intakeMismatch),
        throwsA(isA<FormatException>()),
      );

      final intakeSupplementMismatch = await fixture.snapshot();
      _rows(
        intakeSupplementMismatch,
        'supplement_intakes',
      ).single['supplement_id'] = 'supplement-2';
      await expectLater(
        fixture.service.merge(intakeSupplementMismatch),
        throwsA(isA<FormatException>()),
      );

      final movementMismatch = await fixture.snapshot();
      _rows(movementMismatch, 'inventory_movements').single['supplement_id'] =
          'supplement-2';
      await expectLater(
        fixture.service.merge(movementMismatch),
        throwsA(isA<FormatException>()),
      );

      final eventMismatch = await fixture.snapshot();
      _rows(eventMismatch, 'health_events').single['kind'] = 'tag';
      await expectLater(
        fixture.service.merge(eventMismatch),
        throwsA(isA<FormatException>()),
      );

      final measurementMismatch = await fixture.snapshot();
      _rows(measurementMismatch, 'measurements').single['profile_id'] =
          'profile-2';
      await expectLater(
        fixture.service.merge(measurementMismatch),
        throwsA(isA<FormatException>()),
      );
      expect(await fixture.profileName(), 'Current local profile');
    },
  );

  test(
    'rejects invalid known enum values before applying a snapshot',
    () async {
      final fixture = await _Fixture.create(withRelations: true);
      addTearDown(fixture.dispose);

      final invalidSex = await fixture.snapshot();
      _rows(invalidSex, 'profiles').first['sex'] = 'unknown';
      await expectLater(
        fixture.service.merge(invalidSex),
        throwsA(isA<FormatException>()),
      );

      final invalidParseStatus = await fixture.snapshot();
      _rows(invalidParseStatus, 'documents').single['parse_status'] = 'parsed';
      await expectLater(
        fixture.service.merge(invalidParseStatus),
        throwsA(isA<FormatException>()),
      );

      final invalidConversion = await fixture.snapshot();
      _rows(invalidConversion, 'measurements').single['conversion_status'] =
          'guessed';
      await expectLater(
        fixture.service.merge(invalidConversion),
        throwsA(isA<FormatException>()),
      );

      final invalidRecordStatus = await fixture.snapshot();
      _rows(invalidRecordStatus, 'named_health_records').single['status'] =
          'unknown';
      await expectLater(
        fixture.service.merge(invalidRecordStatus),
        throwsA(isA<FormatException>()),
      );

      final invalidPlanStatus = await fixture.snapshot();
      _rows(invalidPlanStatus, 'lab_plans').single['status'] = 'approved';
      await expectLater(
        fixture.service.merge(invalidPlanStatus),
        throwsA(isA<FormatException>()),
      );

      final invalidRole = await fixture.snapshot();
      _rows(invalidRole, 'advisor_messages').single['role'] = 'system';
      await expectLater(
        fixture.service.merge(invalidRole),
        throwsA(isA<FormatException>()),
      );
      expect(await fixture.profileName(), 'Current local profile');
    },
  );
}

class _Fixture {
  _Fixture(this.database, this.repository, this.service);

  final AppDatabase database;
  final HealthRepository repository;
  final SnapshotService service;

  static Future<_Fixture> create({
    bool withSchedule = false,
    bool withRelations = false,
  }) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final at = DateTime.utc(2026, 7, 24, 12);
    await repository.saveProfile(
      Profile(
        id: 'profile-1',
        displayName: 'Current local profile',
        heightCm: 180,
        createdAt: at,
        updatedAt: at,
      ),
    );
    if (withSchedule || withRelations) {
      await repository.saveSupplement(
        Supplement(
          id: 'supplement-1',
          name: 'Vitamin D',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveSchedule(
        SupplementSchedule(
          id: 'schedule-1',
          profileId: 'profile-1',
          supplementId: 'supplement-1',
          dose: 1,
          unit: 'capsule',
          timeOfDay: '08:00',
          weekdays: const ['mon'],
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
    if (withRelations) {
      await repository.saveProfile(
        Profile(
          id: 'profile-2',
          displayName: 'Other profile',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveSupplement(
        Supplement(
          id: 'supplement-2',
          name: 'Other supplement',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveIntake(
        SupplementIntake(
          id: 'intake-1',
          profileId: 'profile-1',
          supplementId: 'supplement-1',
          scheduleId: 'schedule-1',
          takenAt: at,
          dose: 1,
          unit: 'capsule',
          createdAt: at,
          updatedAt: at,
        ),
        inventoryUnits: 1,
      );
      await repository.saveEventDefinition(
        HealthEventDefinition(
          id: 'definition-1',
          profileId: 'profile-1',
          kind: EventKind.symptom,
          name: 'Headache',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveEvent(
        HealthEvent(
          id: 'event-1',
          profileId: 'profile-1',
          definitionId: 'definition-1',
          kind: EventKind.symptom,
          name: 'Headache',
          observedAt: at,
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveBiomarker(
        Biomarker(
          id: 'biomarker-1',
          canonicalName: 'example',
          displayName: 'Example',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveDocument(
        HealthDocument(
          id: 'document-1',
          profileId: 'profile-1',
          fileName: 'lab.pdf',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveMeasurement(
        Measurement(
          id: 'measurement-1',
          profileId: 'profile-1',
          biomarkerId: 'biomarker-1',
          documentId: 'document-1',
          takenAt: at,
          value: 1,
          unit: 'mg/dL',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveNamedRecord(
        NamedHealthRecord(
          id: 'record-1',
          profileId: 'profile-1',
          name: 'Goal',
          kind: 'goal',
          status: 'active',
          createdAt: at,
          updatedAt: at,
        ),
      );
      await repository.saveLabPlan(
        LabPlan(
          id: 'plan-1',
          profileId: 'profile-1',
          title: 'Plan',
          contextHash: 'context',
          createdAt: at,
          updatedAt: at,
          items: const [],
        ),
      );
      await repository.saveMessage(
        AdvisorMessage(
          id: 'message-1',
          profileId: 'profile-1',
          conversationId: 'conversation-1',
          role: 'user',
          content: 'Hello',
          createdAt: at,
        ),
      );
    }
    return _Fixture(
      database,
      repository,
      SnapshotService(database, repository),
    );
  }

  Future<Map<String, Object?>> snapshot() async => Map<String, Object?>.from(
    jsonDecode(jsonEncode(await repository.fullSyncSnapshot())) as Map,
  );

  Future<String> profileName() async =>
      (await (await database.database).query(
            'profiles',
            where: 'id = ?',
            whereArgs: const ['profile-1'],
          )).single['display_name']
          as String;

  Future<void> dispose() => database.close();
}

List<Map<String, Object?>> _rows(Map<String, Object?> snapshot, String table) =>
    ((snapshot['tables'] as Map<String, Object?>)[table] as List)
        .cast<Map<String, Object?>>();
