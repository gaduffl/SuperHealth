import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/chatgpt_auth.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/ui/ai_error_text.dart';
import 'package:super_health/ui/common.dart';

void main() {
  // Built from local wall-clock times, so the expectations hold whatever time
  // zone the test runs in.
  final resetsAt = DateTime(2026, 10, 3, 14, 30).toUtc();
  final limit = ProviderUsageLimitException(resetsAt: resetsAt);

  test('a limit that lifts today names only the time', () {
    final morning = DateTime(2026, 10, 3, 9);

    expect(
      usageLimitErrorText(AppLocalizations.english, limit, now: morning),
      startsWith('ChatGPT usage limit reached – it resets at 14:30.'),
    );
    expect(
      usageLimitErrorText(AppLocalizations.german, limit, now: morning),
      startsWith(
        'ChatGPT-Nutzungsgrenze erreicht – sie wird um 14:30 zurückgesetzt.',
      ),
    );
  });

  test('a limit that lifts on another day names the date as well', () {
    final dayBefore = DateTime(2026, 10, 2, 22);

    expect(
      usageLimitErrorText(AppLocalizations.english, limit, now: dayBefore),
      contains('resets on 03.10.2026 at 14:30'),
    );
    expect(
      usageLimitErrorText(AppLocalizations.german, limit, now: dayBefore),
      contains('am 03.10.2026 um 14:30 zurückgesetzt'),
    );
  });

  test('a limit without a reset time still says what to do', () {
    final text = usageLimitErrorText(
      AppLocalizations.english,
      const ProviderUsageLimitException(),
      now: DateTime(2026, 10, 3),
    );

    expect(text, contains('Try again later'));
    expect(text, contains('API-key provider'));
  });

  test('a sign-in failure is phrased in the reader\'s language', () {
    expect(
      chatGptAuthErrorText(
        AppLocalizations.german,
        const ChatGptAuthException(ChatGptAuthFailure.sessionExpired),
      ),
      'Die ChatGPT-Anmeldung ist abgelaufen. Melde dich erneut an.',
    );
  });

  testWidgets('every flow that reports through showAppError shows the usage '
      'limit in words rather than as a raw provider error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppError(context, limit),
              child: const Text('fail'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('fail'));
    await tester.pump();

    expect(find.textContaining('ChatGPT usage limit reached'), findsOneWidget);
    expect(find.textContaining('14:30'), findsOneWidget);
  });
}
