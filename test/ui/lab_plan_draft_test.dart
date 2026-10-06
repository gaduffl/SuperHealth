import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/ai_models.dart';
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
import 'package:super_health/ui/lab_price_screen.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    initializeDateFormatting('en');
    initializeDateFormatting('de');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'the planner offers named labs without changing an existing draft',
    (tester) async {
      final controller = _seededController(draft: _generation(approved: true));
      controller.labPlannerSettings = const AiTaskSettings(
        provider: AiProvider.openai,
        model: 'gpt-5.6',
      );
      controller.labPrices = [
        for (final lab in ['Lab A', 'Lab B'])
          LabPrice(
            id: lab,
            labName: lab,
            biomarkerId: 'glucose',
            priceEur: 15,
            createdAt: _now,
            updatedAt: _now,
          ),
      ];
      final navigation = ShellNavigation();
      addTearDown(() {
        controller.dispose();
        navigation.dispose();
      });
      await _openPlanner(tester, controller, navigation);
      await tester.tap(find.text('Plan'));
      await tester.pumpAndSettle();
      expect(find.byType(LabSelectionField), findsOneWidget);
      await tester.tap(find.text('Existing catalog prices').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab B').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(controller.draftLabPlan!.plan.labName, isNull);
    },
  );

  testWidgets(
    'manual lab prices accept decimal commas and keep the catalog price intact',
    (tester) async {
      final controller = _seededController(draft: _generation(approved: true));
      addTearDown(controller.dispose);
      await tester.runAsync(() async {
        await controller.repository.saveProfile(controller.activeProfile!);
        await controller.repository.saveBiomarker(controller.biomarkers.single);
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: const MaterialApp(
            locale: Locale('en'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: LabPriceScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add laboratory'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Laboratory name'),
        'Lab B',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add laboratory'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('price-m:glucose')),
        '12,50',
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Save 1 prices'));
        for (var i = 0; i < 200 && controller.labPrices.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(controller.labPrices.single.priceEur, 12.5);
      expect(controller.labPrices.single.labName, 'Lab B');
      final savedBiomarkers = await tester.runAsync(
        controller.repository.biomarkers,
      );
      expect(
        savedBiomarkers!.singleWhere((item) => item.id == 'glucose').priceEur,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'price search includes synonyms and a missing-price filter stays scoped to the selected laboratory',
    (tester) async {
      final controller = _seededController(draft: _generation(approved: true));
      addTearDown(controller.dispose);
      controller.biomarkers = [
        Biomarker.fromMap({
          ...controller.biomarkers.single.toMap(),
          'synonyms_json': '["Blood sugar"]',
        }),
        Biomarker(
          id: 'ferritin',
          canonicalName: 'Ferritin',
          displayName: 'Ferritin',
          createdAt: _now,
          updatedAt: _now,
        ),
        Biomarker(
          id: 'derived',
          canonicalName: 'Derived',
          displayName: 'Derived',
          isCalculated: true,
          createdAt: _now,
          updatedAt: _now,
        ),
      ];
      controller.labPrices = [
        LabPrice(
          id: 'offer-a',
          labName: 'Lab A',
          biomarkerId: 'glucose',
          priceEur: 10,
          createdAt: _now,
          updatedAt: _now,
        ),
        LabPrice(
          id: 'offer-b',
          labName: 'Lab B',
          biomarkerId: 'ferritin',
          priceEur: 20,
          createdAt: _now,
          updatedAt: _now,
        ),
      ];
      await _openPrices(tester, controller);
      expect(find.text('1 of 2 tests priced · 1 missing'), findsOneWidget);
      await tester.tap(find.text('Missing prices'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-m:ferritin')), findsOneWidget);
      expect(find.byKey(const ValueKey('price-m:glucose')), findsNothing);
      await tester.tap(find.text('Missing prices'));
      await tester.enterText(
        find.widgetWithText(TextField, 'Search tests or packages'),
        'blood sugar',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('price-m:glucose')), findsOneWidget);
      expect(find.byKey(const ValueKey('price-m:ferritin')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'prices edited across search filters save in one batch with their source and package membership intact',
    (tester) async {
      final controller = _seededController(draft: _generation(approved: true));
      addTearDown(controller.dispose);
      final ferritin = Biomarker(
        id: 'ferritin',
        canonicalName: 'Ferritin',
        displayName: 'Ferritin',
        createdAt: _now,
        updatedAt: _now,
      );
      final package = BiomarkerPackage(
        id: 'bundle',
        name: 'Bundle',
        createdAt: _now,
        updatedAt: _now,
      );
      await tester.runAsync(() async {
        await controller.repository.saveProfile(controller.activeProfile!);
        await controller.repository.saveBiomarker(controller.biomarkers.single);
        await controller.repository.saveBiomarker(ferritin);
        await controller.repository.saveBiomarkerPackage(package, {
          'glucose',
          'ferritin',
        });
        await controller.repository.saveLabPrices([
          LabPrice(
            id: 'offer',
            labName: 'Lab A',
            biomarkerId: 'glucose',
            priceEur: 10,
            sourceUrl: 'https://example.com/prices',
            quote: 'Glucose 10 EUR',
            createdAt: _now,
            updatedAt: _now,
          ),
        ]);
        await controller.refreshActiveData();
      });
      await _openPrices(tester, controller);
      final search = find.widgetWithText(TextField, 'Search tests or packages');
      await tester.enterText(search, 'glucose');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('price-m:glucose')),
        '12,50',
      );
      await tester.pumpAndSettle();
      await tester.enterText(search, 'ferritin');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('price-m:ferritin')),
        '19,75',
      );
      await tester.pumpAndSettle();
      await tester.enterText(search, 'bundle');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('price-p:bundle')),
        '25,00',
      );
      await tester.pumpAndSettle();
      expect(find.text('Save 3 prices'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save 3 prices'));
        for (var i = 0; i < 200 && controller.labPrices.length < 3; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      final pricing = controller.pricesForLab('Lab A');
      expect(pricing.priceFor('glucose')!.priceEur, 12.5);
      expect(
        pricing.priceFor('glucose')!.sourceUrl,
        'https://example.com/prices',
      );
      expect(pricing.priceFor('glucose')!.quote, isEmpty);
      expect(pricing.priceFor('ferritin')!.priceEur, 19.75);
      expect(pricing.priceFor('bundle', isPackage: true)!.priceEur, 25);
      expect(controller.biomarkerPackageMembers['bundle'], {
        'glucose',
        'ferritin',
      });
      expect(find.text('Save 3 prices'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invalid price input cannot partially save a batch and can be corrected',
    (tester) async {
      final controller = _seededController(draft: _generation(approved: true));
      addTearDown(controller.dispose);
      controller.labPrices = [
        LabPrice(
          id: 'offer',
          labName: 'Lab A',
          biomarkerId: 'glucose',
          priceEur: 10,
          createdAt: _now,
          updatedAt: _now,
        ),
      ];
      controller.biomarkers = [
        ...controller.biomarkers,
        Biomarker(
          id: 'ferritin',
          canonicalName: 'Ferritin',
          displayName: 'Ferritin',
          createdAt: _now,
          updatedAt: _now,
        ),
      ];
      await _openPrices(tester, controller);
      final search = find.widgetWithText(TextField, 'Search tests or packages');
      await tester.enterText(search, 'ferritin');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('price-m:ferritin')),
        '20,50',
      );
      await tester.pumpAndSettle();
      await tester.enterText(search, 'glucose');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('price-m:glucose')),
        '0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save 2 prices'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid price'), findsOneWidget);
      expect(controller.labPrices.single.priceEur, 10);
      await tester.enterText(
        find.byKey(const ValueKey('price-m:glucose')),
        '10,00',
      );
      await tester.pumpAndSettle();
      await tester.pumpAndSettle();
      expect(find.text('Save 1 prices'), findsOneWidget);
      expect(controller.labPrices, hasLength(1));
      expect(find.text('Invalid price'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancelling a lab switch preserves the selected lab and its unsaved field',
    (tester) async {
      final controller = _seededController(draft: _generation(approved: true));
      addTearDown(controller.dispose);
      controller.labPrices = [
        for (final lab in ['Lab A', 'Lab B'])
          LabPrice(
            id: lab,
            labName: lab,
            biomarkerId: 'glucose',
            priceEur: lab == 'Lab A' ? 10 : 20,
            createdAt: _now,
            updatedAt: _now,
          ),
      ];
      await _openPrices(tester, controller);
      await tester.enterText(
        find.byKey(const ValueKey('price-m:glucose')),
        '12',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab A').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab B').last);
      await tester.pumpAndSettle();
      expect(find.text('Discard price changes?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Lab A'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('price-m:glucose')))
            .controller!
            .text,
        '12',
      );
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lab B').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('price-m:glucose')))
            .controller!
            .text,
        '20.00',
      );
      expect(find.text('Save 1 prices'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving price entry asks before discarding a pending price', (
    tester,
  ) async {
    final controller = _seededController(draft: _generation(approved: true));
    addTearDown(controller.dispose);
    controller.labPrices = [
      LabPrice(
        id: 'offer',
        labName: 'Lab A',
        biomarkerId: 'glucose',
        priceEur: 10,
        createdAt: _now,
        updatedAt: _now,
      ),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          locale: Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(body: Text('Back target')),
        ),
      ),
    );
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const LabPriceScreen()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('price-m:glucose')), '12');
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard price changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Save 1 prices'), findsOneWidget);
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Back target'), findsOneWidget);
    expect(find.byType(LabPriceScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'German price entry remains scrollable with the phone keyboard open and larger text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      final controller = _seededController(draft: _generation(approved: true));
      addTearDown(controller.dispose);
      controller.labPrices = [
        LabPrice(
          id: 'offer',
          labName: 'Lab A',
          biomarkerId: 'glucose',
          priceEur: 10,
          checkedAt: _now,
          createdAt: _now,
          updatedAt: _now,
        ),
      ];
      await _openPrices(tester, controller, locale: const Locale('de'));
      expect(find.text('Laborpreise pflegen'), findsOneWidget);
      final field = find.byKey(const ValueKey('price-m:glucose'));
      await tester.ensureVisible(field);
      await tester.enterText(field, '12,50');
      tester.view.viewInsets = const FakeViewPadding(bottom: 310);
      await tester.pumpAndSettle();
      await tester.ensureVisible(field);
      expect(find.text('1 Preise speichern'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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

Future<void> _openPrices(
  WidgetTester tester,
  AppController controller, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const LabPriceScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
