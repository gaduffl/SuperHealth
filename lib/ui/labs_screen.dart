import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/document_parsing_service.dart';
import '../ai/lab_planner_service.dart';
import '../app/app_controller.dart';
import '../domain/entities.dart';
import '../export/lab_plan_export_service.dart';
import 'biomarker_detail_sheet.dart';
import 'biomarker_lists_sheet.dart';
import 'common.dart';
import 'dialogs.dart';

class LabsScreen extends StatelessWidget {
  const LabsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final latestByBiomarker = <String, Measurement>{};
    for (final measurement in controller.measurements) {
      latestByBiomarker.putIfAbsent(measurement.biomarkerId, () => measurement);
    }
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          SectionHeader(
            title: 'Lab visit planner',
            subtitle:
                'Three cumulative tiers priced from your biomarker catalog',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Import lab PDF',
                  onPressed: controller.busy
                      ? null
                      : () => _importPdf(context, controller),
                  icon: const Icon(Icons.document_scanner_outlined),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: controller.busy || controller.biomarkers.isEmpty
                      ? null
                      : () => _generate(context, controller),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Plan'),
                ),
              ],
            ),
          ),
          if (controller.biomarkers.isEmpty)
            EmptyState(
              icon: Icons.science_outlined,
              title: 'Import or add your biomarker catalog first',
              message:
                  'The planner only selects known biomarkers and calculates tiers from stored EUR prices.',
              action: FilledButton.tonal(
                onPressed: () => showAddBiomarkerDialog(context, controller),
                child: const Text('Add biomarker'),
              ),
            )
          else if (controller.draftLabPlan case final draft?)
            _DraftPlanCard(
              generation: draft,
              onSave: () async {
                try {
                  await controller.saveDraftLabPlan();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lab plan saved.')),
                    );
                  }
                } on Object catch (error) {
                  if (context.mounted) await showAppError(context, error);
                }
              },
              onExport: () => _export(context, controller, draft.plan),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        'The advisor will review the complete active profile, including past '
                        'results, supplements, conditions, medicines, goals, symptoms, and prices.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (controller.labPlans.isNotEmpty) ...[
            const SectionHeader(title: 'Saved plans'),
            for (final plan in controller.labPlans)
              _SavedPlanCard(
                plan: plan,
                onExport: () => _export(context, controller, plan),
                onToggle: (item, checked) =>
                    controller.setLabPlanItemChecked(plan, item, checked),
                onDelete: () async {
                  final confirmed = await showConfirmAction(
                    context,
                    title: 'Delete ${plan.title}?',
                    message: 'The exported files, if any, are not affected.',
                    confirmLabel: 'Delete',
                    destructive: true,
                  );
                  if (confirmed) await controller.deleteLabPlan(plan);
                },
              ),
          ],
          if (controller.dueBiomarkers.isNotEmpty) ...[
            const SectionHeader(
              title: 'Due for retest',
              subtitle: 'From the active profile’s saved biomarker lists',
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final due in controller.dueBiomarkers)
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.event_repeat_outlined),
                      ),
                      title: Text(due.biomarker.displayName),
                      subtitle: Text(
                        '${due.listName} · every ${due.intervalDays} days · '
                        '${due.lastMeasuredAt == null ? 'never measured' : '${due.daysOverdue} days overdue'}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showBiomarkerDetail(
                        context,
                        controller,
                        due.biomarker,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (controller.documents.isNotEmpty) ...[
            const SectionHeader(
              title: 'Lab documents',
              subtitle: 'Reviewed PDF imports and their extraction status',
            ),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final document in controller.documents)
                    ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.picture_as_pdf_outlined),
                      ),
                      title: Text(document.fileName),
                      subtitle: Text(
                        [
                          if (document.labName?.isNotEmpty == true)
                            document.labName!,
                          if (document.documentDate != null)
                            DateFormat(
                              'dd.MM.yyyy',
                            ).format(document.documentDate!),
                          '${document.parserProvider ?? 'import'} · ${document.parserModel ?? 'legacy'}',
                        ].join(' · '),
                      ),
                      trailing: Icon(
                        document.oneDriveItemId == null
                            ? Icons.phone_android
                            : Icons.cloud_done_outlined,
                      ),
                      onTap: () => _showDocument(context, controller, document),
                    ),
                ],
              ),
            ),
          ],
          SectionHeader(
            title: 'Biomarker catalog',
            subtitle:
                '${controller.biomarkers.length} tests · ${controller.measurements.length} results',
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: 'Saved biomarker lists',
                  onPressed: () => showBiomarkerListsSheet(context, controller),
                  icon: const Icon(Icons.checklist_outlined),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Add biomarker',
                  onPressed: () => showAddBiomarkerDialog(context, controller),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          if (controller.biomarkers.isNotEmpty)
            _BiomarkerCatalog(
              controller: controller,
              latestByBiomarker: latestByBiomarker,
            ),
        ],
      ),
    );
  }

  Future<void> _importPdf(
    BuildContext context,
    AppController controller,
  ) async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        dialogTitle: 'Choose a lab report PDF',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final selected = selection.files.single;
      final bytes =
          selected.bytes ??
          (selected.path == null
              ? null
              : await File(selected.path!).readAsBytes());
      if (bytes == null) {
        throw StateError('The selected PDF could not be read.');
      }
      final report = await controller.parseLabPdf(
        fileName: selected.name,
        bytes: bytes,
      );
      if (!context.mounted) return;
      await _reviewParsedReport(context, controller, report);
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  Future<void> _reviewParsedReport(
    BuildContext context,
    AppController controller,
    ParsedLabReport report,
  ) async {
    final candidates = [...report.measurements];
    var reportDate = report.reportDate ?? DateTime.now();
    final comment = TextEditingController();
    const temporary = '__temporary__';
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Review extracted lab report'),
          content: SizedBox(
            width: 720,
            height: MediaQuery.sizeOf(context).height * 0.68,
            child: ListView(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(report.fileName),
                  subtitle: Text(
                    '${report.provider.name} · ${report.model} · '
                    '${(report.pdfBytes.length / 1024).toStringAsFixed(0)} KB',
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Sample / report date *'),
                  subtitle: Text(DateFormat('dd.MM.yyyy').format(reportDate)),
                  trailing: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime(1950),
                      lastDate: DateTime.now(),
                      initialDate: reportDate.isAfter(DateTime.now())
                          ? DateTime.now()
                          : reportDate,
                    );
                    if (date != null) setState(() => reportDate = date);
                  },
                ),
                TextField(
                  controller: comment,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Report comment',
                  ),
                ),
                if (report.errors.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final error in report.errors)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: const Icon(Icons.error_outline),
                        title: Text(error),
                      ),
                    ),
                ],
                if (report.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final warning in report.warnings)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(warning),
                    ),
                ],
                const Divider(height: 28),
                Text(
                  '${candidates.length} measurements',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < candidates.length; index++)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${candidates[index].reportedName}: '
                                  '${candidates[index].value} ${candidates[index].unit}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              Chip(
                                avatar: Icon(
                                  candidates[index].confidence >= 0.85
                                      ? Icons.check
                                      : Icons.priority_high,
                                  size: 15,
                                ),
                                label: Text(
                                  '${(candidates[index].confidence * 100).round()}%',
                                ),
                              ),
                              IconButton(
                                tooltip: 'Exclude row',
                                onPressed: () =>
                                    setState(() => candidates.removeAt(index)),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          DropdownButtonFormField<String>(
                            key: ValueKey(
                              'mapping-$index-${candidates[index].biomarkerId}',
                            ),
                            initialValue:
                                candidates[index].biomarkerId ?? temporary,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Map to biomarker',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: temporary,
                                child: Text('Create temporary biomarker'),
                              ),
                              for (final biomarker in controller.biomarkers)
                                DropdownMenuItem(
                                  value: biomarker.id,
                                  child: Text(
                                    biomarker.displayName,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) => setState(() {
                              candidates[index] = candidates[index].copyWith(
                                biomarkerId: value == temporary ? null : value,
                                clearMapping: value == temporary,
                              );
                            }),
                          ),
                          if (candidates[index].rowText?.isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Page ${candidates[index].page ?? '?'} · '
                                '${candidates[index].rowText}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Discard'),
            ),
            FilledButton.icon(
              onPressed: report.errors.isNotEmpty || candidates.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save PDF + results'),
            ),
          ],
        ),
      ),
    );
    if (approved == true && context.mounted) {
      try {
        final result = await controller.saveReviewedLabReport(
          report: report,
          measurements: candidates,
          reportDate: reportDate,
          reportComment: comment.text,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.cloudWarning ??
                    'Saved ${candidates.length} measurements from ${report.fileName}.',
              ),
            ),
          );
        }
      } on Object catch (error) {
        if (context.mounted) await showAppError(context, error);
      }
    }
    comment.dispose();
  }

  Future<void> _showDocument(
    BuildContext context,
    AppController controller,
    HealthDocument document,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(document.fileName),
              subtitle: Text(
                '${controller.measurements.where((item) => item.documentId == document.id).length} linked results',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit report metadata'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('Delete report and linked results'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'edit') {
      await _editDocument(context, controller, document);
    } else {
      final confirmed = await showConfirmAction(
        context,
        title: 'Delete ${document.fileName}?',
        message:
            'The PDF record and every measurement imported from it will be removed.',
        confirmLabel: 'Delete all',
        destructive: true,
      );
      if (confirmed) await controller.deleteDocument(document);
    }
  }

  Future<void> _editDocument(
    BuildContext context,
    AppController controller,
    HealthDocument document,
  ) async {
    final lab = TextEditingController(text: document.labName);
    final comment = TextEditingController(text: document.reportComment);
    var date = document.documentDate;
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit lab report'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lab,
                decoration: const InputDecoration(labelText: 'Lab name'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Report date'),
                subtitle: Text(
                  date == null
                      ? 'Not set'
                      : DateFormat('dd.MM.yyyy').format(date!),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime(1950),
                    lastDate: DateTime.now(),
                    initialDate: date ?? DateTime.now(),
                  );
                  if (selected != null) setState(() => date = selected);
                },
              ),
              TextField(
                controller: comment,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Comment'),
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
    try {
      if (save == true) {
        await controller.updateDocument(
          HealthDocument(
            id: document.id,
            profileId: document.profileId,
            fileName: document.fileName,
            mimeType: document.mimeType,
            sha256: document.sha256,
            localPath: document.localPath,
            oneDriveItemId: document.oneDriveItemId,
            documentDate: date,
            parsedAt: document.parsedAt,
            parserProvider: document.parserProvider,
            parserModel: document.parserModel,
            labName: lab.text,
            reportComment: comment.text,
            parseStatus: document.parseStatus,
            warnings: document.warnings,
            errors: document.errors,
            createdAt: document.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } finally {
      lab.dispose();
      comment.dispose();
    }
  }

  Future<void> _generate(BuildContext context, AppController controller) async {
    final priorities = TextEditingController();
    DateTime? targetDate;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Plan a lab visit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priorities,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Priorities (optional)',
                  hintText:
                      'e.g. cardiometabolic risk, fatigue, 250 € upper budget',
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Target visit date'),
                subtitle: Text(
                  targetDate == null
                      ? 'Not set'
                      : DateFormat('dd.MM.yyyy').format(targetDate!),
                ),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: () async {
                  final selected = await showDatePicker(
                    context: context,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (selected != null) setState(() => targetDate = selected);
                },
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline),
                title: Text('Complete active-profile context'),
                subtitle: Text(
                  'No silent truncation; only the configured provider receives it.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate draft'),
            ),
          ],
        ),
      ),
    );
    if (approved == true && context.mounted) {
      try {
        await controller.generateLabPlan(
          targetDate: targetDate,
          priorities: priorities.text,
        );
      } on Object catch (error) {
        if (context.mounted) await showAppError(context, error);
      }
    }
    priorities.dispose();
  }

  Future<void> _export(
    BuildContext context,
    AppController controller,
    LabPlan plan,
  ) async {
    final format = await showModalBottomSheet<LabPlanExportFormat>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Export checklist'),
              subtitle: Text(
                'You will choose the destination before a file is created.',
              ),
            ),
            for (final format in LabPlanExportFormat.values)
              ListTile(
                leading: Icon(switch (format) {
                  LabPlanExportFormat.pdf => Icons.picture_as_pdf_outlined,
                  LabPlanExportFormat.csv => Icons.table_chart_outlined,
                  LabPlanExportFormat.json => Icons.data_object,
                }),
                title: Text(format.name.toUpperCase()),
                onTap: () => Navigator.pop(context, format),
              ),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;
    try {
      final file = await controller.exportService.build(plan, format);
      final extension = format.name;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save ${file.fileName}',
        fileName: file.fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: file.bytes,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${format.name.toUpperCase()} export saved.')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }
}

