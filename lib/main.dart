import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'ai/advisor_service.dart';
import 'ai/ai_settings.dart';
import 'ai/api_key_store.dart';
import 'ai/document_parsing_service.dart';
import 'ai/health_context_builder.dart';
import 'ai/lab_planner_service.dart';
import 'ai/provider_clients.dart';
import 'analysis/correlation_service.dart';
import 'app/app_controller.dart';
import 'app/super_health_app.dart';
import 'data/app_database.dart';
import 'data/health_repository.dart';
import 'export/lab_plan_export_service.dart';
import 'import/legacy_import_service.dart';
import 'sync/one_drive_service.dart';
import 'sync/snapshot_service.dart';
import 'workspace/safe_workspace_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final database = AppDatabase();
  final repository = HealthRepository(database);
  final keyStore = ApiKeyStore();
  final settingsStore = AiSettingsStore();
  final clientFactory = AiProviderClientFactory();
  final contextBuilder = HealthContextBuilder(repository);
  final snapshotService = SnapshotService(database, repository);
  final oneDriveService = OneDriveService(snapshotService);
  final workspaceService = SafeWorkspaceService(
    oneDriveService: oneDriveService,
  );
  final documentParsingService = DocumentParsingService(
    repository: repository,
    keyStore: keyStore,
    oneDriveService: oneDriveService,
  );
  final controller = AppController(
    database: database,
    repository: repository,
    keyStore: keyStore,
    aiSettingsStore: settingsStore,
    advisorService: AdvisorService(
      repository: repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: contextBuilder,
      workspaceService: workspaceService,
    ),
    labPlannerService: LabPlannerService(
      repository: repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: contextBuilder,
    ),
    documentParsingService: documentParsingService,
    correlationService: CorrelationService(repository),
    importService: LegacyImportService(database, repository),
    oneDriveService: oneDriveService,
    workspaceService: workspaceService,
    exportService: LabPlanExportService(),
    clientFactory: clientFactory,
  );

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const SuperHealthApp(),
    ),
  );
  controller.initialize();
}
