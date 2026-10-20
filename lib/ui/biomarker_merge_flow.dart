import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../data/health_repository.dart';
import '../domain/entities.dart';
import 'common.dart';

String _mergeText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// The catalog entries [source] can be merged into, those whose name differs
/// from it only in spelling first.
///
/// "Transferrin-Sättigung" and "Transferrinsättigung" are the case this
/// exists for: the duplicate the person came to remove should not be one
/// entry among two hundred.
List<Biomarker> mergeTargetCandidates(
  Biomarker source,
  List<Biomarker> catalog,
) {
  String fold(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß]+'), '');
  final spellings = {
    for (final name in [
      source.displayName,
      source.canonicalName,
      ...source.synonyms,
    ])
      fold(name),
  }..remove('');
  bool spelledAlike(Biomarker item) => [
    item.displayName,
    item.canonicalName,
    ...item.synonyms,
  ].any((name) => spellings.contains(fold(name)));
  final candidates = [
    for (final item in catalog)
      if (item.id != source.id &&
          !item.deleted &&
          !item.isTemporary &&
          !item.isCalculated)
        item,
  ];
  return [
    ...candidates.where(spelledAlike),
    ...candidates.where((item) => !spelledAlike(item)),
  ];
}

/// Merges [source] into a catalog biomarker the person picks, after saying
/// what will move. Returns null when nothing was merged.
///
/// One flow for the detail sheet and the temporary-entry screen, so the two
/// cannot drift into confirming different things.
Future<BiomarkerMergeResult?> mergeBiomarkerFlow(
  BuildContext context,
  AppController controller,
  Biomarker source,
) async {
  final candidates = mergeTargetCandidates(source, controller.biomarkers);
  if (candidates.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _mergeText(
            context,
            'There is no other catalog test to merge into.',
            'Es gibt keinen anderen Katalogtest zum Zusammenführen.',
          ),
        ),
      ),
    );
    return null;
  }
  final targetId = await _pickTarget(context, source, candidates);
  if (targetId == null || !context.mounted) return null;
  final target = candidates.firstWhere((item) => item.id == targetId);
  try {
    final preview = await controller.previewBiomarkerMerge(
      sourceBiomarkerId: source.id,
      targetBiomarkerId: target.id,
    );
    if (!context.mounted) return null;
    final confirmed = await showConfirmAction(
      context,
      title: _mergeText(
        context,
        'Merge into “${target.displayName}”?',
        'Mit „${target.displayName}“ zusammenführen?',
      ),
      message: _mergeSummary(context, source, target, preview),
      confirmLabel: _mergeText(context, 'Merge', 'Zusammenführen'),
    );
    if (!confirmed || !context.mounted) return null;
    final result = await controller.mergeBiomarker(
      sourceBiomarkerId: source.id,
      targetBiomarkerId: target.id,
    );
    if (context.mounted) {
      final count = result.movedMeasurements;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _mergeText(
              context,
              '${count == 1 ? '1 result' : '$count results'} now under '
                  '“${target.displayName}”.',
              '${count == 1 ? '1 Ergebnis' : '$count Ergebnisse'} jetzt unter '
                  '„${target.displayName}“.',
            ),
          ),
        ),
      );
    }
    return result;
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
    return null;
  }
}

