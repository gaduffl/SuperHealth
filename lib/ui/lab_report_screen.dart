import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../biomarkers/biomarker_status_service.dart';
import '../domain/entities.dart';
import 'biomarker_detail_sheet.dart';
import 'common.dart';

String _reportText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// Opens the extraction overview for [document].
Future<void> showLabReport(
  BuildContext context,
  HealthDocument document, {
  String? highlightMeasurementId,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => LabReportScreen(
      documentId: document.id,
      highlightMeasurementId: highlightMeasurementId,
    ),
  ),
);

/// Hands a report's PDF to the system so it opens in a viewer.
///
/// A report held only in OneDrive has no local file yet, and the honest answer
/// there is to name the sync that brings it back rather than to fail silently.
Future<void> openLabReportFile(
  BuildContext context,
  HealthDocument document,
) async {
  final path = document.localPath?.trim() ?? '';
  if (path.isEmpty || !File(path).existsSync()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          document.oneDriveItemId == null
              ? _reportText(
                  context,
                  'The PDF for ${document.fileName} is not stored on this device.',
                  'Die PDF-Datei für ${document.fileName} liegt nicht auf diesem Gerät.',
                )
              : _reportText(
                  context,
                  '${document.fileName} is in OneDrive and arrives with the next sync.',
                  '${document.fileName} liegt in OneDrive und kommt mit der nächsten Synchronisierung.',
                ),
        ),
      ),
    );
    return;
  }
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(path, mimeType: document.mimeType)],
      subject: document.fileName,
    ),
  );
}

/// Everything one PDF import produced, on one page.
///
/// A parsed value is a claim about a document. Judging it means seeing the
/// claim in company: which other markers came out of the same report, what the
/// lab's own reference range said, which page each row was read from, and how
/// confident the parser was. Scattered across a per-biomarker history those
/// facts exist but can never be seen together.
///
/// Read from the controller by ID rather than held, so a re-parse, an edit, or
/// a sync that lands while this is open is reflected instead of frozen.
class LabReportScreen extends StatelessWidget {
  const LabReportScreen({
    required this.documentId,
    this.highlightMeasurementId,
    super.key,
  });

  final String documentId;

