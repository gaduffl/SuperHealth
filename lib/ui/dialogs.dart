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
  AppController controller, {
  Supplement? existing,
}) async {
  final name = TextEditingController(text: existing?.name);
  final brand = TextEditingController(text: existing?.brand);
  final form = TextEditingController(text: existing?.form);
  final price = TextEditingController(
    text: existing?.priceEur?.toString() ?? '',
  );
  final unitsPerContainer = TextEditingController(
    text: existing?.unitsPerContainer?.toString() ?? '',
  );
  final initialContainers = TextEditingController();
  final stockUnit = TextEditingController(text: existing?.stockUnit ?? 'unit');
  final lowStock = TextEditingController(
    text: existing?.lowStockThresholdUnits?.toString() ?? '',
  );
  final bioavailability = TextEditingController(
    text: existing?.bioavailability,
  );
  final notes = TextEditingController(text: existing?.notes);
  final ingredients = TextEditingController(
    text: existing?.ingredients
        .map(
          (item) => [
            item['name'] ?? '',
            item['amount'] ?? '',
            item['unit'] ?? '',
          ].join(' | '),
        )
        .join('\n'),
  );
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(existing == null ? 'Add supplement' : 'Edit supplement'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Product name *'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: brand,
                      decoration: const InputDecoration(labelText: 'Brand'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: form,
                      decoration: const InputDecoration(
                        labelText: 'Form (capsule, powder…)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ingredients,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Ingredients — one per line',
                  hintText: 'Magnesium glycinate | 100 | mg',
                  helperText: 'Format: name | amount per stock unit | unit',
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: unitsPerContainer,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Units / container',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: stockUnit,
                      decoration: const InputDecoration(
                        labelText: 'Stock unit *',
                      ),
                    ),
                  ),
                ],
              ),
              if (existing == null) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: initialContainers,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Current containers (initial stock)',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Price / container (EUR)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: lowStock,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Low-stock threshold',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bioavailability,
                decoration: const InputDecoration(
                  labelText: 'Form / bioavailability notes',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(existing == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      final parsedIngredients = _parseIngredients(ingredients.text);
      final units = parseOptionalInt(unitsPerContainer.text);
      if (stockUnit.text.trim().isEmpty ||
          (units != null && units <= 0) ||
          parsedIngredients == null) {
        throw StateError(
          'Check the stock unit, container size, and ingredient lines.',
        );
      }
      if (existing == null) {
        await controller.addSupplement(
          name: name.text,
          brand: brand.text,
          form: form.text,
          priceEur: parseOptionalDouble(price.text),
          ingredients: parsedIngredients,
          unitsPerContainer: units,
          initialContainers: parseOptionalDouble(initialContainers.text),
          stockUnit: stockUnit.text,
          lowStockThresholdUnits: parseOptionalDouble(lowStock.text),
          bioavailability: bioavailability.text,
          notes: notes.text,
        );
      } else {
        await controller.updateSupplement(
          Supplement(
            id: existing.id,
            name: name.text,
            brand: brand.text,
            form: form.text,
            ingredients: parsedIngredients,
            unitsPerContainer: units,
            containerCount: existing.containerCount,
            priceEur: parseOptionalDouble(price.text),
            bioavailability: bioavailability.text,
            notes: notes.text,
            active: existing.active,
            lowStockAlerts: existing.lowStockAlerts,
            lowStockThresholdUnits: parseOptionalDouble(lowStock.text),
            stockUnit: stockUnit.text,
            sourceId: existing.sourceId,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
          ),
        );
      }
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [
    name,
    brand,
    form,
    price,
    ingredients,
    unitsPerContainer,
    initialContainers,
    stockUnit,
    lowStock,
    bioavailability,
    notes,
  ]) {
    item.dispose();
  }
}

List<Map<String, Object?>>? _parseIngredients(String source) {
  final result = <Map<String, Object?>>[];
  for (final raw in source.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('|').map((item) => item.trim()).toList();
    if (parts.first.isEmpty || parts.length > 3) return null;
    final amount = parts.length > 1 && parts[1].isNotEmpty
        ? parseOptionalDouble(parts[1])
        : null;
    if (parts.length > 1 && parts[1].isNotEmpty && amount == null) return null;
    result.add({
      'name': parts.first,
      if (amount != null) 'amount': amount,
      if (parts.length > 2 && parts[2].isNotEmpty) 'unit': parts[2],
    });
  }
  return result;
}