String _mergeSummary(
  BuildContext context,
  Biomarker source,
  Biomarker target,
  BiomarkerMergePreview preview,
) {
  final strings = AppLocalizations.of(context);
  final count = preview.measurements;
  final documents = preview.documents;
  final from = source.displayName;
  final into = target.displayName;
  return [
    if (count == 0)
      strings.pick(
        '“$from” has no stored results.',
        '„$from“ hat keine gespeicherten Ergebnisse.',
      )
    else ...[
      strings.pick(
        '${count == 1 ? '1 result' : '$count results'}'
            '${documents == 0 ? '' : ' from ${documents == 1 ? '1 lab report' : '$documents lab reports'}'}'
            ' will be filed under “$into”. Each keeps its link to the report, '
            'page and source row.',
        '${count == 1 ? '1 Ergebnis' : '$count Ergebnisse'}'
            '${documents == 0 ? '' : ' aus ${documents == 1 ? '1 Laborbericht' : '$documents Laborberichten'}'}'
            ' ${count == 1 ? 'wird' : 'werden'} „$into“ zugeordnet. Die '
            'Verknüpfung zu Bericht, Seite und Originalzeile bleibt erhalten.',
      ),
      if (preview.profiles > 1)
        strings.pick(
          'The catalog is shared, so this includes results from '
              '${preview.profiles} profiles.',
          'Der Katalog ist gemeinsam, das betrifft Ergebnisse aus '
              '${preview.profiles} Profilen.',
        ),
    ],
    if (preview.unconvertedMeasurements > 0)
      strings.pick(
        '${preview.unconvertedMeasurements == 1 ? '1 result is' : '${preview.unconvertedMeasurements} results are'}'
            ' in a unit that cannot be converted to ${preview.targetUnit}. '
            'They stay as reported but cannot join the trend line of “$into”.',
        '${preview.unconvertedMeasurements == 1 ? '1 Ergebnis hat' : '${preview.unconvertedMeasurements} Ergebnisse haben'}'
            ' eine Einheit, die sich nicht in ${preview.targetUnit} umrechnen '
            'lässt. Sie bleiben wie berichtet erhalten, erscheinen aber nicht '
            'in der Verlaufskurve von „$into“.',
      ),
    strings.pick(
      'Reference ranges, targets, lists, packages and plans move with them. '
          '“$from” leaves the catalog and stays a synonym of “$into”, so a '
          'later report that prints it is matched to “$into”. This cannot be '
          'undone in the app.',
      'Referenzbereiche, Ziele, Listen, Pakete und Pläne werden mit '
          'übertragen. „$from“ verschwindet aus dem Katalog und bleibt als '
          'Synonym von „$into“ erhalten, damit spätere Berichte mit diesem '
          'Namen „$into“ zugeordnet werden. Das lässt sich in der App nicht '
          'rückgängig machen.',
    ),
  ].join('\n\n');
}

Future<String?> _pickTarget(
  BuildContext context,
  Biomarker source,
  List<Biomarker> candidates,
) async {
  final search = TextEditingController();
  String? selectedId;
  final chosenId = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          _mergeText(
            context,
            'Merge “${source.displayName}”',
            '„${source.displayName}“ zusammenführen',
          ),
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _mergeText(
                  context,
                  'Choose the test that stays. The results of '
                      '“${source.displayName}” move to it.',
                  'Wähle den Test, der bleibt. Die Ergebnisse von '
                      '„${source.displayName}“ werden ihm zugeordnet.',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _mergeText(
                    context,
                    'Search the catalog',
                    'Katalog durchsuchen',
                  ),
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 260,
                child: _MergeTargetResults(
                  catalog: candidates,
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
            child: Text(_mergeText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: selectedId == null
                ? null
                : () => Navigator.pop(dialogContext, selectedId),
            child: Text(_mergeText(context, 'Continue', 'Weiter')),
          ),
        ],
      ),
    ),
  );
  search.dispose();
  return chosenId;
}

class _MergeTargetResults extends StatelessWidget {
  const _MergeTargetResults({
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
          _mergeText(
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
        // The unit, because two entries for one test often differ only in it,
        // and that decides which trend line the results can join.
        final detail = [
          if (item.category.isNotEmpty) item.category,
          if (item.defaultUnit.isNotEmpty) item.defaultUnit,
        ].join(' · ');
        return ListTile(
          selected: item.id == selectedId,
          title: Text(item.displayName),
          subtitle: detail.isEmpty ? null : Text(detail),
          trailing: item.id == selectedId
              ? const Icon(Icons.check_circle)
              : const Icon(Icons.circle_outlined),
          onTap: () => onSelected(item.id),
        );
      },
    );
  }
}
