import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/plan_coverage_view.dart';

final _now = DateTime(2026, 9, 30);

LabPlan _plan(List<PlanCoverage>? coverage) => LabPlan(
  id: 'plan',
  profileId: 'p',
  title: 'Plan',
  createdAt: _now,
  updatedAt: _now,
  items: [
    LabPlanItem(
      id: 'item',
      planId: 'plan',
      biomarkerId: 'tsh',
      biomarkerName: 'TSH',
      tier: LabTier.core,
      priority: 1,
      rationale: 'Schilddrüse.',
      evidenceClass: EvidenceClass.guideline,
    ),
  ],
  coverage: coverage,
);

const _coverage = [
  PlanCoverage(
    id: 'exp:biotin',
    kind: 'substance',
    label: 'Biotin',
    verdict: PlanCoverageVerdict.addressed,
    biomarkerIds: ['tsh'],
    why: '72 Std. vorher pausieren.',
  ),
  PlanCoverage(
    id: 'med:levo',
    kind: 'medication',
    label: 'L-Thyroxin 50',
    verdict: PlanCoverageVerdict.notNeeded,
    why: 'Über TSH abgedeckt.',
  ),
  PlanCoverage(
    id: 'finding:biotin-streptavidin-immunoassay',
    kind: 'finding',
    label: 'Biotin can distort many blood tests',
    verdict: PlanCoverageVerdict.notConsidered,
  ),
  PlanCoverage(
    id: 'exp:product:mystery',
    kind: 'substance',
    label: 'Beauty Complex (contents not recorded)',
    verdict: PlanCoverageVerdict.notConsidered,
  ),
];

Future<void> _pump(
  WidgetTester tester,
  LabPlan plan, {
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
      home: Scaffold(
        body: SingleChildScrollView(child: PlanCoveragePanel(plan: plan)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gaps lead, in the summary and first in the list', (
    tester,
  ) async {
    await _pump(tester, _plan(_coverage));

    expect(
      find.text('2 of 4 accounted for — 2 not considered'),
      findsOneWidget,
    );
    await tester.tap(find.text('2 of 4 accounted for — 2 not considered'));
    await tester.pumpAndSettle();

    final gapsHeading = tester.getTopLeft(
      find.textContaining('Not considered'),
    );
    final addressedHeading = tester.getTopLeft(
      find.text('Addressed by the plan'),
    );
    expect(gapsHeading.dy, lessThan(addressedHeading.dy));
    // A verdict names the planned test by name, never by id.
    expect(
      find.text('• Biotin — TSH: 72 Std. vorher pausieren.'),
      findsOneWidget,
    );
    expect(find.text('• L-Thyroxin 50: Über TSH abgedeckt.'), findsOneWidget);
  });

  testWidgets('what the app itself wrote is translated', (tester) async {
    await _pump(tester, _plan(_coverage), locale: const Locale('de'));
    await tester.tap(find.textContaining('nicht berücksichtigt'));
    await tester.pumpAndSettle();

    // The rule title comes from the curated table in German, and the note
    // about unrecorded contents is the app's, so it is translated too.
    expect(
      find.textContaining('Beauty Complex (Inhalt nicht erfasst)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Biotin kann viele Bluttests verfälschen'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Biotin can distort many blood tests'),
      findsNothing,
    );
  });

  testWidgets('a complete plan says so', (tester) async {
    await _pump(
      tester,
      _plan(const [
        PlanCoverage(
          id: 'exp:biotin',
          kind: 'substance',
          label: 'Biotin',
          verdict: PlanCoverageVerdict.addressed,
          biomarkerIds: ['tsh'],
        ),
      ]),
    );

    expect(
      find.text('Accounted for all 1 items in your record'),
      findsOneWidget,
    );
  });

  testWidgets('an old plan and an empty record are told apart', (tester) async {
    await _pump(tester, _plan(null));
    expect(
      find.text('Made before plans recorded what they accounted for'),
      findsOneWidget,
    );

    await _pump(tester, _plan(const []));
    expect(
      find.text('Nothing current in your record needed accounting for'),
      findsOneWidget,
    );
  });
}