Future<void> showAdjustStockDialog(
  BuildContext context,
  AppController controller,
  Supplement supplement, {
  bool purchase = false,
}) async {
  final amount = TextEditingController();
  final notes = TextEditingController();
  var direction = purchase ? 'add' : 'set';
  final current = controller.stockLevels[supplement.id] ?? 0;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(purchase ? 'Record purchase' : 'Adjust stock'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(supplement.name),
                subtitle: Text(
                  '${current.toStringAsFixed(1)} ${supplement.stockUnit} on hand',
                ),
              ),
              if (!purchase)
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'set', label: Text('Set total')),
                    ButtonSegment(value: 'add', label: Text('Add')),
                    ButtonSegment(value: 'remove', label: Text('Remove')),
                  ],
                  selected: {direction},
                  onSelectionChanged: (value) =>
                      setState(() => direction = value.first),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: direction == 'set'
                      ? 'New total (${supplement.stockUnit})'
                      : 'Quantity (${supplement.stockUnit})',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: const InputDecoration(
                  labelText: 'Note / order reference',
                ),
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
    final parsed = parseOptionalDouble(amount.text);
    if (parsed == null || parsed < 0) {
      await showAppError(context, 'Enter a non-negative quantity.');
    } else {
      final delta = switch (direction) {
        'set' => parsed - current,
        'remove' => -parsed,
        _ => parsed,
      };
      try {
        await controller.adjustStock(
          supplement: supplement,
          quantityUnits: delta,
          reason: purchase ? 'purchase' : 'correction',
          notes: notes.text,
        );
      } on Object catch (error) {
        if (context.mounted) await showAppError(context, error);
      }
    }
  }
  amount.dispose();
  notes.dispose();
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
  Supplement supplement, {
  SupplementSchedule? existing,
}) async {
  final dose = TextEditingController(text: existing?.dose.toString() ?? '1');
  final unit = TextEditingController(
    text:
        existing?.unit ??
        (supplement.form.isEmpty ? supplement.stockUnit : supplement.form),
  );
  final instructions = TextEditingController(text: existing?.instructions);
  var time = existing?.timeOfDay ?? 'Morning';
  var weekdays = {
    ...(existing?.weekdays ??
        const [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ]),
  };
  var reminderEnabled = existing?.reminderEnabled ?? false;
  var active = existing?.active ?? true;
  var startDate = existing?.startDate;
  var endDate = existing?.endDate;
  const dayLabels = {
    'monday': 'M',
    'tuesday': 'T',
    'wednesday': 'W',
    'thursday': 'T',
    'friday': 'F',
    'saturday': 'S',
    'sunday': 'S',
  };
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null
              ? 'Schedule ${supplement.name}'
              : 'Edit ${supplement.name} schedule',
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 520,
            child: Column(
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
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Days',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final day in dayLabels.entries)
                      FilterChip(
                        label: Text(day.value),
                        tooltip: day.key,
                        selected: weekdays.contains(day.key),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            weekdays.add(day.key);
                          } else {
                            weekdays.remove(day.key);
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Starts'),
                        subtitle: Text(
                          startDate?.toIso8601String().split('T').first ??
                              'Immediately',
                        ),
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDate: startDate ?? DateTime.now(),
                          );
                          if (value != null) setState(() => startDate = value);
                        },
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ends'),
                        subtitle: Text(
                          endDate?.toIso8601String().split('T').first ??
                              'No end date',
                        ),
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            firstDate: startDate ?? DateTime(2000),
                            lastDate: DateTime(2100),
                            initialDate:
                                endDate ??
                                startDate ??
                                DateTime.now().add(const Duration(days: 30)),
                          );
                          if (value != null) setState(() => endDate = value);
                        },
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: instructions,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Instructions',
                    hintText: 'With food, separated from medication…',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reminder notification'),
                  value: reminderEnabled,
                  onChanged: (value) => setState(() => reminderEnabled = value),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Active schedule'),
                    value: active,
                    onChanged: (value) => setState(() => active = value),
                  ),
              ],
            ),
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
    final parsedDose = parseOptionalDouble(dose.text);
    if (parsedDose == null ||
        parsedDose < 0 ||
        unit.text.trim().isEmpty ||
        weekdays.isEmpty ||
        (startDate != null &&
            endDate != null &&
            endDate!.isBefore(startDate!))) {
      await showAppError(context, 'Check dose, unit, days, and date range.');
    } else {
      try {
        if (existing == null) {
          await controller.addSchedule(
            supplement: supplement,
            dose: parsedDose,
            unit: unit.text,
            timeOfDay: time,
            weekdays: weekdays.toList(),
            instructions: instructions.text,
            startDate: startDate,
            endDate: endDate,
            reminderEnabled: reminderEnabled,
          );
        } else {
          await controller.updateSchedule(
            SupplementSchedule(
              id: existing.id,
              profileId: existing.profileId,
              supplementId: existing.supplementId,
              dose: parsedDose,
              unit: unit.text,
              timeOfDay: time,
              weekdays: weekdays.toList(),
              instructions: instructions.text,
              startDate: startDate,
              endDate: endDate,
              active: active,
              reminderEnabled: reminderEnabled,
              createdAt: existing.createdAt,
              updatedAt: existing.updatedAt,
            ),
          );
        }
      } on Object catch (error) {
        await showAppError(context, error);
      }
    }
  }
  dose.dispose();
  unit.dispose();
  instructions.dispose();
}

