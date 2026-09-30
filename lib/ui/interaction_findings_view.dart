import 'package:flutter/material.dart';

import '../ai/advisor_review.dart';
import '../analysis/interaction_findings.dart';
import '../app/app_localizations.dart';
import '../domain/interaction_rules.dart';
import '../domain/localized_text.dart';

/// Shared rendering of interaction findings and advisor reviews.
///
/// One vocabulary for every screen that shows a finding — the advisor, the
/// biomarker sheet — so a rule reads the same wherever it surfaces and a
/// change of wording cannot drift between them.

String _pickText(BuildContext context, LocalizedText text) =>
    AppLocalizations.of(context).pick(text.en, text.de);

String _pick(BuildContext context, String en, String de) =>
    AppLocalizations.of(context).pick(en, de);

String effectDirectionLabel(BuildContext context, EffectDirection direction) =>
    switch (direction) {
      EffectDirection.falselyLow => _pick(
        context,
        'can read falsely low',
        'kann falsch niedrig ausfallen',
      ),
      EffectDirection.falselyHigh => _pick(
        context,
        'can read falsely high',
        'kann falsch hoch ausfallen',
      ),
      EffectDirection.raises => _pick(context, 'raised', 'erhöht'),
      EffectDirection.lowers => _pick(context, 'lowered', 'gesenkt'),
      EffectDirection.masks => _pick(
        context,
        'can look normal despite a deficiency',
        'kann trotz Mangel normal aussehen',
      ),
      EffectDirection.unpredictable => _pick(
        context,
        'can shift either way',
        'kann sich in beide Richtungen verschieben',
      ),
    };

String _window(BuildContext context, Duration window) => window.inHours < 48
    ? _pick(context, '${window.inHours} h', '${window.inHours} Std.')
    : _pick(context, '${window.inDays} days', '${window.inDays} Tage');

