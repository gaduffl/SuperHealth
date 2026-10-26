import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:super_health/app/app_localizations.dart';
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

  for (final language in ['en', 'de']) {
    testWidgets('inactive profile details stay hidden in $language', (
      tester,
    ) async {
      final controller = _controller()
        ..profiles = [_alice, _ben]
        ..activeProfile = _alice;
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      try {
        await _pumpSettings(tester, controller, Locale(language));

        expect(find.text('Alice'), findsOneWidget);
        expect(find.text('Ben'), findsOneWidget);
        final aliceRow = find.widgetWithText(ListTile, 'Alice');
        final benRow = find.widgetWithText(ListTile, 'Ben');
        expect(tester.widget<ListTile>(benRow).subtitle, isNull);
        expect(find.textContaining('62.0 kg'), findsOneWidget);
        expect(find.textContaining('170.0 cm'), findsOneWidget);
        expect(find.textContaining('79.3 kg'), findsNothing);
        expect(find.textContaining('181.0 cm'), findsNothing);
        expect(
          find.textContaining(
            language == 'de' ? 'Alter ${_ben.age}' : 'Age ${_ben.age}',
          ),
          findsNothing,
        );
        expect(
          find.textContaining(language == 'de' ? 'Männlich' : 'Male'),
          findsNothing,
        );
        final inactiveLabel = tester.getSemantics(benRow).label;
        expect(inactiveLabel, contains('Ben'));
        for (final detail in [
          '79.3',
          '181.0',
          '${_ben.age}',
          'Male',
          'Männlich',
        ]) {
          expect(inactiveLabel, isNot(contains(detail)));
        }
        expect(tester.getSemantics(aliceRow).label, contains('62.0 kg'));

        controller
          ..activeProfile = _ben
          ..notifyListeners();
        await tester.pumpAndSettle();

        expect(tester.widget<ListTile>(aliceRow).subtitle, isNull);
        expect(find.textContaining('62.0 kg'), findsNothing);
        expect(find.textContaining('170.0 cm'), findsNothing);
        expect(find.textContaining('79.3 kg'), findsOneWidget);
        expect(find.textContaining('181.0 cm'), findsOneWidget);
        expect(tester.getSemantics(aliceRow).label, isNot(contains('62.0')));
        expect(tester.getSemantics(benRow).label, contains('79.3 kg'));
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('no personal details appear before a profile is selected', (
    tester,
  ) async {
    final controller = _controller()..profiles = [_alice, _ben];
    addTearDown(controller.dispose);
    await _pumpSettings(tester, controller, const Locale('en'));

    for (final name in ['Alice', 'Ben']) {
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, name)).subtitle,
        isNull,
      );
    }
    expect(find.textContaining('62.0 kg'), findsNothing);
    expect(find.textContaining('79.3 kg'), findsNothing);
  });

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

Future<void> _pumpSettings(
  WidgetTester tester,
  AppController controller,
  Locale locale,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 2200);
  addTearDown(tester.view.reset);
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
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _profileDate = DateTime(2020);
final _alice = Profile(
  id: 'alice',
  displayName: 'Alice',
  dateOfBirth: DateTime(1990, 7, 18),
  sex: 'female',
  heightCm: 170,
  weightKg: 62,
  createdAt: _profileDate,
  updatedAt: _profileDate,
);
final _ben = Profile(
  id: 'ben',
  displayName: 'Ben',
  dateOfBirth: DateTime(1984, 2, 10),
  sex: 'male',
  heightCm: 181,
  weightKg: 79.3,
  createdAt: _profileDate,
  updatedAt: _profileDate,
);

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
