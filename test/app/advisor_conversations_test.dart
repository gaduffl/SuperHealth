import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new conversation exists only once it has been spoken in', () async {
    // Nothing is written when the button is pressed, so backing out of a fresh
    // conversation leaves no empty entry for anyone to tidy up.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('First question.');

    final firstId = fixture.controller.activeConversationId;
    expect(fixture.controller.advisorConversations, hasLength(1));

    fixture.controller.startNewAdvisorConversation();

    expect(fixture.controller.activeConversationId, isNot(firstId));
    expect(fixture.controller.advisorMessages, isEmpty);
    expect(fixture.controller.advisorConversations, hasLength(1));

    await fixture.controller.askAdvisor('Second question.');

    expect(fixture.controller.advisorConversations, hasLength(2));
  });

  test('the question in flight is visible while it is answered', () async {
    // Nothing is stored until the answer arrives, which is what keeps a failed
    // turn out of the history — but it also meant the question vanished the
    // moment it was sent: gone from the input box, absent from the thread, and
    // in a new conversation the welcome screen still showing.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final seen = <String?>[];
    fixture.controller.addListener(
      () => seen.add(fixture.controller.pendingAdvisorQuestion),
    );

    await fixture.controller.askAdvisor('  What about my ferritin?  ');

    // Trimmed, so the bubble matches the message that replaces it.
    expect(seen, contains('What about my ferritin?'));
    // And gone once the stored message takes over, or the bubble would double.
    expect(fixture.controller.pendingAdvisorQuestion, isNull);
    expect(fixture.controller.advisorMessages, hasLength(2));
  });

  test('a failed question is not left hanging in the thread', () async {
    // The screen puts the text back in the input box on failure, so a bubble
    // left behind would be a question the user is looking at in two places.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.client.failNext = true;

    await expectLater(
      fixture.controller.askAdvisor('Doomed.'),
      throwsA(isA<Object>()),
    );

    expect(fixture.controller.pendingAdvisorQuestion, isNull);
    expect(fixture.controller.advisorMessages, isEmpty);
  });

  test('a fresh conversation does not carry the previous one', () async {
    // The whole point of starting one: the model must not answer the new
    // question in the light of the old thread.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('About my ferritin.');
    fixture.controller.startNewAdvisorConversation();

    await fixture.controller.askAdvisor('Unrelated question.');

    expect(fixture.client.requests.last.history, isEmpty);
    expect(fixture.controller.advisorMessages, hasLength(2));
  });

  test('pressing new twice in a row is not two conversations', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('A question.');

    fixture.controller.startNewAdvisorConversation();
    final first = fixture.controller.activeConversationId;
    fixture.controller.startNewAdvisorConversation();

    // The second press would hand out a different id for an identical empty
    // screen, which reads as losing what was just started.
    expect(fixture.controller.activeConversationId, first);
  });

  test('a past conversation reopens with its own messages', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('The first thread.');
    final first = fixture.controller.activeConversationId;
    fixture.controller.startNewAdvisorConversation();
    await fixture.controller.askAdvisor('The second thread.');

    await fixture.controller.openAdvisorConversation(first);

    expect(fixture.controller.activeConversationId, first);
    expect(
      fixture.controller.advisorMessages.first.content,
      'The first thread.',
    );

    // And a question asked now continues that thread rather than the newer one.
    await fixture.controller.askAdvisor('A follow-up.');
    expect(fixture.controller.advisorMessages, hasLength(4));
    expect(fixture.client.requests.last.history, hasLength(2));
  });

  test('the list is titled by first question, newest first', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('Older thread.');
    fixture.controller.startNewAdvisorConversation();
    await fixture.controller.askAdvisor('Newer thread.');

    final conversations = fixture.controller.advisorConversations;
    expect(conversations.map((item) => item.title), [
      'Newer thread.',
      'Older thread.',
    ]);
    expect(conversations.first.messageCount, 2);
  });

  test('deleting the open conversation lands on a real one', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('Keep me.');
    final kept = fixture.controller.activeConversationId;
    fixture.controller.startNewAdvisorConversation();
    await fixture.controller.askAdvisor('Delete me.');
    final doomed = fixture.controller.activeConversationId;

    await fixture.controller.deleteAdvisorConversation(doomed);

    // The screen cannot be left pointing at something that no longer exists.
    expect(fixture.controller.activeConversationId, kept);
    expect(fixture.controller.advisorMessages.first.content, 'Keep me.');
    expect(fixture.controller.advisorConversations, hasLength(1));
  });

  test('deleting the last conversation leaves an empty new one', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('The only one.');

    await fixture.controller.deleteAdvisorConversation(
      fixture.controller.activeConversationId,
    );

    expect(fixture.controller.advisorConversations, isEmpty);
    expect(fixture.controller.advisorMessages, isEmpty);
    // A usable id, not the one just emptied: asking again must not resurrect
    // the deleted thread's name.
    expect(fixture.controller.activeConversationId, isNotEmpty);
  });

  test('a deleted conversation is gone from the ledger too', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('Delete me.');
    final doomed = fixture.controller.activeConversationId;

    await fixture.controller.deleteAdvisorConversation(doomed);

    expect(
      await fixture.repository.messages(fixture.profile.id, doomed),
      isEmpty,
    );
    expect(
      await fixture.repository.advisorConversations(fixture.profile.id),
      isEmpty,
    );
  });

  test('a reload lands on the most recent conversation', () async {
    // Nothing persists the active id: the newest conversation *is* where the
    // user left off, so it needs no separate record to be kept honest.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.controller.askAdvisor('Older.');
    fixture.controller.startNewAdvisorConversation();
    await fixture.controller.askAdvisor('Newest.');
    final newest = fixture.controller.activeConversationId;

    // What an app restart looks like: the field is in memory only, so it
    // comes back unresolved rather than pointing anywhere.
    fixture.controller.forgetActiveConversationForTest();
    await fixture.controller.refreshActiveData();

    expect(fixture.controller.activeConversationId, newest);
    expect(fixture.controller.advisorMessages.first.content, 'Newest.');
  });

  test('an install that only ever had "primary" keeps it', () async {
    // Every conversation before this feature was called `primary`. It has to
    // show up as an ordinary conversation, not disappear.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    await fixture.controller.askAdvisor('The old thread.');

    expect(
      fixture.controller.activeConversationId,
      AppController.defaultConversationId,
    );
    expect(
      fixture.controller.advisorConversations.single.id,
      AppController.defaultConversationId,
    );
  });
}

