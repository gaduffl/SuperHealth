import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../biomarkers/reference_range_exchange.dart';
import '../domain/entities.dart';
import 'common.dart';

String _rangesText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

Future<void> showReferenceRangeEditor(
  BuildContext context,
  AppController controller,
  Biomarker biomarker, {
  BiomarkerReferenceRange? existing,
}) async {
  final formKey = GlobalKey<FormState>();
  final rangeType = TextEditingController(
    text: existing?.rangeType ?? 'reference',
  );
  final sex = TextEditingController(text: existing?.sex ?? '');
  final ageMin = TextEditingController(
    text: existing?.ageMin?.toString() ?? '',
  );
  final ageMax = TextEditingController(
    text: existing?.ageMax?.toString() ?? '',
  );
  final low = TextEditingController(text: existing?.low?.toString() ?? '');
  final high = TextEditingController(text: existing?.high?.toString() ?? '');
  final optimalLow = TextEditingController(
    text: existing?.optimalLow?.toString() ?? '',
  );
  final optimalHigh = TextEditingController(
    text: existing?.optimalHigh?.toString() ?? '',
  );
  final unit = TextEditingController(
    text: existing?.unit ?? biomarker.defaultUnit,
  );
  final evidenceLabel = TextEditingController(
    text: existing?.evidenceLabel ?? '',
  );
  final evidenceUrl = TextEditingController(text: existing?.evidenceUrl ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        existing == null
            ? _rangesText(
                context,
                'Add reference range',
                'Referenzbereich hinzufügen',
              )
            : _rangesText(
                context,
                'Edit reference range',
                'Referenzbereich bearbeiten',
              ),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 560,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: rangeType,
                  decoration: InputDecoration(
                    labelText: _rangesText(
                      context,
                      'Range type *',
                      'Bereichstyp *',
                    ),
                  ),
                  validator: (value) => _required(context, value),
                ),
                _fieldRow(
                  TextFormField(
                    controller: sex,
                    decoration: InputDecoration(
                      labelText: _rangesText(
                        context,
                        'Sex (optional)',
                        'Geschlecht (optional)',
                      ),
                    ),
                  ),
                  TextFormField(
                    controller: unit,
                    decoration: InputDecoration(
                      labelText: _rangesText(context, 'Unit *', 'Einheit *'),
                    ),
                    validator: (value) => _required(context, value),
                  ),
                ),
                _fieldRow(
                  _integerField(
                    context,
                    ageMin,
                    _rangesText(context, 'Minimum age', 'Mindestalter'),
                  ),
                  _integerField(
                    context,
                    ageMax,
                    _rangesText(context, 'Maximum age', 'Höchstalter'),
                  ),
                ),
                _fieldRow(
                  _numberField(
                    context,
                    low,
                    _rangesText(context, 'Reference low', 'Referenz unten'),
                  ),
                  _numberField(
                    context,
                    high,
                    _rangesText(context, 'Reference high', 'Referenz oben'),
                  ),
                ),
                _fieldRow(
                  _numberField(
                    context,
                    optimalLow,
                    _rangesText(context, 'Optimal low', 'Optimal unten'),
                  ),
                  _numberField(
                    context,
                    optimalHigh,
                    _rangesText(context, 'Optimal high', 'Optimal oben'),
                  ),
                ),
                TextFormField(
                  controller: evidenceLabel,
                  decoration: InputDecoration(
                    labelText: _rangesText(
                      context,
                      'Evidence label',
                      'Evidenzbezeichnung',
                    ),
                  ),
                ),
                TextFormField(
                  controller: evidenceUrl,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: _rangesText(
                      context,
                      'Evidence URL',
                      'Evidenz-URL',
                    ),
                  ),
                ),
                TextFormField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: _rangesText(context, 'Notes', 'Notizen'),
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
          child: Text(_rangesText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            if (!_ordered(_int(ageMin.text), _int(ageMax.text)) ||
                !_agesValid(_int(ageMin.text), _int(ageMax.text)) ||
                !_ordered(_number(low.text), _number(high.text)) ||
                !_ordered(
                  _number(optimalLow.text),
                  _number(optimalHigh.text),
                )) {
              showAppError(
                dialogContext,
                _rangesText(
                  context,
                  'Range bounds must be ordered low to high.',
                  'Bereichsgrenzen müssen von niedrig nach hoch geordnet sein.',
                ),
              );
              return;
            }
            if (_number(low.text) == null &&
                _number(high.text) == null &&
                _number(optimalLow.text) == null &&
                _number(optimalHigh.text) == null) {
              showAppError(
                dialogContext,
                _rangesText(
                  context,
                  'Enter at least one reference or optimal bound.',
                  'Gib mindestens eine Referenz- oder Optimalgrenze ein.',
                ),
              );
              return;
            }
            if (!_isHttpUrl(_blank(evidenceUrl.text))) {
              showAppError(
                dialogContext,
                _rangesText(
                  context,
                  'Evidence URL must use http or https.',
                  'Die Evidenz-URL muss http oder https verwenden.',
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, true);
          },
          child: Text(_rangesText(context, 'Save range', 'Bereich speichern')),
        ),
      ],
    ),
  );
  if (saved == true && context.mounted) {
    final now = DateTime.now();
    try {
      await controller.saveBiomarkerRange(
        BiomarkerReferenceRange(
          id: existing?.id ?? controller.repository.newId(),
          biomarkerId: biomarker.id,
          rangeType: rangeType.text.trim(),
          sex: _blank(sex.text),
          ageMin: _int(ageMin.text),
          ageMax: _int(ageMax.text),
          low: _number(low.text),
          high: _number(high.text),
          optimalLow: _number(optimalLow.text),
          optimalHigh: _number(optimalHigh.text),
          unit: unit.text.trim(),
          evidenceLabel: _blank(evidenceLabel.text),
          evidenceUrl: _blank(evidenceUrl.text),
          notes: notes.text.trim(),
          createdAt: existing?.createdAt ?? now,
          updatedAt: now,
        ),
      );
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }
  for (final field in [
    rangeType,
    sex,
    ageMin,
    ageMax,
    low,
    high,
    optimalLow,
    optimalHigh,
    unit,
    evidenceLabel,
    evidenceUrl,
    notes,
  ]) {
    field.dispose();
  }
}

