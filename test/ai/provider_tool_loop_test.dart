import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/provider_clients.dart';

/// Answers each request with the next scripted server-sent-event stream and
/// keeps a deep copy of every body as it was *sent* — the clients grow one
/// transcript list across rounds, so a reference would show only its end.
class _Script {
  _Script(this.streams);

  final List<String> streams;
  final bodies = <Map<String, Object?>>[];

  Dio dio() {
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          bodies.add(
            Map<String, Object?>.from(
              jsonDecode(jsonEncode(options.data)) as Map,
            ),
          );
          final stream =
              streams[(bodies.length - 1).clamp(0, streams.length - 1)];
          handler.resolve(
            Response<ResponseBody>(
              requestOptions: options,
              statusCode: 200,
              data: ResponseBody.fromString(stream, 200),
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

String _openAi(List<Map<String, Object?>> output, {int input = 100}) => _sse([
  {
    'type': 'response.completed',
    'response': {
      'id': 'resp',
      'status': 'completed',
      'output': output,
      'usage': {'input_tokens': input, 'output_tokens': 10},
    },
  },
]);

String _anthropic(List<Map<String, Object?>> blocks, String stopReason) {
  final events = <Map<String, Object?>>[
    {
      'type': 'message_start',
      'message': {
        'id': 'msg',
        'role': 'assistant',
        'content': <Object?>[],
        'usage': {'input_tokens': 100, 'output_tokens': 1},
      },
    },
  ];
  for (var i = 0; i < blocks.length; i++) {
    final block = blocks[i];
    switch (block['type']) {
      case 'thinking':
        events
          ..add({
            'type': 'content_block_start',
            'index': i,
            'content_block': {'type': 'thinking', 'thinking': ''},
          })
          ..add({
            'type': 'content_block_delta',
            'index': i,
            'delta': {'type': 'thinking_delta', 'thinking': block['thinking']},
          })
          ..add({
            'type': 'content_block_delta',
            'index': i,
            'delta': {
              'type': 'signature_delta',
              'signature': block['signature'],
            },
          });
      case 'tool_use':
        final input = jsonEncode(block['input']);
        events
          ..add({
            'type': 'content_block_start',
            'index': i,
            'content_block': {
              'type': 'tool_use',
              'id': block['id'],
              'name': block['name'],
              'input': <String, Object?>{},
            },
          })
          ..add({
            'type': 'content_block_delta',
            'index': i,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': input.substring(0, input.length ~/ 2),
            },
          })
          ..add({
            'type': 'content_block_delta',
            'index': i,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': input.substring(input.length ~/ 2),
            },
          });
      default:
        events
          ..add({
            'type': 'content_block_start',
            'index': i,
            'content_block': {'type': 'text', 'text': ''},
          })
          ..add({
            'type': 'content_block_delta',
            'index': i,
            'delta': {'type': 'text_delta', 'text': block['text']},
          });
    }
    events.add({'type': 'content_block_stop', 'index': i});
  }
  events
    ..add({
      'type': 'message_delta',
      'delta': {'stop_reason': stopReason},
      'usage': {'output_tokens': 20},
    })
    ..add({'type': 'message_stop'});
  return _sse(events);
}

const _tool = AgentToolSpec(
  name: 'biomarker_history',
  description: 'Every measurement of one biomarker.',
  inputSchema: {
    'type': 'object',
    'properties': {
      'biomarker': {'type': 'string'},
    },
    'required': ['biomarker'],
  },
);

ProviderRequest _request(String model) => ProviderRequest(
  model: model,
  systemPrompt: 'system',
  userPrompt: 'Should I get my TSH checked?',
  contextJson: '',
  digestText: '{"digest":true}',
  tools: const [_tool],
  reasoningLevel: 'high',
);

void main() {
  group('OpenAI tool loop', () {
    test('echoes the reasoning and call items, answers the call, and returns '
        'only the final text', () async {
      const reasoning = {
        'type': 'reasoning',
        'id': 'rs_1',
        'summary': <Object?>[],
        'encrypted_content': 'opaque-reasoning',
      };
      const call = {
        'type': 'function_call',
        'id': 'fc_1',
        'call_id': 'call_1',
        'name': 'biomarker_history',
        'arguments': '{"biomarker":"tsh"}',
      };
      final script = _Script([
        _openAi([reasoning, call]),
        _openAi([
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': 'Final answer.'},
            ],
          },
        ], input: 150),
      ]);
      final client = OpenAiClient(script.dio(), ProviderCapabilityRegistry());
      final seen = <(List<AgentToolCall>, int)>[];

      final response = await client.respond(
        'key',
        _request('gpt-5.6'),
        onToolCalls: (calls, round) async {
          seen.add((calls, round));
          return [
            for (final call in calls)
              AgentToolResult(callId: call.id, content: '{"ok":true}'),
          ];
        },
      );

      expect(response.text, 'Final answer.');
      expect(response.toolRounds, 1);
      expect(response.usage!.inputTokens, 250);
      expect(seen.single.$2, 1);
      expect(seen.single.$1.single.id, 'call_1');
      expect(seen.single.$1.single.input, {'biomarker': 'tsh'});

      final first = script.bodies.first;
      expect(first['include'], ['reasoning.encrypted_content']);
      final tools = first['tools']! as List;
      expect(tools.single, {
        'type': 'function',
        'name': 'biomarker_history',
        'description': 'Every measurement of one biomarker.',
        'parameters': _tool.inputSchema,
        'strict': false,
      });
      final firstInput = first['input']! as List;
      final context = (firstInput.first as Map)['content'] as String;
      expect(context, startsWith('<clinical_digest>'));
      expect(context, isNot(contains('complete_health_context')));

      final second = script.bodies.last['input']! as List;
      expect(second.sublist(firstInput.length), [
        reasoning,
        call,
        {
          'type': 'function_call_output',
          'call_id': 'call_1',
          'output': '{"ok":true}',
        },
      ]);
      // The tools and instructions are identical in both rounds: they are
      // part of the cached prefix.
      expect(script.bodies.last['tools'], first['tools']);
      expect(script.bodies.last['instructions'], first['instructions']);
    });

    test(
      'arguments that are not JSON reach the handler as an input error',
      () async {
        final script = _Script([
          _openAi([
            {
              'type': 'function_call',
              'call_id': 'call_1',
              'name': 'biomarker_history',
              'arguments': '{"biomarker":',
            },
          ]),
          _openAi([
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': 'Done.'},
              ],
            },
          ]),
        ]);
        final client = OpenAiClient(script.dio(), ProviderCapabilityRegistry());
        AgentToolCall? received;

        await client.respond(
          'key',
          _request('gpt-5.6'),
          onToolCalls: (calls, round) async {
            received = calls.single;
            return [AgentToolResult(callId: calls.single.id, content: '{}')];
          },
        );

        expect(received!.inputError, isNotNull);
      },
    );

