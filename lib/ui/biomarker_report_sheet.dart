import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../export/biomarker_report_annotations.dart';
import '../export/biomarker_report_export_service.dart';
import 'biomarker_category_localization.dart';
import 'common.dart';

String _reportText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// Chooses what goes into the doctor's PDF, then saves it.
///
/// The PDF itself is always German — it is written for the doctors, not for
/// whoever is reading the app — so only this sheet follows the app language.
Future<void> showBiomarkerReportSheet(
  BuildContext context,
  AppController controller,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.92,
    child: BiomarkerReportSheet(controller: controller),
  ),
);

class BiomarkerReportSheet extends StatefulWidget {
  const BiomarkerReportSheet({required this.controller, super.key});

  final AppController controller;

  @override
  State<BiomarkerReportSheet> createState() => _BiomarkerReportSheetState();
}

class _BiomarkerReportSheetState extends State<BiomarkerReportSheet> {
  final _excluded = <String>{};
  final _suppressed = <String>{};
  var _valueTables = true;
  var _busy = false;

  AppController get _controller => widget.controller;

  BiomarkerReportRequest? _request() {
    final profile = _controller.activeProfile;
    if (profile == null) return null;
    return buildBiomarkerReportRequest(
      profile: profile,
      biomarkers: _controller.biomarkers,
      measurements: _controller.measurements,
      documents: _controller.documents,
      targets: _controller.profileTargets,
      referenceRanges: _controller.biomarkerRanges,
      categoryTitle: (category) => biomarkerCategoryLabel(category, 'de'),
      excludedCategories: _excluded,
      suppressedDocumentIds: _suppressed,
      valueTables: _valueTables,
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final categories =
        biomarkerReportCategories(
          biomarkers: _controller.biomarkers,
          measurements: _controller.measurements,
        ).toList()..sort(
          (a, b) => biomarkerCategoryLabel(a, languageCode)
              .toLowerCase()
              .compareTo(biomarkerCategoryLabel(b, languageCode).toLowerCase()),
        );
    final request = _request();
    final comments = <ReportMark>[
      ...?request?.annotations.reports,
      ...?request?.annotations.suppressed,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final chartCount =
        request?.sections.fold<int>(
          0,
          (sum, section) => sum + section.charts.length,
        ) ??
        0;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  _reportText(
                    context,
                    'PDF for your doctor',
                    'PDF für die Ärztin oder den Arzt',
                  ),
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _reportText(
                    context,
                    'Your biomarker trends as a German PDF, two charts per row. '
                        'Lab-report comments are marked with letters, notes on '
                        'single values with numbers.',
                    'Deine Biomarker-Verläufe als deutsches PDF, zwei '
                        'Diagramme pro Zeile. Kommentare aus Laborberichten '
                        'werden mit Buchstaben markiert, Anmerkungen zu '
                        'einzelnen Werten mit Zahlen.',
                  ),
                ),
                const SizedBox(height: 16),
                SectionHeader(
                  title: _reportText(context, 'Categories', 'Kategorien'),
                  subtitle: _reportText(
                    context,
                    'Excluded categories are named on the first page, so the '
                        'PDF never reads as your complete record.',
                    'Ausgelassene Kategorien werden auf der ersten Seite '
                        'genannt, damit das PDF nicht als vollständige Akte '
                        'gelesen wird.',
                  ),
                ),
                for (final category in categories)
                  CheckboxListTile(
                    value: !_excluded.contains(category),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(biomarkerCategoryLabel(category, languageCode)),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _excluded.remove(category);
                      } else {
                        _excluded.add(category);
                      }
                    }),
                  ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _valueTables,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _reportText(
                      context,
                      'Value table under each chart',
                      'Wertetabelle unter jedem Diagramm',
                    ),
                  ),
                  subtitle: Text(
                    _reportText(
                      context,
                      'Exact numbers for the ${BiomarkerReportExportService.maxTableRows} most recent readings.',
                      'Genaue Zahlen für die letzten ${BiomarkerReportExportService.maxTableRows} Messungen.',
                    ),
                  ),
                  onChanged: (value) => setState(() => _valueTables = value),
                ),
                const SizedBox(height: 8),
                SectionHeader(
                  title: _reportText(
                    context,
                    'Lab-report comments',
                    'Kommentare aus Laborberichten',
                  ),
                  subtitle: _reportText(
                    context,
                    'A comment covers the whole report, so it can mention '
                        'tests you left out. Untick any you do not want printed.',
                    'Ein Kommentar gilt für den ganzen Bericht und kann '
                        'ausgelassene Tests erwähnen. Entferne den Haken bei '
                        'allen, die nicht gedruckt werden sollen.',
                  ),
                ),
                if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _reportText(
                        context,
                        'None of the included reports has a comment.',
                        'Keiner der enthaltenen Berichte hat einen Kommentar.',
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final comment in comments)
                  CheckboxListTile(
                    value: !_suppressed.contains(comment.documentId),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(comment.comment),
                    subtitle: Text(
                      [
                        if (comment.letter.isNotEmpty) comment.letter,
                        DateFormat('dd.MM.yyyy').format(comment.date),
                        ?comment.labName,
                      ].join(' · '),
                    ),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _suppressed.remove(comment.documentId);
                      } else {
                        _suppressed.add(comment.documentId);
                      }
                    }),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy || chartCount == 0 || request == null
                    ? null
                    : () => _export(request),
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  chartCount == 0
                      ? _reportText(
                          context,
                          'Select at least one category',
                          'Mindestens eine Kategorie wählen',
                        )
                      : _reportText(
                          context,
                          'Create PDF · $chartCount charts',
                          'PDF erstellen · $chartCount Diagramme',
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BiomarkerReportRequest request) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final saved = _reportText(context, 'PDF saved.', 'PDF gespeichert.');
    final dialogTitle = _reportText(context, 'Save PDF', 'PDF speichern');
    try {
      final file = await BiomarkerReportExportService().build(request);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: file.fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: file.bytes,
      );
      if (path != null) messenger.showSnackBar(SnackBar(content: Text(saved)));
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
