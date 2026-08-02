import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'manage_check_ins_dialog.dart';

/// Scores every tracked symptom for one day in a single pass.
///
/// Supplement Manager's morning check-in existed because scoring symptoms one
/// dialog at a time is too much friction to keep up daily — and without a daily
/// series the correlation analysis has nothing to work with.
Future<void> showDailyCheckInDialog(
  BuildContext context,
  AppController controller, {
  required DateTime day,
}) async {
  final strings = AppLocalizations.of(context);
  final definitions = controller.eventDefinitions
      .where(
        (item) =>
            item.kind == EventKind.symptom && !item.archived && !item.deleted,
      )
      .toList();
  final existing = {
    for (final event in controller.events.where(
      (item) =>
          !item.deleted &&
          item.kind == EventKind.symptom &&
          _sameDay(item.observedAt, day),
    ))
      _keyFor(event.definitionId, event.name): event,
  };

  final scores = <String, int?>{
    for (final definition in definitions)
      definition.id: _scoreFromEvent(
        existing[_keyFor(definition.id, definition.name)],
      ),
  };
  final noteController = TextEditingController(
    text:
        existing.values
            .firstWhereOrNull((event) => event.notes.trim().isNotEmpty)
            ?.notes ??
        '',
  );
  final newSymptomController = TextEditingController();

  // Only tags explicitly opted into the check-in appear here, and an amount
  // tag needs a defined portion before it has anything quick to ask about —
  // without one, only the full log dialog can record an exact amount.
  final tagDefinitions = controller.eventDefinitions
      .where(
        (item) =>
            item.kind == EventKind.tag &&
            item.includeInCheckIn &&
            !item.archived &&
            !item.deleted &&
            (item.valueMode != TagValueMode.amount ||
                (item.portionAmount != null && item.portionAmount! > 0)),
      )
      .toList();
  final todaysTagEvents = controller.events
      .where(
        (item) =>
            !item.deleted &&
            item.kind == EventKind.tag &&
            _sameDay(item.observedAt, day),
      )
      .toList();
  final existingTagEvent = {
    for (final event in todaysTagEvents)
      _keyFor(event.definitionId, event.name): event,
  };
  final tagScores = <String, int?>{
    for (final definition in tagDefinitions)
      if (definition.valueMode == TagValueMode.intensity)
        definition.id: _scoreFromEvent(
          existingTagEvent[_keyFor(definition.id, definition.name)],
        ),
  };
  final tagOccurred = <String, bool>{
    for (final definition in tagDefinitions)
      if (definition.valueMode == TagValueMode.occurrence)
        definition.id:
            existingTagEvent[_keyFor(definition.id, definition.name)] != null,
  };
  final tagPortionCount = <String, int>{
    for (final definition in tagDefinitions)
      if (definition.valueMode == TagValueMode.amount)
        definition.id: _portionCount(
          todaysTagEvents,
          definition.id,
          definition.portionAmount!,
        ),
  };

  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (builderContext, setLocalState) {
        Future<void> addSymptom() async {
          final name = newSymptomController.text.trim();
          if (name.isEmpty) return;
          final now = DateTime.now();
          final definition = HealthEventDefinition(
            id: controller.repository.newId(),
            profileId: controller.activeProfile!.id,
            kind: EventKind.symptom,
            name: name,
            useScore: true,
            createdAt: now,
            updatedAt: now,
          );
          await controller.saveEventDefinition(definition);
          newSymptomController.clear();
          setLocalState(() {
            definitions.add(definition);
            scores[definition.id] = null;
          });
        }

        return AlertDialog(
          title: Row(
            children: [
              Expanded(
                child: Text(
                  strings.pick('Daily check-in', 'Täglicher Check-in'),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.pick(
                  'Manage symptoms and tags',
                  'Symptome und Tags verwalten',
                ),
                onPressed: () async {
                  final previousTagDefinitions = {
                    for (final definition in tagDefinitions)
                      definition.id: definition,
                  };
                  await showManageCheckInsDialog(builderContext, controller);
                  if (!builderContext.mounted) return;

                  final refreshedSymptoms = controller.eventDefinitions
                      .where(
                        (item) =>
                            item.kind == EventKind.symptom &&
                            !item.archived &&
                            !item.deleted,
                      )
                      .toList();
                  final refreshedTags = controller.eventDefinitions
                      .where(
                        (item) =>
                            item.kind == EventKind.tag &&
                            item.includeInCheckIn &&
                            !item.archived &&
                            !item.deleted &&
                            (item.valueMode != TagValueMode.amount ||
                                (item.portionAmount != null &&
                                    item.portionAmount! > 0)),
                      )
                      .toList();
                  final currentDayEvents = controller.events.where(
                    (item) => !item.deleted && _sameDay(item.observedAt, day),
                  );
                  final currentSymptoms = {
                    for (final event in currentDayEvents.where(
                      (item) => item.kind == EventKind.symptom,
                    ))
                      _keyFor(event.definitionId, event.name): event,
                  };
                  final currentTagEvents = currentDayEvents
                      .where((item) => item.kind == EventKind.tag)
                      .toList();
                  final currentTags = {
                    for (final event in currentTagEvents)
                      _keyFor(event.definitionId, event.name): event,
                  };

                  setLocalState(() {
                    definitions
                      ..clear()
                      ..addAll(refreshedSymptoms);
                    for (final definition in refreshedSymptoms) {
                      scores.putIfAbsent(
                        definition.id,
                        () => _scoreFromEvent(
                          currentSymptoms[_keyFor(
                            definition.id,
                            definition.name,
                          )],
                        ),
                      );
                    }

                    tagDefinitions
                      ..clear()
                      ..addAll(refreshedTags);
                    for (final definition in refreshedTags) {
                      final event =
                          currentTags[_keyFor(definition.id, definition.name)];
                      final previousDefinition =
                          previousTagDefinitions[definition.id];
                      switch (definition.valueMode) {
                        case TagValueMode.intensity:
                          if (previousDefinition?.valueMode !=
                                  TagValueMode.intensity ||
                              !tagScores.containsKey(definition.id)) {
                            tagScores[definition.id] = _scoreFromEvent(event);
                          }
                        case TagValueMode.occurrence:
                          if (previousDefinition?.valueMode !=
                                  TagValueMode.occurrence ||
                              !tagOccurred.containsKey(definition.id)) {
                            tagOccurred[definition.id] = event != null;
                          }
                        case TagValueMode.amount:
                          if (previousDefinition?.valueMode !=
                                  TagValueMode.amount ||
                              previousDefinition?.portionAmount !=
                                  definition.portionAmount ||
                              previousDefinition?.defaultUnit !=
                                  definition.defaultUnit ||
                              !tagPortionCount.containsKey(definition.id)) {
                            tagPortionCount[definition.id] = _portionCount(
                              currentTagEvents,
                              definition.id,
                              definition.portionAmount!,
                            );
                          }
                      }
                    }
                  });
                },
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.formatTrackingDate(day),
                    style: Theme.of(builderContext).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 12),
                  if (definitions.isEmpty)
                    Text(
                      strings.pick(
                        'Add the symptoms you want to follow, for example '
                            'energy, mood, or sleep quality.',
                        'Lege die Symptome an, die du verfolgen möchtest, '
                            'zum Beispiel Energie, Stimmung oder Schlafqualität.',
                      ),
                      style: Theme.of(builderContext).textTheme.bodySmall,
                    ),
                  for (final definition in definitions)
                    _ScoreRow(
                      name: definition.name,
                      score: scores[definition.id],
                      maxScore: 5,
                      onChanged: (value) =>
                          setLocalState(() => scores[definition.id] = value),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newSymptomController,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => addSymptom(),
                          decoration: InputDecoration(
                            labelText: strings.pick(
                              'New symptom',
                              'Neues Symptom',
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonal(
                        onPressed: addSymptom,
                        child: Text(strings.pick('Add', 'Hinzufügen')),
                      ),
                    ],
                  ),
                  if (tagDefinitions.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      strings.tag,
                      style: Theme.of(builderContext).textTheme.labelLarge,
                    ),
                    for (final definition in tagDefinitions)
                      switch (definition.valueMode) {
                        TagValueMode.intensity => _ScoreRow(
                          name: definition.name,
                          score: tagScores[definition.id],
                          maxScore: 5,
                          onChanged: (value) => setLocalState(
                            () => tagScores[definition.id] = value,
                          ),
                        ),
                        TagValueMode.occurrence => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: tagOccurred[definition.id] ?? false,
                          title: Text(definition.name),
                          onChanged: (value) => setLocalState(
                            () => tagOccurred[definition.id] = value ?? false,
                          ),
                        ),
                        TagValueMode.amount => _PortionRow(
                          name: definition.name,
                          unit: definition.defaultUnit ?? '',
                          portionAmount: definition.portionAmount!,
                          portionLabel: definition.portionLabel,
                          count: tagPortionCount[definition.id] ?? 0,
                          onChanged: (value) => setLocalState(
                            () => tagPortionCount[definition.id] = value,
                          ),
                        ),
                      },
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: strings.pick('Note for the day', 'Tagesnotiz'),
                      alignLabelWithHint: true,
                    ),
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
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(strings.pick('Save', 'Speichern')),
            ),
          ],
        );
      },
    ),
  );

  final note = noteController.text.trim();
  noteController.dispose();
  newSymptomController.dispose();
  if (saved != true) return;

  // Timestamp at the current time of day when checking in for today, and at
  // midday otherwise, so a back-filled entry still lands on the right date.
  final now = DateTime.now();
  final observedAt = _sameDay(day, now)
      ? now
      : DateTime(day.year, day.month, day.day, 12);

  try {
    for (final definition in definitions) {
      final score = scores[definition.id];
      final previous = existing[_keyFor(definition.id, definition.name)];
      if (score == null) {
        // Clearing a score removes the entry rather than storing a zero, which
        // would otherwise read as "worst possible" in the trend.
        if (previous != null) await controller.deleteEvent(previous);
        continue;
      }
      if (previous == null) {
        await controller.addEvent(
          kind: EventKind.symptom,
          name: definition.name,
          definition: definition,
          score: score,
          observedAt: observedAt,
          notes: note,
        );
      } else {
        await controller.updateEvent(
          HealthEvent(
            id: previous.id,
            profileId: previous.profileId,
            definitionId: previous.definitionId ?? definition.id,
            kind: EventKind.symptom,
            name: definition.name,
            observedAt: previous.observedAt,
            score: score,
            numericValue: previous.numericValue,
            unit: previous.unit,
            durationMinutes: previous.durationMinutes,
            notes: note,
            colorValue: previous.colorValue,
            archived: previous.archived,
            createdAt: previous.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      }
    }
    for (final definition in tagDefinitions) {
      final previous =
          existingTagEvent[_keyFor(definition.id, definition.name)];
      switch (definition.valueMode) {
        case TagValueMode.intensity:
          final score = tagScores[definition.id];
          if (score == null) {
            if (previous != null) await controller.deleteEvent(previous);
            continue;
          }
          if (previous == null) {
            await controller.addEvent(
              kind: EventKind.tag,
              name: definition.name,
              definition: definition,
              score: score,
              observedAt: observedAt,
            );
          } else {
            await controller.updateEvent(
              HealthEvent(
                id: previous.id,
                profileId: previous.profileId,
                definitionId: previous.definitionId ?? definition.id,
                kind: EventKind.tag,
                name: definition.name,
                observedAt: previous.observedAt,
                score: score,
                numericValue: previous.numericValue,
                unit: previous.unit,
                durationMinutes: previous.durationMinutes,
                notes: previous.notes,
                colorValue: previous.colorValue,
                archived: previous.archived,
                createdAt: previous.createdAt,
                updatedAt: DateTime.now(),
              ),
            );
          }
        case TagValueMode.occurrence:
          final wants = tagOccurred[definition.id] ?? false;
          if (wants && previous == null) {
            await controller.addEvent(
              kind: EventKind.tag,
              name: definition.name,
              definition: definition,
              observedAt: observedAt,
            );
          } else if (!wants && previous != null) {
            await controller.deleteEvent(previous);
          }
        case TagValueMode.amount:
          // Multiple portions a day are ordinary discrete entries, so the
          // stepper's target is reached by adding or removing whole
          // portion-events rather than editing a single running total.
          final portion = definition.portionAmount!;
          final todaysEvents =
              todaysTagEvents
                  .where((event) => event.definitionId == definition.id)
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          final existingCount = _portionCount(
            todaysTagEvents,
            definition.id,
            portion,
          );
          final target = tagPortionCount[definition.id] ?? existingCount;
          final delta = target - existingCount;
          if (delta > 0) {
            for (var index = 0; index < delta; index++) {
              await controller.addEvent(
                kind: EventKind.tag,
                name: definition.name,
                definition: definition,
                value: portion,
                unit: definition.defaultUnit,
                observedAt: observedAt,
              );
            }
          } else if (delta < 0) {
            for (final event in todaysEvents.take(-delta)) {
              await controller.deleteEvent(event);
            }
          }
      }
    }
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
    return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          strings.pick(
            'Check-in saved for ${strings.formatTrackingDate(day)}.',
            'Check-in für ${strings.formatTrackingDate(day)} gespeichert.',
          ),
        ),
      ),
    );
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.name,
    required this.score,
    required this.maxScore,
    required this.onChanged,
  });

  final String name;
  final int? score;
  final int maxScore;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name)),
              Text(
                score == null
                    ? '—'
                    : score! > maxScore
                    ? '$score/10 (${strings.pick('legacy', 'alt')})'
                    : '$score/$maxScore',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: strings.pick('Clear', 'Zurücksetzen'),
                onPressed: score == null ? null : () => onChanged(null),
                icon: const Icon(Icons.backspace_outlined, size: 18),
              ),
            ],
          ),
          Slider(
            value: (score ?? 0).clamp(0, maxScore).toDouble(),
            min: 0,
            max: maxScore.toDouble(),
            divisions: maxScore,
            label: '${(score ?? 0).clamp(0, maxScore)}',
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}

