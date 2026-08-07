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

void main() {
  setUpAll(sqfliteFfiInit);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'profile actions expose editing fields and deletion safety copy',
    (tester) async {
      final controller = _controller();
      final now = DateTime(2020);
      final alice = Profile(
        id: 'alice',
        displayName: 'Alice',
        dateOfBirth: DateTime(1990, 7, 18),
        sex: 'female',
        heightCm: 170,
        weightKg: 62,
        notes: 'Training goal',
        createdAt: now,
        updatedAt: now,
      );
      controller.profiles = [
        alice,
        Profile(id: 'ben', displayName: 'Ben', createdAt: now, updatedAt: now),
      ];
      controller.activeProfile = alice;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(home: SettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Active profile'), findsOneWidget);
      expect(find.byTooltip('Actions for Alice'), findsOneWidget);

      await tester.tap(find.byTooltip('Actions for Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit profile'));
      await tester.pumpAndSettle();

      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('Notes / goals'), findsOneWidget);
      expect(find.text('Height (cm)'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Age '),
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Save changes'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(1), '251');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a height from 30 to 250 cm.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, ' ');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a display name.'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Actions for Alice'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete profile'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Alice?'), findsOneWidget);
      expect(
        find.textContaining('profile-scoped health records will be deleted'),
        findsOneWidget,
      );
      expect(
        find.textContaining('shared supplement catalog and stock remain'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Delete profile'),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      controller.dispose();
    },
  );
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
