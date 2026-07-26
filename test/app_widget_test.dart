import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:super_health/app/super_health_app.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  testWidgets('shows profile onboarding when the local record is empty', (
    tester,
  ) async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final keyStore = ApiKeyStore();
    final clientFactory = AiProviderClientFactory();
    final contextBuilder = HealthContextBuilder(repository);
    final snapshot = SnapshotService(database, repository);
    final oneDrive = OneDriveService(snapshot);
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

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const SuperHealthApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to SuperHealth'), findsOneWidget);
    expect(find.text('Start fresh'), findsOneWidget);
    expect(find.text('Restore or transfer existing data'), findsOneWidget);

    controller.dispose();
  });
}