/// A portion stepper for an amount tag: how many portions today, and the
/// resulting total. Multiple portions a day are ordinary discrete entries —
/// this only decides how many of them should exist, not their exact amount.
class _PortionRow extends StatelessWidget {
  const _PortionRow({
    required this.name,
    required this.unit,
    required this.portionAmount,
    required this.portionLabel,
    required this.count,
    required this.onChanged,
  });

  final String name;
  final String unit;
  final double portionAmount;
  final String? portionLabel;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name),
              Text(
                [
                  if (portionLabel?.trim().isNotEmpty ?? false)
                    '$count× ${portionLabel!.trim()}',
                  '${_formatAmount(portionAmount * count)} $unit',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: count <= 0 ? null : () => onChanged(count - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        Text('$count', style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(count + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}

/// A legacy entry may have been stored as a numeric value rather than a score.
int? _scoreFromEvent(HealthEvent? event) {
  final value = event?.score?.toDouble() ?? event?.numericValue;
  if (value == null || !value.isFinite) return null;
  return value.clamp(0, 10).round();
}

/// How many whole portions the day's amount entries for [definitionId] add
/// up to. An entry that isn't an exact portion multiple (logged with the
/// full dialog rather than the stepper) is rounded to the nearest one.
int _portionCount(
  List<HealthEvent> todaysTagEvents,
  String definitionId,
  double portionAmount,
) {
  final total = todaysTagEvents
      .where((event) => event.definitionId == definitionId)
      .fold<double>(0, (sum, event) => sum + (event.numericValue ?? 0));
  return (total / portionAmount).round();
}

/// Renders a portion amount without a trailing ".0" for whole numbers.
String _formatAmount(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

String _keyFor(String? definitionId, String name) =>
    definitionId ?? 'name:${name.trim().toLowerCase()}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
