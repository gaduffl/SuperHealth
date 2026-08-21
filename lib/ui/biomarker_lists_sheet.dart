import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';

String _listsText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

Future<void> showBiomarkerListsSheet(
  BuildContext context,
  AppController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.92,
    child: _BiomarkerListsSheet(controller: controller),
  ),
);

class _BiomarkerListsSheet extends StatelessWidget {
  const _BiomarkerListsSheet({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _listsText(context, 'Biomarker lists', 'Biomarkerlisten'),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      _listsText(
                        context,
                        'Reusable checklists with profile-specific retest intervals.',
                        'Wiederverwendbare Checklisten mit profilspezifischen Wiederholungsintervallen.',
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _editList(context),
                icon: const Icon(Icons.add),
                label: Text(_listsText(context, 'List', 'Liste')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (controller.biomarkerLists.isEmpty)
            EmptyState(
              icon: Icons.checklist_outlined,
              title: _listsText(
                context,
                'No saved lists',
                'Keine gespeicherten Listen',
              ),
              message: _listsText(
                context,
                'Create a list such as Annual baseline or Cardiometabolic follow-up.',
                'Erstelle beispielsweise eine jährliche Basisliste oder eine kardiometabolische Verlaufsliste.',
              ),
            )
          else
            for (final list in controller.biomarkerLists)
              _ListCard(
                list: list,
                controller: controller,
                onEdit: () => _editList(context, existing: list),
                onDelete: () => _deleteList(context, list),
                onAddItem: () => _editItem(context, list),
                onAddPackage: () => _addPackage(context, list),
                onEditItem: (item) => _editItem(context, list, existing: item),
              ),
        ],
      ),
    ),
  );

