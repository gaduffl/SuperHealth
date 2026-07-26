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
    required this.onEditItem,
  });

  final BiomarkerList list;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddItem;
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
            child: TextButton.icon(
              onPressed: onAddItem,
              icon: const Icon(Icons.add),
              label: Text(
                _listsText(context, 'Add biomarker', 'Biomarker hinzufügen'),
              ),
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

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