class _DraftPlanCard extends StatelessWidget {
  const _DraftPlanCard({
    required this.generation,
    required this.onSave,
    required this.onExport,
  });

  final LabPlanGeneration generation;
  final VoidCallback onSave;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(
      context,
    ).colorScheme.primaryContainer.withValues(alpha: 0.35),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Unsaved draft · ${generation.plan.title}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          if (generation.warnings.isNotEmpty)
            ...generation.warnings.map(
              (warning) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_outlined),
                title: Text(warning),
              ),
            ),
          _PlanTiers(plan: generation.plan),
          if (generation.citations.isNotEmpty)
            Wrap(
              spacing: 6,
              children: [
                for (
                  var index = 0;
                  index < generation.citations.length;
                  index++
                )
                  ActionChip(
                    avatar: const Icon(Icons.open_in_new, size: 16),
                    label: Text('Source ${index + 1}'),
                    onPressed: () =>
                        launchUrl(Uri.parse(generation.citations[index])),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Export'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save plan'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SavedPlanCard extends StatelessWidget {
  const _SavedPlanCard({
    required this.plan,
    required this.onExport,
    required this.onToggle,
    required this.onDelete,
  });

  final LabPlan plan;
  final VoidCallback onExport;
  final Future<void> Function(LabPlanItem, bool) onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(plan.title),
      subtitle: Text(
        '${DateFormat.yMMMd().format(plan.plannedFor ?? plan.createdAt)} · '
        '${plan.items.length} tests · ${plan.provider ?? 'manual'}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: 'Plan actions',
        onSelected: (value) => value == 'export' ? onExport() : onDelete(),
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'export', child: Text('Export')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: _PlanTiers(plan: plan, onToggle: onToggle),
        ),
      ],
    ),
  );
}

