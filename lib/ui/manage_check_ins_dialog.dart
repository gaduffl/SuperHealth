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
                      'Symptoms and tags appear here once you have recorded '
                          'one.',
                      'Symptome und Tags erscheinen hier, sobald du eines '
                          'erfasst hast.',
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
                              if (definition.archived)
                                strings.pick('archived', 'archiviert'),
                            ].join(' · '),
                          ),
                          trailing: Wrap(
                            spacing: 0,
                            children: [
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
  }) => HealthEventDefinition(
    id: value.id,
    profileId: value.profileId,
    kind: kind ?? value.kind,
    name: name ?? value.name,
    defaultUnit: value.defaultUnit,
    useScore: value.useScore,
    colorValue: value.colorValue,
    archived: archived ?? value.archived,
    createdAt: value.createdAt,
    updatedAt: DateTime.now(),
    deleted: value.deleted,
  );
}