Future<void> showReferenceRangeExchange(
  BuildContext context,
  AppController controller,
  Biomarker biomarker,
) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.file_upload_outlined),
          title: Text(
            _rangesText(
              context,
              'Import reference ranges',
              'Referenzbereiche importieren',
            ),
          ),
          subtitle: Text(
            _rangesText(
              context,
              'Preview JSON or CSV before any ranges are added.',
              'JSON oder CSV vor dem Hinzufügen von Bereichen prüfen.',
            ),
          ),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _importRanges(context, controller);
          },
        ),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: Text(
            _rangesText(
              context,
              'Export this biomarker’s ranges',
              'Bereiche dieses Biomarkers exportieren',
            ),
          ),
          subtitle: Text(
            _rangesText(
              context,
              'Create a JSON or CSV evidence file.',
              'Eine JSON- oder CSV-Evidenzdatei erstellen.',
            ),
          ),
          onTap: () async {
            Navigator.pop(sheetContext);
            await _exportRanges(context, controller, biomarker);
          },
        ),
      ],
    ),
  ),
);

Future<void> _exportRanges(
  BuildContext context,
  AppController controller,
  Biomarker biomarker,
) async {
  final extension = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.data_object_outlined),
            title: const Text('JSON'),
            onTap: () => Navigator.pop(sheetContext, 'json'),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('CSV'),
            onTap: () => Navigator.pop(sheetContext, 'csv'),
          ),
        ],
      ),
    ),
  );
  if (extension == null || !context.mounted) return;
  try {
    final exchange = BiomarkerRangeExchange();
    final ranges = controller.biomarkerRanges.where(
      (range) => range.biomarkerId == biomarker.id,
    );
    final content = extension == 'json'
        ? exchange.exportJson(ranges, controller.biomarkers)
        : exchange.exportCsv(ranges, controller.biomarkers);
    final path = await FilePicker.platform.saveFile(
      dialogTitle: _rangesText(
        context,
        'Export ${biomarker.displayName} ranges',
        'Bereiche für ${biomarker.displayName} exportieren',
      ),
      fileName: '${biomarker.canonicalName}_reference_ranges.$extension',
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List.fromList(utf8.encode(content)),
    );
    if (path != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _rangesText(
              context,
              'Reference range export saved.',
              'Referenzbereich-Export gespeichert.',
            ),
          ),
        ),
      );
    }
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
  }
}

Future<void> _importRanges(
  BuildContext context,
  AppController controller,
) async {
  try {
    final selection = await FilePicker.platform.pickFiles(
      dialogTitle: _rangesText(
        context,
        'Choose reference ranges (JSON or CSV)',
        'Referenzbereiche auswählen (JSON oder CSV)',
      ),
      type: FileType.custom,
      allowedExtensions: const ['json', 'csv'],
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return;
    final file = selection.files.single;
    final bytes =
        file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) {
      throw StateError(
        _rangesText(
          context,
          'The selected file could not be read.',
          'Die ausgewählte Datei konnte nicht gelesen werden.',
        ),
      );
    }
    final extension =
        file.extension?.toLowerCase() ??
        file.name.split('.').last.toLowerCase();
    final preview = BiomarkerRangeExchange().parse(
      text: utf8.decode(bytes),
      extension: extension,
      biomarkers: controller.biomarkers,
      existingRanges: controller.biomarkerRanges,
    );
    if (!context.mounted) return;
    final approved = await _showImportPreview(context, preview);
    if (!approved || !context.mounted) return;
    final now = DateTime.now();
    await controller.repository.saveBiomarkerRanges([
      for (final item in preview.records)
        BiomarkerReferenceRange(
          id: controller.repository.newId(),
          biomarkerId: item.biomarkerId,
          rangeType: item.rangeType,
          sex: item.sex,
          ageMin: item.ageMin,
          ageMax: item.ageMax,
          low: item.low,
          high: item.high,
          optimalLow: item.optimalLow,
          optimalHigh: item.optimalHigh,
          unit: item.unit,
          evidenceLabel: item.evidenceLabel,
          evidenceUrl: item.evidenceUrl,
          notes: item.notes,
          createdAt: now,
          updatedAt: now,
        ),
    ]);
    await controller.refreshActiveData();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _rangesText(
              context,
              'Imported ${preview.records.length} reference range(s).',
              '${preview.records.length} Referenzbereich(e) importiert.',
            ),
          ),
        ),
      );
    }
  } on Object catch (error) {
    if (context.mounted) await showAppError(context, error);
  }
}

