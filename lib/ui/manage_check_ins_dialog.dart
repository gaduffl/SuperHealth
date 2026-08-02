import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';

/// Manages the reusable symptoms and tags a person checks in against.
///
/// Ports Supplement Manager's tag management: rename, archive, and the
/// symptom-versus-predictor distinction. Here that distinction is the existing
/// [EventKind] — a tag is an intake proxy such as caffeine or exercise, used as
/// a predictor in correlations, and a symptom is the outcome being explained.
Future<void> showManageCheckInsDialog(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _ManageCheckIns(controller: controller),
    ),
  );
}

class _ManageCheckIns extends StatefulWidget {
  const _ManageCheckIns({required this.controller});

  final AppController controller;

  @override
  State<_ManageCheckIns> createState() => _ManageCheckInsState();
}

class _ManageCheckInsState extends State<_ManageCheckIns> {
  var _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final definitions =
        widget.controller.eventDefinitions
            .where((item) => !item.deleted && (_showArchived || !item.archived))
            .toList()
          ..sort((a, b) {
            if (a.kind != b.kind) {
              return a.kind == EventKind.symptom ? -1 : 1;
            }
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.pick('Symptoms and tags', 'Symptome und Tags'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      strings.pick(
                        'Tags are intake proxies used only as predictors in '
                            'correlations. Symptoms are the outcomes.',
                        'Tags sind Einnahme-Marker und dienen in Korrelationen '
                            'nur als Prädiktoren. Symptome sind die Ergebnisse.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: strings.pick(
                  'Add symptom or tag',
                  'Symptom oder Tag hinzufügen',
                ),
                onPressed: _addDefinition,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  strings.pick('Show archived', 'Archivierte anzeigen'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Switch(
                value: _showArchived,
                onChanged: (value) => setState(() => _showArchived = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: definitions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyState(
                    icon: Icons.sell_outlined,
                    title: strings.pick(
                      'Nothing to manage yet',
                      'Noch nichts zu verwalten',
                    ),
                    message: strings.pick(
                      'Add the symptoms and tags you want to include in your '
                          'daily check-in.',
                      'Füge die Symptome und Tags hinzu, die du in deinem '
                          'täglichen Check-in erfassen möchtest.',
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    for (final definition in definitions)
                      Card(
                        child: ListTile(
                          leading: Icon(
                            definition.kind == EventKind.symptom
                                ? Icons.monitor_heart_outlined
                                : Icons.sell_outlined,
                            color: definition.archived ? colors.outline : null,
                          ),
                          title: Text(
                            definition.name,
                            style: definition.archived
                                ? TextStyle(color: colors.onSurfaceVariant)
                                : null,
                          ),
                          subtitle: Text(
                            [
                              definition.kind == EventKind.symptom
                                  ? strings.symptom
                                  : strings.tag,
                              if (definition.kind == EventKind.tag)
                                _tagModeSummary(strings, definition),
                              if (definition.includeInCheckIn)
                                strings.pick('in check-in', 'im Check-in'),
                              if (definition.archived)
                                strings.pick('archived', 'archiviert'),
                            ].join(' · '),
                          ),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
                              if (definition.kind == EventKind.tag)
                                IconButton(
                                  tooltip: strings.pick(
                                    'Tag settings',
                                    'Tag-Einstellungen',
                                  ),
                                  onPressed: () => _editTagSettings(definition),
                                  icon: const Icon(Icons.tune),
                                ),
                              IconButton(
                                tooltip: strings.pick('Rename', 'Umbenennen'),
                                onPressed: () => _rename(definition),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: definition.kind == EventKind.symptom
                                    ? strings.pick(
                                        'Make it a tag',
                                        'In Tag umwandeln',
                                      )
                                    : strings.pick(
                                        'Make it a symptom',
                                        'In Symptom umwandeln',
                                      ),
                                onPressed: () => _switchKind(definition),
                                icon: const Icon(Icons.swap_horiz),
                              ),
                              IconButton(
                                tooltip: definition.archived
                                    ? strings.pick(
                                        'Restore',
                                        'Wiederherstellen',
                                      )
                                    : strings.pick('Archive', 'Archivieren'),
                                onPressed: () => _setArchived(
                                  definition,
                                  !definition.archived,
                                ),
                                icon: Icon(
                                  definition.archived
                                      ? Icons.unarchive_outlined
                                      : Icons.archive_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _addDefinition() async {
    final strings = AppLocalizations.of(context);
    final field = TextEditingController();
    var kind = EventKind.symptom;
    var name = '';
    final result = await showDialog<(EventKind, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            strings.pick('Add symptom or tag', 'Symptom oder Tag hinzufügen'),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<EventKind>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: EventKind.symptom,
                      label: Text(strings.symptom),
                      icon: const Icon(Icons.monitor_heart_outlined),
                    ),
                    ButtonSegment(
                      value: EventKind.tag,
                      label: Text(strings.tag),
                      icon: const Icon(Icons.sell_outlined),
                    ),
                  ],
                  selected: {kind},
                  onSelectionChanged: (value) =>
                      setDialogState(() => kind = value.first),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: field,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (value) =>
                      setDialogState(() => name = value.trim()),
                  onSubmitted: (_) {
                    if (name.isNotEmpty) {
                      Navigator.pop(dialogContext, (kind, name));
                    }
                  },
                  decoration: InputDecoration(
                    labelText: strings.pick('Name', 'Name'),
                    hintText: kind == EventKind.symptom
                        ? strings.pick('Energy', 'Energie')
                        : strings.pick('Coffee', 'Kaffee'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: name.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, (kind, name)),
              child: Text(strings.pick('Add', 'Hinzufügen')),
            ),
          ],
        ),
      ),
    );
    field.dispose();
    if (result == null || !mounted) return;

    final now = DateTime.now();
    try {
      await widget.controller.saveEventDefinition(
        HealthEventDefinition(
          id: widget.controller.repository.newId(),
          profileId: widget.controller.activeProfile!.id,
          kind: result.$1,
          name: result.$2,
          useScore: result.$1 == EventKind.symptom,
          includeInCheckIn: result.$1 == EventKind.tag,
          createdAt: now,
          updatedAt: now,
        ),
      );
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _rename(HealthEventDefinition definition) async {
    final strings = AppLocalizations.of(context);
    final field = TextEditingController(text: definition.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.pick('Rename', 'Umbenennen')),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: strings.pick('Name', 'Name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.pick('Save', 'Speichern')),
          ),
        ],
      ),
    );
    final name = field.text.trim();
    field.dispose();
    if (confirmed != true || name.isEmpty || name == definition.name) return;
    await _apply(_copy(definition, name: name), renameHistoryTo: name);
  }

  Future<void> _switchKind(HealthEventDefinition definition) async {
    final next = definition.kind == EventKind.symptom
        ? EventKind.tag
        : EventKind.symptom;
    await _apply(_copy(definition, kind: next), changeHistoryKindTo: next);
  }

  Future<void> _setArchived(
    HealthEventDefinition definition,
    bool archived,
  ) async {
    // Archiving hides the definition from check-ins; recorded history stays,
    // because removing past observations would silently rewrite the record the
    // correlations are computed from.
    await _apply(_copy(definition, archived: archived));
  }

  /// Saves the definition and, when asked, carries the change into the events
  /// that reference it.
  ///
  /// `HealthEvent` stores its own name and kind, so leaving history untouched
  /// after a rename would show the same thing under two names in the journal.
  Future<void> _apply(
    HealthEventDefinition definition, {
    String? renameHistoryTo,
    EventKind? changeHistoryKindTo,
  }) async {
    try {
      await widget.controller.saveEventDefinition(definition);
      if (renameHistoryTo == null && changeHistoryKindTo == null) return;
      final affected = widget.controller.events
          .where(
            (event) => !event.deleted && event.definitionId == definition.id,
          )
          .toList();
      for (final event in affected) {
        await widget.controller.updateEvent(
          HealthEvent(
            id: event.id,
            profileId: event.profileId,
            definitionId: event.definitionId,
            kind: changeHistoryKindTo ?? event.kind,
            name: renameHistoryTo ?? event.name,
            observedAt: event.observedAt,
            score: event.score,
            numericValue: event.numericValue,
            unit: event.unit,
            durationMinutes: event.durationMinutes,
            notes: event.notes,
            colorValue: event.colorValue,
            archived: event.archived,
            createdAt: event.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  HealthEventDefinition _copy(
    HealthEventDefinition value, {
    String? name,
    EventKind? kind,
    bool? archived,
    TagValueMode? valueMode,
    String? defaultUnit,
    bool clearDefaultUnit = false,
    double? portionAmount,
    bool clearPortionAmount = false,
    String? portionLabel,
    bool clearPortionLabel = false,
    bool? includeInCheckIn,
  }) => HealthEventDefinition(
    id: value.id,
    profileId: value.profileId,
    kind: kind ?? value.kind,
    name: name ?? value.name,
    defaultUnit: clearDefaultUnit ? null : defaultUnit ?? value.defaultUnit,
    useScore: value.useScore,
    valueMode: valueMode ?? value.valueMode,
    portionAmount: clearPortionAmount
        ? null
        : portionAmount ?? value.portionAmount,
    portionLabel: clearPortionLabel ? null : portionLabel ?? value.portionLabel,
    includeInCheckIn: includeInCheckIn ?? value.includeInCheckIn,
    colorValue: value.colorValue,
    archived: archived ?? value.archived,
    createdAt: value.createdAt,
    updatedAt: DateTime.now(),
    deleted: value.deleted,
  );

  /// Opens the per-tag settings sheet: what its number means, its canonical
  /// unit and portion shortcut when it is an amount, and whether it is asked
  /// about in the daily check-in.
  Future<void> _editTagSettings(HealthEventDefinition definition) async {
    var mode = definition.valueMode;
    final unitField = TextEditingController(text: definition.defaultUnit ?? '');
    final portionField = TextEditingController(
      text: definition.portionAmount == null
          ? ''
          : _formatSettingsAmount(definition.portionAmount!),
    );
    final portionLabelField = TextEditingController(
      text: definition.portionLabel ?? '',
    );
    var includeInCheckIn = definition.includeInCheckIn;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) {
          final strings = AppLocalizations.of(builderContext);
          final needsUnit = mode == TagValueMode.amount;
          return AlertDialog(
            title: Text(strings.pick('Tag settings', 'Tag-Einstellungen')),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      definition.name,
                      style: Theme.of(builderContext).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      strings.pick(
                        'What does the number mean?',
                        'Was bedeutet die Zahl?',
                      ),
                      style: Theme.of(builderContext).textTheme.labelLarge,
                    ),
                    RadioGroup<TagValueMode>(
                      groupValue: mode,
                      onChanged: (value) =>
                          setState(() => mode = value ?? mode),
                      child: Column(
                        children: [
                          RadioListTile<TagValueMode>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: TagValueMode.occurrence,
                            title: Text(
                              strings.pick(
                                'Just happened',
                                'Ist einfach passiert',
                              ),
                            ),
                            subtitle: Text(
                              strings.pick(
                                'No number — logging just counts how often.',
                                'Keine Zahl — die Erfassung zählt nur, wie '
                                    'oft.',
                              ),
                            ),
                          ),
                          RadioListTile<TagValueMode>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: TagValueMode.intensity,
                            title: Text(
                              strings.pick(
                                'Felt strength (0-5)',
                                'Gefühlte Stärke (0-5)',
                              ),
                            ),
                            subtitle: Text(
                              strings.pick(
                                'A rating with no physical unit, like a '
                                    'symptom.',
                                'Eine Bewertung ohne Einheit, wie bei einem '
                                    'Symptom.',
                              ),
                            ),
                          ),
                          RadioListTile<TagValueMode>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: TagValueMode.amount,
                            title: Text(
                              strings.pick('A real amount', 'Eine echte Menge'),
                            ),
                            subtitle: Text(
                              strings.pick(
                                'A quantity in a fixed unit, e.g. grams of '
                                    'coffee beans.',
                                'Eine Menge in einer festen Einheit, z. B. '
                                    'Gramm Kaffeebohnen.',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (needsUnit) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: unitField,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: strings.pick('Unit', 'Einheit'),
                                hintText: strings.pick('g', 'g'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: portionField,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: strings.pick(
                                  'One portion',
                                  'Eine Portion',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: portionLabelField,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: strings.pick(
                            'What is a portion? (optional)',
                            'Was ist eine Portion? (optional)',
                          ),
                          hintText: strings.pick(
                            'e.g. filter coffee',
                            'z. B. Filterkaffee',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: includeInCheckIn,
                      title: Text(
                        strings.pick(
                          'Ask in daily check-in',
                          'Im täglichen Check-in abfragen',
                        ),
                      ),
                      onChanged: (value) =>
                          setState(() => includeInCheckIn = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: needsUnit && unitField.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(strings.pick('Save', 'Speichern')),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true) {
      for (final field in [unitField, portionField, portionLabelField]) {
        field.dispose();
      }
      return;
    }
    final newUnit = mode == TagValueMode.amount ? unitField.text.trim() : null;
    final newPortion = mode == TagValueMode.amount
        ? double.tryParse(portionField.text.trim().replaceAll(',', '.'))
        : null;
    final newPortionLabel = mode == TagValueMode.amount
        ? (portionLabelField.text.trim().isEmpty
              ? null
              : portionLabelField.text.trim())
        : null;
    for (final field in [unitField, portionField, portionLabelField]) {
      field.dispose();
    }
    if (!mounted) return;

    var factor = 1.0;
    if (mode == TagValueMode.amount && newUnit != null && newUnit.isNotEmpty) {
      final affectedCount = widget.controller.events
          .where(
            (event) =>
                !event.deleted &&
                event.definitionId == definition.id &&
                (event.score != null || event.numericValue != null) &&
                event.unit?.trim().toLowerCase() != newUnit.toLowerCase(),
          )
          .length;
      if (affectedCount > 0) {
        final resolvedFactor = await _askConversionFactor(
          definition: definition,
          newUnit: newUnit,
          affectedCount: affectedCount,
        );
        // The user backed out of committing to a conversion, so the whole
        // settings change is abandoned rather than leaving the definition
        // claiming an amount its own history was never reinterpreted for.
        if (resolvedFactor == null) return;
        factor = resolvedFactor;
      }
    }

    try {
      await widget.controller.saveEventDefinition(
        _copy(
          definition,
          valueMode: mode,
          defaultUnit: newUnit,
          clearDefaultUnit: newUnit == null,
          portionAmount: newPortion,
          clearPortionAmount: newPortion == null,
          portionLabel: newPortionLabel,
          clearPortionLabel: newPortionLabel == null,
          includeInCheckIn: includeInCheckIn,
        ),
      );
      if (mode == TagValueMode.amount &&
          newUnit != null &&
          newUnit.isNotEmpty) {
        await widget.controller.reinterpretEventHistory(
          definition: definition,
          factor: factor,
          newUnit: newUnit,
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  /// Asks how to convert a tag's existing felt-strength scores or
  /// previous-unit amounts into the new canonical unit, so switching a
  /// tag's mode or unit never leaves stale, mis-typed numbers in a series
  /// correlation relies on.
  Future<double?> _askConversionFactor({
    required HealthEventDefinition definition,
    required String newUnit,
    required int affectedCount,
  }) async {
    final strings = AppLocalizations.of(context);
    final oldDescriptor = definition.valueMode == TagValueMode.intensity
        ? strings.pick('rating point', 'Bewertungspunkt')
        : (definition.defaultUnit?.trim().isNotEmpty ?? false)
        ? definition.defaultUnit!.trim()
        : strings.pick('previous entry', 'bisheriger Eintrag');
    final factorField = TextEditingController(text: '1');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setState) {
          final strings = AppLocalizations.of(builderContext);
          final parsed = double.tryParse(
            factorField.text.trim().replaceAll(',', '.'),
          );
          return AlertDialog(
            title: Text(
              strings.pick(
                'Convert existing entries?',
                'Bestehende Einträge umrechnen?',
              ),
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.pick(
                      '$affectedCount existing ${definition.name} '
                          '${affectedCount == 1 ? 'entry' : 'entries'} will be '
                          'rewritten as an amount in $newUnit so correlations '
                          'stay consistent.',
                      '$affectedCount bestehende ${definition.name}-Einträge '
                          'werden als Menge in $newUnit umgeschrieben, damit '
                          'Korrelationen konsistent bleiben.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text('1 $oldDescriptor ='),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: factorField,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(newUnit),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: parsed == null || parsed <= 0
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                child: Text(
                  strings.pick('Convert and save', 'Umrechnen und speichern'),
                ),
              ),
            ],
          );
        },
      ),
    );
    final factor = confirmed == true
        ? double.tryParse(factorField.text.trim().replaceAll(',', '.'))
        : null;
    factorField.dispose();
    return factor;
  }
}

String _tagModeSummary(
  AppLocalizations strings,
  HealthEventDefinition definition,
) => switch (definition.valueMode) {
  TagValueMode.occurrence => strings.pick('just happened', 'einfach passiert'),
  TagValueMode.intensity => strings.pick(
    'felt strength 0-5',
    'gefühlte Stärke 0-5',
  ),
  TagValueMode.amount =>
    (definition.defaultUnit?.trim().isEmpty ?? true)
        ? strings.pick('amount', 'Menge')
        : strings.pick(
            'amount in ${definition.defaultUnit}',
            'Menge in ${definition.defaultUnit}',
          ),
};

/// Renders a portion amount without a trailing ".0" for whole numbers.
String _formatSettingsAmount(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');
