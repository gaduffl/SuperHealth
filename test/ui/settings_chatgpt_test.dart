import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/chatgpt_auth.dart';
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

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final profile = Profile(
    id: 'p',
    displayName: 'Pat',
    createdAt: DateTime(2020),
    updatedAt: DateTime(2020),
  );

  // Tall enough that the lazy list builds every row, so an assertion about
  // absence means the row is not there rather than not yet scrolled to.
  void useTallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<AppController> pumpSettings(
    WidgetTester tester, {
    void Function(AppController controller)? configure,
  }) async {
    final controller = _controller()
      ..profiles = [profile]
      ..activeProfile = profile;
    configure?.call(controller);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets(
    'Settings carries a labelled ChatGPT sign-in beside the API keys',
    (tester) async {
      useTallScreen(tester);
      await pumpSettings(tester);

      // A credential that needs a tap to reveal its button, or that is only
      // an icon, is one the owner does not find.
      expect(find.text('ChatGPT subscription'), findsOneWidget);
      expect(find.text('Not signed in'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Sign in with ChatGPT'),
        findsOneWidget,
      );
    },
  );

  testWidgets('a signed-in subscription says whose plan it is', (tester) async {
    useTallScreen(tester);
    await pumpSettings(
      tester,
      configure: (controller) => controller
        ..hasApiKey[AiProvider.chatgpt] = true
        ..chatGptAccount = const ChatGptAccount(
          email: 'pat@example.com',
          planType: 'plus',
        ),
    );

    expect(find.text('Signed in as pat@example.com · Plus'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
    expect(find.text('Sign in with ChatGPT'), findsNothing);
  });

  testWidgets('the controller refuses the subscription for document parsing', (
    tester,
  ) async {
    final controller = _controller();

    await expectLater(
      controller.saveTaskSettings(
        AiTask.parsing,
        const AiTaskSettings(provider: AiProvider.chatgpt, model: 'gpt-5.5'),
      ),
      throwsStateError,
    );
    expect(controller.parsingSettings, isNull);
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
