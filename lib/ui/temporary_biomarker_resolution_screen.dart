import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
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
                                    : () => _merge(
                                        context,
                                        controller,
                                        biomarker,
                                        canonical,
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

  Future<void> _merge(
    BuildContext context,
    AppController controller,
    Biomarker temporary,
    List<Biomarker> canonical,
  ) async {
    final search = TextEditingController();
    String? selectedId;
    final chosenId = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            _temporaryText(
              context,
              'Merge ${temporary.displayName}',
              '${temporary.displayName} zusammenführen',
            ),
          ),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _temporaryText(
                    context,
                    'All results, targets, lists, plans, and reference ranges will be reassigned in one transaction. Conflicting target and list links are retained as tombstones.',
                    'Alle Ergebnisse, Ziele, Listen, Pläne und Referenzbereiche werden in einer Transaktion neu zugeordnet. Konfliktierende Verknüpfungen bleiben als Löschmarker erhalten.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _temporaryText(
                      context,
                      'Search canonical biomarkers',
                      'Kanonische Biomarker durchsuchen',
                    ),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 260,
                  child: _CanonicalSearchResults(
                    catalog: canonical,
                    query: search.text,
                    selectedId: selectedId,
                    onSelected: (id) => setState(() => selectedId = id),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_temporaryText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton(
              onPressed: selectedId == null
                  ? null
                  : () => Navigator.pop(dialogContext, selectedId),
              child: Text(_temporaryText(context, 'Merge', 'Zusammenführen')),
            ),
          ],
        ),
      ),
    );
    search.dispose();
    if (chosenId == null || !context.mounted) return;
    try {
      final result = await controller.repository.mergeTemporaryBiomarker(
        temporaryBiomarkerId: temporary.id,
        canonicalBiomarkerId: chosenId,
      );
      await controller.refreshActiveData();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _temporaryText(
                context,
                'Merged ${result.movedMeasurements} result(s), ${result.movedRanges} range(s), and ${result.movedListItems} list item(s).',
                '${result.movedMeasurements} Ergebnis(se), ${result.movedRanges} Bereich(e) und ${result.movedListItems} Listeneintrag/-einträge zusammengeführt.',
              ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
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
      await controller.repository.makeTemporaryBiomarkerPermanent(biomarker.id);
      await controller.refreshActiveData();
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

class _CanonicalSearchResults extends StatelessWidget {
  const _CanonicalSearchResults({
    required this.catalog,
    required this.query,
    required this.selectedId,
    required this.onSelected,
  });

  final List<Biomarker> catalog;
  final String query;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final matches = catalog
        .where((item) {
          return needle.isEmpty ||
              item.displayName.toLowerCase().contains(needle) ||
              item.canonicalName.toLowerCase().contains(needle) ||
              item.synonyms.any(
                (synonym) => synonym.toLowerCase().contains(needle),
              );
        })
        .take(100)
        .toList(growable: false);
    if (matches.isEmpty) {
      return Center(
        child: Text(
          _temporaryText(
            context,
            'No matching biomarkers.',
            'Keine passenden Biomarker.',
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final item = matches[index];
        return ListTile(
          selected: item.id == selectedId,
          title: Text(item.displayName),
          subtitle: Text(item.canonicalName),
          trailing: item.id == selectedId
              ? const Icon(Icons.check_circle)
              : const Icon(Icons.circle_outlined),
          onTap: () => onSelected(item.id),
        );
      },
    );
  }
}
