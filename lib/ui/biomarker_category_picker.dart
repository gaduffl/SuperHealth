import 'package:flutter/material.dart';

import '../app/app_localizations.dart';
import 'biomarker_category_localization.dart';

String _pickerText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// Lets the owner choose a biomarker's category.
///
/// Offers no category, every built-in category under its translated name,
/// the custom categories already in use, and a field for a new one. Returns
/// the value to store (`''` for none), or null when the dialog was dismissed.
Future<String?> showBiomarkerCategoryPicker(
  BuildContext context, {
  required String current,
  Iterable<String> categoriesInUse = const [],
}) {
  final languageCode = Localizations.localeOf(context).languageCode;
  final selected = normalizeBiomarkerCategory(current);
  final options = biomarkerCategoryOptions(
    languageCode: languageCode,
    categoriesInUse: [...categoriesInUse, selected],
  );
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(_pickerText(context, 'Category', 'Kategorie')),
      children: [
        _CategoryOption(
          label: _pickerText(context, 'No category', 'Ohne Kategorie'),
          selected: selected.isEmpty,
          italic: true,
          onTap: () => Navigator.pop(dialogContext, ''),
        ),
        for (final id in options)
          _CategoryOption(
            label: biomarkerCategoryLabel(id, languageCode),
            selected: id == selected,
            onTap: () => Navigator.pop(dialogContext, id),
          ),
        const Divider(),
        SimpleDialogOption(
          onPressed: () async {
            final typed = await _askCustomCategory(dialogContext);
            if (typed != null && dialogContext.mounted) {
              Navigator.pop(dialogContext, normalizeBiomarkerCategory(typed));
            }
          },
          child: Row(
            children: [
              const Icon(Icons.add, size: 20),
              const SizedBox(width: 12),
              Text(_pickerText(context, 'Custom…', 'Eigene…')),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Built-in categories sorted by their label, then custom ones in use.
@visibleForTesting
List<String> biomarkerCategoryOptions({
  required String languageCode,
  Iterable<String> categoriesInUse = const [],
}) {
  int byLabel(String a, String b) => biomarkerCategoryLabel(a, languageCode)
      .toLowerCase()
      .compareTo(biomarkerCategoryLabel(b, languageCode).toLowerCase());
  final known = knownBiomarkerCategoryIds.toList()..sort(byLabel);
  final custom = biomarkerCategoriesInUse(
    categoriesInUse,
  ).where((id) => !known.contains(id)).toList()..sort(byLabel);
  return [...known, ...custom];
}

Future<String?> _askCustomCategory(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(_pickerText(context, 'Custom category', 'Eigene Kategorie')),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: _pickerText(context, 'Name', 'Name'),
        ),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(_pickerText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(_pickerText(context, 'Use', 'Übernehmen')),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == null || result.trim().isEmpty) return null;
  return result;
}

class _CategoryOption extends StatelessWidget {
  const _CategoryOption({
    required this.label,
    required this.selected,
    required this.onTap,
    this.italic = false,
  });

  final String label;
  final bool selected;
  final bool italic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SimpleDialogOption(
    onPressed: onTap,
    child: Row(
      children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          size: 20,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: italic ? const TextStyle(fontStyle: FontStyle.italic) : null,
          ),
        ),
      ],
    ),
  );
}
