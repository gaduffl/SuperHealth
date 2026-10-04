import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/clinical_digest.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/lab_price_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/app/shell_navigation.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/ui/health_screen.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a rejected draft says beside its disabled Save button why it cannot be saved',
    (tester) async {
      final controller = _seededController(
        draft: _generation(
          approved: false,
          blockingIssues: const ['Fasting glucose lacks its preparation note.'],
        ),
      );
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });

      await _openPlanner(tester, controller, navigation);

      expect(
        find.text('Cannot be saved: the independent check rejected this draft'),
        findsOneWidget,
      );
      // Shown in the notice itself, not only inside the collapsed plan notes,
      // whose children are not built until opened.
      expect(
        find.text('Fasting glucose lacks its preparation note.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Rejected by the independent check'),
        findsOneWidget,
      );
      final save = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('Save plan'),
          matching: find.bySubtype<ButtonStyleButton>(),
        ),
      );
      expect(save.onPressed, isNull);
    },
  );

  testWidgets('an approved draft carries no save-blocked notice', (
    tester,
  ) async {
    final controller = _seededController(draft: _generation(approved: true));
    final navigation = ShellNavigation();
    addTearDown(() {
      controller.dispose();
      navigation.dispose();
    });

    await _openPlanner(tester, controller, navigation);

    expect(find.textContaining('Cannot be saved'), findsNothing);
    final save = tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text('Save plan'),
        matching: find.bySubtype<ButtonStyleButton>(),
      ),
    );
    expect(save.onPressed, isNotNull);
  });

  testWidgets(
    'an earlier draft under a running generation is labelled as the previous one',
    (tester) async {
      // It sat under the progress card titled "Unsaved draft", which read as
      // the running generation's result arriving while the app still said it
      // was working.
      final controller = _seededController(draft: _generation(approved: true))
        ..labPlanStage = LabPlanStage.drafting
        ..labPlanStartedAt = DateTime.now();
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });

      await _openPlanner(tester, controller, navigation, settle: false);

      expect(find.text('Previous draft · Lab visit'), findsOneWidget);
      expect(find.text('Unsaved draft · Lab visit'), findsNothing);
      expect(
        find.textContaining('replaces it when it arrives'),
        findsOneWidget,
      );

      controller
        ..labPlanStage = null
        ..labPlanStartedAt = null
        ..notifyListeners();
      await tester.pumpAndSettle();

      expect(find.text('Unsaved draft · Lab visit'), findsOneWidget);
      expect(find.text('Previous draft · Lab visit'), findsNothing);
    },
  );
}

Future<void> _openPlanner(
  WidgetTester tester,
  AppController controller,
  ShellNavigation navigation, {
  bool settle = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: navigation),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: HealthScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Biomarkers'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lab planning and biomarker management'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lab visit planner'));
  // The progress card runs a clock, so a screen with a generation in flight
  // never settles.
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

final _now = DateTime(2026, 7, 27);

LabPlanGeneration _generation({
  required bool approved,
  List<String> blockingIssues = const [],
}) {
  final plan = LabPlan(
    id: 'plan',
    profileId: 'profile',
    title: 'Lab visit',
    createdAt: _now,
    updatedAt: _now,
    items: const [
      LabPlanItem(
        id: 'item',
        planId: 'plan',
        biomarkerId: 'glucose',
        biomarkerName: 'Glucose',
        tier: LabTier.core,
        priority: 1,
        rationale: 'Seed rationale.',
        evidenceClass: EvidenceClass.guideline,
      ),
    ],
  );
  return LabPlanGeneration(
    plan: plan,
    digest: const ClinicalDigest(json: '{}', checklist: [], sha256: 'seed'),
    warnings: const [],
    citations: const [],
    verification: LabPlanVerification(
      approved: approved,
      summary: approved ? 'Consistent with the record.' : 'Seed rejection.',
      blockingIssues: blockingIssues,
      warnings: const [],
    ),
  );
}

AppController _seededController({required LabPlanGeneration draft}) {
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex',
    createdAt: _now,
    updatedAt: _now,
  );
  return _controller()
    ..initialized = true
    ..profiles = [profile]
    ..activeProfile = profile
    ..biomarkers = [
      Biomarker(
        id: 'glucose',
        canonicalName: 'glucose',
        displayName: 'Glucose',
        defaultUnit: 'mg/dL',
        createdAt: _now,
        updatedAt: _now,
      ),
    ]
    ..draftLabPlan = draft;
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
  final oneDrive = OneDriveService(snapshot, repository: repository);
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
  );
}
