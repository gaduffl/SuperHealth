import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'ai/advisor_service.dart';
import 'ai/ai_settings.dart';
import 'ai/api_key_store.dart';
import 'ai/document_parsing_service.dart';
import 'ai/health_context_builder.dart';
import 'ai/ai_trace_store.dart';
import 'ai/lab_planner_service.dart';
import 'ai/lab_price_service.dart';
import 'ai/provider_clients.dart';
import 'analysis/correlation_service.dart';
import 'backup/portable_backup_service.dart';
import 'app/app_controller.dart';
import 'app/super_health_app.dart';
import 'data/app_database.dart';
import 'data/health_repository.dart';
import 'export/lab_plan_export_service.dart';
import 'import/legacy_import_service.dart';
import 'reminders/reminder_service.dart';
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
  // The two flows take deliberately different slices of the record: the
  // planner needs catalog entries never measured, the advisor does not.
  final advisorContextBuilder = HealthContextBuilder(
    repository,
    scope: HealthContextScope.advisory,
  );
  final labPlanningContextBuilder = HealthContextBuilder(
    repository,
    scope: HealthContextScope.labPlanning,
  );
  final snapshotService = SnapshotService(database, repository);
  final oneDriveService = OneDriveService(
    snapshotService,
    repository: repository,
  );
  final workspaceService = SafeWorkspaceService(
    oneDriveService: oneDriveService,
  );
  final documentParsingService = DocumentParsingService(
    repository: repository,
    keyStore: keyStore,
    oneDriveService: oneDriveService,
  );
  final portableBackupService = PortableBackupService(
    database,
    documentsDirectory: getApplicationDocumentsDirectory,
  );
  final labPlanTraceStore = AiTraceStore(
    documentsDirectory: getApplicationDocumentsDirectory,
    fileName: AiTraceStore.labPlannerFileName,
  );
  final advisorTraceStore = AiTraceStore(
    documentsDirectory: getApplicationDocumentsDirectory,
    fileName: AiTraceStore.advisorFileName,
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
      contextBuilder: advisorContextBuilder,
      workspaceService: workspaceService,
      trace: advisorTraceStore.trace(),
    ),
    labPriceService: LabPriceService(keyStore, clientFactory),
    labPlannerService: LabPlannerService(
      repository: repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: labPlanningContextBuilder,
      trace: labPlanTraceStore.trace(),
    ),
    documentParsingService: documentParsingService,
    correlationService: CorrelationService(repository),
    importService: LegacyImportService(database, repository),
    oneDriveService: oneDriveService,
    workspaceService: workspaceService,
    exportService: LabPlanExportService(),
    clientFactory: clientFactory,
    reminderService: ReminderService(),
    portableBackupService: portableBackupService,
    documentsDirectory: getApplicationDocumentsDirectory,
    labPlanTraceStore: labPlanTraceStore,
    advisorTraceStore: advisorTraceStore,
  );

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const SuperHealthApp(),
    ),
  );
  controller.initialize();
}
