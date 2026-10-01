import 'package:dio/dio.dart';
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
import 'package:super_health/ai/lab_price_service.dart';
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
import 'package:super_health/ui/settings_screen.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

import 'package:super_health/updates/app_version.dart';
import 'package:super_health/updates/update_controller.dart';
import 'package:super_health/updates/update_downloader.dart';
import 'package:super_health/updates/update_models.dart';
import 'package:super_health/updates/update_settings.dart';

import '../updates/fakes.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Profile profile({required bool easy}) => Profile(
    id: 'p',
    displayName: 'Pat',
    easyMode: easy,
    createdAt: DateTime(2020),
    updatedAt: DateTime(2020),
  );

  Future<void> pumpSettings(
    WidgetTester tester, {
    required bool easy,
    UpdateController? updates,
  }) async {
    final controller = _controller()
      ..profiles = [profile(easy: easy)]
      ..activeProfile = profile(easy: easy);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          if (updates != null) ChangeNotifierProvider.value(value: updates),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
  }

  UpdateController updates() {
    final downloads = tempDir();
    return UpdateController(
      installer: FakeInstaller(),
      settingsStore: UpdateSettingsStore(),
      tokenStore: MemoryTokens(),
      downloader: UpdateDownloader(
        dio: Dio(),
        directory: () async => downloads,
      ),
      sourceFactory: (_, _) => FixedSource(
        AvailableUpdate(
          version: AppVersion.tryParse('0.43.0+72')!,
          downloadUri: Uri.parse('https://api.github.com/a'),
        ),
      ),
    );
  }

  // Tall enough that the lazy list builds every row, so an assertion about
  // absence means the section is not there rather than not yet scrolled to.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('Settings carries a labelled way to check for updates', (
    tester,
  ) async {
    useTallScreen(tester);
    final controller = updates();
    await pumpSettings(tester, easy: false, updates: controller);
    await tester.runAsync(controller.load);
    await tester.pumpAndSettle();

    // The lab-report import once vanished because its only entry was a bare
    // icon; this one must be a button with words on the screen that owns it.
    expect(find.text('App updates'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Check for updates'),
      findsOneWidget,
    );
  });

  testWidgets('the About line shows the installed build, not a literal', (
    tester,
  ) async {
    useTallScreen(tester);
    final controller = updates();
    await pumpSettings(tester, easy: false, updates: controller);
    await tester.runAsync(controller.load);
    await tester.pumpAndSettle();

    expect(
      find.text('SuperHealth 0.42.0+71 · Personal-use Android build'),
      findsOneWidget,
    );
    expect(find.textContaining('0.5.0'), findsNothing);
  });

  testWidgets('the About line omits the number rather than guess one', (
    tester,
  ) async {
    useTallScreen(tester);
    await pumpSettings(tester, easy: false);

    expect(
      find.text('SuperHealth · Personal-use Android build'),
      findsOneWidget,
    );
  });

  testWidgets('easy mode never shows the updater', (tester) async {
    useTallScreen(tester);
    await pumpSettings(tester, easy: true, updates: updates());

    expect(find.text('Profiles'), findsOneWidget, reason: 'the page did build');
    expect(find.text('App updates'), findsNothing);
    expect(find.text('Check for updates'), findsNothing);
  });
}

AppController _controller() {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final repository = HealthRepository(database);
  final keyStore = ApiKeyStore();
  final clientFactory = AiProviderClientFactory();
  final contextBuilder = HealthContextBuilder(repository);
  final snapshot = SnapshotService(database, repository);
  final oneDrive = _TestOneDriveService(snapshot);
  final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
  return AppController(
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
    labPriceService: LabPriceService(keyStore, clientFactory),
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
}

class _TestOneDriveService extends OneDriveService {
  _TestOneDriveService(super.snapshotService);

  @override
  Future<bool> isSignedIn() async => false;
}