  /// The reading this screen was opened from, marked so it can be found in a
  /// report that extracted forty of them.
  final String? highlightMeasurementId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final document = controller.documents.firstWhereOrNull(
      (item) => item.id == documentId,
    );
    if (document == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_reportText(context, 'Lab report', 'Laborbericht')),
        ),
        body: Center(
          child: EmptyState(
            icon: Icons.description_outlined,
            title: _reportText(
              context,
              'This report is no longer available',
              'Dieser Bericht ist nicht mehr verfügbar',
            ),
            message: _reportText(
              context,
              'It was deleted, on this device or another one.',
              'Er wurde gelöscht – auf diesem oder einem anderen Gerät.',
            ),
          ),
        ),
      );
    }
    final rows =
        controller.measurements
            .where((item) => item.documentId == document.id)
            .toList()
          ..sort((a, b) {
            final byPage = (a.page ?? 1 << 30).compareTo(b.page ?? 1 << 30);
            return byPage != 0 ? byPage : a.id.compareTo(b.id);
          });
    final profile = controller.activeProfile;
    final statusService = BiomarkerStatusService();
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: Text(document.fileName, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: _reportText(context, 'Open PDF', 'PDF öffnen'),
            onPressed: () => openLabReportFile(context, document),
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.fileName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (document.labName?.trim().isNotEmpty == true)
                          document.labName!.trim(),
                        if (document.documentDate != null)
                          DateFormat(
                            'dd.MM.yyyy',
                          ).format(document.documentDate!),
                        _reportText(
                          context,
                          '${rows.length} result(s)',
                          '${rows.length} Ergebnis(se)',
                        ),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${document.parserProvider ?? _reportText(context, 'import', 'Import')}'
                            ' · ${document.parserModel ?? _reportText(context, 'legacy', 'Altbestand')}',
                        if (document.parsedAt != null)
                          _reportText(
                            context,
                            'parsed ${DateFormat('dd.MM.yyyy').format(document.parsedAt!)}',
                            'ausgewertet ${DateFormat('dd.MM.yyyy').format(document.parsedAt!)}',
                          ),
                        document.oneDriveItemId == null
                            ? _reportText(
                                context,
                                'this device only',
                                'nur auf diesem Gerät',
                              )
                            : _reportText(
                                context,
                                'in OneDrive',
                                'in OneDrive',
                              ),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (document.reportComment.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(document.reportComment.trim()),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => openLabReportFile(context, document),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _reportText(context, 'Open the PDF', 'PDF öffnen'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Parser complaints belong beside the rows they are about, not
            // only in the import flow the reader has long since left.
            for (final warning in document.warnings)
              _Note(
                icon: Icons.warning_amber_outlined,
                text: warning,
                tone: Theme.of(context).colorScheme.tertiary,
              ),
            for (final error in document.errors)
              _Note(
                icon: Icons.error_outline,
                text: error,
                tone: Theme.of(context).colorScheme.error,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
              child: Text(
                _reportText(
                  context,
                  'Extracted results',
                  'Extrahierte Ergebnisse',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            if (rows.isEmpty)
              Card(
                child: ListTile(
                  title: Text(
                    _reportText(
                      context,
                      'No results are linked to this report',
                      'Mit diesem Bericht sind keine Ergebnisse verknüpft',
                    ),
                  ),
                  subtitle: Text(
                    _reportText(
                      context,
                      'Every row was excluded during review, or the results were deleted afterwards.',
                      'Alle Zeilen wurden bei der Prüfung ausgeschlossen oder die Ergebnisse später gelöscht.',
                    ),
                  ),
                ),
              )
            else
              for (final row in rows)
                Builder(
                  builder: (context) {
                    // A row can outlive its biomarker, or name one this device
                    // never received. It still belongs on the page: the report
                    // did extract it.
                    final marker = controller.biomarkers.firstWhereOrNull(
                      (item) => item.id == row.biomarkerId,
                    );
                    return _ExtractedRow(
                      measurement: row,
                      biomarker: marker,
                      status: profile == null || marker == null
                          ? null
                          : statusService.evaluate(
                              biomarker: marker,
                              measurement: row,
                              profile: profile,
                              targets: controller.profileTargets,
                              referenceRanges: controller.biomarkerRanges,
                              now: now,
                            ),
                      highlighted: row.id == highlightMeasurementId,
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, required this.tone});

  final IconData icon;
  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon, color: tone),
      title: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    ),
  );
}

/// One row the parser produced, with everything recorded about it.
class _ExtractedRow extends StatelessWidget {
  const _ExtractedRow({
    required this.measurement,
    required this.biomarker,
    required this.status,
    required this.highlighted,
  });

  final Measurement measurement;
  final Biomarker? biomarker;
  final BiomarkerStatus? status;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name =
        biomarker?.displayName ??
        _reportText(context, 'Unknown biomarker', 'Unbekannter Biomarker');
    final confidence = measurement.extractionConfidence;
    return Card(
      // The reading this screen was opened from, so it can be found among
      // forty others without hunting for the number.
      color: highlighted ? theme.colorScheme.secondaryContainer : null,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Expanded(child: Text(name)),
            Text(
              '${measurement.value} ${measurement.unit}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        subtitle: Text(
          [
            if (measurement.labRefLow != null || measurement.labRefHigh != null)
              '${_reportText(context, 'Lab ref', 'Laborreferenz')} '
                  '${measurement.labRefLow ?? '…'}–${measurement.labRefHigh ?? '…'}'
            else
              _reportText(
                context,
                'No lab range on the report',
                'Kein Laborbereich im Bericht',
              ),
            if (measurement.page != null)
              _reportText(
                context,
                'page ${measurement.page}',
                'Seite ${measurement.page}',
              ),
            if (confidence != null)
              '${_reportText(context, 'parse', 'Extraktion')} ${(confidence * 100).round()}%',
          ].join(' · '),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (status != null)
            _Detail(
              label: _reportText(context, 'Status', 'Status'),
              value: status!.label,
            ),
          if (measurement.canonicalValue != null &&
              measurement.canonicalUnit != null)
            _Detail(
              label: _reportText(context, 'Standardised', 'Standardisiert'),
              value:
                  '${measurement.canonicalValue!.toStringAsPrecision(5)} '
                  '${measurement.canonicalUnit}',
            ),
          if (measurement.conversionStatus == 'unsupported')
            _Detail(
              label: _reportText(context, 'Conversion', 'Umrechnung'),
              value: _reportText(
                context,
                'No safe conversion to the standard unit',
                'Keine sichere Umrechnung in die Standardeinheit',
              ),
            ),
          _Detail(
            label: _reportText(context, 'Taken', 'Entnommen'),
            value: DateFormat('dd.MM.yyyy').format(measurement.takenAt),
          ),
          if (measurement.notes.trim().isNotEmpty)
            _Detail(
              label: _reportText(context, 'Remark', 'Anmerkung'),
              value: measurement.notes.trim(),
            ),
          // What the parser actually read. When a value looks wrong this is
          // the line that says whether the report or the parser is at fault.
          if (measurement.rowText?.trim().isNotEmpty == true)
            _Detail(
              label: _reportText(context, 'Raw row', 'Rohzeile'),
              value: measurement.rowText!.trim(),
              monospace: true,
            ),
          if (biomarker case final target?) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showBiomarkerDetail(context, target),
                icon: const Icon(Icons.timeline_outlined),
                label: Text(
                  _reportText(
                    context,
                    'History for ${target.displayName}',
                    'Verlauf für ${target.displayName}',
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: monospace
                  ? theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace')
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
