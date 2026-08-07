import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/lab_price_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/app/initial_setup_progress.dart';
import 'package:super_health/backup/portable_backup_service.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/restore_sync_gate.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'loading progress never records an action and explicit skips persist',
    () async {
      final store = InitialSetupProgressStore();

      expect(await store.loadFacts(), isA<InitialSetupFacts>());
      var facts = await store.loadFacts();
      expect(facts.legacyJsonSkipped, isFalse);
      expect(facts.cloudSkipped, isFalse);
      expect(facts.aiSkipped, isFalse);

      await store.recordLegacyJsonSkipped();
      await store.recordLegacyPdfsSkipped();
      await store.recordCloudSkipped();
      await store.recordAiSkipped();

      facts = await InitialSetupProgressStore().loadFacts();
      expect(facts.legacyJsonSkipped, isTrue);
      expect(facts.legacyPdfsSkipped, isTrue);
      expect(facts.cloudSkipped, isTrue);
      expect(facts.aiSkipped, isTrue);
    },
  );

  test(
    'conflicted sync is not recorded, but a successful empty upload is',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      fixture.oneDrive
        ..signedIn = true
        ..mode = OneDriveStorageMode.appFolder
        ..syncResult = const OneDriveSyncResult(
          remoteFound: true,
          appliedRows: 3,
          keptLocalRows: 0,
          conflicts: 1,
          uploadedBytes: 0,
        );

      await fixture.controller.synchronizeOneDrive();
      expect(
        fixture.controller.initialSetupProgress.firstSuccessfulSync,
        isFalse,
      );
      expect(fixture.controller.initialSetupProgress.dataRestored, isFalse);

      fixture.oneDrive.syncResult = const OneDriveSyncResult(
        remoteFound: false,
        appliedRows: 0,
        keptLocalRows: 0,
        conflicts: 0,
        uploadedBytes: 120,
      );
      await fixture.controller.synchronizeOneDrive();

      expect(
        fixture.controller.initialSetupProgress.firstSuccessfulSync,
        isTrue,
      );
      expect(fixture.controller.initialSetupProgress.dataRestored, isFalse);
      expect((await fixture.store.loadFacts()).firstSuccessfulSync, isTrue);
    },
  );

  test(
    'successful remote changes can satisfy legacy migration steps',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.repository.createProfile(displayName: 'Alex');
      fixture.oneDrive
        ..signedIn = true
        ..mode = OneDriveStorageMode.appFolder
        ..syncResult = const OneDriveSyncResult(
          remoteFound: true,
          appliedRows: 4,
          keptLocalRows: 0,
          conflicts: 0,
          uploadedBytes: 0,
        );

      await fixture.controller.synchronizeOneDrive();

      expect(fixture.controller.initialSetupProgress.dataRestored, isTrue);
      expect(fixture.controller.initialSetupProgress.legacyJsonHandled, isTrue);
      expect(fixture.controller.initialSetupProgress.legacyPdfsHandled, isTrue);
    },
  );

  test(
    'derives advisor and OneDrive readiness without recording completion',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      fixture.controller
        ..advisorSettings = const AiTaskSettings(
          provider: AiProvider.openai,
          model: 'gpt-5.4',
        )
        ..hasApiKey[AiProvider.openai] = true;
      fixture.oneDrive
        ..signedIn = true
        ..mode = OneDriveStorageMode.sharedFolder;

      await fixture.controller.refreshInitialSetupProgress();
      expect(fixture.controller.initialSetupProgress.advisorReady, isTrue);
      expect(fixture.controller.initialSetupProgress.oneDriveReady, isFalse);
      expect(
        fixture.controller.initialSetupProgress.firstSuccessfulSync,
        isFalse,
      );

      fixture.oneDrive.folder = const OneDriveFolder(
        driveId: 'family-drive',
        itemId: 'family-folder',
        name: 'Family health',
        isShared: true,
      );
      await fixture.controller.refreshInitialSetupProgress();

      expect(fixture.controller.initialSetupProgress.oneDriveReady, isTrue);
      expect(
        fixture.controller.initialSetupProgress.firstSuccessfulSync,
        isFalse,
      );
    },
  );

  test(
    'restored data can complete setup once a profile is available',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.store.recordDataRestored();
      await fixture.store.recordCloudSkipped();
      await fixture.store.recordAiSkipped();

      await fixture.controller.refreshInitialSetupProgress();
      expect(fixture.controller.initialSetupProgress.legacyJsonHandled, isTrue);
      expect(fixture.controller.initialSetupProgress.legacyPdfsHandled, isTrue);
      expect(fixture.controller.initialSetupProgress.isComplete, isFalse);

      await fixture.repository.createProfile(displayName: 'Alex');
      await fixture.controller.refreshProfiles();

      expect(fixture.controller.initialSetupProgress.profileExists, isTrue);
      expect(fixture.controller.initialSetupProgress.isComplete, isTrue);
    },
  );

  test(
    'controller skip actions persist only after their explicit calls',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      await fixture.controller.refreshInitialSetupProgress();
      expect(
        fixture.controller.initialSetupProgress.legacyJsonSkipped,
        isFalse,
      );

      await fixture.controller.markLegacyJsonImportSkipped();
      await fixture.controller.markLegacyPdfsImportSkipped();
      await fixture.controller.markCloudSetupSkipped();
      await fixture.controller.markAiSetupSkipped();

      final facts = await fixture.store.loadFacts();
      expect(facts.legacyJsonSkipped, isTrue);
      expect(facts.legacyPdfsSkipped, isTrue);
      expect(facts.cloudSkipped, isTrue);
      expect(facts.aiSkipped, isTrue);
    },
  );

  test(
    'portable restore pauses normal sync until an explicit choice',
    () async {
      final fixture = await _Fixture.create(withPortableBackups: true);
      addTearDown(fixture.dispose);
      final source = await fixture.portableBackupService!.createJson();

      await fixture.controller.restorePortableBackup(source);

      expect(fixture.controller.restoreSyncDecisionPending, isTrue);
      expect(await fixture.restoreGate.isPending(), isTrue);
      await expectLater(
        fixture.controller.synchronizeOneDrive(),
        throwsA(isA<RestoreSyncDecisionRequiredError>()),
      );
      expect(fixture.oneDrive.normalSyncCalls, 0);
      expect(await fixture.restoreGate.isPending(), isTrue);
    },
  );

  test(
    'failed portable restore clears its provisional gate and leaves normal sync available',
    () async {
      final fixture = await _Fixture.create(withPortableBackups: true);
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.controller.restorePortableBackup('not a portable backup'),
        throwsA(isA<FormatException>()),
      );

      expect(fixture.controller.restoreSyncDecisionPending, isFalse);
      expect(await fixture.restoreGate.isPending(), isFalse);
      await fixture.controller.synchronizeOneDrive();
      expect(fixture.oneDrive.normalSyncCalls, 1);
    },
  );

  test('resume and merge re-closes the restore gate when sync fails', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.restoreGate.requireDecision();
    fixture.oneDrive.normalSyncError = StateError('offline');

    await expectLater(
      fixture.controller.resumeRestoredDataAndMerge(),
      throwsA(isA<StateError>()),
    );

    expect(fixture.oneDrive.normalSyncCalls, 1);
    expect(fixture.controller.restoreSyncDecisionPending, isTrue);
    expect(await fixture.restoreGate.isPending(), isTrue);
  });

  test(
    'resume and merge clears the gate only after normal sync begins',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.restoreGate.requireDecision();

      await fixture.controller.resumeRestoredDataAndMerge();

      expect(fixture.oneDrive.normalSyncCalls, 1);
      expect(fixture.controller.restoreSyncDecisionPending, isFalse);
      expect(await fixture.restoreGate.isPending(), isFalse);
    },
  );

  test(
    'authoritative publish retains the gate when the upload fails',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.restoreGate.requireDecision();
      fixture.oneDrive.publishError = StateError('precondition failed');

      await expectLater(
        fixture.controller.publishRestoredDataToOneDrive(),
        throwsA(isA<StateError>()),
      );

      expect(fixture.oneDrive.authoritativePublishCalls, 1);
      expect(fixture.oneDrive.normalSyncCalls, 0);
      expect(fixture.controller.restoreSyncDecisionPending, isTrue);
      expect(await fixture.restoreGate.isPending(), isTrue);
    },
  );

  test(
    'authoritative publish clears the gate after complete success',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await fixture.restoreGate.requireDecision();
      fixture.oneDrive.publishResult = const OneDriveSyncResult(
        remoteFound: true,
        appliedRows: 0,
        keptLocalRows: 0,
        conflicts: 0,
        uploadedBytes: 12,
      );

      await fixture.controller.publishRestoredDataToOneDrive();

      expect(fixture.oneDrive.authoritativePublishCalls, 1);
      expect(fixture.oneDrive.normalSyncCalls, 0);
      expect(fixture.controller.restoreSyncDecisionPending, isFalse);
      expect(await fixture.restoreGate.isPending(), isFalse);
    },
  );
}

