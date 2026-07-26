import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ui/common.dart';

void main() {
  group('parseOptionalDouble', () {
    test('accepts finite comma decimals and rejects non-finite values', () {
      expect(parseOptionalDouble('1,25'), 1.25);
      expect(parseOptionalDouble('-2.5'), -2.5);
      expect(parseOptionalDouble(''), isNull);
      expect(parseOptionalDouble('NaN'), isNull);
      expect(parseOptionalDouble('Infinity'), isNull);
      expect(parseOptionalDouble('-Infinity'), isNull);
    });
  });

  group('sanitizeAppErrorMessage', () {
    test('redacts OpenAI authorization bearer tokens', () {
      const token = 'sk-proj-openai-secret-value';
      final message = sanitizeAppErrorMessage(
        'DioException: Authorization: Bearer $token returned 401.',
      );

      expect(message, isNot(contains(token)));
      expect(
        message,
        'DioException: Authorization: Bearer [redacted] returned 401.',
      );
      expect(sanitizeAppErrorMessage(message), message);
      expect(message, isNot(contains('[redacted]]')));
      expect(message, contains('returned 401.'));
    });

    test('redacts Anthropic and Gemini API-key header values', () {
      const anthropicKey = 'sk-ant-api03-anthropic-secret';
      const geminiKey = 'AIzaGeminiSecret';
      final message = sanitizeAppErrorMessage(
        'x-api-key: $anthropicKey; x-goog-api-key: $geminiKey',
      );

      expect(message, isNot(contains(anthropicKey)));
      expect(message, isNot(contains(geminiKey)));
      expect(message, contains('x-api-key: [redacted]'));
      expect(message, contains('x-goog-api-key: [redacted]'));
    });

    test('redacts Microsoft OAuth and query credentials', () {
      const accessToken = 'EwBAA8l6BAAU7qfsecret';
      const refreshToken = '0.AXoA.refresh-secret';
      const authorizationCode = '0.AXoA.oauth-code-secret';
      const clientSecret = 'client-secret-value';
      final message = sanitizeAppErrorMessage(
        'https://callback.example/?code=$authorizationCode&access_token=$accessToken&refresh_token=$refreshToken&client_secret=$clientSecret&key=AIzaQuerySecret',
      );

      for (final secret in [
        accessToken,
        refreshToken,
        authorizationCode,
        clientSecret,
        'AIzaQuerySecret',
      ]) {
        expect(message, isNot(contains(secret)));
      }
      expect(message, contains('code=[redacted]'));
      expect(message, contains('access_token=[redacted]'));
      expect(message, contains('key=[redacted]'));
    });

    test('preserves ordinary actionable errors and cleans exception prefixes', () {
      expect(
        sanitizeAppErrorMessage(
          'StateError: Could not save lab result: 2.5 mmol/L is outside the selected range.',
        ),
        'Could not save lab result: 2.5 mmol/L is outside the selected range.',
      );
    });

    test('redacts JSON-style API keys and bounds pathological messages', () {
      const apiKey = 'sk-json-secret';
      final message = sanitizeAppErrorMessage(
        '{"apiKey":"$apiKey"} ${'x' * 1300}',
      );

      expect(message, isNot(contains(apiKey)));
      expect(message, contains('"apiKey":"[redacted]"'));
      expect(message, endsWith('… [truncated]'));
      expect(message.length, lessThanOrEqualTo(1214));
    });
  });

  testWidgets('section actions stack without overflow on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SectionHeader(
            title: 'Sehr langer deutscher Abschnittstitel',
            subtitle:
                'Eine längere Beschreibung, die auf einem kleinen Telefon umbrechen muss.',
            action: FilledButton(onPressed: null, child: Text('Lange Aktion')),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