  Future<void> _editList(
    BuildContext context, {
    BiomarkerList? existing,
  }) async {
    final name = TextEditingController(text: existing?.name);
    final description = TextEditingController(text: existing?.description);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null
              ? _listsText(
                  context,
                  'Create biomarker list',
                  'Biomarkerliste erstellen',
                )
              : _listsText(context, 'Edit list', 'Liste bearbeiten'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _listsText(context, 'Name *', 'Name *'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _listsText(context, 'Description', 'Beschreibung'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_listsText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_listsText(context, 'Save', 'Speichern')),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    try {
      if (save == true && name.text.trim().isNotEmpty) {
        if (existing == null) {
          await controller.createBiomarkerList(
            name: name.text,
            description: description.text,
          );
        } else {
          await controller.updateBiomarkerList(
            BiomarkerList(
              id: existing.id,
              profileId: existing.profileId,
              name: name.text,
              description: description.text,
              createdAt: existing.createdAt,
              updatedAt: DateTime.now(),
              items: existing.items,
            ),
          );
        }
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    } finally {
      name.dispose();
      description.dispose();
    }
  }

  Future<void> _editItem(
    BuildContext context,
    BiomarkerList list, {
    BiomarkerListItem? existing,
  }) async {
    if (controller.biomarkers.isEmpty) return;
    var biomarkerId = existing?.biomarkerId;
    biomarkerId ??= controller.biomarkers
        .where(
          (item) =>
              !list.items.any((listItem) => listItem.biomarkerId == item.id),
        )
        .firstOrNull
        ?.id;
    if (biomarkerId == null) {
      await showAppError(
        context,
        _listsText(
          context,
          'Every catalog biomarker is already listed.',
          'Jeder Biomarker aus dem Katalog ist bereits enthalten.',
        ),
      );
      return;
    }
    final interval = TextEditingController(
      text: existing?.dueIntervalDays?.toString() ?? '365',
    );
    final notes = TextEditingController(text: existing?.notes);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            existing == null
                ? _listsText(context, 'Add to list', 'Zur Liste hinzufügen')
                : _listsText(
                    context,
                    'Edit list item',
                    'Listeneintrag bearbeiten',
                  ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: biomarkerId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _listsText(context, 'Biomarker', 'Biomarker'),
                ),
                items: [
                  for (final biomarker in controller.biomarkers)
                    if (biomarker.id == existing?.biomarkerId ||
                        !list.items.any(
                          (item) => item.biomarkerId == biomarker.id,
                        ))
                      DropdownMenuItem(
                        value: biomarker.id,
                        child: Text(biomarker.displayName),
                      ),
                ],
                onChanged: (value) => setState(() => biomarkerId = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: interval,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _listsText(
                    context,
                    'Retest interval (days)',
                    'Wiederholungsintervall (Tage)',
                  ),
                  helperText: _listsText(
                    context,
                    'Leave empty to keep the item without due alerts.',
                    'Leer lassen, um den Eintrag ohne Fälligkeitshinweise zu behalten.',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _listsText(context, 'Notes', 'Notizen'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_listsText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_listsText(context, 'Save', 'Speichern')),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    try {
      if (save == true && biomarkerId != null) {
        final parsed = interval.text.trim().isEmpty
            ? null
            : int.tryParse(interval.text.trim());
        if (parsed != null && parsed <= 0) {
          throw StateError(
            _listsText(
              context,
              'The retest interval must be a positive number.',
              'Das Wiederholungsintervall muss positiv sein.',
            ),
          );
        }
        final biomarker = controller.biomarkers.firstWhere(
          (item) => item.id == biomarkerId,
        );
        if (existing != null && existing.biomarkerId != biomarker.id) {
          await controller.removeBiomarkerListItem(existing);
        }
        final currentList = controller.biomarkerLists.firstWhere(
          (item) => item.id == list.id,
          orElse: () => list,
        );
        await controller.setBiomarkerListItem(
          list: currentList,
          biomarker: biomarker,
          dueIntervalDays: parsed,
          notes: notes.text,
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    } finally {
      interval.dispose();
      notes.dispose();
    }
  }

  Future<void> _addPackage(BuildContext context, BiomarkerList list) async {
    final package = await showDialog<BiomarkerPackage>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(_listsText(context, 'Add a package', 'Paket hinzufügen')),
        children: [
          for (final item in controller.biomarkerPackages)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, item),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                subtitle: Text(
                  _listsText(
                    context,
                    '${(controller.biomarkerPackageMembers[item.id] ?? const <String>{}).length} test(s) will be added individually',
                    '${(controller.biomarkerPackageMembers[item.id] ?? const <String>{}).length} Test(s) werden einzeln hinzugefügt',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (package == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Resolved before the await, so the context is not read across the gap.
    String message(int added, int present) => _listsText(
      context,
      added == 0
          ? 'Every test in ${package.name} was already on this list.'
          : '$added test(s) added from ${package.name}'
                '${present == 0 ? '.' : ', $present already there.'}',
      added == 0
          ? 'Alle Tests aus ${package.name} waren bereits auf dieser Liste.'
          : '$added Test(s) aus ${package.name} hinzugefügt'
                '${present == 0 ? '.' : ', $present bereits vorhanden.'}',
    );
    try {
      final currentList = controller.biomarkerLists.firstWhere(
        (item) => item.id == list.id,
        orElse: () => list,
      );
      final result = await controller.addPackageToBiomarkerList(
        list: currentList,
        package: package,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(message(result.added, result.alreadyPresent))),
      );
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  Future<void> _deleteList(BuildContext context, BiomarkerList list) async {
    final confirmed = await showConfirmAction(
      context,
      title: _listsText(
        context,
        'Delete ${list.name}?',
        '${list.name} löschen?',
      ),
      message: _listsText(
        context,
        'This removes the list and its retest schedule.',
        'Dadurch werden die Liste und ihr Wiederholungsplan entfernt.',
      ),
      confirmLabel: _listsText(context, 'Delete', 'Löschen'),
      destructive: true,
    );
    if (confirmed) await controller.deleteBiomarkerList(list);
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.list,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
    required this.onAddItem,
    required this.onAddPackage,
    required this.onEditItem,
  });

  final BiomarkerList list;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddItem;
  final VoidCallback onAddPackage;
  final ValueChanged<BiomarkerListItem> onEditItem;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      leading: const Icon(Icons.checklist_outlined),
      title: Text(list.name),
      subtitle: Text(
        '${_listsText(context, '${list.items.length} biomarkers', '${list.items.length} Biomarker')}'
        '${list.description.isEmpty ? '' : ' · ${list.description}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'edit',
            child: Text(_listsText(context, 'Edit list', 'Liste bearbeiten')),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text(_listsText(context, 'Delete list', 'Liste löschen')),
          ),
        ],
      ),
      children: [
        for (final item in list.items)
          ListTile(
            dense: true,
            leading: const Icon(Icons.science_outlined),
            title: Text(_biomarkerName(context, item.biomarkerId)),
            subtitle: Text(
              [
                if (item.dueIntervalDays != null)
                  _listsText(
                    context,
                    'Every ${item.dueIntervalDays} days',
                    'Alle ${item.dueIntervalDays} Tage',
                  ),
                if (item.notes.isNotEmpty) item.notes,
              ].join(' · '),
            ),
            onTap: () => onEditItem(item),
            trailing: IconButton(
              tooltip: _listsText(
                context,
                'Remove from list',
                'Aus Liste entfernen',
              ),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: () => controller.removeBiomarkerListItem(item),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: onAddItem,
                  icon: const Icon(Icons.add),
                  label: Text(
                    _listsText(
                      context,
                      'Add biomarker',
                      'Biomarker hinzufügen',
                    ),
                  ),
                ),
                // A package is expanded into its members rather than stored as
                // one entry: "due" is a per-marker question, and each member
                // keeps its own interval afterwards.
                if (controller.biomarkerPackages.isNotEmpty)
                  TextButton.icon(
                    onPressed: onAddPackage,
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(
                      _listsText(context, 'Add a package', 'Paket hinzufügen'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  String _biomarkerName(BuildContext context, String id) {
    for (final biomarker in controller.biomarkers) {
      if (biomarker.id == id) return biomarker.displayName;
    }
    return _listsText(
      context,
      'Missing catalog item',
      'Fehlender Katalogeintrag',
    );
  }
}

/// Puts one biomarker onto lists, from the biomarker's own side.
///
/// The lists sheet answers "what is on this list", and adding a marker there
/// means finding it in a dropdown of the whole catalog. This answers the
/// question you actually have while looking at a result — "which lists should
/// this be on" — so the marker is fixed and the lists are what you tick.
Future<void> showAddBiomarkerToListDialog(
  BuildContext context,
  AppController controller,
  Biomarker biomarker,
) async {
  final selected = _listIdsHolding(controller, biomarker);
  final interval = TextEditingController(text: '365');
  try {
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AnimatedBuilder(
          // A list created from inside this dialog has to appear in it.
          animation: controller,
          builder: (context, _) => AlertDialog(
            title: Text(
              _listsText(context, 'Add to list', 'Zur Liste hinzufügen'),
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    biomarker.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (controller.biomarkerLists.isEmpty)
                    Text(
                      _listsText(
                        context,
                        'No lists yet. Create one to schedule this test for retesting.',
                        'Noch keine Listen. Erstelle eine, um diesen Test zur Wiederholung einzuplanen.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final list in controller.biomarkerLists)
                            CheckboxListTile(
                              value: selected.contains(list.id),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(list.name),
                              subtitle: Text(
                                _membershipLabel(context, list, biomarker),
                              ),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  selected.add(list.id);
                                } else {
                                  selected.remove(list.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _createListFor(
                        dialogContext,
                        controller,
                        selected,
                        setState,
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(
                        _listsText(context, 'New list', 'Neue Liste'),
                      ),
                    ),
                  ),
                  TextField(
                    controller: interval,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _listsText(
                        context,
                        'Retest interval (days)',
                        'Wiederholungsintervall (Tage)',
                      ),
                      helperText: _listsText(
                        context,
                        'Used only where it is newly added. Empty means no due alerts.',
                        'Gilt nur für neu hinzugefügte Listen. Leer bedeutet keine Fälligkeitshinweise.',
                      ),
                      helperMaxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_listsText(context, 'Cancel', 'Abbrechen')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_listsText(context, 'Save', 'Speichern')),
              ),
            ],
          ),
        ),
      ),
    );
    if (save != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // Resolved before the await, so no context is read across the gap.
    String message(int added, int removed) => _listsText(
      context,
      added == 0 && removed == 0
          ? 'List membership is unchanged.'
          : [
              if (added > 0) 'Added to $added list(s)',
              if (removed > 0) 'removed from $removed',
            ].join(', '),
      added == 0 && removed == 0
          ? 'Listenzuordnung unverändert.'
          : [
              if (added > 0) 'Zu $added Liste(n) hinzugefügt',
              if (removed > 0) 'aus $removed entfernt',
            ].join(', '),
    );
    final raw = interval.text.trim();
    final parsed = raw.isEmpty ? null : int.tryParse(raw);
    if (raw.isNotEmpty && parsed == null) {
      throw StateError(
        _listsText(
          context,
          'The retest interval must be a whole number of days.',
          'Das Wiederholungsintervall muss eine ganze Zahl von Tagen sein.',
        ),
      );
    }
    if (parsed != null && parsed <= 0) {
      throw StateError(
        _listsText(
          context,
          'The retest interval must be a positive number.',
          'Das Wiederholungsintervall muss positiv sein.',
        ),
      );
    }
    final result = await controller.setBiomarkerListMemberships(
      biomarker: biomarker,
      listIds: selected,
      dueIntervalDays: parsed,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(message(result.added, result.removed))),
    );
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
  } finally {
    interval.dispose();
  }
}

Set<String> _listIdsHolding(AppController controller, Biomarker biomarker) => {
  for (final list in controller.biomarkerLists)
    if (list.items.any((item) => item.biomarkerId == biomarker.id)) list.id,
};

String _membershipLabel(
  BuildContext context,
  BiomarkerList list,
  Biomarker biomarker,
) {
  final item = list.items.firstWhereOrNull(
    (entry) => entry.biomarkerId == biomarker.id,
  );
  if (item == null) {
    final count = list.items.length;
    return _listsText(context, '$count test(s)', '$count Test(s)');
  }
  final days = item.dueIntervalDays;
  return days == null
      ? _listsText(context, 'Already on this list', 'Bereits auf dieser Liste')
      : _listsText(
          context,
          'Already on this list · every $days days',
          'Bereits auf dieser Liste · alle $days Tage',
        );
}

/// Creates a list from inside the add-to-list dialog and ticks it.
///
/// Without this, a marker on a phone with no lists yet is a dead end: the
/// dialog would say there is nothing to add to and send you somewhere else.
Future<void> _createListFor(
  BuildContext context,
  AppController controller,
  Set<String> selected,
  void Function(void Function()) setState,
) async {
  final name = TextEditingController();
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _listsText(
            context,
            'Create biomarker list',
            'Biomarkerliste erstellen',
          ),
        ),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: _listsText(context, 'Name *', 'Name *'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_listsText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_listsText(context, 'Create', 'Erstellen')),
          ),
        ],
      ),
    );
    if (confirmed != true || name.text.trim().isEmpty) return;
    final created = await controller.createBiomarkerList(name: name.text);
    setState(() => selected.add(created.id));
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
  } finally {
    name.dispose();
  }
}