Future<void> showAddEventDialog(
  BuildContext context,
  AppController controller, {
  EventKind initialKind = EventKind.symptom,
  HealthEvent? existing,
}) async {
  final name = TextEditingController(text: existing?.name);
  final score = TextEditingController(text: existing?.score?.toString() ?? '');
  final value = TextEditingController(
    text: existing?.numericValue?.toString() ?? '',
  );
  final unit = TextEditingController(text: existing?.unit);
  final duration = TextEditingController(
    text: existing?.durationMinutes?.toString() ?? '',
  );
  final notes = TextEditingController(text: existing?.notes);
  var kind = existing?.kind ?? initialKind;
  var observedAt = existing?.observedAt ?? DateTime.now();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Track health event' : 'Edit event'),
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
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final definition
                        in controller.eventDefinitions
                            .where((item) => item.kind == kind)
                            .take(8))
                      ActionChip(
                        label: Text(definition.name),
                        onPressed: () {
                          name.text = definition.name;
                          unit.text = definition.defaultUnit ?? unit.text;
                        },
                      ),
                  ],
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
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes)',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Observed at'),
                subtitle: Text(
                  '${observedAt.toIso8601String().split('T').first} · '
                  '${TimeOfDay.fromDateTime(observedAt).format(context)}',
                ),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                    initialDate: observedAt,
                  );
                  if (date == null || !context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.fromDateTime(observedAt),
                  );
                  if (time != null) {
                    setState(() {
                      observedAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      );
                    });
                  }
                },
              ),
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
      final parsedScore = parseOptionalInt(score.text);
      if (parsedScore != null && (parsedScore < 0 || parsedScore > 10)) {
        throw StateError('Symptom score must be between 0 and 10.');
      }
      if (existing == null) {
        await controller.addEvent(
          kind: kind,
          name: name.text,
          score: parsedScore,
          value: parseOptionalDouble(value.text),
          unit: unit.text,
          observedAt: observedAt,
          durationMinutes: parseOptionalInt(duration.text),
          notes: notes.text,
        );
      } else {
        await controller.updateEvent(
          HealthEvent(
            id: existing.id,
            profileId: existing.profileId,
            definitionId: existing.definitionId,
            kind: kind,
            name: name.text,
            observedAt: observedAt,
            score: parsedScore,
            numericValue: parseOptionalDouble(value.text),
            unit: unit.text,
            durationMinutes: parseOptionalInt(duration.text),
            notes: notes.text,
            colorValue: existing.colorValue,
            archived: existing.archived,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
          ),
        );
      }
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [name, score, value, unit, duration, notes]) {
    item.dispose();
  }
}