class _PlanTiers extends StatelessWidget {
  const _PlanTiers({required this.plan, this.onToggle});

  final LabPlan plan;
  final Future<void> Function(LabPlanItem, bool)? onToggle;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final tier in LabTier.values)
        ExpansionTile(
          initiallyExpanded: tier == LabTier.core,
          tilePadding: EdgeInsets.zero,
          title: Text(_label(tier)),
          subtitle: Text(
            '${plan.itemsThrough(tier).length} tests · '
            '${plan.knownTotal(tier).toStringAsFixed(2)} € known'
            '${plan.missingPriceCount(tier) == 0 ? '' : ' + ${plan.missingPriceCount(tier)} unpriced'}',
          ),
          children: [
            for (final item in plan.itemsThrough(tier))
              CheckboxListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 8),
                title: Text(item.biomarkerName),
                subtitle: Text(
                  [
                    item.evidenceClass.name,
                    item.rationale,
                    if (item.preparation.isNotEmpty) item.preparation,
                    item.priceEur == null
                        ? 'Price unknown'
                        : '${item.priceEur!.toStringAsFixed(2)} €',
                  ].join(' · '),
                ),
                value: item.checked,
                onChanged: onToggle == null
                    ? null
                    : (checked) => onToggle!(item, checked ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
          ],
        ),
    ],
  );

  String _label(LabTier tier) => switch (tier) {
    LabTier.core => 'Core',
    LabTier.advanced => 'Advanced (includes Core)',
    LabTier.comprehensive => 'Comprehensive (includes all)',
  };
}

