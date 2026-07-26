import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/provider_clients.dart';

void main() {
  ProviderRequest fileRequest({required String checksum, bool code = true}) =>
      ProviderRequest(
        model: 'gpt-5.6',
        systemPrompt: 'system',
        userPrompt: 'question',
        contextJson: '{"complete":true}',
        contextFile: true,
        contextFileSha256: checksum,
        codeExecution: code,
      );

  test(
    'refuses a context-file upload whose checksum differs from its bytes',
    () async {
      final client = OpenAiClient(Dio(), ProviderCapabilityRegistry());

      await expectLater(
        client.respond(
          'test-key',
          fileRequest(checksum: List<String>.filled(64, '0').join()),
        ),
        throwsA(
          isA<AiProviderException>().having(
            (error) => error.message,
            'message',
            contains('checksum does not match'),
          ),
        ),
      );
    },
  );

  test('refuses a context-file request without code execution', () async {
    final client = OpenAiClient(Dio(), ProviderCapabilityRegistry());

    await expectLater(
      client.respond('test-key', fileRequest(checksum: '', code: false)),
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          contains('requires code execution'),
        ),
      ),
    );
  });
}
