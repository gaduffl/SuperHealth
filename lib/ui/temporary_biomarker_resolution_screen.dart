import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'biomarker_merge_flow.dart';
import 'common.dart';

String _temporaryText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

class TemporaryBiomarkerResolutionScreen extends StatelessWidget {
  const TemporaryBiomarkerResolutionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final temporary = controller.biomarkers
        .where((biomarker) => biomarker.isTemporary)
        .toList(growable: false);
    final canonical = controller.biomarkers
        .where((biomarker) => !biomarker.isTemporary)
        .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _temporaryText(
            context,
            'Resolve temporary biomarkers',
            'Temporäre Biomarker zuordnen',
          ),
        ),
      ),
      body: temporary.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _temporaryText(
                    context,
                    'There are no temporary biomarker mappings to resolve.',
                    'Es gibt keine temporären Biomarkerzuordnungen.',
                  ),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text(
                  _temporaryText(
                    context,
                    'Temporary entries are created while importing a lab report. Merge each one into a matching catalog biomarker or keep its history and make it permanent.',
                    'Temporäre Einträge entstehen beim Import eines Laborberichts. Führe sie mit einem passenden Katalog-Biomarker zusammen oder behalte den Verlauf und mache sie dauerhaft.',
                  ),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                for (final biomarker in temporary)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            biomarker.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (biomarker.defaultUnit.isNotEmpty ||
                              biomarker.category.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                [
                                  if (biomarker.category.isNotEmpty)
                                    biomarker.category,
                                  if (biomarker.defaultUnit.isNotEmpty)
                                    biomarker.defaultUnit,
                                ].join(' · '),
                              ),
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            alignment: WrapAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: canonical.isEmpty
                                    ? null
                                    : () => mergeBiomarkerFlow(
                                        context,
                                        controller,
                                        biomarker,
                                      ),
                                icon: const Icon(Icons.merge_type_outlined),
                                label: Text(
                                  _temporaryText(
                                    context,
                                    'Merge into catalog',
                                    'Mit Katalog zusammenführen',
                                  ),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () => _makePermanent(
                                  context,
                                  controller,
                                  biomarker,
                                ),
                                icon: const Icon(Icons.verified_outlined),
                                label: Text(
                                  _temporaryText(
                                    context,
                                    'Make permanent',
                                    'Dauerhaft übernehmen',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _makePermanent(
    BuildContext context,
    AppController controller,
    Biomarker biomarker,
  ) async {
    final confirmed = await showConfirmAction(
      context,
      title: _temporaryText(
        context,
        'Make ${biomarker.displayName} permanent?',
        '${biomarker.displayName} dauerhaft übernehmen?',
      ),
      message: _temporaryText(
        context,
        'Its imported results and reference data remain unchanged.',
        'Importierte Ergebnisse und Referenzdaten bleiben unverändert.',
      ),
      confirmLabel: _temporaryText(
        context,
        'Make permanent',
        'Dauerhaft übernehmen',
      ),
    );
    if (!confirmed || !context.mounted) return;
    try {
      await controller.makeTemporaryBiomarkerPermanent(biomarker.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _temporaryText(
                context,
                'Biomarker is now permanent.',
                'Der Biomarker ist jetzt dauerhaft.',
              ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }
}
