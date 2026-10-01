import 'package:flutter/material.dart';

import '../app/app_localizations.dart';
import '../domain/entities.dart';
import '../domain/interaction_rules.dart';

/// What a lab plan did about everything current in the record.
///
/// Gaps lead and are drawn in the error colour: an item nobody judged looks
/// exactly like one judged irrelevant unless the screen says otherwise. A plan
/// made before coverage was recorded says so rather than showing nothing,
/// which would read as "nothing to account for".
class PlanCoveragePanel extends StatelessWidget {
  const PlanCoveragePanel({required this.plan, super.key});

  final LabPlan plan;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final coverage = plan.coverage;
    if (coverage == null || coverage.isEmpty) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.rule_outlined, color: scheme.outline),
        title: Text(
          coverage == null
              ? strings.pick(
                  'Made before plans recorded what they accounted for',
                  'Erstellt, bevor Pläne festhielten, was sie berücksichtigen',
                )
              : strings.pick(
                  'Nothing current in your record needed accounting for',
                  'Nichts Aktuelles in deinen Daten musste berücksichtigt '
                      'werden',
                ),
        ),
      );
    }
    final names = {
      for (final item in plan.items) item.biomarkerId: item.biomarkerName,
    };
    final gaps = plan.notConsidered;
    final addressed = [
      for (final entry in coverage)
        if (entry.verdict == PlanCoverageVerdict.addressed) entry,
    ];
    final notNeeded = [
      for (final entry in coverage)
        if (entry.verdict == PlanCoverageVerdict.notNeeded) entry,
    ];
    final total = coverage.length;
    final complete = gaps.isEmpty;

    Widget group(String heading, List<String> lines, {Color? color}) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            heading,
            style: theme.textTheme.labelLarge?.copyWith(color: color),
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '• $line',
                style: color == null ? null : TextStyle(color: color),
              ),
            ),
        ],
      ),
    );

    String line(PlanCoverage entry) {
      final label = planCoverageLabel(strings, entry);
      final tests = [for (final id in entry.biomarkerIds) names[id] ?? id];
      final head = tests.isEmpty ? label : '$label — ${tests.join(', ')}';
      return entry.why.isEmpty ? head : '$head: ${entry.why}';
    }

    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      leading: Icon(
        complete ? Icons.fact_check_outlined : Icons.rule_outlined,
        color: complete ? scheme.primary : scheme.error,
      ),
      title: Text(
        complete
            ? strings.pick(
                'Accounted for all $total items in your record',
                'Alle $total Punkte deiner Daten berücksichtigt',
              )
            : strings.pick(
                '${total - gaps.length} of $total accounted for — '
                    '${gaps.length} not considered',
                '${total - gaps.length} von $total berücksichtigt — '
                    '${gaps.length} nicht berücksichtigt',
              ),
        style: complete ? null : TextStyle(color: scheme.error),
      ),
      subtitle: Text(
        strings.pick(
          '${addressed.length} by the plan · ${notNeeded.length} need no test',
          '${addressed.length} im Plan · ${notNeeded.length} ohne nötigen Test',
        ),
      ),
      children: [
        if (gaps.isNotEmpty)
          group(
            strings.pick(
              'Not considered — ask about these before the visit',
              'Nicht berücksichtigt – vor dem Termin gezielt nachfragen',
            ),
            [for (final entry in gaps) planCoverageLabel(strings, entry)],
            color: scheme.error,
          ),
        if (addressed.isNotEmpty)
          group(
            strings.pick('Addressed by the plan', 'Im Plan berücksichtigt'),
            [for (final entry in addressed) line(entry)],
          ),
        if (notNeeded.isNotEmpty)
          group(strings.pick('No test needed', 'Kein Test nötig'), [
            for (final entry in notNeeded) line(entry),
          ]),
      ],
    );
  }
}

/// A coverage item named in the reader's language.
///
/// The stored label is the name at the time the plan was made — a product, a
/// medicine, a condition the person typed, which have no translation. What
/// the app itself wrote is translated: a finding's rule title, the note that a
/// product's contents were never recorded, and the overdue marker.
String planCoverageLabel(AppLocalizations strings, PlanCoverage entry) {
  var label = entry.label;
  const unrecorded = ' (contents not recorded)';
  if (label.endsWith(unrecorded)) {
    label = strings.pick(
      label,
      '${label.substring(0, label.length - unrecorded.length)} '
      '(Inhalt nicht erfasst)',
    );
  }
  if (entry.kind == 'finding' && entry.id.startsWith('finding:')) {
    final ruleId = entry.id.substring('finding:'.length).split('@').first;
    final rule = interactionRules
        .where((rule) => rule.id == ruleId)
        .firstOrNull;
    if (rule != null && label.startsWith(rule.title.en)) {
      label = strings.pick(
        label,
        '${rule.title.de}${label.substring(rule.title.en.length)}',
      );
    }
  }
  if (entry.kind == 'overdue_test') {
    label = strings.pick(
      '$label (overdue on a list)',
      '$label (auf einer Liste überfällig)',
    );
  }
  return label;
}
