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

/// Names a retest interval the way a person would say it.
///
/// Stored in days, because that is what due arithmetic needs, but "every 365
/// days" reads like a machine setting where "every year" reads like a plan.
String retestIntervalLabel(AppLocalizations strings, int days) {
  String unit(int count, String one, String many, String einer, String viele) =>
      count == 1
      ? strings.pick('Every $one', einer)
      : strings.pick('Every $count $many', 'Alle $count $viele');
  if (days % 365 == 0) {
    return unit(days ~/ 365, 'year', 'years', 'Jährlich', 'Jahre');
  }
  if (days % 30 == 0) {
    return unit(days ~/ 30, 'month', 'months', 'Monatlich', 'Monate');
  }
  if (days % 7 == 0) {
    return unit(days ~/ 7, 'week', 'weeks', 'Wöchentlich', 'Wochen');
  }
  return unit(days, 'day', 'days', 'Täglich', 'Tage');
}

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
                        'Each list is a retest schedule. Its biomarkers follow '
                            'the list’s interval unless one has its own.',
                        'Jede Liste ist ein Wiederholungsplan. Ihre Biomarker '
                            'folgen dem Intervall der Liste, außer einer hat '
                            'ein eigenes.',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
    // A new list is almost always a recall schedule, and one created without
    // an interval would silently never make anything due.
    final interval = _IntervalChoice(
      existing == null ? 365 : existing.dueIntervalDays,
    );
    final ownIntervals =
        existing?.items.where((item) => item.dueIntervalDays != null).length ??
        0;
    var resetItemIntervals = false;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            existing == null
                ? _listsText(
                    context,
                    'Create biomarker list',
                    'Biomarkerliste erstellen',
                  )
                : _listsText(context, 'Edit list', 'Liste bearbeiten'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  autofocus: existing == null,
                  decoration: InputDecoration(
                    labelText: _listsText(context, 'Name *', 'Name *'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: _listsText(
                      context,
                      'Description',
                      'Beschreibung',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _IntervalPicker(
                  choice: interval,
                  label: _listsText(
                    context,
                    'Retest schedule',
                    'Wiederholungsplan',
                  ),
                  emptyLabel: _listsText(
                    context,
                    'No schedule (checklist only)',
                    'Kein Plan (nur Checkliste)',
                  ),
                  helperText: _listsText(
                    context,
                    'Biomarkers without their own interval become due on this schedule.',
                    'Biomarker ohne eigenes Intervall werden nach diesem Plan fällig.',
                  ),
                ),
                if (ownIntervals > 0)
                  CheckboxListTile(
                    value: resetItemIntervals,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      _listsText(
                        context,
                        'Apply to every biomarker',
                        'Auf alle Biomarker anwenden',
                      ),
                    ),
                    subtitle: Text(
                      _listsText(
                        context,
                        'Clears the own interval of $ownIntervals biomarker(s) so they follow the list.',
                        'Entfernt das eigene Intervall von $ownIntervals Biomarker(n), damit sie der Liste folgen.',
                      ),
                    ),
                    onChanged: (value) =>
                        setState(() => resetItemIntervals = value ?? false),
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
    );
    if (!context.mounted) return;
    try {
      if (save == true && name.text.trim().isNotEmpty) {
        interval.requireValid(context);
        if (existing == null) {
          await controller.createBiomarkerList(
            name: name.text,
            description: description.text,
            dueIntervalDays: interval.days,
          );
        } else {
          await controller.updateBiomarkerList(
            BiomarkerList(
              id: existing.id,
              profileId: existing.profileId,
              name: name.text,
              description: description.text,
              dueIntervalDays: interval.days,
              createdAt: existing.createdAt,
              updatedAt: DateTime.now(),
              items: existing.items,
            ),
            resetItemIntervals: resetItemIntervals,
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
    final selectableBiomarkers =
        controller.biomarkers
            .where(
              (biomarker) =>
                  !biomarker.isCalculated ||
                  biomarker.id == existing?.biomarkerId,
            )
            .toList()
          ..sort(
            (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
          );
    if (selectableBiomarkers.isEmpty) return;
    var biomarkerId = existing?.biomarkerId;
    biomarkerId ??= selectableBiomarkers
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
    // Empty follows the list, so a new item needs no interval of its own.
    final interval = _IntervalChoice(existing?.dueIntervalDays);
    final notes = TextEditingController(text: existing?.notes);
    final strings = AppLocalizations.of(context);
    final listSchedule = list.dueIntervalDays;
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
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: biomarkerId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _listsText(context, 'Biomarker', 'Biomarker'),
                  ),
                  items: [
                    for (final biomarker in selectableBiomarkers)
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
                _IntervalPicker(
                  choice: interval,
                  label: _listsText(
                    context,
                    'Retest interval',
                    'Wiederholungsintervall',
                  ),
                  emptyLabel: listSchedule == null
                      ? _listsText(
                          context,
                          'Follow list (no schedule)',
                          'Wie die Liste (kein Plan)',
                        )
                      : _listsText(
                          context,
                          'Follow list (${retestIntervalLabel(strings, listSchedule).toLowerCase()})',
                          'Wie die Liste (${retestIntervalLabel(strings, listSchedule).toLowerCase()})',
                        ),
                  helperText: listSchedule == null
                      ? _listsText(
                          context,
                          'This list has no schedule, so the biomarker is only due with an interval of its own.',
                          'Diese Liste hat keinen Plan; der Biomarker wird nur mit eigenem Intervall fällig.',
                        )
                      : null,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: notes,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: _listsText(context, 'Notes', 'Notizen'),
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
    );
    if (!context.mounted) return;
    try {
      if (save == true && biomarkerId != null) {
        interval.requireValid(context);
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
          dueIntervalDays: interval.days,
          notes: notes.text,
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    } finally {
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

/// The interval a picker settled on, read by the dialog that owns it.
class _IntervalChoice {
  _IntervalChoice(this.days);

  /// Null means the picker's empty option.
  int? days;
  bool valid = true;

  void requireValid(BuildContext context) {
    if (valid) return;
    throw StateError(
      _listsText(
        context,
        'The retest interval must be a positive whole number of days.',
        'Das Wiederholungsintervall muss eine positive ganze Zahl von Tagen sein.',
      ),
    );
  }
}

/// Common intervals as a choice, with a custom number of days as the escape.
///
/// A bare "days" box made every schedule an arithmetic exercise — a year is
/// 365, six months is what exactly — and made "no schedule" an empty field
/// that looked like something had been forgotten.
class _IntervalPicker extends StatefulWidget {
  const _IntervalPicker({
    required this.choice,
    required this.label,
    required this.emptyLabel,
    this.helperText,
  });

  final _IntervalChoice choice;
  final String label;
  final String emptyLabel;
  final String? helperText;

  @override
  State<_IntervalPicker> createState() => _IntervalPickerState();
}

class _IntervalPickerState extends State<_IntervalPicker> {
  static const _presets = [30, 90, 180, 365, 730];
  // Sentinels rather than null: 0 and negatives are never a stored interval.
  static const _empty = 0;
  static const _custom = -1;

  late int _selected;
  late final TextEditingController _days;

  @override
  void initState() {
    super.initState();
    final days = widget.choice.days;
    _selected = days == null
        ? _empty
        : _presets.contains(days)
        ? days
        : _custom;
    _days = TextEditingController(text: _selected == _custom ? '$days' : '');
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  void _update() {
    if (_selected == _custom) {
      final parsed = int.tryParse(_days.text.trim());
      widget.choice
        ..days = parsed
        ..valid = parsed != null && parsed > 0;
    } else {
      widget.choice
        ..days = _selected == _empty ? null : _selected
        ..valid = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<int>(
          initialValue: _selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            helperMaxLines: 3,
          ),
          items: [
            DropdownMenuItem(value: _empty, child: Text(widget.emptyLabel)),
            for (final days in _presets)
              DropdownMenuItem(
                value: days,
                child: Text(retestIntervalLabel(strings, days)),
              ),
            DropdownMenuItem(
              value: _custom,
              child: Text(strings.pick('Custom…', 'Eigenes…')),
            ),
          ],
          onChanged: (value) => setState(() {
            _selected = value ?? _empty;
            _update();
          }),
        ),
        if (_selected == _custom)
          TextField(
            controller: _days,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: strings.pick('Interval in days', 'Intervall in Tagen'),
              errorText: widget.choice.valid || _days.text.isEmpty
                  ? null
                  : strings.pick(
                      'Enter a positive whole number',
                      'Positive ganze Zahl eingeben',
                    ),
            ),
            onChanged: (_) => setState(_update),
          ),
      ],
    );
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
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final rows = [
      for (final item in list.items)
        (
          item: item,
          name: _biomarkerName(context, item.biomarkerId),
          lastMeasured: controller.lastMeasuredAt(item.biomarkerId),
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final dueCount = rows.where((row) {
      final due = list.dueDateFor(row.item, row.lastMeasured);
      return due != null && !due.isAfter(now);
    }).length;
    final unscheduled = rows
        .where((row) => list.intervalFor(row.item) == null)
        .length;
    final schedule = list.dueIntervalDays;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.checklist_outlined),
        title: Text(list.name),
        subtitle: Text(
          [
            schedule == null
                ? _listsText(context, 'No schedule', 'Kein Plan')
                : retestIntervalLabel(strings, schedule),
            _listsText(
              context,
              '${rows.length} biomarkers',
              '${rows.length} Biomarker',
            ),
            if (dueCount > 0)
              _listsText(context, '$dueCount due', '$dueCount fällig'),
          ].join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: _listsText(context, 'List actions', 'Listenaktionen'),
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
          if (list.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  list.description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          // The schedule gets its own labelled row: it used to exist only as a
          // copy inside every item, with nowhere to see or change it for the
          // list as a whole.
          ListTile(
            leading: Icon(
              Icons.event_repeat_outlined,
              color: schedule == null ? colors.error : colors.primary,
            ),
            title: Text(
              schedule == null
                  ? _listsText(
                      context,
                      'No retest schedule',
                      'Kein Wiederholungsplan',
                    )
                  : _listsText(
                      context,
                      'Retest schedule: ${retestIntervalLabel(strings, schedule).toLowerCase()}',
                      'Wiederholungsplan: ${retestIntervalLabel(strings, schedule).toLowerCase()}',
                    ),
            ),
            subtitle: Text(
              unscheduled > 0
                  ? _listsText(
                      context,
                      '$unscheduled biomarker(s) never become due until the list or the biomarker has an interval.',
                      '$unscheduled Biomarker werden nie fällig, bis die Liste oder der Biomarker ein Intervall hat.',
                    )
                  : _listsText(
                      context,
                      'Biomarkers without their own interval follow this.',
                      'Biomarker ohne eigenes Intervall folgen diesem Plan.',
                    ),
              style: unscheduled > 0 ? TextStyle(color: colors.error) : null,
            ),
            trailing: TextButton(
              onPressed: onEdit,
              child: Text(_listsText(context, 'Change', 'Ändern')),
            ),
          ),
          const Divider(height: 1),
          for (final row in rows)
            _ItemTile(
              list: list,
              item: row.item,
              name: row.name,
              lastMeasured: row.lastMeasured,
              now: now,
              onTap: () => onEditItem(row.item),
              onRemove: () => controller.removeBiomarkerListItem(row.item),
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
                  // A package is expanded into its members rather than stored
                  // as one entry: "due" is a per-marker question, and each
                  // member follows the list unless given its own interval.
                  if (controller.biomarkerPackages.isNotEmpty)
                    TextButton.icon(
                      onPressed: onAddPackage,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(
                        _listsText(
                          context,
                          'Add a package',
                          'Paket hinzufügen',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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

/// One biomarker on a list: where its schedule comes from and when it is due.
class _ItemTile extends StatelessWidget {
  const _ItemTile({
    required this.list,
    required this.item,
    required this.name,
    required this.lastMeasured,
    required this.now,
    required this.onTap,
    required this.onRemove,
  });

  final BiomarkerList list;
  final BiomarkerListItem item;
  final String name;
  final DateTime? lastMeasured;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final interval = list.intervalFor(item);
    final dueDate = list.dueDateFor(item, lastMeasured);
    final isDue = dueDate != null && !dueDate.isAfter(now);
    final schedule = interval == null
        ? _listsText(context, 'No schedule, never due', 'Kein Plan, nie fällig')
        : item.dueIntervalDays == null
        ? _listsText(
            context,
            '${retestIntervalLabel(strings, interval)} (list)',
            '${retestIntervalLabel(strings, interval)} (Liste)',
          )
        : _listsText(
            context,
            '${retestIntervalLabel(strings, interval)} (own)',
            '${retestIntervalLabel(strings, interval)} (eigenes)',
          );
    final measured = lastMeasured;
    final status = measured == null
        ? _listsText(context, 'Never measured', 'Noch nie gemessen')
        : dueDate == null
        ? _listsText(
            context,
            'Last ${strings.formatHistoryDate(measured)}',
            'Zuletzt ${strings.formatHistoryDate(measured)}',
          )
        : isDue
        ? _listsText(
            context,
            'Due since ${strings.formatHistoryDate(dueDate)}',
            'Fällig seit ${strings.formatHistoryDate(dueDate)}',
          )
        : _listsText(
            context,
            'Next ${strings.formatHistoryDate(dueDate)}',
            'Nächste ${strings.formatHistoryDate(dueDate)}',
          );
    return ListTile(
      dense: true,
      leading: Icon(
        interval == null
            ? Icons.event_busy_outlined
            : isDue
            ? Icons.error_outline
            : Icons.event_available_outlined,
        color: isDue
            ? colors.error
            : interval == null
            ? colors.onSurfaceVariant
            : colors.primary,
      ),
      title: Text(name),
      subtitle: Text(
        [schedule, status, if (item.notes.isNotEmpty) item.notes].join(' · '),
        style: interval == null || isDue
            ? TextStyle(
                color: interval == null
                    ? colors.onSurfaceVariant
                    : colors.error,
              )
            : null,
      ),
      onTap: onTap,
      trailing: IconButton(
        tooltip: _listsText(context, 'Remove from list', 'Aus Liste entfernen'),
        icon: const Icon(Icons.remove_circle_outline),
        onPressed: onRemove,
      ),
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
  if (biomarker.isCalculated) return;
  final selected = _listIdsHolding(controller, biomarker);
  final interval = _IntervalChoice(null);
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
                  _IntervalPicker(
                    choice: interval,
                    label: _listsText(
                      context,
                      'Retest interval',
                      'Wiederholungsintervall',
                    ),
                    emptyLabel: _listsText(
                      context,
                      'Follow each list’s schedule',
                      'Plan der jeweiligen Liste',
                    ),
                    helperText: _listsText(
                      context,
                      'Used only where it is newly added.',
                      'Gilt nur für neu hinzugefügte Listen.',
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
    interval.requireValid(context);
    final result = await controller.setBiomarkerListMemberships(
      biomarker: biomarker,
      listIds: selected,
      dueIntervalDays: interval.days,
    );
    messenger.showSnackBar(
      SnackBar(content: Text(message(result.added, result.removed))),
    );
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
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
  final days = list.intervalFor(item);
  if (days == null) {
    return _listsText(
      context,
      'Already on this list · no schedule',
      'Bereits auf dieser Liste · kein Plan',
    );
  }
  final label = retestIntervalLabel(AppLocalizations.of(context), days);
  return _listsText(
    context,
    'Already on this list · ${label.toLowerCase()}',
    'Bereits auf dieser Liste · ${label.toLowerCase()}',
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
  final interval = _IntervalChoice(365);
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
            _IntervalPicker(
              choice: interval,
              label: _listsText(
                context,
                'Retest schedule',
                'Wiederholungsplan',
              ),
              emptyLabel: _listsText(
                context,
                'No schedule (checklist only)',
                'Kein Plan (nur Checkliste)',
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
            child: Text(_listsText(context, 'Create', 'Erstellen')),
          ),
        ],
      ),
    );
    if (confirmed != true || name.text.trim().isEmpty || !context.mounted) {
      return;
    }
    interval.requireValid(context);
    final created = await controller.createBiomarkerList(
      name: name.text,
      dueIntervalDays: interval.days,
    );
    setState(() => selected.add(created.id));
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
  } finally {
    name.dispose();
  }
}
