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
import 'package:super_health/domain/units.dart';
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
      expect(find.text('Ingredient history'), findsOneWidget);
      await tester.tap(find.text('Starting now'));
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

  for (final language in ['en', 'de']) {
    testWidgets(
      'cancelling the history choice keeps the ingredient draft in $language',
      (tester) async {
        final controller = _seeded();
        addTearDown(controller.dispose);
        await _open(tester, controller, language: language);
        final amount = _field(language == 'de' ? 'Menge' : 'Amount');
        await tester.ensureVisible(amount);
        await tester.pumpAndSettle();
        await tester.enterText(amount, '1000');
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            language == 'de' ? 'Speichern' : 'Save',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'de' ? 'Ab jetzt' : 'Starting now'),
          findsOneWidget,
        );
        expect(
          find.text(
            language == 'de'
                ? 'Auch Verlauf korrigieren'
                : 'Correct history too',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(language == 'de' ? 'Abbrechen' : 'Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(IngredientEditor), findsOneWidget);
        expect(tester.widget<TextField>(amount).controller!.text, '1000');
        expect(controller.supplements.single.ingredients.single['amount'], 100);
        await tester.tap(
          find.byTooltip(language == 'de' ? 'Abbrechen' : 'Cancel'),
        );
        await tester.pumpAndSettle();
      },
    );
  }

  for (final correctHistory in [false, true]) {
    testWidgets(
      'saving a changed ingredient applies the reviewed history choice: $correctHistory',
      (tester) async {
        final controller = _seeded();
        addTearDown(() async {
          controller.dispose();
          await controller.database.close();
        });
        await tester.runAsync(() async {
          await controller.repository.saveProfile(_profile);
          await controller.repository.saveSupplement(_product);
          await controller.repository.saveIntake(_pastIntake());
        });
        await _open(tester, controller, size: const Size(1000, 1000), scale: 1);
        await tester.enterText(_field('Amount'), '250');
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        expect(controller.supplements.single.ingredients.single['amount'], 100);
        await tester.tap(
          find.text(correctHistory ? 'Correct history too' : 'Starting now'),
        );
        await tester.pumpAndSettle();
        await _drainWrites(tester);
        expect(controller.supplements.single.ingredients.single['amount'], 250);
        expect(
          controller.intakes.single.ingredientSnapshot.single['amount'],
          correctHistory ? 250 : 100,
        );
        final stored = (await tester.runAsync(
          () => controller.repository.intakes(_profile.id),
        ))!.single;
        expect(
          stored.ingredientSnapshot.single['amount'],
          correctHistory ? 250 : 100,
        );
        expect(stored.ingredientSnapshot.single['unit'], 'µg');
        expect(stored.ingredientSnapshotRecorded, isTrue);
        expect(stored.dose, 2);
        expect(stored.notes, 'Retain this');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the history action repairs an already-corrected product without another edit',
    (tester) async {
      final controller = _seeded();
      addTearDown(() async {
        controller.dispose();
        await controller.database.close();
      });
      await tester.runAsync(() async {
        await controller.repository.saveProfile(_profile);
        await controller.repository.saveSupplement(_product);
        await controller.repository.saveIntake(_pastIntake(amount: 101));
      });
      await _open(tester, controller, size: const Size(1000, 1000), scale: 1);
      await tester.tap(find.text('Correct ingredient history…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct history too'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Saving will also correct'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      await _drainWrites(tester);
      expect(
        controller.intakes.single.ingredientSnapshot.single['amount'],
        100,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('metadata edits do not ask for an ingredient history decision', (
    tester,
  ) async {
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
    await tester.enterText(_field('Brand'), 'Changed brand');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Ingredient history'), findsNothing);
    await _drainWrites(tester);
    expect(controller.supplements.single.brand, 'Changed brand');
    expect(tester.takeException(), isNull);
  });

  testWidgets('an older product counted in its form keeps that stock unit', (
    tester,
  ) async {
    final legacy = Supplement(
      id: 'glycine',
      name: 'Glycin',
      form: 'Powder',
      stockUnit: 'Powder',
      ingredients: const [
        {'name': 'Glycin', 'amount': 1, 'unit': 'g'},
      ],
      unitsPerContainer: 500,
      createdAt: _date,
      updatedAt: _date,
    );
    final controller = _seeded()..supplements = [legacy];
    addTearDown(() async {
      controller.dispose();
      await controller.database.close();
    });
    await tester.runAsync(() async {
      await controller.repository.saveProfile(_profile);
      await controller.repository.saveSupplement(legacy);
    });
    await _open(
      tester,
      controller,
      size: const Size(1000, 1200),
      scale: 1,
      existing: legacy,
    );
    final stored = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Powder').last,
    );
    expect(stored.selected, isTrue);
    expect(find.widgetWithText(ChoiceChip, 'g'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'scoop'), findsOneWidget);
    await tester.enterText(_field('Brand'), 'New brand');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    await _drainWrites(tester);
    final saved = controller.supplements.single;
    expect(saved.brand, 'New brand');
    expect(saved.form, 'Powder');
    expect(saved.stockUnit, 'Powder');
    expect(tester.takeException(), isNull);
  });

  for (final language in ['en', 'de']) {
    testWidgets('a new powder is dosed in grams by default in $language', (
      tester,
    ) async {
      final de = language == 'de';
      final controller = _seeded()..supplements = [];
      addTearDown(() async {
        controller.dispose();
        await controller.database.close();
      });
      await tester.runAsync(() => controller.repository.saveProfile(_profile));
      await _open(
        tester,
        controller,
        language: language,
        size: const Size(1000, 1400),
        scale: 1,
        create: true,
      );
      expect(find.text(de ? 'Dosiert in' : 'Dosed in'), findsNothing);
      await tester.tap(
        find.widgetWithText(ChoiceChip, de ? 'Pulver' : 'Powder'),
      );
      await tester.pumpAndSettle();
      expect(find.text(de ? 'Dosiert in' : 'Dosed in'), findsOneWidget);
      final grams = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'g'),
      );
      expect(grams.selected, isTrue);
      expect(
        find.widgetWithText(ChoiceChip, de ? 'Messlöffel' : 'scoop'),
        findsOneWidget,
      );
      expect(
        find.text(de ? 'Mengen je 1 g.' : 'Amounts per 1 g.'),
        findsOneWidget,
      );
      await tester.enterText(
        _field(de ? 'Produktname *' : 'Product name *'),
        'Glycin',
      );
      await tester.enterText(
        _field(de ? 'Inhalt pro Packung' : 'Contents per pack'),
        '500',
      );
      await tester.tap(
        find.widgetWithText(FilledButton, de ? 'Hinzufügen' : 'Add'),
      );
      await tester.pumpAndSettle();
      await _drainWrites(tester);
      final saved = controller.supplements.single;
      expect(saved.form, de ? 'Pulver' : 'Powder');
      expect(saved.stockUnit, 'g');
      expect(saved.unitsPerContainer, 500);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a capsule form needs no separate unit choice', (tester) async {
    final controller = _seeded()..supplements = [];
    addTearDown(controller.dispose);
    await _open(
      tester,
      controller,
      size: const Size(1000, 1400),
      scale: 1,
      create: true,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Softgel'));
    await tester.pumpAndSettle();
    expect(find.text('Dosed in'), findsNothing);
    expect(find.text('Dosed and counted in capsule.'), findsOneWidget);
    expect(find.text('Amounts per 1 capsule.'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Other'));
    await tester.pumpAndSettle();
    expect(_field('Dosed in'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('ingredient units leave out counts unless a row already uses one', () {
    final plain = ingredientUnitChoices();
    expect(plain.map((unit) => unit.symbol), containsAll(['µg', 'mg', 'IU']));
    expect(plain.where((unit) => unit.domain == UnitDomain.count), isEmpty);
    expect(
      ingredientUnitChoices(
        current: 'Kapsel',
      ).where((unit) => unit.domain == UnitDomain.count),
      [CanonicalUnit.capsule],
    );
  });

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
  Future<void> openStock(
    WidgetTester tester,
    AppController controller,
    Supplement supplement,
    String language,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 840);
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
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showAdjustStockDialog(context, controller, supplement),
              child: const Text('Open stock'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open stock'));
    await tester.pumpAndSettle();
  }

  // The dialogs below are left open on purpose: they dispose their text
  // controllers as soon as they pop, before the close animation finishes.
  for (final language in ['en', 'de']) {
    testWidgets(
      'adjust stock adds whole packs on top of the stock by default in $language',
      (tester) async {
        final controller = _seeded()..stockLevels = {_product.id: 30};
        addTearDown(controller.dispose);
        await openStock(tester, controller, _product, language);
        final de = language == 'de';
        final packs = _field(de ? 'Packungen hinzufügen' : 'Packs to add');
        expect(packs, findsOneWidget);
        await tester.enterText(packs, '2');
        await tester.pumpAndSettle();
        expect(find.textContaining('= 200 '), findsOneWidget);
        expect(
          find.textContaining(de ? 'danach 230 ' : 'afterwards 230 '),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a missing pack size can be entered in the stock dialog in $language',
      (tester) async {
        final loose = Supplement(
          id: 'protein',
          name: 'Protein',
          stockUnit: 'g',
          createdAt: _date,
          updatedAt: _date,
        );
        final controller = _seeded()
          ..supplements = [loose]
          ..stockLevels = {loose.id: 300};
        addTearDown(controller.dispose);
        await openStock(tester, controller, loose, language);
        final de = language == 'de';
        final size = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              (widget.decoration?.labelText ?? '').startsWith(
                de ? 'Inhalt pro Packung' : 'Contents per pack',
              ),
        );
        expect(size, findsNothing);
        await tester.tap(find.text(de ? 'Packungen' : 'Packs'));
        await tester.pumpAndSettle();
        expect(size, findsOneWidget);
        await tester.enterText(size, '300');
        await tester.enterText(
          _field(de ? 'Packungen hinzufügen' : 'Packs to add'),
          '2',
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('= 600 '), findsOneWidget);
        expect(
          find.textContaining(de ? 'danach 900 ' : 'afterwards 900 '),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a pack size from the stock dialog is stored on the supplement', (
    tester,
  ) async {
    final controller = _seeded();
    addTearDown(() async {
      controller.dispose();
      await controller.database.close();
    });
    final loose = Supplement(
      id: 'protein',
      name: 'Protein',
      brand: 'Example',
      stockUnit: 'g',
      priceEur: 20,
      createdAt: _date,
      updatedAt: _date,
    );
    final stored = (await tester.runAsync(() async {
      await controller.repository.saveProfile(_profile);
      await controller.repository.saveSupplement(loose);
      controller.supplements = [loose];
      await controller.setUnitsPerContainer(loose, 300);
      await controller.adjustStock(
        supplement: loose,
        quantityUnits: stockAdjustmentDelta(
          direction: 'add',
          amount: 2,
          current: 0,
          mode: StockQuantityMode.packages,
          unitsPerContainer: 300,
        ),
        reason: 'correction',
      );
      return (
        await controller.repository.supplements(_profile.id),
        await controller.repository.stockLevels(),
      );
    }))!;
    final (supplements, levels) = stored;
    final saved = supplements.singleWhere((item) => item.id == loose.id);
    expect(saved.unitsPerContainer, 300);
    expect(saved.brand, 'Example');
    expect(saved.priceEur, 20);
    expect(saved.stockUnit, 'g');
    expect(levels[loose.id], 600);
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
  Supplement? existing,
  bool create = false,
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
              existing: create ? null : existing ?? _product,
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

SupplementIntake _pastIntake({num? amount}) => SupplementIntake(
  id: 'past',
  profileId: _profile.id,
  supplementId: _product.id,
  takenAt: _date,
  dose: 2,
  unit: 'capsule',
  notes: 'Retain this',
  ingredientSnapshot: amount == null
      ? const []
      : [
          {'name': 'B12', 'amount': amount, 'unit': 'µg'},
        ],
  createdAt: _date,
  updatedAt: _date,
);

Future<void> _drainWrites(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}
