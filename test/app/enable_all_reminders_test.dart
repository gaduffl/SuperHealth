import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'turning reminders on covers every active schedule that lacks one',
    () async {
      // A reminder is per schedule and defaults to off, so a library built before
      // anyone opened Settings has none of them on and reports zero scheduled
      // reminders. Switching them on one dialog at a time is the reason people
      // conclude notifications are broken.
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final now = DateTime(2026, 8, 7);
      final profile = await fixture.repository.createProfile(displayName: 'A');
      final supplement = Supplement(
        id: 'magnesium',
        name: 'Magnesium',
        createdAt: now,
        updatedAt: now,
      );
      await fixture.repository.saveSupplement(supplement);
      for (final (id, active, enabled, time) in [
        ('off', true, false, '08:00'),
        ('already-on', true, true, '20:00'),
        ('inactive', false, false, '08:00'),
        ('unreadable', true, false, 'after gym'),
      ]) {
        await fixture.repository.saveSchedule(
          _schedule(
            id,
            profile.id,
            supplement.id,
            now,
            active: active,
            reminderEnabled: enabled,
            timeOfDay: time,
          ),
        );
      }
      fixture.controller
        ..profiles = [profile]
        ..activeProfile = profile;
      await fixture.controller.refreshActiveData();

      final result = await fixture.controller.enableAllScheduleReminders();

      // Two were switched on; the one already on is not counted again and the
      // inactive one is left alone.
      expect(result.enabled, 2);
      // And the caller is told how many of those still cannot fire, rather than
      // reporting a clean success over a schedule that produces nothing.
      expect(result.needingTimeFix, 1);

      final db = await fixture.database.database;
      final rows = await db.query(
        'supplement_schedules',
        columns: ['id', 'reminder_enabled'],
        orderBy: 'id',
      );
      expect(rows, [
        {'id': 'already-on', 'reminder_enabled': 1},
        {'id': 'inactive', 'reminder_enabled': 0},
        {'id': 'off', 'reminder_enabled': 1},
        {'id': 'unreadable', 'reminder_enabled': 1},
      ]);

      // The schedule that cannot fire stays visible, so it can be corrected.
      expect(
        fixture.controller.schedulesWithUnreadableReminderTime.map(
          (item) => item.id,
        ),
        ['unreadable'],
      );

      // Running it again finds nothing left to do.
      expect(
        (await fixture.controller.enableAllScheduleReminders()).enabled,
        0,
      );
    },
  );
}

SupplementSchedule _schedule(
  String id,
  String profileId,
  String supplementId,
  DateTime now, {
  bool active = true,
  bool reminderEnabled = false,
  String timeOfDay = '08:00',
}) => SupplementSchedule(
  id: id,
  profileId: profileId,
  supplementId: supplementId,
  dose: 1,
  unit: 'capsule',
  timeOfDay: timeOfDay,
  weekdays: const ['monday'],
  active: active,
  reminderEnabled: reminderEnabled,
  createdAt: now,
  updatedAt: now,
);

class _Fixture {
  _Fixture({
    required this.database,
    required this.repository,
    required this.controller,
  });

  final AppDatabase database;
  final HealthRepository repository;
  final AppController controller;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final snapshot = SnapshotService(database, repository);
    final oneDrive = OneDriveService(snapshot);
    final keyStore = ApiKeyStore();
    final clientFactory = AiProviderClientFactory();
    final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
    final controller = AppController(
      database: database,
      repository: repository,
      keyStore: keyStore,
      aiSettingsStore: AiSettingsStore(),
      advisorService: AdvisorService(
        repository: repository,
        keyStore: keyStore,
        clientFactory: clientFactory,
        contextBuilder: HealthContextBuilder(repository),
        workspaceService: workspace,
      ),
      labPlannerService: LabPlannerService(
        repository: repository,
        keyStore: keyStore,
        clientFactory: clientFactory,
        contextBuilder: HealthContextBuilder(repository),
      ),
      documentParsingService: DocumentParsingService(
        repository: repository,
        keyStore: keyStore,
        oneDriveService: oneDrive,
      ),
      correlationService: CorrelationService(repository),
      importService: LegacyImportService(database, repository),
      oneDriveService: oneDrive,
      workspaceService: workspace,
      exportService: LabPlanExportService(),
      clientFactory: clientFactory,
    );
    return _Fixture(
      database: database,
      repository: repository,
      controller: controller,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await database.close();
  }
}