class _BiomarkerCatalog extends StatefulWidget {
  const _BiomarkerCatalog({
    required this.controller,
    required this.latestByBiomarker,
  });

  final AppController controller;
  final Map<String, Measurement> latestByBiomarker;

  @override
  State<_BiomarkerCatalog> createState() => _BiomarkerCatalogState();
}

class _BiomarkerCatalogState extends State<_BiomarkerCatalog> {
  final _search = TextEditingController();
  String _category = 'All';
  String _status = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = {
      'All',
      ...widget.controller.biomarkers
          .map((item) => item.category.trim())
          .where((item) => item.isNotEmpty),
    }.toList()..sort();
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.controller.biomarkers.where((biomarker) {
      final latest = widget.latestByBiomarker[biomarker.id];
      final matchesQuery =
          query.isEmpty ||
          biomarker.displayName.toLowerCase().contains(query) ||
          biomarker.synonyms.any((item) => item.toLowerCase().contains(query));
      final matchesCategory =
          _category == 'All' || biomarker.category == _category;
      final matchesStatus = switch (_status) {
        'Measured' => latest != null,
        'Never measured' => latest == null,
        'Missing price' => biomarker.priceEur == null,
        'Conversion issue' => widget.controller.measurements.any(
          (item) =>
              item.biomarkerId == biomarker.id &&
              item.conversionStatus == 'unsupported',
        ),
        _ => true,
      };
      return matchesQuery && matchesCategory && matchesStatus;
    }).toList();
    return Column(
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Search names and lab synonyms',
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.close),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              DropdownButton<String>(
                value: _category,
                items: [
                  for (final category in categories)
                    DropdownMenuItem(value: category, child: Text(category)),
                ],
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: 'All', child: Text('All statuses')),
                  DropdownMenuItem(value: 'Measured', child: Text('Measured')),
                  DropdownMenuItem(
                    value: 'Never measured',
                    child: Text('Never measured'),
                  ),
                  DropdownMenuItem(
                    value: 'Missing price',
                    child: Text('Missing price'),
                  ),
                  DropdownMenuItem(
                    value: 'Conversion issue',
                    child: Text('Conversion issue'),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
              const SizedBox(width: 12),
              Text('${filtered.length} shown'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const EmptyState(
            icon: Icons.filter_alt_off_outlined,
            title: 'No matching biomarkers',
            message: 'Clear or change the catalog filters.',
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final biomarker in filtered)
                  _BiomarkerTile(
                    biomarker: biomarker,
                    latest: widget.latestByBiomarker[biomarker.id],
                    controller: widget.controller,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BiomarkerTile extends StatelessWidget {
  const _BiomarkerTile({
    required this.biomarker,
    required this.latest,
    required this.controller,
  });

  final Biomarker biomarker;
  final Measurement? latest;
  final AppController controller;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const CircleAvatar(child: Icon(Icons.science_outlined)),
    title: Text(biomarker.displayName),
    subtitle: Text(
      [
        if (biomarker.category.isNotEmpty) biomarker.category,
        if (latest != null)
          '${latest!.value} ${latest!.unit} · ${DateFormat.yMMMd().format(latest!.takenAt)}'
        else
          'No result yet',
        if (latest?.conversionStatus == 'unsupported') 'Conversion unavailable',
      ].join(' · '),
    ),
    trailing: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          biomarker.priceEur == null
              ? 'No price'
              : '${biomarker.priceEur!.toStringAsFixed(2)} €',
        ),
        const Icon(Icons.chevron_right, size: 18),
      ],
    ),
    onTap: () => showBiomarkerDetail(context, controller, biomarker),
    onLongPress: () =>
        showAddBiomarkerDialog(context, controller, existing: biomarker),
  );
}
