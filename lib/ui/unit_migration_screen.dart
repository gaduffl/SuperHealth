import 'package:flutter/material.dart';

import '../app/app_localizations.dart';
import '../data/unit_migration_planner.dart';
import 'common.dart';
import 'design.dart';

/// Shows what the unit and substance clean-up would change, and applies only
/// what the owner accepts.
///
/// Mechanical corrections are pre-selected; anything needing judgement starts
/// unselected, so doing nothing is always the safe outcome.
class UnitMigrationScreen extends StatefulWidget {
  const UnitMigrationScreen({
    required this.planner,
    required this.plan,
    super.key,
  });

  final UnitMigrationPlanner planner;
  final UnitMigrationPlan plan;

  @override
  State<UnitMigrationScreen> createState() => _UnitMigrationScreenState();
}

class _UnitMigrationScreenState extends State<UnitMigrationScreen> {
  late final Set<UnitMigrationProposal> _selected = {
    ...widget.plan.automatic.where(
      (proposal) => proposal.reason != UnitMigrationReason.unknownUnit,
    ),
  };
  var _applying = false;

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      final applied = await widget.planner.apply(_selected.toList());
      if (!mounted) return;
      Navigator.of(context).pop(applied);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _applying = false);
      await showAppError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final plan = widget.plan;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.pick('Tidy up units', 'Einheiten aufräumen')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.pick(
                    'One unit, one spelling',
                    'Eine Einheit, eine Schreibweise',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  strings.pick(
                    'The same unit written two ways splits every chart and '
                        'correlation that groups by it. Nothing is changed '
                        'until you apply, and nothing you leave unticked is '
                        'touched.',
                    'Dieselbe Einheit in zwei Schreibweisen teilt jede '
                        'Auswertung, die danach gruppiert. Es wird nichts '
                        'geändert, bis du bestätigst, und nichts ohne Haken '
                        'wird angefasst.',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (plan.automatic.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              title: strings.pick('Safe corrections', 'Sichere Korrekturen'),
              subtitle: strings.pick(
                'The same thing written another way.',
                'Dasselbe, nur anders geschrieben.',
              ),
              proposals: plan.automatic,
              selected: _selected,
              onChanged: (proposal, value) => setState(() {
                value ? _selected.add(proposal) : _selected.remove(proposal);
              }),
            ),
          ],
          if (plan.needsReview.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Section(
              title: strings.pick('Your call', 'Deine Entscheidung'),
              subtitle: strings.pick(
                'These need to know what you meant, so they start unticked.',
                'Hier zählt deine Absicht, daher ohne Haken vorausgewählt.',
              ),
              proposals: plan.needsReview,
              selected: _selected,
              onChanged: (proposal, value) => setState(() {
                value ? _selected.add(proposal) : _selected.remove(proposal);
              }),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _applying || _selected.isEmpty ? null : _apply,
            child: Text(
              _applying
                  ? strings.pick('Applying…', 'Wird angewendet…')
                  : strings.pick(
                      'Apply ${_selected.length} change(s)',
                      '${_selected.length} Änderung(en) anwenden',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.proposals,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<UnitMigrationProposal> proposals;
  final Set<UnitMigrationProposal> selected;
  final void Function(UnitMigrationProposal, bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          for (final proposal in proposals)
            CheckboxListTile(
              value: selected.contains(proposal),
              onChanged: proposal.reason == UnitMigrationReason.unknownUnit
                  ? null
                  : (value) => onChanged(proposal, value ?? false),
              title: Text(proposal.field),
              subtitle: Text(
                proposal.reason == UnitMigrationReason.unknownUnit
                    ? strings.pick(
                        '“${proposal.before}” is not a unit the app knows. '
                            'Edit the entry to fix it.',
                        '„${proposal.before}“ ist keine bekannte Einheit. '
                            'Bearbeite den Eintrag, um das zu ändern.',
                      )
                    : '${proposal.before}  →  ${proposal.after}',
              ),
              isThreeLine: proposal.reason == UnitMigrationReason.unknownUnit,
            ),
        ],
      ),
    );
  }
}
