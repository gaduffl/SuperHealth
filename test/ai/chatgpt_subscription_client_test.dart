import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/chatgpt_auth.dart';
import 'package:super_health/ai/provider_clients.dart';

class _Sessions implements ChatGptSessionSource {
  var token = 'token-1';
  var forced = 0;

  @override
  Future<ChatGptSession> session({bool forceRefresh = false}) async {
    if (forceRefresh) {
      forced += 1;
      token = 'token-${forced + 1}';
    }
    return ChatGptSession(accessToken: token, accountId: 'acct-1');
  }
}

/// An HTTP error with its own body and headers.
class _ErrorReply {
  const _ErrorReply(this.status, this.body, {this.headers = const {}});

  final int status;
  final Map<String, Object?> body;
  final Map<String, List<String>> headers;
}

/// Answers each request with the next scripted stream (or HTTP status) and
/// keeps a deep copy of every request as it was sent.
class _Script {
  _Script(this.replies);

  /// A server-sent-event body, an int for an HTTP error status, or an
  /// [_ErrorReply].
  final List<Object> replies;
  final bodies = <Map<String, Object?>>[];
  final headers = <Map<String, Object?>>[];
  final urls = <String>[];

  Dio dio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          urls.add(options.uri.toString());
          headers.add(Map<String, Object?>.from(options.headers));
          bodies.add(
            Map<String, Object?>.from(
              jsonDecode(jsonEncode(options.data)) as Map,
            ),
          );
          final reply =
              replies[(bodies.length - 1).clamp(0, replies.length - 1)];
          if (reply is int) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<ResponseBody>(
                  requestOptions: options,
                  statusCode: reply,
                  data: ResponseBody.fromString(
                    '{"error":{"message":"token expired"}}',
                    reply,
                  ),
                ),
              ),
            );
            return;
          }
          if (reply is _ErrorReply) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<ResponseBody>(
                  requestOptions: options,
                  statusCode: reply.status,
                  headers: Headers.fromMap(reply.headers),
                  data: ResponseBody.fromString(
                    jsonEncode(reply.body),
                    reply.status,
                  ),
                ),
              ),
            );
            return;
          }
          handler.resolve(
            Response<ResponseBody>(
              requestOptions: options,
              statusCode: 200,
              data: ResponseBody.fromString(reply as String, 200),
            ),
          );
        },
      ),
    );
    return dio;
  }
}

String _sse(List<Map<String, Object?>> events) =>
    '${events.map((event) => 'data: ${jsonEncode(event)}').join('\n\n')}\n\n';

/// The backend's shape: items arrive as `output_item.done` events, and the
/// closing `response.completed` carries only the id and usage.
String _subscription(List<Map<String, Object?>> items) => _sse([
  for (final item in items) {'type': 'response.output_item.done', 'item': item},
  {
    'type': 'response.completed',
    'response': {
      'id': 'resp',
      'status': 'completed',
      'usage': {'input_tokens': 100, 'output_tokens': 10},
    },
  },
]);

Map<String, Object?> _message(String text, {String? phase}) => {
  'type': 'message',
  'role': 'assistant',
  'phase': ?phase,
  'content': [
    {'type': 'output_text', 'text': text},
  ],
};

ChatGptSubscriptionClient _client(_Script script, [_Sessions? sessions]) =>
    ChatGptSubscriptionClient(
      script.dio(),
      ProviderCapabilityRegistry(),
      sessions ?? _Sessions(),
    );