    test('a model that never stops calling tools is cut off', () async {
      final loop = _openAi([
        {
          'type': 'function_call',
          'call_id': 'call_x',
          'name': 'biomarker_history',
          'arguments': '{"biomarker":"tsh"}',
        },
      ]);
      final script = _Script([loop]);
      final client = OpenAiClient(script.dio(), ProviderCapabilityRegistry());
      var handled = 0;

      await expectLater(
        client.respond(
          'key',
          _request('gpt-5.6'),
          onToolCalls: (calls, round) async {
            handled++;
            return [
              for (final call in calls)
                AgentToolResult(callId: call.id, content: '{}'),
            ];
          },
        ),
        throwsA(isA<AiProviderException>()),
      );
      // The handler runs for the budget; the extra round answers with the
      // "budget used up" error instead of running tools.
      expect(handled, maxToolRounds);
      expect(script.bodies, hasLength(maxToolRounds + 2));
      final lastOutput = (script.bodies.last['input']! as List).last as Map;
      expect('${lastOutput['output']}', contains('Tool budget'));
    });
  });

  group('Anthropic tool loop', () {
    test('echoes thinking with its signature, answers with tool_result and '
        'drops the preamble', () async {
      final script = _Script([
        _anthropic([
          {'type': 'thinking', 'thinking': 'Check TSH.', 'signature': 'sig-1'},
          {'type': 'text', 'text': 'Let me look that up.'},
          {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'biomarker_history',
            'input': {'biomarker': 'tsh'},
          },
        ], 'tool_use'),
        _anthropic([
          {'type': 'text', 'text': 'Final answer.'},
        ], 'end_turn'),
      ]);
      final client = AnthropicClient(
        script.dio(),
        ProviderCapabilityRegistry(),
      );
      List<AgentToolCall>? received;

      final response = await client.respond(
        'key',
        _request('claude-opus-5'),
        onToolCalls: (calls, round) async {
          received = calls;
          return [
            AgentToolResult(
              callId: calls.single.id,
              content: '{"error":"x"}',
              isError: true,
            ),
          ];
        },
      );

      expect(response.text, 'Final answer.');
      expect(response.toolRounds, 1);
      expect(received!.single.id, 'toolu_1');
      expect(received!.single.input, {'biomarker': 'tsh'});

      final first = script.bodies.first;
      final tools = first['tools']! as List;
      expect(tools.single, {
        'name': 'biomarker_history',
        'description': 'Every measurement of one biomarker.',
        'input_schema': _tool.inputSchema,
      });
      final firstMessages = first['messages']! as List;
      final context = (firstMessages.first as Map)['content'] as List;
      expect(context, hasLength(1));
      expect((context.single as Map)['text'], startsWith('<clinical_digest>'));
      expect((context.single as Map)['cache_control'], {'type': 'ephemeral'});

      final messages = script.bodies.last['messages']! as List;
      final assistant = messages[messages.length - 2] as Map;
      expect(assistant['role'], 'assistant');
      final thinking = (assistant['content'] as List).first as Map;
      expect(thinking['signature'], 'sig-1');
      expect(thinking['thinking'], 'Check TSH.');
      final toolUse = (assistant['content'] as List).last as Map;
      expect(toolUse['input'], {'biomarker': 'tsh'});
      final results = (messages.last as Map)['content'] as List;
      expect(results.single, {
        'type': 'tool_result',
        'tool_use_id': 'toolu_1',
        'content': '{"error":"x"}',
        'is_error': true,
        'cache_control': {'type': 'ephemeral'},
      });
    });

    test('keeps a single moving cache breakpoint across rounds', () async {
      Map<String, Object?> call(String id) => {
        'type': 'tool_use',
        'id': id,
        'name': 'biomarker_history',
        'input': {'biomarker': id},
      };
      final script = _Script([
        _anthropic([call('a')], 'tool_use'),
        _anthropic([call('b')], 'tool_use'),
        _anthropic([
          {'type': 'text', 'text': 'Done.'},
        ], 'end_turn'),
      ]);
      final client = AnthropicClient(
        script.dio(),
        ProviderCapabilityRegistry(),
      );

      await client.respond(
        'key',
        _request('claude-opus-5'),
        onToolCalls: (calls, round) async => [
          for (final call in calls)
            AgentToolResult(callId: call.id, content: '{}'),
        ],
      );

      final encoded = jsonEncode(script.bodies.last);
      // System, digest and the newest tool result: never more than four.
      expect('cache_control'.allMatches(encoded).length, 3);
    });
  });

  test(
    'Gemini refuses client tools rather than guessing a wire shape',
    () async {
      final client = GeminiClient(Dio(), ProviderCapabilityRegistry());
      expect(providerSupportsClientTools(AiProvider.gemini), isFalse);
      await expectLater(
        client.respond(
          'key',
          _request('gemini-3.1-pro-preview'),
          onToolCalls: (calls, round) async => const [],
        ),
        throwsA(isA<AiProviderException>()),
      );
    },
  );

  test('tools without a handler are a programming error', () async {
    final client = OpenAiClient(Dio(), ProviderCapabilityRegistry());
    await expectLater(
      client.respond('key', _request('gpt-5.6')),
      throwsA(isA<ArgumentError>()),
    );
  });
}