class _Fixture {
  _Fixture({
    required this.database,
    required this.repository,
    required this.oneDrive,
    required this.controller,
    required this.store,
    required this.restoreGate,
    required this.temporaryDirectory,
    this.portableBackupService,
  });

  final AppDatabase database;
  final HealthRepository repository;
  final _TestOneDriveService oneDrive;
  final AppController controller;
  final InitialSetupProgressStore store;
  final RestoreSyncGateStore restoreGate;
  final Directory temporaryDirectory;
  final PortableBackupService? portableBackupService;

  static Future<_Fixture> create({bool withPortableBackups = false}) async {
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
    final store = InitialSetupProgressStore();
    final restoreGate = RestoreSyncGateStore();
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'super-health-restore-gate-',
    );
    final portableBackupService = withPortableBackups
        ? PortableBackupService(
            database,
            documentsDirectory: () async => temporaryDirectory,
          )
        : null;
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
      initialSetupProgressStore: store,
      restoreSyncGateStore: restoreGate,
      portableBackupService: portableBackupService,
    );
    return _Fixture(
      database: database,
      repository: repository,
      oneDrive: oneDrive,
      controller: controller,
      store: store,
      restoreGate: restoreGate,
      temporaryDirectory: temporaryDirectory,
      portableBackupService: portableBackupService,
    );
  }

  Future<void> dispose() async {
    await (await database.database).close();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
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
  OneDriveSyncResult publishResult = const OneDriveSyncResult(
    remoteFound: false,
    appliedRows: 0,
    keptLocalRows: 0,
    conflicts: 0,
    uploadedBytes: 0,
  );
  Object? normalSyncError;
  Object? publishError;
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
    final error = publishError;
    if (error != null) throw error;
    return publishResult;
  }
}
