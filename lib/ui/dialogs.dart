// All async dialog continuations guard context.mounted before UI access.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../domain/entities.dart';
import 'common.dart';

Future<void> showAddProfileDialog(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final weight = TextEditingController();
  final notes = TextEditingController();
  DateTime? birthDate;
  String? sex;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('New profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Display name *'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: sex,
                decoration: const InputDecoration(labelText: 'Sex (optional)'),
                items: const [
                  DropdownMenuItem(value: 'female', child: Text('Female')),
                  DropdownMenuItem(value: 'male', child: Text('Male')),
                  DropdownMenuItem(value: 'intersex', child: Text('Intersex')),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Other / self-described'),
                  ),
                ],
                onChanged: (value) => setState(() => sex = value),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date of birth'),
                subtitle: Text(
                  birthDate == null
                      ? 'Not set'
                      : birthDate!.toIso8601String().split('T').first,
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    initialDate: birthDate ?? DateTime(1990),
                  );
                  if (selected != null) setState(() => birthDate = selected);
                },
              ),
              TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Weight (kg)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: name.text.trim().isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    try {
      await controller.createProfile(
        name: name.text,
        dateOfBirth: birthDate,
        sex: sex,
        weightKg: parseOptionalDouble(weight.text),
        notes: notes.text,
      );
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  name.dispose();
  weight.dispose();
  notes.dispose();
}

Future<void> showAddSupplementDialog(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final brand = TextEditingController();
  final form = TextEditingController();
  final price = TextEditingController();
  final ingredients = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add supplement'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Product name *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: brand,
              decoration: const InputDecoration(labelText: 'Brand'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: form,
              decoration: const InputDecoration(labelText: 'Form'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ingredients,
              decoration: const InputDecoration(
                labelText: 'Ingredients',
                hintText: 'e.g. Magnesium, Vitamin B6',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Price (EUR)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      await controller.addSupplement(
        name: name.text,
        brand: brand.text,
        form: form.text,
        priceEur: parseOptionalDouble(price.text),
        ingredients: ingredients.text
            .split(',')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .map<Map<String, Object?>>((item) => {'name': item})
            .toList(),
      );
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [name, brand, form, price, ingredients]) {
    item.dispose();
  }
}

Future<void> showLogIntakeDialog(
  BuildContext context,
  AppController controller,
  Supplement supplement,
) async {
  final dose = TextEditingController(text: '1');
  final unit = TextEditingController(
    text: supplement.form.isEmpty ? 'unit' : supplement.form,
  );
  final notes = TextEditingController();
  DateTime takenAt = DateTime.now();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Log ${supplement.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: dose,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Dose *'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: 'Unit *'),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Time'),
              subtitle: Text(TimeOfDay.fromDateTime(takenAt).format(context)),
              trailing: const Icon(Icons.schedule),
              onTap: () async {
                final value = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.fromDateTime(takenAt),
                );
                if (value != null) {
                  setState(() {
                    takenAt = DateTime(
                      takenAt.year,
                      takenAt.month,
                      takenAt.day,
                      value.hour,
                      value.minute,
                    );
                  });
                }
              },
            ),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log intake'),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsedDose = parseOptionalDouble(dose.text);
    if (parsedDose == null || unit.text.trim().isEmpty) {
      await showAppError(context, 'Enter a valid dose and unit.');
    } else {
      try {
        await controller.logIntake(
          supplement: supplement,
          dose: parsedDose,
          unit: unit.text,
          takenAt: takenAt,
          notes: notes.text,
        );
      } on Object catch (error) {
        await showAppError(context, error);
      }
    }
  }
  dose.dispose();
  unit.dispose();
  notes.dispose();
}

Future<void> showAddScheduleDialog(
  BuildContext context,
  AppController controller,
  Supplement supplement,
) async {
  final dose = TextEditingController(text: '1');
  final unit = TextEditingController(
    text: supplement.form.isEmpty ? 'unit' : supplement.form,
  );
  String time = 'Morning';
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Schedule ${supplement.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: dose,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Dose'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: time,
              decoration: const InputDecoration(labelText: 'Time of day'),
              items: const [
                DropdownMenuItem(value: 'Morning', child: Text('Morning')),
                DropdownMenuItem(value: 'Midday', child: Text('Midday')),
                DropdownMenuItem(value: 'Evening', child: Text('Evening')),
                DropdownMenuItem(value: 'Bedtime', child: Text('Bedtime')),
              ],
              onChanged: (value) => setState(() => time = value ?? time),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsedDose = parseOptionalDouble(dose.text);
    if (parsedDose == null) {
      await showAppError(context, 'Enter a valid dose.');
    } else {
      try {
        await controller.addSchedule(
          supplement: supplement,
          dose: parsedDose,
          unit: unit.text,
          timeOfDay: time,
        );
      } on Object catch (error) {
        await showAppError(context, error);
      }
    }
  }
  dose.dispose();
  unit.dispose();
}

