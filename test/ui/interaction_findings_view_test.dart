import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/advisor_review.dart';
import 'package:super_health/analysis/exposure_analysis.dart';
import 'package:super_health/analysis/interaction_findings.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/advisor_screen.dart';
import 'package:super_health/ui/interaction_findings_view.dart';

final _now = DateTime.utc(2026, 9, 30, 12);

List<InteractionFinding> _biotinFindings() {
  final exposure = ExposureAnalysis.build(
    supplements: [
      Supplement(
        id: 'hair',
        name: 'Haut, Haare & Nägel',
        ingredients: const [
          {'name': 'Biotin', 'amount': 10, 'unit': 'mg'},
        ],
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    schedules: const [],
    intakes: [
      SupplementIntake(
        id: 'dose',
        profileId: 'p',
        supplementId: 'hair',
        takenAt: _now.subtract(const Duration(hours: 5)),
        dose: 1,
        unit: 'capsule',
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    records: const [],
    now: _now,
  );
  return const InteractionFindingsEngine().evaluate(
    exposure: exposure,
    biomarkers: [
      Biomarker(
        id: 'tsh',
        canonicalName: 'tsh',
        displayName: 'TSH',
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    measurements: const [],
    events: const [],
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('en'),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 1800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

AdvisorMessage _answer(String content) => AdvisorMessage(
  id: 'a',
  profileId: 'p',
  conversationId: 'primary',
  role: 'assistant',
  content: content,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('an answer shows what was checked, collapsed, and never the '
      'stored bookkeeping', (tester) async {
    const review = AdvisorReview(
      relevant: [
        ReviewVerdict(what: 'Biotin', why: 'Can make TSH read falsely low.'),
      ],
      uncertain: [],
      notRelevant: ['Magnesium', 'Zink'],
      notAssessed: [],
    );
    await _pump(
      tester,
      AdvisorMessageBubble(
        message: _answer(withReviewSection('Pause biotin first.', review)),
      ),
    );

    expect(find.textContaining('superhealth-review'), findsNothing);
    expect(
      find.textContaining('Pause biotin first.', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('Checked against all 3 supplements, medicines and findings'),
      findsOneWidget,
    );
    expect(find.textContaining('falsely low'), findsNothing);

    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();

    expect(
      find.text('• Biotin: Can make TSH read falsely low.'),
      findsOneWidget,
    );
    expect(find.text('Not relevant here: Magnesium, Zink'), findsOneWidget);
  });

  testWidgets('a review that missed items says so instead of implying they '
      'were judged', (tester) async {
    const review = AdvisorReview(
      relevant: [],
      uncertain: [],
      notRelevant: ['Zink'],
      notAssessed: ['Magnesium'],
    );
    await _pump(
      tester,
      AdvisorMessageBubble(
        message: _answer(withReviewSection('Answer.', review)),
      ),
    );

    expect(find.text('Checked 1 of 2 — 1 not assessed'), findsOneWidget);
    await tester.tap(find.byType(ExpansionTile));
    await tester.pumpAndSettle();
    expect(
      find.text('Not assessed — ask about these directly: Magnesium'),
      findsOneWidget,
    );
  });

  testWidgets('a finding reads in German when the app does', (tester) async {
    final finding = _biotinFindings().first;
    await _pump(
      tester,
      InteractionFindingCard(finding: finding),
      locale: const Locale('de'),
    );

    expect(
      find.text('Biotin kann viele Bluttests verfälschen'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Biotin vor Blutabnahmen pausieren'),
      findsOneWidget,
    );
    expect(find.textContaining('Wegen: Biotin'), findsOneWidget);
    expect(find.textContaining('Bis zu 10 mg pro Tag'), findsOneWidget);
    expect(find.textContaining('Quelle: FDA'), findsOneWidget);
  });

  testWidgets('the banner is labelled and opens every check', (tester) async {
    await _pump(tester, InteractionFindingsBanner(findings: _biotinFindings()));

    expect(find.text('1 automatic interaction check applies'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pumpAndSettle();

    expect(find.text('Automatic interaction checks'), findsOneWidget);
    expect(find.text('Biotin can distort many blood tests'), findsWidgets);
  });

  testWidgets('no findings, no banner', (tester) async {
    await _pump(tester, const InteractionFindingsBanner(findings: []));

    expect(find.byType(ListTile), findsNothing);
  });
}
