import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
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
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/ui/lab_report_screen.dart';
import 'package:super_health/ui/labs_screen.dart';
import 'package:super_health/ui/lab_self_paid_selection.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    initializeDateFormatting('en');
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the report shows every result it produced, and no others', (
    tester,
  ) async {
    // The point of the page: one surprising value is judged against the rest
    // of the same extraction, so the whole report has to be on it — and only
    // that report, or the comparison is meaningless.
    final controller = _controller(
      measurements: [
        _reading(id: 'a', biomarkerId: 'glucose', value: 95, page: 1),
        _reading(id: 'b', biomarkerId: 'hba1c', value: 5.4, page: 2),
        _reading(
          id: 'c',
          biomarkerId: 'glucose',
          value: 88,
          documentId: 'other',
        ),
      ],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('Glucose'), findsOneWidget);
    expect(find.text('HbA1c'), findsOneWidget);
    expect(find.text('95.0 mg/dL'), findsOneWidget);
    expect(find.text('88.0 mg/dL'), findsNothing);
    expect(find.text('2 result(s)'), findsNothing);
    expect(find.textContaining('2 result(s)'), findsOneWidget);
  });

  testWidgets('a row carries its lab range, page, and confidence', (
    tester,
  ) async {
    final controller = _controller(
      measurements: [
        _reading(
          id: 'a',
          biomarkerId: 'glucose',
          value: 95,
          page: 3,
          labRefLow: 70,
          labRefHigh: 99,
          confidence: 0.92,
        ),
      ],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('Lab ref 70.0–99.0 · page 3 · parse 92%'), findsOneWidget);
  });

  testWidgets('a row with no lab range says so rather than showing a gap', (
    tester,
  ) async {
    final controller = _controller(
      measurements: [_reading(id: 'a', biomarkerId: 'glucose', value: 95)],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.textContaining('No lab range on the report'), findsOneWidget);
  });

  testWidgets('parser complaints travel with the report', (tester) async {
    // They were shown once during import and then only lived in the database.
    final controller = _controller(
      measurements: [_reading(id: 'a', biomarkerId: 'glucose', value: 95)],
      warnings: const ['Two rows shared one reference range'],
    );
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('Two rows shared one reference range'), findsOneWidget);
  });

  testWidgets('a report with no linked results explains the emptiness', (
    tester,
  ) async {
    final controller = _controller();
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('No results are linked to this report'), findsOneWidget);
  });

  testWidgets('saved report payment ticks persist individually and in bulk', (
    tester,
  ) async {
    final controller = _controller(
      measurements: [
        _reading(id: 'a', biomarkerId: 'glucose', value: 95),
        _reading(id: 'b', biomarkerId: 'hba1c', value: 5.4),
      ],
    );
    addTearDown(controller.dispose);
    await tester.runAsync(() async {
      await controller.repository.saveProfile(controller.activeProfile!);
      for (final marker in controller.biomarkers) {
        await controller.repository.saveBiomarker(marker);
      }
      await controller.repository.saveDocument(controller.documents.single);
      for (final row in controller.measurements) {
        await controller.repository.saveMeasurement(row);
      }
    });
    await _pump(tester, controller);
    expect(find.text('0 of 2 marked'), findsOneWidget);
    await tester.runAsync(
      () => tester.tap(find.byKey(const ValueKey('self-paid-a'))),
    );
    await _waitForSave(tester, controller);
    expect(find.text('1 of 2 marked'), findsOneWidget);
    final a = controller.measurements.singleWhere((row) => row.id == 'a');
    expect(a.isSelfPaid, isTrue);
    await tester.runAsync(() => tester.tap(find.text('Mark all IGeL')));
    await _waitForSave(tester, controller);
    expect(find.text('2 of 2 marked'), findsOneWidget);
    await tester.runAsync(() => tester.tap(find.text('Clear IGeL marks')));
    await _waitForSave(tester, controller);
    expect(find.text('0 of 2 marked'), findsOneWidget);
    expect(controller.measurements.every((row) => !row.isSelfPaid), isTrue);
  });

  testWidgets(
    'review ticks survive mapping and exclusion and discard writes nothing',
    (tester) async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await _pump(tester, controller);
      final report = ParsedLabReport(
        profileId: 'profile',
        fileName: 'review.pdf',
        pdfBytes: Uint8List(0),
        sha256: 'fixture-hash',
        provider: AiProvider.openai,
        model: 'fixture-model',
        reportDate: DateTime(2026, 1, 1),
        warnings: const [],
        errors: const [],
        measurements: const [
          ParsedMeasurementCandidate(
            biomarkerId: 'glucose',
            reportedName: 'Glucose',
            value: 95,
            unit: 'mg/dL',
            confidence: 0.9,
          ),
          ParsedMeasurementCandidate(
            biomarkerId: 'hba1c',
            reportedName: 'HbA1c',
            value: 5.4,
            unit: '%',
            confidence: 0.9,
          ),
        ],
      );
      final review = reviewParsedLabReport(
        tester.element(find.byType(LabReportScreen)),
        controller,
        report,
      );
      await tester.pumpAndSettle();
      expect(find.text('0 of 2 marked'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('self-paid-0')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 2 marked'), findsOneWidget);
      await tester.tap(find.text('Mark all IGeL'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 marked'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create temporary biomarker').last);
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 marked'), findsOneWidget);
      await tester.tap(find.byTooltip('Review and edit row').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 2 marked'), findsOneWidget);
      await tester.tap(find.byTooltip('Exclude row').first);
      await tester.pumpAndSettle();
      expect(find.text('1 of 1 marked'), findsOneWidget);
      await tester.tap(find.text('Clear IGeL marks'));
      await tester.pumpAndSettle();
      expect(find.text('0 of 1 marked'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await review;
      expect(report.measurements.every((row) => !row.isSelfPaid), isTrue);
      final stored = await tester.runAsync(
        () => controller.repository.reportedMeasurements('profile'),
      );
      expect(stored, isEmpty);
    },
  );

  testWidgets('German payment controls fit a phone screen', (tester) async {
    final controller = _controller(
      measurements: [_reading(id: 'a', biomarkerId: 'glucose', value: 95)],
    );
    addTearDown(controller.dispose);
    await _pump(
      tester,
      controller,
      locale: const Locale('de'),
      size: const Size(360, 1000),
    );
    expect(find.text('Selbst bezahlt (IGeL)'), findsWidgets);
    expect(find.text('Alle als IGeL markieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.byType(LabSelfPaidSelection), findsOneWidget);
  });

  testWidgets('a deleted report says so instead of rendering blank', (
    tester,
  ) async {
    final controller = _controller(documents: const []);
    addTearDown(controller.dispose);
    await _pump(tester, controller);

    expect(find.text('This report is no longer available'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  AppController controller, {
  Locale locale = const Locale('en'),
  Size size = const Size(900, 2400),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const LabReportScreen(documentId: 'doc'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Measurement _reading({
  required String id,
  required String biomarkerId,
  required double value,
  String documentId = 'doc',
  int? page,
  double? labRefLow,
  double? labRefHigh,
  double? confidence,
}) => Measurement(
  id: id,
  profileId: 'profile',
  biomarkerId: biomarkerId,
  takenAt: DateTime(2026, 1, 2),
  value: value,
  unit: 'mg/dL',
  documentId: documentId,
  page: page,
  labRefLow: labRefLow,
  labRefHigh: labRefHigh,
  extractionConfidence: confidence,
  createdAt: DateTime(2026, 1, 2),
  updatedAt: DateTime(2026, 1, 2),
);

Biomarker _marker(String id, String name) => Biomarker(
  id: id,
  canonicalName: id,
  displayName: name,
  defaultUnit: 'mg/dL',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

AppController _controller({
  List<Measurement> measurements = const [],
  List<String> warnings = const [],
  List<HealthDocument>? documents,
}) {
  final database = AppDatabase(
    factory: databaseFactoryFfi,
    databasePath: inMemoryDatabasePath,
  );
  final repository = HealthRepository(database);
  final snapshot = SnapshotService(database, repository);
  final oneDrive = OneDriveService(snapshot);
  final keyStore = ApiKeyStore();
  final clientFactory = AiProviderClientFactory();
  final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
  final now = DateTime(2026, 1, 1);
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex',
    createdAt: now,
    updatedAt: now,
  );
  return AppController(
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
    )
    ..profiles = [profile]
    ..activeProfile = profile
    ..biomarkers = [_marker('glucose', 'Glucose'), _marker('hba1c', 'HbA1c')]
    ..measurements = measurements
    ..documents =
        documents ??
        [
          HealthDocument(
            id: 'doc',
            profileId: 'profile',
            fileName: 'labor-2026-01.pdf',
            labName: 'Labor X',
            warnings: warnings,
            createdAt: now,
            updatedAt: now,
          ),
        ];
}

Future<void> _waitForSave(WidgetTester tester, AppController controller) async {
  await tester.runAsync(() async {
    while (controller.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pumpAndSettle();
}