Future<void> showAddEventDialog(
  BuildContext context,
  AppController controller, {
  EventKind initialKind = EventKind.symptom,
}) async {
  final name = TextEditingController();
  final score = TextEditingController();
  final value = TextEditingController();
  final unit = TextEditingController();
  final notes = TextEditingController();
  var kind = initialKind;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Track health event'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<EventKind>(
                segments: const [
                  ButtonSegment(
                    value: EventKind.symptom,
                    label: Text('Symptom'),
                  ),
                  ButtonSegment(value: EventKind.tag, label: Text('Tag')),
                ],
                selected: {kind},
                onSelectionChanged: (value) =>
                    setState(() => kind = value.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: kind == EventKind.symptom
                      ? 'Symptom name *'
                      : 'Tag name *',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: score,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Score (0–10)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: value,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Numeric value',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unit,
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      await controller.addEvent(
        kind: kind,
        name: name.text,
        score: parseOptionalInt(score.text),
        value: parseOptionalDouble(value.text),
        unit: unit.text,
        notes: notes.text,
      );
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [name, score, value, unit, notes]) {
    item.dispose();
  }
}

Future<void> showAddBiomarkerDialog(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final category = TextEditingController();
  final unit = TextEditingController();
  final price = TextEditingController();
  final lab = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add biomarker'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: category,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unit,
              decoration: const InputDecoration(labelText: 'Default unit'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Lab price (EUR)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: lab,
              decoration: const InputDecoration(labelText: 'Lab name'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      await controller.addBiomarker(
        name: name.text,
        category: category.text,
        unit: unit.text,
        priceEur: parseOptionalDouble(price.text),
        labName: lab.text,
      );
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [name, category, unit, price, lab]) {
    item.dispose();
  }
}

Future<void> showAddMeasurementDialog(
  BuildContext context,
  AppController controller,
  Biomarker biomarker,
) async {
  final value = TextEditingController();
  final unit = TextEditingController(text: biomarker.defaultUnit);
  final low = TextEditingController();
  final high = TextEditingController();
  final notes = TextEditingController();
  var date = DateTime.now();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Record ${biomarker.displayName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: value,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Value *'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unit,
                      decoration: const InputDecoration(labelText: 'Unit *'),
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sample date'),
                subtitle: Text(date.toIso8601String().split('T').first),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                    initialDate: date,
                  );
                  if (selected != null) setState(() => date = selected);
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: low,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Lab ref. low',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: high,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Lab ref. high',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsed = parseOptionalDouble(value.text);
    if (parsed == null || unit.text.trim().isEmpty) {
      await showAppError(context, 'Enter a valid value and unit.');
    } else {
      try {
        await controller.addMeasurement(
          biomarker: biomarker,
          value: parsed,
          unit: unit.text,
          takenAt: date,
          refLow: parseOptionalDouble(low.text),
          refHigh: parseOptionalDouble(high.text),
          notes: notes.text,
        );
      } on Object catch (error) {
        await showAppError(context, error);
      }
    }
  }
  for (final item in [value, unit, low, high, notes]) {
    item.dispose();
  }
}

Future<void> showAddNamedRecordDialog(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final dose = TextEditingController();
  final unit = TextEditingController();
  final schedule = TextEditingController();
  final notes = TextEditingController();
  var kind = 'condition';
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add health context'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(
                    value: 'condition',
                    child: Text('Condition'),
                  ),
                  DropdownMenuItem(
                    value: 'medication',
                    child: Text('Medication'),
                  ),
                  DropdownMenuItem(value: 'goal', child: Text('Goal')),
                  DropdownMenuItem(
                    value: 'family_history',
                    child: Text('Family history'),
                  ),
                ],
                onChanged: (value) => setState(() => kind = value ?? kind),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name *'),
              ),
              if (kind == 'medication') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dose,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Dose'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: schedule,
                  decoration: const InputDecoration(labelText: 'Schedule'),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      await controller.addNamedRecord(
        kind: kind,
        name: name.text,
        dose: parseOptionalDouble(dose.text),
        unit: unit.text,
        schedule: schedule.text,
        notes: notes.text,
      );
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [name, dose, unit, schedule, notes]) {
    item.dispose();
  }
}
