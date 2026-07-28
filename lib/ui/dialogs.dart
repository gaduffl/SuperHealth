// All async dialog continuations guard context.mounted before UI access.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../domain/entities.dart';
import 'common.dart';
import 'ingredient_editor.dart';

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
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<bool>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
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
  final result = await navigator.push(route);
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
  await route.completed;
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
  final stockUnit = TextEditingController(
    // A new product starts blank so a real unit gets chosen, rather than
    // inheriting the placeholder that reads as "3 unit" in every list.
    text: existing == null || existing.stockUnit.trim() == genericStockUnit
        ? ''
        : existing.stockUnit,
  );
  final lowStock = TextEditingController(
    text: existing?.lowStockThresholdUnits?.toString() ?? '',
  );
  final bioavailability = TextEditingController(
    text: existing?.bioavailability,
  );
  final notes = TextEditingController(text: existing?.notes);
  final ingredients = IngredientRows.from(existing?.ingredients ?? const []);
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
              const SizedBox(height: 14),
              IngredientEditor(
                rows: ingredients,
                stockUnitLabel: existing?.stockUnit,
              ),
              const SizedBox(height: 14),
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
                    child: _StockUnitField(controller: stockUnit, form: form),
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
      final parsedIngredients = ingredients.parse();
      final units = parseOptionalInt(unitsPerContainer.text);
      final resolvedStockUnit = stockUnit.text.trim().isEmpty
          ? genericStockUnit
          : stockUnit.text.trim();
      if ((units != null && units <= 0) || parsedIngredients == null) {
        throw StateError(
          _dialogText(
            context,
            'Check the container size and the ingredient rows. Every '
                'ingredient needs a name, and an amount must be a number.',
            'Prüfe Behältergröße und Inhaltsstoffzeilen. Jeder Inhaltsstoff '
                'braucht einen Namen, und eine Menge muss eine Zahl sein.',
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
          stockUnit: resolvedStockUnit,
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
            stockUnit: resolvedStockUnit,
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
  ingredients.dispose();
  for (final item in [
    name,
    brand,
    form,
    price,
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
                    '${current.toStringAsFixed(1)} ${unitLabel(AppLocalizations.of(context), unit: supplement.stockUnit, form: supplement.form)} on hand',
                    '${current.toStringAsFixed(1)} ${unitLabel(AppLocalizations.of(context), unit: supplement.stockUnit, form: supplement.form)} vorhanden',
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
                          'New total (${unitLabel(AppLocalizations.of(context), unit: supplement.stockUnit, form: supplement.form)})',
                          'Neuer Gesamtbestand (${unitLabel(AppLocalizations.of(context), unit: supplement.stockUnit, form: supplement.form)})',
                        )
                      : _dialogText(
                          context,
                          'Quantity (${unitLabel(AppLocalizations.of(context), unit: supplement.stockUnit, form: supplement.form)})',
                          'Menge (${unitLabel(AppLocalizations.of(context), unit: supplement.stockUnit, form: supplement.form)})',
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
  Supplement supplement, {
  SupplementIntake? existing,
  DateTime? initialTakenAt,
}) async {
  final dose = TextEditingController(text: existing?.dose.toString() ?? '1');
  final unit = TextEditingController(
    text:
        existing?.unit ??
        (supplement.stockUnit.trim().isNotEmpty
            ? supplement.stockUnit
            : (supplement.form.trim().isNotEmpty ? supplement.form : 'unit')),
  );
  final notes = TextEditingController(text: existing?.notes ?? '');
  DateTime takenAt = existing?.takenAt ?? initialTakenAt ?? DateTime.now();
  var skipped = existing?.skipped ?? false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null
              ? _dialogText(
                  context,
                  'Log ${supplement.name}',
                  '${supplement.name} erfassen',
                )
              : _dialogText(
                  context,
                  'Edit ${supplement.name} intake',
                  'Einnahme von ${supplement.name} bearbeiten',
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
              title: Text(_dialogText(context, 'Date', 'Datum')),
              subtitle: Text(
                MaterialLocalizations.of(context).formatMediumDate(takenAt),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final value = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                  initialDate: takenAt,
                );
                if (value != null) {
                  setState(() {
                    takenAt = DateTime(
                      value.year,
                      value.month,
                      value.day,
                      takenAt.hour,
                      takenAt.minute,
                    );
                  });
                }
              },
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
            if (existing != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_dialogText(context, 'Skipped', 'Übersprungen')),
                value: skipped,
                onChanged: (value) => setState(() => skipped = value),
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
              existing == null
                  ? _dialogText(context, 'Log intake', 'Einnahme erfassen')
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
    final parsedDose = parseOptionalDouble(dose.text);
    if (parsedDose == null || parsedDose <= 0 || unit.text.trim().isEmpty) {
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
        if (existing == null) {
          await controller.logIntake(
            supplement: supplement,
            dose: parsedDose,
            unit: unit.text,
            takenAt: takenAt,
            notes: notes.text,
          );
        } else {
          await controller.updateIntake(
            SupplementIntake(
              id: existing.id,
              profileId: existing.profileId,
              supplementId: existing.supplementId,
              scheduleId: existing.scheduleId,
              takenAt: takenAt,
              dose: parsedDose,
              unit: unit.text,
              skipped: skipped,
              notes: notes.text,
              ingredientSnapshot: existing.ingredientSnapshot,
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

/// Records a symptom or a tag.
///
/// A symptom is normally just a name and a 0-10 rating, and a tag is normally
/// just "this happened". Asking for a score, a numeric value, a unit, and a
/// duration on every entry made the quick check-ins anything but quick, so the
/// dialog now shows only what the chosen kind actually needs and keeps the
/// rest — which the correlation analysis can use but rarely requires — behind
/// one disclosure.
Future<void> showAddEventDialog(
  BuildContext context,
  AppController controller, {
  EventKind initialKind = EventKind.symptom,
  String? initialName,
  HealthEvent? existing,
}) async {
  final name = TextEditingController(text: existing?.name ?? initialName);
  final value = TextEditingController(
    text: existing?.numericValue?.toString() ?? '',
  );
  final unit = TextEditingController(text: existing?.unit);
  final duration = TextEditingController(
    text: existing?.durationMinutes?.toString() ?? '',
  );
  final notes = TextEditingController(text: existing?.notes);
  var kind = existing?.kind ?? initialKind;
  var score = existing?.score;
  var observedAt = existing?.observedAt ?? DateTime.now();
  var showDetails =
      existing != null &&
      (existing.numericValue != null ||
          existing.durationMinutes != null ||
          existing.notes.trim().isNotEmpty);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) {
        final strings = AppLocalizations.of(context);
        final isSymptom = kind == EventKind.symptom;
        final suggestions = controller.eventDefinitions
            .where(
              (item) => item.kind == kind && !item.archived && !item.deleted,
            )
            .take(8)
            .toList();
        return AlertDialog(
          title: Text(
            existing == null
                ? (isSymptom
                      ? _dialogText(context, 'Log symptom', 'Symptom erfassen')
                      : _dialogText(context, 'Log tag', 'Markierung erfassen'))
                : _dialogText(context, 'Edit entry', 'Eintrag bearbeiten'),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    onSelectionChanged: (next) =>
                        setState(() => kind = next.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isSymptom
                        ? _dialogText(
                            context,
                            'Something you feel, rated so it can be tracked '
                                'over time.',
                            'Etwas, das du spürst — bewertet, damit es über '
                                'die Zeit verfolgbar ist.',
                          )
                        : _dialogText(
                            context,
                            'Something you did or took, used as a predictor '
                                'in correlations.',
                            'Etwas, das du getan oder zu dir genommen hast — '
                                'dient als Prädiktor in Korrelationen.',
                          ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: name,
                    autofocus: name.text.isEmpty,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: isSymptom
                          ? _dialogText(context, 'Symptom', 'Symptom')
                          : _dialogText(context, 'Tag', 'Markierung'),
                      hintText: isSymptom
                          ? _dialogText(context, 'Energy', 'Energie')
                          : _dialogText(context, 'Coffee', 'Kaffee'),
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final definition in suggestions)
                          ChoiceChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(definition.name),
                            selected:
                                name.text.trim().toLowerCase() ==
                                definition.name.toLowerCase(),
                            onSelected: (_) => setState(() {
                              name.text = definition.name;
                              if (definition.defaultUnit?.isNotEmpty ?? false) {
                                unit.text = definition.defaultUnit!;
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                  if (isSymptom) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dialogText(context, 'How strong?', 'Wie stark?'),
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        Text(
                          score == null ? '—' : '$score/10',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                    Slider(
                      value: (score ?? 0).toDouble(),
                      max: 10,
                      divisions: 10,
                      label: '${score ?? 0}',
                      onChanged: (next) => setState(() => score = next.round()),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: value,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: _dialogText(
                                context,
                                'How much? (optional)',
                                'Wie viel? (optional)',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: unit,
                            decoration: InputDecoration(
                              isDense: true,
                              labelText: _dialogText(
                                context,
                                'Unit',
                                'Einheit',
                              ),
                              hintText: _dialogText(context, 'cups', 'Tassen'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => showDetails = !showDetails),
                      icon: Icon(
                        showDetails ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                      label: Text(
                        _dialogText(context, 'More details', 'Mehr Details'),
                      ),
                    ),
                  ),
                  if (showDetails) ...[
                    if (isSymptom) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: value,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: _dialogText(
                                  context,
                                  'Measured value',
                                  'Messwert',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: unit,
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: _dialogText(
                                  context,
                                  'Unit',
                                  'Einheit',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: duration,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: _dialogText(
                          context,
                          'Duration (minutes)',
                          'Dauer (Minuten)',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notes,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: _dialogText(context, 'Notes', 'Notizen'),
                      ),
                    ),
                  ],
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(Icons.schedule, size: 20),
                    title: Text(
                      _sameCalendarDay(observedAt, DateTime.now())
                          ? _dialogText(context, 'Now', 'Jetzt')
                          : '${strings.formatTrackingDate(observedAt)} · '
                                '${strings.formatTime(observedAt)}',
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
                      if (time == null) return;
                      setState(() {
                        observedAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
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
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(_dialogText(context, 'Save', 'Speichern')),
            ),
          ],
        );
      },
    ),
  );

  if (result == true && name.text.trim().isNotEmpty && context.mounted) {
    try {
      // A tag carries no rating, so switching kind must not leave a stale one
      // behind on the saved entry.
      final resolvedScore = kind == EventKind.symptom ? score : null;
      if (existing == null) {
        await controller.addEvent(
          kind: kind,
          name: name.text,
          score: resolvedScore,
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
            score: resolvedScore,
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
  for (final item in [name, value, unit, duration, notes]) {
    item.dispose();
  }
}

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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

/// The product's counting unit, with the common answers one tap away.
///
/// Left as free text underneath, because a unit is the person's own
/// vocabulary in their own language — the suggestions only save typing.
class _StockUnitField extends StatefulWidget {
  const _StockUnitField({required this.controller, required this.form});

  final TextEditingController controller;

  /// The product's form field. Offered first, since a product described as a
  /// capsule is almost always counted in capsules.
  final TextEditingController form;

  @override
  State<_StockUnitField> createState() => _StockUnitFieldState();
}

class _StockUnitFieldState extends State<_StockUnitField> {
  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final suggestions = <String>{
      if (widget.form.text.trim().isNotEmpty) widget.form.text.trim(),
      ...strings
          .pick(
            'capsule,tablet,softgel,scoop,drop,ml,g,sachet',
            'Kapsel,Tablette,Softgel,Messlöffel,Tropfen,ml,g,Beutel',
          )
          .split(','),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _dialogText(context, 'Stock unit', 'Bestandseinheit'),
            hintText: strings.pick('capsule', 'Kapsel'),
            helperText: _dialogText(
              context,
              'What one of these is called',
              'Wie eine Einheit davon heißt',
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final suggestion in suggestions)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(suggestion),
                    selected:
                        widget.controller.text.trim().toLowerCase() ==
                        suggestion.toLowerCase(),
                    onSelected: (_) => setState(() {
                      widget.controller.text = suggestion;
                    }),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