Future<void> showAddBiomarkerDialog(
  BuildContext context,
  AppController controller, {
  Biomarker? existing,
}) async {
  final name = TextEditingController(text: existing?.displayName);
  final category = TextEditingController(text: existing?.category);
  final unit = TextEditingController(text: existing?.defaultUnit);
  final price = TextEditingController(
    text: existing?.priceEur?.toStringAsFixed(2) ?? '',
  );
  final lab = TextEditingController(text: existing?.labName);
  final description = TextEditingController(text: existing?.description);
  final synonyms = TextEditingController(text: existing?.synonyms.join(', '));
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(existing == null ? 'Add biomarker' : 'Edit biomarker'),
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
            const SizedBox(height: 10),
            TextField(
              controller: synonyms,
              decoration: const InputDecoration(
                labelText: 'Synonyms',
                hintText: 'Comma-separated names used on lab reports',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
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
          child: Text(existing == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      final parsedSynonyms = synonyms.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();
      if (existing == null) {
        await controller.addBiomarker(
          name: name.text,
          category: category.text,
          unit: unit.text,
          priceEur: parseOptionalDouble(price.text),
          labName: lab.text,
          description: description.text,
          synonyms: parsedSynonyms,
        );
      } else {
        await controller.updateBiomarker(
          Biomarker(
            id: existing.id,
            canonicalName: existing.canonicalName,
            displayName: name.text,
            category: category.text,
            defaultUnit: unit.text,
            priceEur: parseOptionalDouble(price.text),
            labName: lab.text,
            priceCheckedAt: price.text.trim().isEmpty
                ? existing.priceCheckedAt
                : DateTime.now(),
            description: description.text,
            synonyms: parsedSynonyms,
            isTemporary: existing.isTemporary,
            createdAt: existing.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [
    name,
    category,
    unit,
    price,
    lab,
    description,
    synonyms,
  ]) {
    item.dispose();
  }
}

Future<void> showAddMeasurementDialog(
  BuildContext context,
  AppController controller,
  Biomarker biomarker, {
  Measurement? existing,
}) async {
  final value = TextEditingController(text: existing?.value.toString() ?? '');
  final unit = TextEditingController(
    text: existing?.unit ?? biomarker.defaultUnit,
  );
  final low = TextEditingController(text: existing?.labRefLow?.toString());
  final high = TextEditingController(text: existing?.labRefHigh?.toString());
  final notes = TextEditingController(text: existing?.notes);
  var date = existing?.takenAt ?? DateTime.now();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null
              ? 'Record ${biomarker.displayName}'
              : 'Edit ${biomarker.displayName}',
        ),
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
            child: Text(existing == null ? 'Add result' : 'Save'),
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
        if (existing == null) {
          await controller.addMeasurement(
            biomarker: biomarker,
            value: parsed,
            unit: unit.text,
            takenAt: date,
            refLow: parseOptionalDouble(low.text),
            refHigh: parseOptionalDouble(high.text),
            notes: notes.text,
          );
        } else {
          await controller.updateMeasurement(
            Measurement(
              id: existing.id,
              profileId: existing.profileId,
              biomarkerId: existing.biomarkerId,
              documentId: existing.documentId,
              takenAt: date,
              value: parsed,
              unit: unit.text,
              labRefLow: parseOptionalDouble(low.text),
              labRefHigh: parseOptionalDouble(high.text),
              page: existing.page,
              rowText: existing.rowText,
              extractionConfidence: existing.extractionConfidence,
              flags: existing.flags,
              notes: notes.text,
              createdAt: existing.createdAt,
              updatedAt: DateTime.now(),
            ),
          );
        }
      } on Object catch (error) {
        await showAppError(context, error);
      }
    }
  }
  for (final item in [value, unit, low, high, notes]) {
    item.dispose();
  }
}

Future<void> showProfileTargetDialog(
  BuildContext context,
  AppController controller,
  Biomarker biomarker, {
  ProfileBiomarkerTarget? existing,
}) async {
  final low = TextEditingController(text: existing?.low?.toString() ?? '');
  final high = TextEditingController(text: existing?.high?.toString() ?? '');
  final borderlineLow = TextEditingController(
    text: existing?.borderlineLow?.toString() ?? '',
  );
  final borderlineHigh = TextEditingController(
    text: existing?.borderlineHigh?.toString() ?? '',
  );
  final unit = TextEditingController(
    text: existing?.unit ?? biomarker.defaultUnit,
  );
  final source = TextEditingController(text: existing?.source ?? 'personal');
  final notes = TextEditingController(text: existing?.notes);
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Personal target · ${biomarker.displayName}'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Card(
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('This target belongs only to the active profile'),
                  subtitle: Text(
                    'It does not overwrite lab reference ranges or another profile’s longevity target.',
                  ),
                ),
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
                        labelText: 'Target low',
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
                        labelText: 'Target high',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: borderlineLow,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Borderline low',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: borderlineHigh,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Borderline high',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unit,
                decoration: const InputDecoration(labelText: 'Unit *'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: source,
                decoration: const InputDecoration(
                  labelText: 'Source / rationale',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Cancel'),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Save target'),
        ),
      ],
    ),
  );
  if (result == true && context.mounted) {
    final parsedLow = parseOptionalDouble(low.text);
    final parsedHigh = parseOptionalDouble(high.text);
    if (unit.text.trim().isEmpty ||
        (parsedLow != null && parsedHigh != null && parsedLow > parsedHigh)) {
      await showAppError(context, 'Check the target range and unit.');
    } else {
      final now = DateTime.now();
      try {
        await controller.saveProfileTarget(
          ProfileBiomarkerTarget(
            id: existing?.id ?? controller.repository.newId(),
            profileId: controller.activeProfile!.id,
            biomarkerId: biomarker.id,
            low: parsedLow,
            high: parsedHigh,
            borderlineLow: parseOptionalDouble(borderlineLow.text),
            borderlineHigh: parseOptionalDouble(borderlineHigh.text),
            unit: unit.text,
            source: source.text,
            notes: notes.text,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now,
          ),
        );
      } on Object catch (error) {
        if (context.mounted) await showAppError(context, error);
      }
    }
  }
  for (final item in [
    low,
    high,
    borderlineLow,
    borderlineHigh,
    unit,
    source,
    notes,
  ]) {
    item.dispose();
  }
}

