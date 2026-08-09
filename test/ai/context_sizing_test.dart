import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/provider_clients.dart';

void main() {
  group('token estimation', () {
    test('matches the ratio measured on a real package', () {
      // 2,020,279 bytes billed as 847,443 input tokens on a real run. The old
      // 3.5 divisor called that 577,223 — 46% low.
      final estimate = estimatedJsonTokens(2020279);

      expect(estimate, greaterThan(800000));
      expect(estimate, lessThan(950000));
    });

    test('errs high rather than low', () {
      // The two directions are not symmetric. Over-estimating routes to the
      // lossless file path; under-estimating quietly fills the context window
      // past the point the working-room guard exists to defend.
      expect(estimatedJsonTokens(2020279), greaterThanOrEqualTo(847443));
    });

    test('is monotonic and never zero for real content', () {
      expect(estimatedJsonTokens(1), greaterThan(0));
      expect(estimatedJsonTokens(1000), lessThan(estimatedJsonTokens(2000)));
    });
  });

  group('delivery decision', () {
    HealthContextEnvelope envelope(int bytes) => HealthContextEnvelope(
      json: '',
      sha256: 'a' * 64,
      fileSha256: 'b' * 64,
      byteLength: bytes,
      estimatedTokens: estimatedJsonTokens(bytes),
      recordCount: 2872,
      manifest: const {},
      sectionHashes: const {},
    );

    final builder = HealthContextBuilder.fromLoader((_) async => const {});

    test('the package that overshot the guard no longer passes as inline', () {
      // The real 2 MB package needed ~866k tokens against a 720k inline budget
      // on a 1M model. The old estimate let it through.
      expect(
        () => builder.deliveryFor(
          context: envelope(2020279),
          capabilities: const ModelCapabilities(contextWindowTokens: 1000000),
          maxOutputTokens: 16000,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a model with a lossless file path takes it instead of failing', () {
      expect(
        builder.deliveryFor(
          context: envelope(2020279),
          capabilities: const ModelCapabilities(
            contextWindowTokens: 1000000,
            losslessContextFile: true,
            codeExecution: true,
          ),
          maxOutputTokens: 16000,
        ),
        HealthContextDelivery.providerFile,
      );
    });

    test('a package that genuinely fits still goes inline', () {
      expect(
        builder.deliveryFor(
          context: envelope(200000),
          capabilities: const ModelCapabilities(contextWindowTokens: 1000000),
          maxOutputTokens: 16000,
        ),
        HealthContextDelivery.inline,
      );
    });
  });

  group('prompt cache key', () {
    test('is short enough for the provider to accept', () {
      // A 20-char prefix plus a 64-char SHA is 84. OpenAI caps it at 64 and
      // rejects the whole request with HTTP 400 — the generation died before
      // the first token.
      final key = labPlanCacheKeyFor('a' * 64);

      expect(
        key.length,
        lessThanOrEqualTo(ProviderRequest.promptCacheKeyMaxLength),
      );
      expect(key, startsWith('superhealth-lab-'));
    });

    test('still distinguishes two catalogs', () {
      expect(labPlanCacheKeyFor('a' * 64), isNot(labPlanCacheKeyFor('b' * 64)));
    });

    test('an unusable key is dropped, not sent', () {
      // Caching is an optimisation. It must never be the reason a plan fails,
      // so an over-long key becomes a cold prefill rather than a 400.
      expect(usablePromptCacheKey('x' * 65), isNull);
      expect(usablePromptCacheKey(''), isNull);
      expect(usablePromptCacheKey('   '), isNull);
      expect(usablePromptCacheKey(null), isNull);
      expect(usablePromptCacheKey('x' * 64), 'x' * 64);
    });

    test('it is never silently truncated into a collision', () {
      // Shortening an over-long key would let two different catalogs share one,
      // and one could be served the other's prefix.
      expect(usablePromptCacheKey('x' * 100), isNull);
    });
  });

  test('a prompt cache key is carried on the request', () {
    // Two calls over the same ~800k-token context minutes apart. Without a
    // shared key they can land on different machines and each pay a full
    // prefill — measured at four and a half minutes.
    const request = ProviderRequest(
      model: 'test',
      systemPrompt: 'system',
      userPrompt: 'user',
      contextJson: '{}',
      promptCacheKey: 'superhealth-labplan-abc',
    );

    expect(request.promptCacheKey, 'superhealth-labplan-abc');
  });

  group('stop reason', () {
    test('reads Anthropic', () {
      expect(providerStopReason({'stop_reason': 'max_tokens'}), 'max_tokens');
    });

    test('reads OpenAI, including why it was incomplete', () {
      // "incomplete" alone does not say why, and a response truncated at the
      // output limit looks exactly like one that simply failed to parse.
      expect(
        providerStopReason({
          'status': 'incomplete',
          'incomplete_details': {'reason': 'max_output_tokens'},
        }),
        'incomplete reason=max_output_tokens',
      );
      expect(providerStopReason({'status': 'completed'}), 'completed');
    });

    test('surfaces an OpenAI failure message', () {
      expect(
        providerStopReason({
          'status': 'failed',
          'error': {'message': 'context length exceeded'},
        }),
        contains('context length exceeded'),
      );
    });

    test('reads Gemini', () {
      expect(
        providerStopReason({
          'candidates': [
            {'finishReason': 'MAX_TOKENS'},
          ],
        }),
        'MAX_TOKENS',
      );
    });

    test('returns null rather than inventing one', () {
      expect(providerStopReason(const {}), isNull);
    });
  });

  group('provider error description', () {
    test('reads a top-level message', () {
      expect(
        describeProviderError({'message': 'rate limit exceeded'}, 'fallback'),
        'rate limit exceeded',
      );
    });

    test('reads a nested one, which is what the shrug came from', () {
      // The handler only read event['message'], so this shape produced
      // "OpenAI stream error." with the real reason discarded.
      expect(
        describeProviderError({
          'type': 'error',
          'error': {'message': 'context length exceeded', 'code': 'ctx'},
        }, 'fallback'),
        'context length exceeded (code ctx)',
      );
    });

    test('reads the error inside a failed response', () {
      expect(
        describeProviderError({
          'response': {
            'status': 'failed',
            'error': {'message': 'server had an error'},
          },
        }, 'fallback'),
        'server had an error',
      );
    });

    test('an unrecognised shape keeps the payload instead of dropping it', () {
      // The case where the text matters most: nobody knows the shape yet, so
      // the next report has to carry it.
      final described = describeProviderError({
        'type': 'error',
        'weird_field': 'something useful',
      }, 'Provider reported a stream error.');

      expect(described, contains('Provider reported a stream error.'));
      expect(described, contains('weird_field'));
      expect(described, contains('something useful'));
    });

    test('a huge payload is bounded', () {
      final described = describeProviderError({
        'type': 'error',
        'blob': 'x' * 5000,
      }, 'fallback');

      expect(described.length, lessThan(1000));
      expect(described, endsWith('…'));
    });
  });
}
