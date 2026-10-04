import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:super_health/app/long_task_guard.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

const _notice = LongTaskNotice(title: 'Planning', text: 'A few minutes');

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'a second lab plan cannot start while one is running, and the claim is released when it ends',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final first = fixture.controller.generateLabPlan(notice: _notice);
      // Claimed before the first await: the screen shows the run at once, and
      // a second tap in the same frame already finds it taken.
      expect(fixture.controller.labPlanStage, isNotNull);
      expect(fixture.controller.labPlanStartedAt, isNotNull);

      await expectLater(
        fixture.controller.generateLabPlan(notice: _notice),
        throwsA(isA<StateError>()),
      );
      await fixture.client.called.future;
      expect(fixture.client.calls, 1);

      fixture.client.answer.completeError(StateError('connection dropped'));
      await expectLater(first, throwsA(isA<StateError>()));

      expect(fixture.controller.labPlanStage, isNull);
      expect(fixture.controller.labPlanStartedAt, isNull);
      expect(fixture.controller.busy, isFalse);
      expect(fixture.guard.isHolding, isFalse);
    },
  );

  test(
    'another operation finishing during a lab plan leaves the app busy until the plan ends',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final plan = fixture.controller.generateLabPlan(notice: _notice);
      await fixture.client.called.future;
      expect(fixture.controller.busy, isTrue);

      // A flag cleared by whichever operation ended first: an automatic sync
      // finishing mid-plan re-enabled "Plan" and told auto-update that nothing
      // was running.
      await fixture.controller.analyzeCorrelations();
      expect(fixture.controller.busy, isTrue);
      expect(fixture.controller.workInFlight, isTrue);

      fixture.client.answer.completeError(StateError('connection dropped'));
      await expectLater(plan, throwsA(isA<StateError>()));
      expect(fixture.controller.busy, isFalse);
    },
  );
}

/// Answers the first call only when the test says so, which is what holds a
/// generation open long enough to act on the controller while it runs.
class _HeldClient implements AiProviderClient {
  final Completer<void> called = Completer<void>();
  final Completer<ProviderResponse> answer = Completer<ProviderResponse>();
  int calls = 0;

  @override
  AiProvider get provider => AiProvider.openai;

  @override
  Future<List<AiModelInfo>> listModels(String apiKey) async => const [];

  @override
  Future<int?> countContextTokens(
    String apiKey, {
    required String model,
    required String contextJson,
  }) async => null;

  @override
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
    AgentToolHandler? onToolCalls,
  }) {
    calls++;
    if (!called.isCompleted) called.complete();
    return answer.future;
  }
}

class _KeyStore extends ApiKeyStore {
  @override
  Future<String?> read(AiProvider provider) async => 'test-key';
}

class _Factory extends AiProviderClientFactory {
  _Factory(this.client) : super(dio: Dio());

  final AiProviderClient client;

  @override
  AiProviderClient create(AiProvider provider) => client;
}

class _TestOneDriveService extends OneDriveService {
  _TestOneDriveService(super.snapshotService);

  @override
  Future<bool> isSignedIn() async => false;
}

class _Fixture {
  _Fixture(this.database, this.controller, this.client, this.guard);

  final AppDatabase database;
  final AppController controller;
  final _HeldClient client;
  final LongTaskGuard guard;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Alice');
    final now = DateTime.now();
    await repository.saveBiomarker(
      Biomarker(
        id: 'bio-1',
        canonicalName: 'apob',
        displayName: 'ApoB',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final keyStore = _KeyStore();
    final client = _HeldClient();
    final clientFactory = _Factory(client);
    final contextBuilder = HealthContextBuilder(repository);
    final oneDrive = _TestOneDriveService(
      SnapshotService(database, repository),
    );
    final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
    final guard = LongTaskGuard(
      startService: (_) async => true,
      stopService: () async {},
      holdScreenAwake: (_) async {},
    );
    final controller =
        AppController(
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
            longTaskGuard: guard,
          )
          ..activeProfile = profile
          ..labPlannerSettings = const AiTaskSettings(
            provider: AiProvider.openai,
            model: 'gpt-5.6',
          );
    return _Fixture(database, controller, client, guard);
  }

  Future<void> dispose() async => (await database.database).close();
}
