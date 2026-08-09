import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/health_context_builder.dart';

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
}