Future<bool> _showImportPreview(
  BuildContext context,
  RangeImportPreview preview,
) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        _rangesText(
          context,
          'Reference range import preview',
          'Vorschau des Referenzbereich-Imports',
        ),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _rangesText(
                  context,
                  '${preview.records.length} valid range(s) will be added. Existing ranges are not overwritten.',
                  '${preview.records.length} gültige Bereich(e) werden hinzugefügt. Bestehende Bereiche werden nicht überschrieben.',
                ),
              ),
              if (preview.issues.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _rangesText(
                    context,
                    'Fix these rows before importing:',
                    'Korrigiere diese Zeilen vor dem Import:',
                  ),
                ),
                for (final issue in preview.issues)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${_rangesText(context, 'Row', 'Zeile')} '
                      '${issue.row}: ${issue.message}',
                    ),
                  ),
              ] else ...[
                for (final record in preview.records)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(record.biomarkerName),
                    subtitle: Text(
                      '${record.rangeType} · ${record.low ?? '…'}–${record.high ?? '…'} ${record.unit}',
                    ),
                  ),
                for (final skipped in preview.skipped)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(
                      _rangesText(
                        context,
                        '${skipped.record.biomarkerName} (skipped)',
                        '${skipped.record.biomarkerName} (übersprungen)',
                      ),
                    ),
                    subtitle: Text(
                      '${_rangesText(context, 'Row', 'Zeile')} '
                      '${skipped.row}: ${skipped.message}',
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_rangesText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: preview.canImport
              ? () => Navigator.pop(dialogContext, true)
              : null,
          child: Text(
            _rangesText(context, 'Import ranges', 'Bereiche importieren'),
          ),
        ),
      ],
    ),
  );
  return approved ?? false;
}

String? _required(BuildContext context, String? value) =>
    value == null || value.trim().isEmpty
    ? _rangesText(context, 'Required.', 'Erforderlich.')
    : null;

TextFormField _numberField(
  BuildContext context,
  TextEditingController controller,
  String label,
) => TextFormField(
  controller: controller,
  keyboardType: const TextInputType.numberWithOptions(
    decimal: true,
    signed: true,
  ),
  decoration: InputDecoration(labelText: label),
  validator: (value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = double.tryParse(value.trim());
    return parsed == null || !parsed.isFinite
        ? _rangesText(
            context,
            'Enter a finite number.',
            'Gib eine endliche Zahl ein.',
          )
        : null;
  },
);

TextFormField _integerField(
  BuildContext context,
  TextEditingController controller,
  String label,
) => TextFormField(
  controller: controller,
  keyboardType: TextInputType.number,
  decoration: InputDecoration(labelText: label),
  validator: (value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null) {
      return _rangesText(
        context,
        'Enter a whole number.',
        'Gib eine ganze Zahl ein.',
      );
    }
    return parsed < 0 || parsed > 150
        ? _rangesText(
            context,
            'Use an age from 0 to 150.',
            'Verwende ein Alter von 0 bis 150.',
          )
        : null;
  },
);

Widget _fieldRow(Widget left, Widget right) => Padding(
  padding: const EdgeInsets.only(top: 10),
  child: Row(
    children: [
      Expanded(child: left),
      const SizedBox(width: 10),
      Expanded(child: right),
    ],
  ),
);

String? _blank(String value) => value.trim().isEmpty ? null : value.trim();

double? _number(String value) =>
    value.trim().isEmpty ? null : double.tryParse(value.trim());

int? _int(String value) =>
    value.trim().isEmpty ? null : int.tryParse(value.trim());

bool _ordered(num? low, num? high) =>
    low == null || high == null || low <= high;

bool _agesValid(int? low, int? high) =>
    (low == null || (low >= 0 && low <= 150)) &&
    (high == null || (high >= 0 && high <= 150));

bool _isHttpUrl(String? value) {
  if (value == null) return true;
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      uri.host.isNotEmpty &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}
