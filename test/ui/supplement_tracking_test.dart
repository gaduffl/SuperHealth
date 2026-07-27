import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:super_health/ui/tracking_screen.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'historical scheduled intake can be logged, edited, and deleted',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final today = DateTime.now();
      final selectedDay = DateTime(
        today.year,
        today.month,
        today.day,
      ).subtract(const Duration(days: 7));
      final profile = await fixture.repository.createProfile(displayName: 'Me');
      final supplement = Supplement(
        id: 'magnesium',
        name: 'Magnesium',
        stockUnit: 'capsule',
        createdAt: selectedDay,
        updatedAt: selectedDay,
      );
      final schedule = SupplementSchedule(
        id: 'morning-magnesium',
        profileId: profile.id,
        supplementId: supplement.id,
        dose: 2,
        unit: 'capsules',
        timeOfDay: '08:00',
        weekdays: [_weekdays[selectedDay.weekday - 1]],
        createdAt: selectedDay,
        updatedAt: selectedDay,
      );
      await fixture.repository.saveSupplement(supplement);
      await fixture.repository.saveSchedule(schedule);
      fixture.controller
        ..profiles = [profile]
        ..activeProfile = profile;
      await fixture.controller.refreshActiveData();

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: fixture.controller,
          child: const MaterialApp(home: Scaffold(body: TrackingScreen())),
        ),
      );
      await _pumpFrames(tester);

      await tester.tap(find.byType(ChoiceChip).first);
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('Mark taken'));
      await _pumpFrames(tester);

      expect(fixture.controller.intakes, hasLength(1));
      final logged = fixture.controller.intakes.single;
      expect(logged.scheduleId, schedule.id);
      expect(
        DateTime(logged.takenAt.year, logged.takenAt.month, logged.takenAt.day),
        selectedDay,
      );
      expect(find.byTooltip('Undo check-in'), findsOneWidget);

      await tester.tap(find.text('History'));
      await _pumpFrames(tester);
      expect(find.text('Magnesium'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);

      await tester.tap(find.byTooltip('Edit'));
      await _pumpFrames(tester);
      final dialog = find.byType(AlertDialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)).first,
        '3',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await _pumpFrames(tester);
      expect(fixture.controller.intakes.single.dose, 3);

      await tester.tap(find.byTooltip('Delete'));
      await _pumpFrames(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await _pumpFrames(tester);
      expect(fixture.controller.intakes, isEmpty);
    },
  );
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var index = 0; index < 20; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

const _weekdays = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

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
    final oneDrive = _TestOneDriveService(snapshot);
    final keyStore = ApiKeyStore();
    final clientFactory = AiProviderClientFactory();
    final contextBuilder = HealthContextBuilder(repository);
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
        contextBuilder: contextBuilder,
        workspaceService: workspace,
      ),
      labPlannerService: LabPlannerService(
        repository: repository,
        keyStore: keyStore,
        clientFactory: clientFactory,
        contextBuilder: contextBuilder,
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
    )..initialized = true;
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

class _TestOneDriveService extends OneDriveService {
  _TestOneDriveService(super.snapshotService);

  @override
  Future<bool> isSignedIn() async => false;
}
