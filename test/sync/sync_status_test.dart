import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/lab_price_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/restore_sync_gate.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/sync/sync_status.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Controller initialization reads API-key presence from secure storage,
    // which has no platform implementation under `flutter test`.
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('an unrecorded device reports no successful sync', () async {
    expect(await SyncStatusStore().lastSuccessfulSync(), isNull);
  });

  test('a recorded sync survives as a UTC instant', () async {
    final at = DateTime.now();
    await SyncStatusStore().recordSuccessfulSync(at);

    final stored = await SyncStatusStore().lastSuccessfulSync();
    expect(stored, isNotNull);
    expect(stored!.isUtc, isTrue);
    expect(
      stored.difference(at.toUtc()).abs(),
      lessThan(const Duration(seconds: 1)),
    );
  });

  test('an unparsable stored value reads as never synchronized', () async {
    SharedPreferences.setMockInitialValues({
      'onedrive_last_successful_sync_at': 'not a timestamp',
    });

    expect(await SyncStatusStore().lastSuccessfulSync(), isNull);
  });

  test('a conflicted sync never claims the cloud copy is current', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder
      ..syncResult = const OneDriveSyncResult(
        remoteFound: true,
        appliedRows: 2,
        keptLocalRows: 1,
        conflicts: 1,
        uploadedBytes: 0,
      );

    await fixture.controller.synchronizeOneDrive();

    expect(fixture.controller.lastSuccessfulSyncAt, isNull);
    expect(await fixture.syncStatus.lastSuccessfulSync(), isNull);
  });

  test('a clean sync records the upload for the next launch', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder
      ..syncResult = const OneDriveSyncResult(
        remoteFound: true,
        appliedRows: 0,
        keptLocalRows: 0,
        conflicts: 0,
        uploadedBytes: 4096,
      );

    await fixture.controller.synchronizeOneDrive();

    expect(fixture.controller.lastSuccessfulSyncAt, isNotNull);
    expect(await fixture.syncStatus.lastSuccessfulSync(), isNotNull);
  });

  test('an automatic sync runs when the cloud copy is stale', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.syncStatus.recordSuccessfulSync(
      DateTime.now().toUtc().subtract(const Duration(hours: 6)),
    );
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder;

    expect(await fixture.controller.maybeAutoSynchronize(), isTrue);
    expect(fixture.oneDrive.normalSyncCalls, 1);
    expect(fixture.controller.busy, isFalse);
  });

  test('a recent sync is not repeated on the next resume', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.syncStatus.recordSuccessfulSync(DateTime.now().toUtc());
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder;

    expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
    expect(fixture.oneDrive.normalSyncCalls, 0);
  });

  test('a successful automatic sync throttles the one after it', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder;

    expect(await fixture.controller.maybeAutoSynchronize(), isTrue);
    expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
    expect(fixture.oneDrive.normalSyncCalls, 1);
  });

  test('a failed automatic sync is reported, not thrown', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder
      ..normalSyncError = StateError('OneDrive is unreachable');

    expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
    expect(
      fixture.controller.lastAutoSyncError,
      contains('OneDrive is unreachable'),
    );
    expect(fixture.controller.lastSuccessfulSyncAt, isNull);
    expect(fixture.controller.busy, isFalse);
  });

  test('a failed automatic sync does not retry on every resume', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder
      ..normalSyncError = StateError('OneDrive is unreachable');

    await fixture.controller.maybeAutoSynchronize();
    await fixture.controller.maybeAutoSynchronize();

    expect(fixture.oneDrive.normalSyncCalls, 1);
  });

  test('a later success clears the recorded automatic failure', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder
      ..normalSyncError = StateError('OneDrive is unreachable');
    await fixture.controller.maybeAutoSynchronize();
    expect(fixture.controller.lastAutoSyncError, isNotNull);

    fixture.oneDrive.normalSyncError = null;
    await fixture.controller.synchronizeOneDrive();

    expect(fixture.controller.lastAutoSyncError, isNull);
  });

  test('an unconfigured device never starts an automatic sync', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    fixture.oneDrive.signedIn = false;

    expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
    expect(fixture.oneDrive.normalSyncCalls, 0);
  });

  test('a shared-folder device without a folder waits for one', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.sharedFolder
      ..folder = null;

    expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
    expect(fixture.oneDrive.normalSyncCalls, 0);
  });

  test('a pending restore decision blocks the automatic sync', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.restoreGate.requireDecision();
    await fixture.controller.initialize();
    fixture.oneDrive
      ..signedIn = true
      ..mode = OneDriveStorageMode.appFolder;

    expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
    expect(fixture.oneDrive.normalSyncCalls, 0);
    expect(fixture.oneDrive.authoritativePublishCalls, 0);
    expect(fixture.controller.restoreSyncDecisionPending, isTrue);
  });

  test(
    'a restore made after initialization still blocks the automatic sync',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.controller.initialize();
      fixture.oneDrive
        ..signedIn = true
        ..mode = OneDriveStorageMode.appFolder;
      // The durable gate is armed without the cached flag being refreshed,
      // which is exactly the state a restore leaves behind mid-session.
      await fixture.restoreGate.requireDecision();

      expect(await fixture.controller.maybeAutoSynchronize(), isFalse);
      expect(fixture.oneDrive.normalSyncCalls, 0);
      expect(fixture.controller.restoreSyncDecisionPending, isTrue);
    },
  );
}

class _Fixture {
  _Fixture({
    required this.database,
    required this.oneDrive,
    required this.controller,
    required this.syncStatus,
    required this.restoreGate,
  });

  final AppDatabase database;
  final _TestOneDriveService oneDrive;
  final AppController controller;
  final SyncStatusStore syncStatus;
  final RestoreSyncGateStore restoreGate;

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
    final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
    final syncStatus = SyncStatusStore();
    final restoreGate = RestoreSyncGateStore();
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
      labPriceService: LabPriceService(keyStore, clientFactory),
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
      restoreSyncGateStore: restoreGate,
      syncStatusStore: syncStatus,
    );
    return _Fixture(
      database: database,
      oneDrive: oneDrive,
      controller: controller,
      syncStatus: syncStatus,
      restoreGate: restoreGate,
    );
  }

  Future<void> dispose() async {
    await (await database.database).close();
  }
}

class _TestOneDriveService extends OneDriveService {
  _TestOneDriveService(super.snapshotService);

  bool signedIn = false;
  OneDriveStorageMode? mode;
  OneDriveFolder? folder;
  OneDriveSyncResult syncResult = const OneDriveSyncResult(
    remoteFound: false,
    appliedRows: 0,
    keptLocalRows: 0,
    conflicts: 0,
    uploadedBytes: 0,
  );
  Object? normalSyncError;
  int normalSyncCalls = 0;
  int authoritativePublishCalls = 0;

  @override
  Future<bool> isSignedIn() async => signedIn;

  @override
  Future<OneDriveStorageMode?> currentStorageMode() async => mode;

  @override
  Future<OneDriveFolder?> selectedFolder() async => folder;

  @override
  Future<OneDriveSyncResult> synchronize() async {
    normalSyncCalls++;
    final error = normalSyncError;
    if (error != null) throw error;
    return syncResult;
  }

  @override
  Future<OneDriveSyncResult> publishRestoredDataAuthoritatively() async {
    authoritativePublishCalls++;
    return syncResult;
  }
}