Future<void> showAddNamedRecordDialog(
  BuildContext context,
  AppController controller, {
  NamedHealthRecord? existing,
}) async {
  final name = TextEditingController(text: existing?.name);
  final dose = TextEditingController(text: existing?.dose?.toString() ?? '');
  final unit = TextEditingController(text: existing?.unit);
  final schedule = TextEditingController(text: existing?.schedule);
  final priority = TextEditingController(
    text: existing?.priority?.toString() ?? '',
  );
  final notes = TextEditingController(text: existing?.notes);
  var kind = existing?.kind ?? 'condition';
  var status = existing?.status ?? 'active';
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null ? 'Add health context' : 'Edit context'),
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
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(
                    value: 'monitoring',
                    child: Text('Monitoring'),
                  ),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'paused', child: Text('Paused')),
                ],
                onChanged: (value) => setState(() => status = value ?? status),
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
              if (kind == 'goal') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: priority,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Priority (1–5)',
                  ),
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
      if (existing == null) {
        await controller.addNamedRecord(
          kind: kind,
          name: name.text,
          status: status,
          dose: parseOptionalDouble(dose.text),
          unit: unit.text,
          schedule: schedule.text,
          priority: parseOptionalInt(priority.text),
          notes: notes.text,
        );
      } else {
        await controller.updateNamedRecord(
          NamedHealthRecord(
            id: existing.id,
            profileId: existing.profileId,
            name: name.text,
            kind: kind,
            status: status,
            dose: parseOptionalDouble(dose.text),
            unit: unit.text,
            schedule: schedule.text,
            startDate: existing.startDate,
            endDate: existing.endDate,
            priority: parseOptionalInt(priority.text),
            targetDate: existing.targetDate,
            notes: notes.text,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
          ),
        );
      }
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  for (final item in [name, dose, unit, schedule, priority, notes]) {
    item.dispose();
  }
}
