import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/advisor_screen.dart';

void main() {
  testWidgets('an answer renders its markdown rather than the source', (
    tester,
  ) async {
    // The model writes headings, bold labels and bullet lists. Showing the
    // source made a structured answer read as a wall of asterisks.
    await _pump(
      tester,
      _message(
        role: 'assistant',
        content: '## Befunde\n\n- **Lp(a)** deutlich erhöht\n- Ferritin normal',
      ),
    );

    expect(find.byType(MarkdownBody), findsOneWidget);
    // The asterisks and hashes are gone from what is actually painted.
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('##'), findsNothing);
    expect(find.textContaining('Lp(a)', findRichText: true), findsOneWidget);
  });

  testWidgets('a typed question is shown exactly as typed', (tester) async {
    // Interpreting the user's own text would mangle anything containing a `*`
    // or a `#` — and they did not write markdown, they wrote a question.
    await _pump(
      tester,
      _message(role: 'user', content: 'Was ist mit **Ferritin** und #1?'),
    );

    expect(find.byType(MarkdownBody), findsNothing);
    expect(find.text('Was ist mit **Ferritin** und #1?'), findsOneWidget);
  });
}

AdvisorMessage _message({required String role, required String content}) =>
    AdvisorMessage(
      id: 'm1',
      profileId: 'profile',
      conversationId: 'primary',
      role: role,
      content: content,
      createdAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, AdvisorMessage message) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: AdvisorMessageBubble(message: message)),
    ),
  );
  await tester.pumpAndSettle();
}
