// All async dialog continuations guard context.mounted before UI access.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';

String _dialogText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

Future<void> showAddProfileDialog(
  BuildContext context,
  AppController controller,
) => showProfileDialog(context, controller);

Future<void> showEditProfileDialog(
  BuildContext context,
  AppController controller,
  Profile profile,
) => showProfileDialog(context, controller, existing: profile);

/// Creates or updates a profile using only fields persisted by [Profile].
Future<void> showProfileDialog(
  BuildContext context,
  AppController controller, {
  Profile? existing,
}) async {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(text: existing?.displayName ?? '');
  final weight = TextEditingController(
    text: existing?.weightKg?.toString() ?? '',
  );
  final height = TextEditingController(
    text: existing?.heightCm?.toString() ?? '',
  );
  final notes = TextEditingController(text: existing?.notes ?? '');
  DateTime? birthDate = existing?.dateOfBirth;
  String? sex = existing?.sex;
  String? birthDateError;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null
              ? _dialogText(context, 'New profile', 'Neues Profil')
              : _dialogText(context, 'Edit profile', 'Profil bearbeiten'),
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 520,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: _dialogText(
                        context,
                        'Display name *',
                        'Anzeigename *',
                      ),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? _dialogText(
                            context,
                            'Enter a display name.',
                            'Gib einen Anzeigenamen ein.',
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey(sex),
                    initialValue: sex,
                    decoration: InputDecoration(
                      labelText: _dialogText(
                        context,
                        'Sex (optional)',
                        'Geschlecht (optional)',
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'female',
                        child: Text(_dialogText(context, 'Female', 'Weiblich')),
                      ),
                      DropdownMenuItem(
                        value: 'male',
                        child: Text(_dialogText(context, 'Male', 'Männlich')),
                      ),
                      DropdownMenuItem(
                        value: 'intersex',
                        child: Text(
                          _dialogText(
                            context,
                            'Intersex',
                            'Intergeschlechtlich',
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(
                          _dialogText(
                            context,
                            'Other / self-described',
                            'Andere / selbst beschrieben',
                          ),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => sex = value),
                  ),
                  if (sex != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => setState(() => sex = null),
                        icon: const Icon(Icons.clear),
                        label: Text(
                          _dialogText(
                            context,
                            'Clear sex',
                            'Geschlecht löschen',
                          ),
                        ),
                      ),
                    ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _dialogText(context, 'Date of birth', 'Geburtsdatum'),
                    ),
                    subtitle: Text(
                      birthDate == null
                          ? _dialogText(context, 'Not set', 'Nicht festgelegt')
                          : '${_formatProfileDate(birthDate!)} · ${_profileAgeLabel(context, birthDate!)}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (birthDate != null)
                          IconButton(
                            tooltip: _dialogText(
                              context,
                              'Clear date of birth',
                              'Geburtsdatum löschen',
                            ),
                            onPressed: () => setState(() => birthDate = null),
                            icon: const Icon(Icons.clear),
                          ),
                        const Icon(Icons.calendar_today_outlined),
                      ],
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1900),
                        lastDate: now,
                        initialDate: _profilePickerDate(birthDate, now),
                      );
                      if (selected != null) {
                        setState(() {
                          birthDate = selected;
                          birthDateError = null;
                        });
                      }
                    },
                  ),
                  if (birthDateError != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        birthDateError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  TextFormField(
                    controller: height,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: _dialogText(
                        context,
                        'Height (cm)',
                        'Größe (cm)',
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = parseOptionalDouble(value);
                      if (parsed == null || parsed < 30 || parsed > 250) {
                        return _dialogText(
                          context,
                          'Enter a height from 30 to 250 cm.',
                          'Gib eine Größe von 30 bis 250 cm ein.',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: _dialogText(
                        context,
                        'Weight (kg)',
                        'Gewicht (kg)',
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      final parsed = parseOptionalDouble(value);
                      if (parsed == null || parsed <= 0 || parsed > 500) {
                        return _dialogText(
                          context,
                          'Enter a weight from 0 to 500 kg.',
                          'Gib ein Gewicht über 0 bis 500 kg ein.',
                        );
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: _dialogText(
                        context,
                        'Notes / goals',
                        'Notizen / Ziele',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () {
              final today = DateTime.now();
              final dateIsValid =
                  birthDate == null || !birthDate!.isAfter(today);
              setState(() {
                birthDateError = dateIsValid
                    ? null
                    : _dialogText(
                        context,
                        'Date of birth cannot be in the future.',
                        'Das Geburtsdatum darf nicht in der Zukunft liegen.',
                      );
              });
              if (formKey.currentState!.validate() && dateIsValid) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: Text(
              existing == null
                  ? _dialogText(context, 'Create', 'Erstellen')
                  : _dialogText(
                      context,
                      'Save changes',
                      'Änderungen speichern',
                    ),
            ),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    try {
      if (existing == null) {
        await controller.createProfile(
          name: name.text,
          dateOfBirth: birthDate,
          sex: sex,
          heightCm: parseOptionalDouble(height.text),
          weightKg: parseOptionalDouble(weight.text),
          notes: notes.text,
        );
      } else {
        await controller.updateProfile(
          Profile(
            id: existing.id,
            displayName: name.text,
            dateOfBirth: birthDate,
            sex: sex,
            heightCm: parseOptionalDouble(height.text),
            weightKg: parseOptionalDouble(weight.text),
            notes: notes.text,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt,
            deleted: existing.deleted,
          ),
        );
      }
    } on Object catch (error) {
      await showAppError(context, error);
    }
  }
  name.dispose();
  height.dispose();
  weight.dispose();
  notes.dispose();
}

DateTime _profilePickerDate(DateTime? date, DateTime today) {
  final fallback = DateTime(today.year - 35, today.month, today.day);
  if (date == null) return fallback;
  if (date.isAfter(today)) return today;
  if (date.isBefore(DateTime(1900))) return DateTime(1900);
  return date;
}

String _formatProfileDate(DateTime date) =>
    date.toIso8601String().split('T').first;

String _profileAgeLabel(BuildContext context, DateTime date) {
  final today = DateTime.now();
  var age = today.year - date.year;
  if (today.month < date.month ||
      (today.month == date.month && today.day < date.day)) {
    age--;
  }
  return age < 0
      ? _dialogText(context, 'Future date', 'Zukünftiges Datum')
      : _dialogText(context, 'Age $age', 'Alter $age');
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
      title: Text(
        existing == null
            ? _dialogText(
                context,
                'Add supplement',
                'Nahrungsergänzung hinzufügen',
              )
            : _dialogText(
                context,
                'Edit supplement',
                'Nahrungsergänzung bearbeiten',
              ),
      ),
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
                decoration: InputDecoration(
                  labelText: _dialogText(
                    context,
                    'Product name *',
                    'Produktname *',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: brand,
                      decoration: InputDecoration(
                        labelText: _dialogText(context, 'Brand', 'Marke'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: form,
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Form (capsule, powder…)',
                          'Form (Kapsel, Pulver …)',
                        ),
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
                decoration: InputDecoration(
                  labelText: _dialogText(
                    context,
                    'Ingredients — one per line',
                    'Inhaltsstoffe — einer pro Zeile',
                  ),
                  hintText: 'Magnesium glycinate | 100 | mg',
                  helperText: _dialogText(
                    context,
                    'Format: name | amount per stock unit | unit',
                    'Format: Name | Menge je Bestandseinheit | Einheit',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: unitsPerContainer,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Units / container',
                          'Einheiten / Behälter',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: stockUnit,
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Stock unit *',
                          'Bestandseinheit *',
                        ),
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
                  decoration: InputDecoration(
                    labelText: _dialogText(
                      context,
                      'Current containers (initial stock)',
                      'Aktuelle Behälter (Anfangsbestand)',
                    ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Price / container (EUR)',
                          'Preis / Behälter (EUR)',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Low-stock threshold',
                          'Grenze für niedrigen Bestand',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bioavailability,
                decoration: InputDecoration(
                  labelText: _dialogText(
                    context,
                    'Form / bioavailability notes',
                    'Hinweise zu Form / Bioverfügbarkeit',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Notes', 'Notizen'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            existing == null
                ? _dialogText(context, 'Add', 'Hinzufügen')
                : _dialogText(context, 'Save', 'Speichern'),
          ),
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
          _dialogText(
            context,
            'Check the stock unit, container size, and ingredient lines.',
            'Prüfe Bestandseinheit, Behältergröße und Inhaltsstoffzeilen.',
          ),
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
      'amount': ?amount,
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
        title: Text(
          purchase
              ? _dialogText(context, 'Record purchase', 'Einkauf erfassen')
              : _dialogText(context, 'Adjust stock', 'Bestand anpassen'),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(supplement.name),
                subtitle: Text(
                  _dialogText(
                    context,
                    '${current.toStringAsFixed(1)} ${supplement.stockUnit} on hand',
                    '${current.toStringAsFixed(1)} ${supplement.stockUnit} vorhanden',
                  ),
                ),
              ),
              if (!purchase)
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'set',
                      label: Text(
                        _dialogText(context, 'Set total', 'Gesamt setzen'),
                      ),
                    ),
                    ButtonSegment(
                      value: 'add',
                      label: Text(_dialogText(context, 'Add', 'Hinzufügen')),
                    ),
                    ButtonSegment(
                      value: 'remove',
                      label: Text(_dialogText(context, 'Remove', 'Entfernen')),
                    ),
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
                      ? _dialogText(
                          context,
                          'New total (${supplement.stockUnit})',
                          'Neuer Gesamtbestand (${supplement.stockUnit})',
                        )
                      : _dialogText(
                          context,
                          'Quantity (${supplement.stockUnit})',
                          'Menge (${supplement.stockUnit})',
                        ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: InputDecoration(
                  labelText: _dialogText(
                    context,
                    'Note / order reference',
                    'Notiz / Bestellreferenz',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_dialogText(context, 'Save', 'Speichern')),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsed = parseOptionalDouble(amount.text);
    if (parsed == null || parsed < 0) {
      await showAppError(
        context,
        _dialogText(
          context,
          'Enter a non-negative quantity.',
          'Gib eine nichtnegative Menge ein.',
        ),
      );
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
    text: supplement.stockUnit.trim().isNotEmpty
        ? supplement.stockUnit
        : (supplement.form.trim().isNotEmpty ? supplement.form : 'unit'),
  );
  final notes = TextEditingController();
  DateTime takenAt = DateTime.now();
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          _dialogText(
            context,
            'Log ${supplement.name}',
            '${supplement.name} erfassen',
          ),
        ),
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
                    decoration: InputDecoration(
                      labelText: _dialogText(context, 'Dose *', 'Dosis *'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unit,
                    decoration: InputDecoration(
                      labelText: _dialogText(context, 'Unit *', 'Einheit *'),
                    ),
                  ),
                ),
              ],
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_dialogText(context, 'Time', 'Zeit')),
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
              decoration: InputDecoration(
                labelText: _dialogText(context, 'Notes', 'Notizen'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              _dialogText(context, 'Log intake', 'Einnahme erfassen'),
            ),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsedDose = parseOptionalDouble(dose.text);
    if (parsedDose == null || unit.text.trim().isEmpty) {
      await showAppError(
        context,
        _dialogText(
          context,
          'Enter a valid dose and unit.',
          'Gib eine gültige Dosis und Einheit ein.',
        ),
      );
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
  var selectedNamedTime = _namedTimeChoice(time);
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
  const days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null
              ? _dialogText(
                  context,
                  'Schedule ${supplement.name}',
                  '${supplement.name} planen',
                )
              : _dialogText(
                  context,
                  'Edit ${supplement.name} schedule',
                  'Plan für ${supplement.name} bearbeiten',
                ),
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
                        decoration: InputDecoration(
                          labelText: _dialogText(context, 'Dose', 'Dosis'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unit,
                        decoration: InputDecoration(
                          labelText: _dialogText(context, 'Unit', 'Einheit'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: ValueKey(selectedNamedTime),
                  initialValue: selectedNamedTime,
                  decoration: InputDecoration(
                    labelText: _dialogText(context, 'Time of day', 'Tageszeit'),
                    hintText: selectedNamedTime == null
                        ? _dialogText(
                            context,
                            'Custom exact time',
                            'Benutzerdefinierte Uhrzeit',
                          )
                        : null,
                  ),
                  items: [
                    for (final value in const [
                      'Morning',
                      'Midday',
                      'Evening',
                      'Bedtime',
                    ])
                      DropdownMenuItem(
                        value: value,
                        child: Text(_namedTimeLabel(context, value)),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    if (value == null) return;
                    selectedNamedTime = value;
                    time = value;
                  }),
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(
                    _dialogText(
                      context,
                      'Choose exact time',
                      'Genaue Uhrzeit wählen',
                    ),
                  ),
                  subtitle: Text(
                    selectedNamedTime == null
                        ? _exactTimeDescription(context, time)
                        : _dialogText(
                            context,
                            '${selectedNamedTime!} uses ${_namedTimeDescription(selectedNamedTime!)}',
                            '${_namedTimeLabel(context, selectedNamedTime!)} verwendet ${_namedTimeDescription(selectedNamedTime!)}',
                          ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final initial = _timeOfDayForPicker(time);
                    final selected = await showTimePicker(
                      context: context,
                      initialTime: initial,
                      helpText: _dialogText(
                        context,
                        'Choose reminder time',
                        'Erinnerungszeit wählen',
                      ),
                    );
                    if (selected == null) return;
                    setState(() {
                      time = _formatTimeOfDay(selected);
                      selectedNamedTime = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _dialogText(context, 'Days', 'Tage'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final day in days)
                      FilterChip(
                        label: Text(_weekdayShort(context, day)),
                        tooltip: _weekdayLabel(context, day),
                        selected: weekdays.contains(day),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            weekdays.add(day);
                          } else {
                            weekdays.remove(day);
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
                        title: Text(_dialogText(context, 'Starts', 'Beginnt')),
                        subtitle: Text(
                          startDate?.toIso8601String().split('T').first ??
                              _dialogText(context, 'Immediately', 'Sofort'),
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
                        title: Text(_dialogText(context, 'Ends', 'Endet')),
                        subtitle: Text(
                          endDate?.toIso8601String().split('T').first ??
                              _dialogText(
                                context,
                                'No end date',
                                'Kein Enddatum',
                              ),
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
                  decoration: InputDecoration(
                    labelText: _dialogText(
                      context,
                      'Instructions',
                      'Anweisungen',
                    ),
                    hintText: _dialogText(
                      context,
                      'With food, separated from medication…',
                      'Mit Essen, zeitlich getrennt von Medikamenten …',
                    ),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _dialogText(
                      context,
                      'Reminder notification',
                      'Erinnerungsbenachrichtigung',
                    ),
                  ),
                  value: reminderEnabled,
                  onChanged: (value) => setState(() => reminderEnabled = value),
                ),
                if (existing != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      _dialogText(context, 'Active schedule', 'Aktiver Plan'),
                    ),
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
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_dialogText(context, 'Save', 'Speichern')),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsedDose = parseOptionalDouble(dose.text);
    if (!_isValidScheduleTime(time)) {
      await showAppError(
        context,
        _dialogText(
          context,
          'Choose a named time or an exact time from the time picker to repair this schedule.',
          'Wähle eine benannte Zeit oder eine genaue Uhrzeit, um diesen Plan zu reparieren.',
        ),
      );
    } else if (parsedDose == null ||
        parsedDose < 0 ||
        unit.text.trim().isEmpty ||
        weekdays.isEmpty ||
        (startDate != null &&
            endDate != null &&
            endDate!.isBefore(startDate!))) {
      await showAppError(
        context,
        _dialogText(
          context,
          'Check dose, unit, days, and date range.',
          'Prüfe Dosis, Einheit, Tage und Datumsbereich.',
        ),
      );
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

TimeOfDay _timeOfDayForPicker(String value) {
  switch (value.trim().toLowerCase()) {
    case 'morning':
      return const TimeOfDay(hour: 8, minute: 0);
    case 'midday':
      return const TimeOfDay(hour: 12, minute: 0);
    case 'evening':
      return const TimeOfDay(hour: 18, minute: 0);
    case 'bedtime':
      return const TimeOfDay(hour: 22, minute: 0);
  }
  final match = _exact24HourTime.firstMatch(value.trim());
  if (match == null) return TimeOfDay.now();
  return TimeOfDay(
    hour: int.parse(match.group(1)!),
    minute: int.parse(match.group(2)!),
  );
}

String _formatTimeOfDay(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _exactTimeDescription(BuildContext context, String value) {
  final match = _exact24HourTime.firstMatch(value.trim());
  if (match == null) {
    return _dialogText(
      context,
      'Invalid saved value “$value”; choose a time to repair it.',
      'Ungültiger gespeicherter Wert „$value“; wähle eine Uhrzeit zur Reparatur.',
    );
  }
  return _dialogText(
    context,
    'Exact time: ${_formatTimeOfDay(_timeOfDayForPicker(value))}',
    'Genaue Uhrzeit: ${_formatTimeOfDay(_timeOfDayForPicker(value))}',
  );
}

String _namedTimeLabel(BuildContext context, String value) => switch (value) {
  'Morning' => _dialogText(context, 'Morning', 'Morgens'),
  'Midday' => _dialogText(context, 'Midday', 'Mittags'),
  'Evening' => _dialogText(context, 'Evening', 'Abends'),
  'Bedtime' => _dialogText(context, 'Bedtime', 'Vor dem Schlafen'),
  _ => value,
};

String _weekdayShort(BuildContext context, String day) => switch (day) {
  'monday' => _dialogText(context, 'M', 'Mo'),
  'tuesday' => _dialogText(context, 'T', 'Di'),
  'wednesday' => _dialogText(context, 'W', 'Mi'),
  'thursday' => _dialogText(context, 'T', 'Do'),
  'friday' => _dialogText(context, 'F', 'Fr'),
  'saturday' => _dialogText(context, 'S', 'Sa'),
  'sunday' => _dialogText(context, 'S', 'So'),
  _ => day,
};

String _weekdayLabel(BuildContext context, String day) => switch (day) {
  'monday' => _dialogText(context, 'Monday', 'Montag'),
  'tuesday' => _dialogText(context, 'Tuesday', 'Dienstag'),
  'wednesday' => _dialogText(context, 'Wednesday', 'Mittwoch'),
  'thursday' => _dialogText(context, 'Thursday', 'Donnerstag'),
  'friday' => _dialogText(context, 'Friday', 'Freitag'),
  'saturday' => _dialogText(context, 'Saturday', 'Samstag'),
  'sunday' => _dialogText(context, 'Sunday', 'Sonntag'),
  _ => day,
};

String _namedTimeDescription(String value) => switch (value) {
  'Morning' => '08:00',
  'Midday' => '12:00',
  'Evening' => '18:00',
  'Bedtime' => '22:00',
  _ => value,
};

String? _namedTimeChoice(String value) => switch (value.trim().toLowerCase()) {
  'morning' => 'Morning',
  'midday' => 'Midday',
  'evening' => 'Evening',
  'bedtime' => 'Bedtime',
  _ => null,
};

final RegExp _exact24HourTime = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');

/// A schedule is either a built-in slot or an exact, zero-padded 24-hour time.
bool _isValidScheduleTime(String value) =>
    _namedTimeChoice(value) != null || _exact24HourTime.hasMatch(value.trim());

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
        title: Text(
          existing == null
              ? _dialogText(
                  context,
                  'Track health event',
                  'Gesundheitsereignis erfassen',
                )
              : _dialogText(context, 'Edit event', 'Ereignis bearbeiten'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<EventKind>(
                segments: [
                  ButtonSegment(
                    value: EventKind.symptom,
                    label: Text(_dialogText(context, 'Symptom', 'Symptom')),
                  ),
                  ButtonSegment(
                    value: EventKind.tag,
                    label: Text(_dialogText(context, 'Tag', 'Markierung')),
                  ),
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
                      ? _dialogText(context, 'Symptom name *', 'Symptomname *')
                      : _dialogText(
                          context,
                          'Tag name *',
                          'Name der Markierung *',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Score (0–10)',
                          'Bewertung (0–10)',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Numeric value',
                          'Zahlenwert',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unit,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Unit', 'Einheit'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: _dialogText(
                    context,
                    'Duration (minutes)',
                    'Dauer (Minuten)',
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _dialogText(context, 'Observed at', 'Beobachtet am'),
                ),
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
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Notes', 'Notizen'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_dialogText(context, 'Save', 'Speichern')),
          ),
        ],
      ),
    ),
  );
  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      final parsedScore = parseOptionalInt(score.text);
      if (parsedScore != null && (parsedScore < 0 || parsedScore > 10)) {
        throw StateError(
          _dialogText(
            context,
            'Symptom score must be between 0 and 10.',
            'Die Symptombewertung muss zwischen 0 und 10 liegen.',
          ),
        );
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
      title: Text(
        existing == null
            ? _dialogText(context, 'Add biomarker', 'Biomarker hinzufügen')
            : _dialogText(context, 'Edit biomarker', 'Biomarker bearbeiten'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: _dialogText(context, 'Name *', 'Name *'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: category,
              decoration: InputDecoration(
                labelText: _dialogText(context, 'Category', 'Kategorie'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: unit,
              decoration: InputDecoration(
                labelText: _dialogText(
                  context,
                  'Default unit',
                  'Standardeinheit',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _dialogText(
                  context,
                  'Lab price (EUR)',
                  'Laborpreis (EUR)',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: lab,
              decoration: InputDecoration(
                labelText: _dialogText(context, 'Lab name', 'Laborname'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: synonyms,
              decoration: InputDecoration(
                labelText: _dialogText(context, 'Synonyms', 'Synonyme'),
                hintText: _dialogText(
                  context,
                  'Comma-separated names used on lab reports',
                  'Kommagetrennte Namen aus Laborberichten',
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _dialogText(context, 'Description', 'Beschreibung'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(
            existing == null
                ? _dialogText(context, 'Add', 'Hinzufügen')
                : _dialogText(context, 'Save', 'Speichern'),
          ),
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
              ? _dialogText(
                  context,
                  'Record ${biomarker.displayName}',
                  '${biomarker.displayName} erfassen',
                )
              : _dialogText(
                  context,
                  'Edit ${biomarker.displayName}',
                  '${biomarker.displayName} bearbeiten',
                ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(context, 'Value *', 'Wert *'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: unit,
                      decoration: InputDecoration(
                        labelText: _dialogText(context, 'Unit *', 'Einheit *'),
                      ),
                    ),
                  ),
                ],
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_dialogText(context, 'Sample date', 'Probendatum')),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Lab ref. low',
                          'Laborreferenz unten',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Lab ref. high',
                          'Laborreferenz oben',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Notes', 'Notizen'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              existing == null
                  ? _dialogText(context, 'Add result', 'Ergebnis hinzufügen')
                  : _dialogText(context, 'Save', 'Speichern'),
            ),
          ),
        ],
      ),
    ),
  );
  if (result == true && context.mounted) {
    final parsed = parseOptionalDouble(value.text);
    if (parsed == null || unit.text.trim().isEmpty) {
      await showAppError(
        context,
        _dialogText(
          context,
          'Enter a valid value and unit.',
          'Gib einen gültigen Wert und eine Einheit ein.',
        ),
      );
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
      title: Text(
        '${_dialogText(context, 'Personal target', 'Persönlicher Zielbereich')} · '
        '${biomarker.displayName}',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    _dialogText(
                      context,
                      'This target belongs only to the active profile',
                      'Dieses Ziel gehört nur zum aktiven Profil',
                    ),
                  ),
                  subtitle: Text(
                    _dialogText(
                      context,
                      'It does not overwrite lab reference ranges or another profile’s longevity target.',
                      'Es überschreibt weder Laborreferenzbereiche noch Langlebigkeitsziele anderer Profile.',
                    ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Target low',
                          'Ziel unten',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Target high',
                          'Ziel oben',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Borderline low',
                          'Grenzbereich unten',
                        ),
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
                      decoration: InputDecoration(
                        labelText: _dialogText(
                          context,
                          'Borderline high',
                          'Grenzbereich oben',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unit,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Unit *', 'Einheit *'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: source,
                decoration: InputDecoration(
                  labelText: _dialogText(
                    context,
                    'Source / rationale',
                    'Quelle / Begründung',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Notes', 'Notizen'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          )
        else
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(_dialogText(context, 'Save target', 'Ziel speichern')),
        ),
      ],
    ),
  );
  if (result == true && context.mounted) {
    final parsedLow = parseOptionalDouble(low.text);
    final parsedHigh = parseOptionalDouble(high.text);
    if (unit.text.trim().isEmpty ||
        (parsedLow != null && parsedHigh != null && parsedLow > parsedHigh)) {
      await showAppError(
        context,
        _dialogText(
          context,
          'Check the target range and unit.',
          'Prüfe Zielbereich und Einheit.',
        ),
      );
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
        title: Text(
          existing == null
              ? _dialogText(
                  context,
                  'Add health context',
                  'Gesundheitskontext hinzufügen',
                )
              : _dialogText(context, 'Edit context', 'Kontext bearbeiten'),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Type', 'Typ'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'condition',
                    child: Text(
                      _dialogText(context, 'Condition', 'Erkrankung'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'medication',
                    child: Text(
                      _dialogText(context, 'Medication', 'Medikament'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'goal',
                    child: Text(_dialogText(context, 'Goal', 'Ziel')),
                  ),
                  DropdownMenuItem(
                    value: 'family_history',
                    child: Text(
                      _dialogText(
                        context,
                        'Family history',
                        'Familienanamnese',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => kind = value ?? kind),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: status,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Status', 'Status'),
                ),
                items: [
                  DropdownMenuItem(
                    value: 'active',
                    child: Text(_dialogText(context, 'Active', 'Aktiv')),
                  ),
                  DropdownMenuItem(
                    value: 'monitoring',
                    child: Text(
                      _dialogText(context, 'Monitoring', 'Beobachtung'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'resolved',
                    child: Text(
                      _dialogText(context, 'Resolved', 'Abgeschlossen'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'paused',
                    child: Text(_dialogText(context, 'Paused', 'Pausiert')),
                  ),
                ],
                onChanged: (value) => setState(() => status = value ?? status),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Name *', 'Name *'),
                ),
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
                        decoration: InputDecoration(
                          labelText: _dialogText(context, 'Dose', 'Dosis'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unit,
                        decoration: InputDecoration(
                          labelText: _dialogText(context, 'Unit', 'Einheit'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: schedule,
                  decoration: InputDecoration(
                    labelText: _dialogText(context, 'Schedule', 'Einnahmeplan'),
                  ),
                ),
              ],
              if (kind == 'goal') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: priority,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: _dialogText(
                      context,
                      'Priority (1–5)',
                      'Priorität (1–5)',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: _dialogText(context, 'Notes', 'Notizen'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_dialogText(context, 'Cancel', 'Abbrechen')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(_dialogText(context, 'Save', 'Speichern')),
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