void main() {
  test(
    'requests go to the Codex backend as SuperHealth, carry the session, and '
    'leave out what that backend refuses',
    () async {
      final script = _Script([
        _subscription([_message('The answer.')]),
      ]);

      final response = await _client(script).respond(
        'ignored',
        const ProviderRequest(
          model: 'gpt-5.5',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{"a":1}',
          history: [
            ProviderChatMessage(role: 'user', content: 'earlier question'),
            ProviderChatMessage(role: 'assistant', content: 'earlier answer'),
          ],
          reasoningLevel: 'high',
          webSearch: true,
          promptCacheKey: 'cache-key-1',
          requireJson: true,
          jsonSchema: {'type': 'object'},
        ),
      );

      expect(response.text, 'The answer.');
      expect(
        script.urls.single,
        'https://chatgpt.com/backend-api/codex/responses',
      );
      final headers = script.headers.single;
      expect(headers['Authorization'], 'Bearer token-1');
      expect(headers['ChatGPT-Account-ID'], 'acct-1');
      expect(headers['originator'], 'superhealth');
      final body = script.bodies.single;
      expect(body.containsKey('max_output_tokens'), isFalse);
      expect(body.containsKey('prompt_cache_retention'), isFalse);
      expect(body['prompt_cache_key'], 'cache-key-1');
      expect(body['store'], false);
      expect(body['stream'], true);
      expect(body['instructions'], 'system');
      expect(body['reasoning'], {'effort': 'high'});
      expect(body['tools'], [
        {'type': 'web_search'},
      ]);
      expect((body['text'] as Map)['format'], {
        'type': 'json_schema',
        'name': 'superhealth_response',
        'strict': true,
        'schema': {'type': 'object'},
      });
      final input = body['input'] as List;
      expect(input, hasLength(4));
      expect(input[1], {
        'type': 'message',
        'role': 'user',
        'content': [
          {'type': 'input_text', 'text': 'earlier question'},
        ],
      });
      expect(input[2], {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': 'earlier answer'},
        ],
      });
      expect(((input[3] as Map)['content'] as List).single, {
        'type': 'input_text',
        'text': 'question',
      });
    },
  );

  test('a tool round trip echoes the model\'s items verbatim and answers from '
      'items the completion event never repeats', () async {
    final call = {
      'type': 'function_call',
      'id': 'fc_1',
      'call_id': 'call_1',
      'name': 'search_records',
      'arguments': '{"query":"biotin"}',
    };
    final reasoning = {
      'type': 'reasoning',
      'id': 'rs_1',
      'summary': <Object?>[],
      'encrypted_content': 'opaque',
    };
    final script = _Script([
      _subscription([reasoning, call]),
      _subscription([_message('Biotin interferes with TSH.')]),
    ]);
    final rounds = <List<AgentToolCall>>[];

    final response = await _client(script).respond(
      'ignored',
      const ProviderRequest(
        model: 'gpt-5.5',
        systemPrompt: 'system',
        userPrompt: 'question',
        contextJson: '',
        digestText: 'digest',
        reasoningLevel: 'medium',
        tools: [
          AgentToolSpec(
            name: 'search_records',
            description: 'search',
            inputSchema: {'type': 'object'},
          ),
        ],
      ),
      onToolCalls: (calls, round) async {
        rounds.add(calls);
        return [
          for (final call in calls)
            AgentToolResult(callId: call.id, content: '{"hits":1}'),
        ];
      },
    );

    expect(response.text, 'Biotin interferes with TSH.');
    expect(response.toolRounds, 1);
    expect(rounds.single.single.input, {'query': 'biotin'});
    expect(script.bodies.first['include'], ['reasoning.encrypted_content']);
    final second = script.bodies.last['input'] as List;
    expect(second, containsAllInOrder([reasoning, call]));
    expect(second.last, {
      'type': 'function_call_output',
      'call_id': 'call_1',
      'output': '{"hits":1}',
    });
  });

  test(
    'a 401 renews the session once and retries with the new token',
    () async {
      final sessions = _Sessions();
      final script = _Script([
        401,
        _subscription([_message('Answer.')]),
      ]);

      final response = await _client(script, sessions).respond(
        'ignored',
        const ProviderRequest(
          model: 'gpt-5.5',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{}',
        ),
      );

      expect(response.text, 'Answer.');
      expect(sessions.forced, 1);
      expect(script.headers.map((headers) => headers['Authorization']), [
        'Bearer token-1',
        'Bearer token-2',
      ]);
    },
  );

  test(
    'progress narration stays out of the answer when a final answer exists',
    () async {
      final script = _Script([
        _subscription([
          _message('Checking the intake history.', phase: 'commentary'),
          _message('Ferritin is due.', phase: 'final_answer'),
        ]),
      ]);

      final response = await _client(script).respond(
        'ignored',
        const ProviderRequest(
          model: 'gpt-5.5',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{}',
        ),
      );

      expect(response.text, 'Ferritin is due.');
    },
  );

  test(
    'the subscription refuses the code sandbox before sending anything',
    () async {
      final script = _Script([_subscription([])]);

      await expectLater(
        _client(script).respond(
          'ignored',
          const ProviderRequest(
            model: 'gpt-5.5',
            systemPrompt: 'system',
            userPrompt: 'question',
            contextJson: '{}',
            codeExecution: true,
          ),
        ),
        throwsA(isA<AiProviderException>()),
      );
      expect(script.bodies, isEmpty);
    },
  );

  test('without a sign-in the client says so instead of sending', () async {
    final script = _Script([_subscription([])]);
    final client = AiProviderClientFactory(
      dio: script.dio(),
    ).create(AiProvider.chatgpt);

    await expectLater(
      client.respond(
        'ignored',
        const ProviderRequest(
          model: 'gpt-5.5',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{}',
        ),
      ),
      throwsA(
        isA<ChatGptAuthException>().having(
          (error) => error.failure,
          'failure',
          ChatGptAuthFailure.notSignedIn,
        ),
      ),
    );
    expect(script.bodies, isEmpty);
  });

  test('every listed subscription model has a 272k window, a tool loop and no '
      'file path, and the list needs no request', () async {
    final script = _Script([_subscription([])]);
    final registry = ProviderCapabilityRegistry();

    final models = await _client(script).listModels('ignored');

    expect(
      models.map((model) => model.id),
      ProviderCapabilityRegistry.chatGptModels,
    );
    expect(script.bodies, isEmpty);
    expect(providerSupportsClientTools(AiProvider.chatgpt), isTrue);
    for (final id in ProviderCapabilityRegistry.chatGptModels) {
      final capabilities = registry.forModel(AiProvider.chatgpt, id);
      expect(capabilities.contextWindowTokens, 272000, reason: id);
      expect(capabilities.reasoningLevels, isNotEmpty, reason: id);
      expect(capabilities.structuredOutput, isTrue, reason: id);
      expect(capabilities.codeExecution, isFalse, reason: id);
      expect(capabilities.losslessContextFile, isFalse, reason: id);
    }
    expect(
      registry.forModel(AiProvider.chatgpt, 'gpt-unknown').reasoningLevels,
      isEmpty,
    );
  });

  test('lab document parsing is the one role a subscription cannot take', () {
    for (final task in AiTask.values) {
      expect(
        providerServesTask(AiProvider.chatgpt, task),
        task != AiTask.parsing,
        reason: task.name,
      );
      for (final provider in [
        AiProvider.openai,
        AiProvider.anthropic,
        AiProvider.gemini,
      ]) {
        expect(providerServesTask(provider, task), isTrue);
      }
    }
  });

  const question = ProviderRequest(
    model: 'gpt-5.5',
    systemPrompt: 'system',
    userPrompt: 'question',
    contextJson: '{}',
  );
  final resetsAt = DateTime.utc(2026, 10, 3, 14, 30);

  test('a usage limit fails at the first answer, carrying its reset and plan, '
      'instead of being retried like a rate limit', () async {
    final script = _Script([
      _ErrorReply(429, {
        'error': {
          'type': 'usage_limit_reached',
          'message': 'The usage limit has been reached',
          'plan_type': 'plus',
          'resets_at': resetsAt.millisecondsSinceEpoch ~/ 1000,
        },
      }),
    ]);

    await expectLater(
      _client(script).respond('ignored', question),
      throwsA(
        isA<ProviderUsageLimitException>()
            .having((error) => error.resetsAt, 'resetsAt', resetsAt)
            .having((error) => error.planType, 'planType', 'plus')
            .having((error) => error.statusCode, 'statusCode', 429),
      ),
    );
    expect(script.bodies, hasLength(1));
  });

  test('a 429 that is not the usage limit is still retried and keeps the '
      'provider\'s own message', () async {
    final script = _Script([
      const _ErrorReply(
        429,
        {
          'error': {'message': 'Slow down for a moment.'},
        },
        headers: {
          'retry-after': ['1'],
        },
      ),
    ]);

    await expectLater(
      _client(script).respond('ignored', question),
      throwsA(
        isA<AiProviderException>()
            .having(
              (error) => error,
              'type',
              isNot(isA<ProviderUsageLimitException>()),
            )
            .having(
              (error) => error.message,
              'message',
              'Slow down for a moment.',
            ),
      ),
    );
    expect(script.bodies, hasLength(3), reason: 'two retries, as before');
  });

  test('a usage limit reported inside the stream is recognised too', () async {
    final script = _Script([
      _sse([
        {
          'type': 'response.failed',
          'response': {
            'status': 'failed',
            'error': {
              'code': 'usage_limit_reached',
              'resets_at': resetsAt.millisecondsSinceEpoch ~/ 1000,
            },
          },
        },
      ]),
    ]);

    await expectLater(
      _client(script).respond('ignored', question),
      throwsA(
        isA<ProviderUsageLimitException>().having(
          (error) => error.resetsAt,
          'resetsAt',
          resetsAt,
        ),
      ),
    );
  });

  test('only a usage-limit payload reads as one', () {
    expect(
      usageLimitFrom({
        'error': {'type': 'rate_limit_exceeded', 'message': 'Slow down.'},
      }),
      isNull,
    );
    expect(usageLimitFrom('not a map'), isNull);
    expect(usageLimitFrom(null), isNull);
    final withoutReset = usageLimitFrom({
      'error': {'type': 'usage_limit_reached'},
    });
    expect(withoutReset, isNotNull);
    expect(withoutReset!.resetsAt, isNull);
    expect(withoutReset.toString(), 'ChatGPT usage limit reached.');
  });
}
