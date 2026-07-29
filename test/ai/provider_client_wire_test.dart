import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/provider_clients.dart';

void main() {
  test(
    'Anthropic uses current tool versions and model-specific thinking',
    () async {
      final cases = <({String model, bool adaptive, bool fallback})>[
        (model: 'claude-fable-5', adaptive: true, fallback: true),
        (model: 'claude-mythos-5', adaptive: true, fallback: true),
        (model: 'claude-opus-5', adaptive: true, fallback: true),
        (model: 'claude-sonnet-5', adaptive: true, fallback: false),
        (model: 'claude-mythos-preview', adaptive: false, fallback: false),
        (model: 'claude-opus-4-8', adaptive: true, fallback: false),
        (model: 'claude-opus-4-6', adaptive: true, fallback: false),
        (model: 'claude-sonnet-4-6', adaptive: true, fallback: false),
        (model: 'claude-opus-4-5', adaptive: false, fallback: false),
      ];

      for (final item in cases) {
        final dio = Dio();
        Map<String, Object?>? body;
        Map<String, Object?>? headers;
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              body = Map<String, Object?>.from(options.data as Map);
              headers = Map<String, Object?>.from(options.headers);
              handler.reject(
                DioException(
                  requestOptions: options,
                  type: DioExceptionType.cancel,
                ),
              );
            },
          ),
        );
        final client = AnthropicClient(dio, ProviderCapabilityRegistry());
        final searching =
            item.model == 'claude-fable-5' ||
            item.model == 'claude-mythos-preview' ||
            item.model == 'claude-opus-4-5';

        await expectLater(
          client.respond(
            'test-key',
            ProviderRequest(
              model: item.model,
              systemPrompt: 'system',
              userPrompt: 'question',
              contextJson: '{}',
              reasoningLevel: 'high',
              webSearch: searching,
              codeExecution: item.model == 'claude-fable-5',
            ),
          ),
          throwsA(isA<AiProviderException>()),
        );

        expect(body?['output_config'], {'effort': 'high'}, reason: item.model);
        expect(
          body?.containsKey('thinking'),
          item.adaptive,
          reason: item.model,
        );
        if (item.adaptive) {
          expect(body?['thinking'], {'type': 'adaptive'}, reason: item.model);
        }
        expect(
          body?['fallbacks'],
          item.fallback ? 'default' : isNull,
          reason: item.model,
        );
        expect(
          headers?['anthropic-beta']?.toString().contains(
                'server-side-fallback-2026-07-01',
              ) ??
              false,
          item.fallback,
          reason: item.model,
        );
        if (item.model == 'claude-fable-5') {
          final tools = body?['tools'] as List;
          expect(tools[0]['type'], 'web_search_20260209');
          expect(tools[1]['type'], 'code_execution_20260521');
        }
        if (item.model == 'claude-mythos-preview' ||
            item.model == 'claude-opus-4-5') {
          final tools = body?['tools'] as List;
          expect(tools[0]['type'], 'web_search_20250305', reason: item.model);
        }
      }
    },
  );

  test(
    'Anthropic caches the stable prefix and enforces a JSON schema',
    () async {
      final dio = Dio();
      Map<String, Object?>? body;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            body = Map<String, Object?>.from(options.data as Map);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
              ),
            );
          },
        ),
      );
      final client = AnthropicClient(dio, ProviderCapabilityRegistry());
      const schema = <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
        'additionalProperties': false,
      };

      await expectLater(
        client.respond(
          'test-key',
          const ProviderRequest(
            model: 'claude-opus-5',
            systemPrompt: 'system',
            userPrompt: 'question',
            contextJson: '{"complete":true}',
            requireJson: true,
            jsonSchema: schema,
          ),
        ),
        throwsA(isA<AiProviderException>()),
      );

      final system = body?['system'] as List;
      expect((system.first as Map)['cache_control'], {'type': 'ephemeral'});
      final message = (body?['messages'] as List).first as Map;
      final content = message['content'] as List;
      expect(
        (content.first as Map)['text'],
        contains('<complete_health_context>'),
      );
      expect((content.first as Map)['cache_control'], {'type': 'ephemeral'});
      expect((content.last as Map)['text'], 'question');
      final outputConfig = body?['output_config'] as Map;
      expect(outputConfig['format'], {'type': 'json_schema', 'schema': schema});
    },
  );

  test('Anthropic omits the JSON schema when web search is enabled', () async {
    final dio = Dio();
    Map<String, Object?>? body;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          body = Map<String, Object?>.from(options.data as Map);
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        },
      ),
    );
    final client = AnthropicClient(dio, ProviderCapabilityRegistry());

    await expectLater(
      client.respond(
        'test-key',
        const ProviderRequest(
          model: 'claude-opus-5',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{}',
          requireJson: true,
          jsonSchema: {'type': 'object'},
          webSearch: true,
        ),
      ),
      throwsA(isA<AiProviderException>()),
    );

    expect(body?.containsKey('output_config'), isFalse);
  });

  test(
    'Anthropic rejects reasoning before a network request for no-effort models',
    () async {
      final dio = Dio();
      var requested = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requested = true;
            handler.next(options);
          },
        ),
      );
      final client = AnthropicClient(dio, ProviderCapabilityRegistry());

      await expectLater(
        client.respond(
          'test-key',
          const ProviderRequest(
            model: 'claude-sonnet-4-5',
            systemPrompt: 'system',
            userPrompt: 'question',
            contextJson: '{}',
            reasoningLevel: 'high',
          ),
        ),
        throwsA(isA<AiProviderException>()),
      );

      expect(requested, isFalse);
    },
  );

  test('Gemini uses the documented JSON response format wire field', () async {
    final dio = Dio();
    Map<String, Object?>? body;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          body = Map<String, Object?>.from(options.data as Map);
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        },
      ),
    );
    final client = GeminiClient(dio, ProviderCapabilityRegistry());

    await expectLater(
      client.respond(
        'test-key',
        const ProviderRequest(
          model: 'gemini-3.1-pro-preview',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{}',
          requireJson: true,
        ),
      ),
      throwsA(isA<AiProviderException>()),
    );

    expect(body?['response_format'], {
      'type': 'text',
      'mime_type': 'application/json',
    });
  });

  test('OpenAI only sends JSON format for a structured-output model', () async {
    final dio = Dio();
    Map<String, Object?>? body;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          body = Map<String, Object?>.from(options.data as Map);
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
        },
      ),
    );
    final client = OpenAiClient(dio, ProviderCapabilityRegistry());
    await expectLater(
      client.respond(
        'test-key',
        const ProviderRequest(
          model: 'gpt-5.5-pro',
          systemPrompt: 'system',
          userPrompt: 'question',
          contextJson: '{}',
          requireJson: true,
        ),
      ),
      throwsA(isA<AiProviderException>()),
    );
    expect(body?['text'], {
      'format': {'type': 'json_object'},
    });
  });

  test(
    'OpenAI omits JSON format for a Pro model without structured output',
    () async {
      final dio = Dio();
      Map<String, Object?>? body;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            body = Map<String, Object?>.from(options.data as Map);
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
              ),
            );
          },
        ),
      );
      final client = OpenAiClient(dio, ProviderCapabilityRegistry());
      await expectLater(
        client.respond(
          'test-key',
          const ProviderRequest(
            model: 'gpt-5.4-pro',
            systemPrompt: 'system',
            userPrompt: 'question',
            contextJson: '{}',
            requireJson: true,
          ),
        ),
        throwsA(isA<AiProviderException>()),
      );
      expect(body?.containsKey('text'), isFalse);
    },
  );
}
