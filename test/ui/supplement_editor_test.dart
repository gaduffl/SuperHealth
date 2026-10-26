import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:super_health/ui/dialogs.dart';
import 'package:super_health/ui/ingredient_editor.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/app/app_theme.dart';
import 'package:super_health/app/appearance_settings.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final language in ['en', 'de']) {
    testWidgets(
      'the phone editor has readable fields and keyboard-safe actions in $language',
      (tester) async {
        final controller = _seeded();
        addTearDown(controller.dispose);
        await _open(tester, controller, language: language);
        final name = _field(language == 'de' ? 'Name' : 'Name');
        await tester.ensureVisible(name);
        await tester.pumpAndSettle();
        expect(tester.getSize(name).width, greaterThan(240));
        final amount = _field(language == 'de' ? 'Menge' : 'Amount');
        await tester.ensureVisible(amount);
        await tester.pumpAndSettle();
        expect(tester.getSize(amount).width, greaterThan(280));
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.enterText(amount, '250');
        await tester.pumpAndSettle();
        final save = find.widgetWithText(
          FilledButton,
          language == 'de' ? 'Speichern' : 'Save',
        );
        expect(tester.getCenter(save).dy, lessThan(100));
        expect(tester.takeException(), isNull);
        await tester.tap(
          find.byTooltip(language == 'de' ? 'Abbrechen' : 'Cancel'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(IngredientEditor), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invalid ingredient input stays open and keeps the other fields',
    (tester) async {
      final controller = _seeded();
      addTearDown(controller.dispose);
      await _open(tester, controller);
      final amount = _field('Amount');
      await tester.ensureVisible(amount);
      await tester.pumpAndSettle();
      await tester.enterText(amount, 'not a number');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.byType(IngredientEditor), findsOneWidget);
      expect(
        find.textContaining('Each ingredient needs a name'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(_field('Name')).controller!.text,
        'Vitamin B12',
      );
      expect(tester.widget<TextField>(amount).controller!.text, 'not a number');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'saving the editor persists reviewed ingredients and retains product metadata',
    (tester) async {
      final controller = _seeded();
      addTearDown(() async {
        controller.dispose();
        await controller.database.close();
      });
      await tester.runAsync(() async {
        await controller.repository.saveProfile(_profile);
        await controller.repository.saveSupplement(_product);
      });
      await _open(tester, controller, size: const Size(1000, 1000), scale: 1);
      await tester.enterText(_field('Amount'), '250');
      await tester.enterText(_field('Unit'), 'mcg');
      await tester.pumpAndSettle();
      if (find.text('µg').evaluate().isEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('µg').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      for (
        var attempt = 0;
        attempt < 100 &&
            controller.supplements.single.ingredients.single['amount'] != 250.0;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final stored = (await tester.runAsync(
        () => controller.repository.supplements(_profile.id),
      ))!.single;
      expect(stored.ingredients.single, {
        'name': 'Vitamin B12',
        'amount': 250.0,
        'unit': 'µg',
      });
      expect(stored.id, _product.id);
      expect(stored.brand, _product.brand);
      expect(stored.priceEur, _product.priceEur);
      expect(stored.lowStockAlerts, _product.lowStockAlerts);
      expect(stored.sourceId, _product.sourceId);
      expect(stored.createdAt, _product.createdAt);
    },
  );

  testWidgets('ingredient unit choices resolve microgram to the µg option', (
    tester,
  ) async {
    final rows = IngredientRows.from(const [
      {'name': 'B12', 'amount': 100, 'unit': 'microgram'},
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: IngredientEditor(rows: rows)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('µg').last);
    await tester.pumpAndSettle();
    expect(rows.parse()!.single['unit'], 'µg');
    await tester.pumpWidget(const SizedBox.shrink());
    rows.dispose();
  });
}

Finder _field(String label) => find.byWidgetPredicate((widget) {
  if (widget is! TextField) return false;
  final fieldLabel = widget.decoration?.label;
  return widget.decoration?.labelText == label ||
      (fieldLabel is Text && fieldLabel.data == label);
});

Future<void> _open(
  WidgetTester tester,
  AppController controller, {
  String language = 'en',
  Size size = const Size(390, 840),
  double scale = 1.4,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(
        brightness: Brightness.light,
        settings: const AppearanceSettings(),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showAddSupplementDialog(
              context,
              controller,
              existing: _product,
            ),
            child: const Text('Open editor'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

final _date = DateTime(2026, 5, 1);
final _profile = Profile(
  id: 'p',
  displayName: 'Example',
  createdAt: _date,
  updatedAt: _date,
);
final _product = Supplement(
  id: 'b12',
  name: 'B12',
  brand: 'Example',
  form: 'Capsule',
  stockUnit: 'capsule',
  ingredients: const [
    {'name': 'Vitamin B12', 'amount': 100, 'unit': 'microgram'},
  ],
  unitsPerContainer: 100,
  priceEur: 30.5,
  lowStockAlerts: false,
  sourceId: 'legacy-b12',
  createdAt: _date,
  updatedAt: _date,
);
AppController _seeded() => _controller()
  ..activeProfile = _profile
  ..profiles = [_profile]
  ..supplements = [_product];

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