class _Fixture {
  _Fixture({
    required this.database,
    required this.repository,
    required this.profile,
    required this.controller,
    required this.client,
  });

  final AppDatabase database;
  final HealthRepository repository;
  final Profile profile;
  final AppController controller;
  final _Client client;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final snapshot = SnapshotService(database, repository);
    final oneDrive = OneDriveService(snapshot);
    final keyStore = _KeyStore();
    final clientFactory = AiProviderClientFactory();
    final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
    final client = _Client();
    final profile = await repository.createProfile(displayName: 'Alex');
    final controller = AppController(
      database: database,
      repository: repository,
      keyStore: keyStore,
      aiSettingsStore: AiSettingsStore(),
      advisorService: AdvisorService(
        repository: repository,
        keyStore: keyStore,
        clientFactory: _Factory(client),
        contextBuilder: HealthContextBuilder(
          repository,
          scope: HealthContextScope.advisory,
        ),
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
    );
    controller
      ..profiles = [profile]
      ..activeProfile = profile
      ..advisorSettings = const AiTaskSettings(
        provider: AiProvider.openai,
        model: 'gpt-5.6',
      );
    await controller.refreshActiveData();
    return _Fixture(
      database: database,
      repository: repository,
      profile: profile,
      controller: controller,
      client: client,
    );
  }

  Future<void> dispose() async {
    controller.dispose();
    await database.close();
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

class _Client implements AiProviderClient {
  final List<ProviderRequest> requests = [];
  bool failNext = false;

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
  }) async {
    requests.add(request);
    if (failNext) throw StateError('provider unavailable');
    final package = jsonDecode(request.contextJson) as Map<String, Object?>;
    final manifest = package['manifest']! as Map<String, Object?>;
    final sections = manifest['sections']! as Map<String, Object?>;
    final receipt = {
      'sha256': manifest['context_sha256'],
      'file_sha256': sha256
          .convert(utf8.encode(request.contextJson))
          .toString(),
      'record_count': manifest['record_count'],
      'reviewed_sections': sections.keys.toList(),
    };
    return ProviderResponse(
      text:
          '<context_coverage>${jsonEncode(receipt)}</context_coverage>\nAnswer.',
      raw: const {},
    );
  }
}
