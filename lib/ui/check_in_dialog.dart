import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';

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
      definition.id:
          existing[_keyFor(definition.id, definition.name)]?.score ??
          _scoreFromValue(existing[_keyFor(definition.id, definition.name)]),
  };
  final noteController = TextEditingController(
    text:
        existing.values
            .firstWhereOrNull((event) => event.notes.trim().isNotEmpty)
            ?.notes ??
        '',
  );
  final newSymptomController = TextEditingController();

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
          title: Text(strings.pick('Daily check-in', 'Täglicher Check-in')),
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
    required this.onChanged,
  });

  final String name;
  final int? score;
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
                score == null ? '—' : '$score/10',
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
            value: (score ?? 0).toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: '${score ?? 0}',
            onChanged: (value) => onChanged(value.round()),
          ),
        ],
      ),
    );
  }
}

/// A legacy entry may have been stored as a numeric value rather than a score.
int? _scoreFromValue(HealthEvent? event) {
  final value = event?.numericValue;
  if (value == null || !value.isFinite) return null;
  return value.clamp(0, 10).round();
}

String _keyFor(String? definitionId, String name) =>
    definitionId ?? 'name:${name.trim().toLowerCase()}';

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
