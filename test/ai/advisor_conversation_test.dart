import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/ai_trace.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a second turn replays the first as chat history', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    await fixture.ask('What about my ferritin?');
    await fixture.ask('And my B12?');

    // Two stored messages become one user turn plus one assistant turn; the
    // new question rides in `userPrompt`, not in the history.
    final second = fixture.client.requests.last;
    expect(second.history.map((turn) => turn.role), ['user', 'assistant']);
    expect(second.history.first.content, 'What about my ferritin?');
    expect(second.userPrompt, startsWith('And my B12?'));
    expect(await fixture.storedMessages(), hasLength(4));
  });

  test('the assistant turn replayed is the stripped one', () async {
    // The receipt is stripped before the answer is stored. If the raw text
    // went into history, every later turn would carry a second
    // `<context_coverage>` block and fail its own "exactly one" check.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);

    await fixture.ask('First.');
    await fixture.ask('Second.');

    final replayed = fixture.client.requests.last.history.last;
    expect(replayed.role, 'assistant');
    expect(replayed.content, isNot(contains('context_coverage')));
  });

  test('a failed turn leaves nothing behind in the conversation', () async {
    // The screen restores the question into the input box and reports the
    // error, so the user believes the turn never happened. Saving the question
    // before the model call made that false: it stayed in the database and
    // every later turn re-sent it.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    fixture.client.failNext = true;

    await expectLater(fixture.ask('Doomed question.'), throwsA(isA<Object>()));

    expect(await fixture.storedMessages(), isEmpty);

    fixture.client.failNext = false;
    await fixture.ask('A question that works.');

    final messages = await fixture.storedMessages();
    expect(messages.map((message) => message.content), [
      'A question that works.',
      'Answer.',
    ]);
    expect(fixture.client.requests.last.history, isEmpty);
  });

  test('an unanswered question already stored is never replayed', () async {
    // Conversations that collected these before the fix heal on the next turn
    // rather than needing a migration — and nothing the user might still want
    // to read is deleted to achieve it.
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final now = DateTime(2026, 1, 1);
    await fixture.repository.saveMessage(
      AdvisorMessage(
        id: 'orphan',
        profileId: fixture.profile.id,
        conversationId: 'primary',
        role: 'user',
        content: 'Never answered.',
        createdAt: now,
      ),
    );

    await fixture.ask('A real question.');

    expect(fixture.client.requests.single.history, isEmpty);
  });

  test('conversationHistory keeps pairs and drops danglers', () {
    AdvisorMessage message(String id, String role, String content) =>
        AdvisorMessage(
          id: id,
          profileId: 'p',
          conversationId: 'primary',
          role: role,
          content: content,
          createdAt: DateTime(2026, 1, 1),
        );

    final history = conversationHistory([
      message('1', 'user', 'answered'),
      message('2', 'assistant', 'answer'),
      message('3', 'user', 'failed'),
      message('4', 'user', 'retyped'),
      message('5', 'assistant', 'answer 2'),
      message('6', 'user', 'still running'),
    ]);

    expect(history.map((turn) => turn.content), [
      'answered',
      'answer',
      'retyped',
      'answer 2',
    ]);
  });

  test('the trace records what a turn cost and whether it cached', () async {
    // `cached_tokens` is the only way to tell whether the prompt cache key is
    // earning anything, and a chat re-sends the whole context every turn.
    final lines = <String>[];
    final fixture = await _Fixture.create(
      trace: AiTrace(write: (line) async => lines.add(line)),
    );
    addTearDown(fixture.dispose);

    await fixture.ask('What about my ferritin?');

    final events = [
      for (final line in lines)
        Map<String, Object?>.from(jsonDecode(line) as Map),
    ];
    final names = events.map((event) => event['event']).toList();
    expect(names.first, 'run_start');
    expect(names, contains('context_built'));
    expect(names, contains('history_loaded'));
    expect(names, contains('delivery_chosen'));
    expect(names, contains('response_received'));
    expect(names.last, 'run_end');

    final received = events.firstWhere(
      (event) => event['event'] == 'response_received',
    );
    expect('${(received['data']! as Map)['usage']}', contains('cached_tokens'));
    final ended = events.last['data']! as Map;
    expect(ended['success'], isTrue);
  });

  test('a failed turn is recorded as a failure, not as silence', () async {
    // A run with no `run_end` reads as "the app was killed". A turn that threw
    // is a different diagnosis and has to look different.
    final lines = <String>[];
    final fixture = await _Fixture.create(
      trace: AiTrace(write: (line) async => lines.add(line)),
    );
    addTearDown(fixture.dispose);
    fixture.client.failNext = true;

    await expectLater(fixture.ask('Doomed.'), throwsA(isA<Object>()));

    final events = [
      for (final line in lines)
        Map<String, Object?>.from(jsonDecode(line) as Map),
    ];
    expect(
      events.map((event) => event['event']),
      containsAllInOrder(['run_start', 'run_failed', 'run_end']),
    );
    expect((events.last['data']! as Map)['success'], isFalse);
  });
}

// A model the capability registry documents a context limit for; without one
// the builder refuses to send rather than guess whether the profile fits.
const _settings = AiTaskSettings(provider: AiProvider.openai, model: 'gpt-5.6');

class _Fixture {
  _Fixture({
    required this.database,
    required this.repository,
    required this.profile,
    required this.service,
    required this.client,
  });

  final AppDatabase database;
  final HealthRepository repository;
  final Profile profile;
  final AdvisorService service;
  final _Client client;

  static Future<_Fixture> create({AiTrace? trace}) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Alex');
    final client = _Client();
    return _Fixture(
      database: database,
      repository: repository,
      profile: profile,
      client: client,
      service: AdvisorService(
        repository: repository,
        keyStore: _KeyStore(),
        clientFactory: _Factory(client),
        contextBuilder: HealthContextBuilder(
          repository,
          scope: HealthContextScope.advisory,
        ),
        trace: trace,
      ),
    );
  }

  Future<AdvisorTurn> ask(String question) => service.ask(
    profileId: profile.id,
    conversationId: 'primary',
    question: question,
    settings: _settings,
  );

  Future<List<AdvisorMessage>> storedMessages() =>
      repository.messages(profile.id, 'primary');

  Future<void> dispose() => database.close();
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
          '<context_coverage>${jsonEncode(receipt)}</context_coverage>\n'
          'Answer.',
      raw: const {
        'usage': {
          'input_tokens': 1000,
          'input_tokens_details': {'cached_tokens': 900},
        },
      },
    );
  }
}