String _number(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

String _day(DateTime at) {
  final local = at.toLocal();
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')}.${local.year}';
}

({Color container, Color onContainer, IconData icon}) _severityStyle(
  ColorScheme scheme,
  InteractionSeverity severity,
) => switch (severity) {
  InteractionSeverity.high => (
    container: scheme.errorContainer,
    onContainer: scheme.onErrorContainer,
    icon: Icons.report_outlined,
  ),
  InteractionSeverity.moderate => (
    container: scheme.tertiaryContainer,
    onContainer: scheme.onTertiaryContainer,
    icon: Icons.warning_amber_outlined,
  ),
  InteractionSeverity.low => (
    container: scheme.surfaceContainerHigh,
    onContainer: scheme.onSurface,
    icon: Icons.info_outline,
  ),
};

/// One finding, complete: what, why, which values, what to do, and the source.
class InteractionFindingCard extends StatelessWidget {
  const InteractionFindingCard({required this.finding, super.key});

  final InteractionFinding finding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = _severityStyle(theme.colorScheme, finding.severity);
    final rule = finding.rule;
    final subjects = finding.subjects.join(', ');
    final partners = finding.partners.join(', ');
    final amount = finding.dailyAmount;
    return Card(
      color: style.container,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: style.onContainer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(style.icon, color: style.onContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _pickText(context, rule.title),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: style.onContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (subjects.isNotEmpty)
                Text(
                  finding.scope == FindingScope.pastMeasurement
                      ? _pick(
                          context,
                          'Before the draw: $subjects',
                          'Vor der Blutabnahme: $subjects',
                        )
                      : _pick(
                          context,
                          'Because of: $subjects',
                          'Wegen: $subjects',
                        ),
                ),
              if (partners.isNotEmpty)
                Text(
                  _pick(
                    context,
                    'Together with: $partners',
                    'Zusammen mit: $partners',
                  ),
                ),
              if (amount != null && finding.amountUnit != null)
                Text(
                  _pick(
                    context,
                    'Up to ${_number(amount)} ${finding.amountUnit!.symbol} a day',
                    'Bis zu ${_number(amount)} ${finding.amountUnit!.symbol} pro Tag',
                  ),
                ),
              if (!finding.doseKnown)
                Text(
                  _pick(
                    context,
                    'Dose not recorded — the check assumes it could matter.',
                    'Dosis nicht erfasst – die Prüfung geht davon aus, dass '
                        'sie relevant sein kann.',
                  ),
                ),
              if (finding.spacing case final spacing?)
                Text(
                  _pick(
                    context,
                    'Taken closer than ${finding.rule.minimumSpacing!.inHours} h '
                        'apart on ${spacing.daysTooClose} of '
                        '${spacing.daysTogether} days.',
                    'An ${spacing.daysTooClose} von ${spacing.daysTogether} '
                        'Tagen mit weniger als '
                        '${finding.rule.minimumSpacing!.inHours} Std. Abstand '
                        'eingenommen.',
                  ),
                ),
              const SizedBox(height: 8),
              Text(_pickText(context, rule.explanation)),
              if (finding.measurements.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _pick(
                    context,
                    'Values that may be affected',
                    'Möglicherweise betroffene Werte',
                  ),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: style.onContainer,
                  ),
                ),
                for (final affected in finding.measurements.reversed.take(6))
                  Text(
                    '• ${affected.biomarker.displayName} '
                    '${_number(affected.measurement.value)} '
                    '${affected.measurement.unit}, '
                    '${_day(affected.measurement.takenAt)}'
                    '${affected.exposureBeforeDraw == null ? '' : _pick(context, ' — ${affected.exposureBeforeDraw!.inHours} h after exposure', ' — ${affected.exposureBeforeDraw!.inHours} Std. nach Einnahme')}'
                    ': ${effectDirectionLabel(context, affected.direction)}',
                  ),
                if (finding.measurements.length > 6)
                  Text(
                    _pick(
                      context,
                      '… and ${finding.measurements.length - 6} earlier',
                      '… und ${finding.measurements.length - 6} frühere',
                    ),
                  ),
              ] else if (rule.affects.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  _pick(context, 'Tests affected: ', 'Betroffene Tests: ') +
                      rule.affects
                          .map(
                            (test) =>
                                '${_pickText(context, test.concept.name)} '
                                '(${effectDirectionLabel(context, test.direction)})',
                          )
                          .join(', '),
                ),
              ],
              if (finding.window != null &&
                  finding.scope == FindingScope.current &&
                  rule.kind == InteractionKind.assayInterference)
                Text(
                  _pick(
                    context,
                    'Counts for ${_window(context, finding.window!)} before a '
                        'blood draw at this dose.',
                    'Wirkt bei dieser Dosis ${_window(context, finding.window!)} '
                        'vor einer Blutabnahme nach.',
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                _pickText(context, rule.advice),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                _pick(context, 'Source: ', 'Quelle: ') + rule.source,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: style.onContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The list of findings, in a sheet.
Future<void> showInteractionFindingsSheet(
  BuildContext context,
  List<InteractionFinding> findings, {
  String? title,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => FractionallySizedBox(
    heightFactor: 0.85,
    child: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            title ??
                _pick(
                  sheetContext,
                  'Automatic interaction checks',
                  'Automatische Wechselwirkungsprüfung',
                ),
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            _pick(
              sheetContext,
              'Computed from your record against a curated table of known '
                  'effects on lab values, interactions and upper intake '
                  'levels. The table is not exhaustive: no finding does not '
                  'mean no interaction.',
              'Aus deinem Profil berechnet, anhand einer kuratierten Tabelle '
                  'bekannter Einflüsse auf Laborwerte, Wechselwirkungen und '
                  'Höchstmengen. Die Tabelle ist nicht vollständig: Kein '
                  'Hinweis heißt nicht, dass keine Wechselwirkung besteht.',
            ),
            style: Theme.of(sheetContext).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          for (final finding in findings)
            InteractionFindingCard(finding: finding),
        ],
      ),
    ),
  ),
);

/// A labelled row that says how many checks apply and opens them.
///
/// Labelled, never an icon alone: a feature reachable only by an icon is one
/// nobody finds on a phone.
class InteractionFindingsBanner extends StatelessWidget {
  const InteractionFindingsBanner({required this.findings, super.key});

  final List<InteractionFinding> findings;

  @override
  Widget build(BuildContext context) {
    if (findings.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final style = _severityStyle(scheme, findings.first.severity);
    return Material(
      color: style.container,
      child: ListTile(
        dense: true,
        leading: Icon(style.icon, color: style.onContainer),
        title: Text(
          _pick(
            context,
            findings.length == 1
                ? '1 automatic interaction check applies'
                : '${findings.length} automatic interaction checks apply',
            findings.length == 1
                ? '1 automatischer Wechselwirkungshinweis'
                : '${findings.length} automatische Wechselwirkungshinweise',
          ),
          style: TextStyle(color: style.onContainer),
        ),
        subtitle: Text(
          _pickText(context, findings.first.rule.title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: style.onContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: style.onContainer),
        onTap: () => showInteractionFindingsSheet(context, findings),
      ),
    );
  }
}

/// What the advisor judged before answering, collapsed under the answer.
class AdvisorReviewPanel extends StatelessWidget {
  const AdvisorReviewPanel({required this.review, super.key});

  final AdvisorReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = review.assessedCount + review.notAssessed.length;
    final title = review.complete
        ? _pick(
            context,
            'Checked against all $total supplements, medicines and findings',
            'Gegen alle $total Präparate, Medikamente und Hinweise geprüft',
          )
        : _pick(
            context,
            'Checked ${review.assessedCount} of $total — '
                '${review.notAssessed.length} not assessed',
            '${review.assessedCount} von $total geprüft — '
                '${review.notAssessed.length} nicht beurteilt',
          );
    final summary = [
      if (review.relevant.isNotEmpty)
        _pick(
          context,
          '${review.relevant.length} relevant',
          '${review.relevant.length} relevant',
        ),
      if (review.uncertain.isNotEmpty)
        _pick(
          context,
          '${review.uncertain.length} uncertain',
          '${review.uncertain.length} unklar',
        ),
    ].join(' · ');
    Widget verdicts(String heading, List<ReviewVerdict> items) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(heading, style: theme.textTheme.labelLarge),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                item.why.isEmpty
                    ? '• ${item.what}'
                    : '• ${item.what}: ${item.why}',
              ),
            ),
        ],
      ),
    );
    // Transparent material: the tile sits on the bubble's coloured box, which
    // would otherwise swallow its ink and its tap feedback.
    return Material(
      type: MaterialType.transparency,
      child: Theme(
        // The tile's own dividers would draw lines through the chat bubble.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          leading: Icon(
            review.complete ? Icons.fact_check_outlined : Icons.rule_outlined,
            color: review.complete ? scheme.primary : scheme.error,
          ),
          title: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: review.complete ? null : scheme.error,
            ),
          ),
          subtitle: summary.isEmpty ? null : Text(summary),
          children: [
            if (review.relevant.isNotEmpty)
              verdicts(_pick(context, 'Relevant', 'Relevant'), review.relevant),
            if (review.uncertain.isNotEmpty)
              verdicts(_pick(context, 'Uncertain', 'Unklar'), review.uncertain),
            if (review.notRelevant.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _pick(
                        context,
                        'Not relevant here: ',
                        'Hier nicht relevant: ',
                      ) +
                      review.notRelevant.join(', '),
                ),
              ),
            if (review.notAssessed.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _pick(
                        context,
                        'Not assessed — ask about these directly: ',
                        'Nicht beurteilt – frage gezielt danach: ',
                      ) +
                      review.notAssessed.join(', '),
                  style: TextStyle(color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
