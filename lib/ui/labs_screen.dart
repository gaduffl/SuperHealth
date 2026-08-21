import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/document_parsing_service.dart';
import '../analysis/lab_plan_pricing.dart';
import '../ai/lab_planner_service.dart';
import '../ai/provider_clients.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/long_task_guard.dart';
import '../app/shell_navigation.dart';
import '../biomarkers/biomarker_status_service.dart';
import '../biomarkers/unit_conversion_service.dart';
import '../domain/entities.dart';
import '../export/lab_plan_export_service.dart';
import 'biomarker_category_localization.dart';
import 'biomarker_detail_sheet.dart';
import 'biomarker_lists_sheet.dart';
import 'charts.dart';
import 'common.dart';
import 'biomarker_package_screen.dart';
import 'dialogs.dart';
import 'lab_price_screen.dart';
import 'lab_report_screen.dart';
import 'dose_underlay.dart';
import 'temporary_biomarker_resolution_screen.dart';

String _labsText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

/// Translates a Today tile's deep link into the catalog's status filter.
///
/// "Without a usable range" covers both an unusable range and a marker that was
/// never measured; the catalog can only show one at a time, so it opens on the
/// unusable ones and the other stays a click away in the dropdown.
({int token, String status})? _statusRequest(ShellNavigation navigation) {
  final request = navigation.request;
  if (request == null) return null;
  final status = switch (request.filter) {
    SectionFilter.dueBiomarkers => 'Due',
    SectionFilter.belowTarget => 'Below',
    SectionFilter.aboveTarget => 'Above',
    SectionFilter.withoutUsableRange => 'No comparison range',
    _ => null,
  };
  if (status == null) return null;
  return (token: request.token, status: status);
}

Uri? _safeWebUri(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
      ? uri
      : null;
}

String _localizedStatusLabel(
  BuildContext context,
  BiomarkerStatus status,
) => switch (status.label) {
  'Never measured' => _labsText(context, status.label, 'Noch nie gemessen'),
  'No comparison range' => _labsText(
    context,
    status.label,
    'Kein Vergleichsbereich',
  ),
  'Unavailable' => _labsText(context, status.label, 'Nicht verfügbar'),
  'Below personal target' => _labsText(
    context,
    status.label,
    'Unter persönlichem Zielbereich',
  ),
  'Above personal target' => _labsText(
    context,
    status.label,
    'Über persönlichem Zielbereich',
  ),
  'In personal target' => _labsText(
    context,
    status.label,
    'Im persönlichen Zielbereich',
  ),
  'In stored optimal band' => _labsText(
    context,
    status.label,
    'Im gespeicherten Optimalbereich',
  ),
  'Below stored reference' => _labsText(
    context,
    status.label,
    'Unter gespeichertem Referenzbereich',
  ),
  'Above stored reference' => _labsText(
    context,
    status.label,
    'Über gespeichertem Referenzbereich',
  ),
  'Within stored reference' => _labsText(
    context,
    status.label,
    'Im gespeicherten Referenzbereich',
  ),
  'Below stored optimal band' => _labsText(
    context,
    status.label,
    'Unter gespeichertem Optimalbereich',
  ),
  'Above stored optimal band' => _labsText(
    context,
    status.label,
    'Über gespeichertem Optimalbereich',
  ),
  'Below lab range' => _labsText(context, status.label, 'Unter Laborbereich'),
  'Above lab range' => _labsText(context, status.label, 'Über Laborbereich'),
  'Within lab range' => _labsText(context, status.label, 'Im Laborbereich'),
  _ => status.label,
};

String _localizedStatusDetail(BuildContext context, BiomarkerStatus status) {
  final german = status.detail
      .replaceAll('No recorded result', 'Kein Ergebnis gespeichert')
      .replaceAll(
        'The reported value or unit cannot be evaluated safely',
        'Der angegebene Wert oder die Einheit kann nicht sicher ausgewertet werden',
      )
      .replaceAll(
        'Result recorded, but no personal target, stored reference, or lab range is available',
        'Ergebnis gespeichert, aber kein persönlicher Ziel-, Referenz- oder Laborbereich verfügbar',
      )
      .replaceAll(
        'A comparison range exists but cannot be evaluated safely',
        'Ein Vergleichsbereich ist vorhanden, kann aber nicht sicher ausgewertet werden',
      )
      .replaceAll('Personal target:', 'Persönlicher Zielbereich:')
      .replaceAll('Borderline:', 'Grenzbereich:')
      .replaceAll('Stored reference:', 'Gespeicherte Referenz:')
      .replaceAll('Stored optimal:', 'Gespeicherter Optimalbereich:')
      .replaceAll('Lab-reported range:', 'Vom Labor angegebener Bereich:');
  return _labsText(context, status.detail, german);
}

class LabsScreen extends StatefulWidget {
  const LabsScreen({super.key});

  @override
  State<LabsScreen> createState() => _LabsScreenState();
}

class _LabsScreenState extends State<LabsScreen> {
  int? _handledRequestToken;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final profile = controller.activeProfile;
    final latestByBiomarker = _latestMeasurements(controller.measurements);
    final statuses = profile == null
        ? const <String, BiomarkerStatus>{}
        : _biomarkerStatuses(
            controller: controller,
            profile: profile,
            latestByBiomarker: latestByBiomarker,
          );
    _openRequestedCatalog(context.watch<ShellNavigation>());

    final latestBiomarkers =
        controller.biomarkers
            .where((item) => latestByBiomarker.containsKey(item.id))
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final attention = latestBiomarkers.where((item) {
      final status = statuses[item.id];
      return status?.isBelow == true || status?.isAbove == true;
    }).toList();

    return PageBody(
      child: RefreshIndicator(
        onRefresh: controller.refreshActiveData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            Text(
              _labsText(context, 'Quick actions', 'Schnellaktionen'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // First, because one PDF carries a whole panel while the manual
                // entry beside it carries a single value. It stays available
                // with an empty catalog: the import is how the catalog fills up.
                Expanded(
                  child: _BiomarkerQuickActionCard(
                    icon: Icons.document_scanner_outlined,
                    label: _labsText(
                      context,
                      'Import lab PDF',
                      'Labor-PDF importieren',
                    ),
                    onTap: controller.busy
                        ? null
                        : () => _importLabPdf(context, controller),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _BiomarkerQuickActionCard(
                    icon: Icons.add,
                    label: _labsText(
                      context,
                      'Add measurement',
                      'Messwert hinzufügen',
                    ),
                    onTap: controller.biomarkers.isEmpty
                        ? null
                        : () => _addMeasurement(controller),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _BiomarkerQuickActionCard(
                    icon: Icons.insights,
                    label: _labsText(context, 'Dashboard', 'Dashboard'),
                    onTap: profile == null ? null : () => _openDashboard(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _BiomarkerQuickActionCard(
                    icon: Icons.list,
                    label: _labsText(
                      context,
                      'Biomarker lists',
                      'Biomarkerlisten',
                    ),
                    onTap: () => showBiomarkerListsSheet(context, controller),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _BiomarkerQuickActionCard(
                    icon: Icons.warning,
                    label: _labsText(
                      context,
                      'Due biomarkers',
                      'Fällige Biomarker',
                    ),
                    onTap: () => _openWorkspace(initialStatus: 'Due'),
                  ),
                ),
                // Keeps the last card the same width as the four above it.
                const SizedBox(width: 16),
                const Expanded(child: SizedBox()),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              _labsText(context, 'Latest values', 'Neueste Werte'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (latestBiomarkers.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.timeline, size: 48, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        _labsText(
                          context,
                          'No measurements yet',
                          'Noch keine Messwerte',
                        ),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _labsText(
                          context,
                          'Add your first measurement to see the status overview.',
                          'Füge den ersten Messwert hinzu, um die Statusübersicht zu sehen.',
                        ),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              _BiomarkerStatusSummary(
                statuses: [
                  for (final item in latestBiomarkers) statuses[item.id]!,
                ],
              ),
              const SizedBox(height: 8),
              if (attention.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _labsText(
                              context,
                              'No latest value is outside its selected comparison range.',
                              'Kein neuester Wert liegt außerhalb seines gewählten Vergleichsbereichs.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                for (final biomarker in attention)
                  _BiomarkerHomeTile(
                    biomarker: biomarker,
                    measurement: latestByBiomarker[biomarker.id]!,
                    status: statuses[biomarker.id]!,
                    controller: controller,
                  ),
            ],
            const SizedBox(height: 24),
            // The workspace is catalogue administration — PDF imports aside,
            // it is prices, packages, plans and the full biomarker list.
            if (controller.visibility.biomarkerCatalogAdmin)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(
                    _labsText(
                      context,
                      'Lab planning and biomarker management',
                      'Laborplanung und Biomarkerverwaltung',
                    ),
                  ),
                  subtitle: Text(
                    _labsText(
                      context,
                      'PDF imports, saved plans, documents, and the complete catalog',
                      'PDF-Importe, gespeicherte Pläne, Dokumente und der vollständige Katalog',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openWorkspace(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openRequestedCatalog(ShellNavigation navigation) {
    final navigationRequest = navigation.request;
    if (navigationRequest == null ||
        navigationRequest.token == _handledRequestToken) {
      return;
    }
    final statusRequest = _statusRequest(navigation);
    if (statusRequest == null && navigationRequest.section != AppSection.labs) {
      return;
    }
    _handledRequestToken = navigationRequest.token;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _openWorkspace(initialStatus: statusRequest?.status);
      }
    });
  }

  Future<void> _addMeasurement(AppController controller) async {
    final biomarker = await _chooseBiomarker(context, controller.biomarkers);
    if (biomarker != null && mounted) {
      await showAddMeasurementDialog(context, controller, biomarker);
    }
  }

  void _openDashboard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _BiomarkerDashboardScreen(),
      ),
    );
  }

  void _openWorkspace({String? initialStatus}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        // A status filter is a request for one section, and that section
        // builds its own scaffold; only the hub needs one wrapped around it.
        builder: (_) => initialStatus != null
            ? _BiomarkerWorkspaceScreen(initialStatus: initialStatus)
            : Scaffold(
                appBar: AppBar(
                  title: Text(
                    _labsText(
                      context,
                      'Biomarker management',
                      'Biomarkerverwaltung',
                    ),
                  ),
                ),
                body: const _BiomarkerWorkspaceScreen(),
              ),
      ),
    );
  }
}

/// The entry points into biomarker management, with what each one holds.
///
/// The counts are the point: a button that says "12 reports" is a decision the
/// reader can make before tapping, where a bare label is a guess.
class _WorkspaceHub extends StatelessWidget {
  const _WorkspaceHub({required this.controller, required this.onOpen});

  final AppController controller;
  final void Function(_WorkspaceSection section) onOpen;

  @override
  Widget build(BuildContext context) {
    final plans = controller.labPlans.length;
    final due = controller.dueBiomarkers.length;
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _HubTile(
            icon: Icons.checklist_rtl_outlined,
            title: _labsText(
              context,
              'Lab visit planner',
              'Laborbesuch planen',
            ),
            detail: controller.draftLabPlan != null
                ? _labsText(
                    context,
                    'An unsaved draft is waiting',
                    'Ein ungespeicherter Entwurf wartet',
                  )
                : _labsText(
                    context,
                    plans == 1 ? '1 saved plan' : '$plans saved plans',
                    plans == 1
                        ? '1 gespeicherter Plan'
                        : '$plans gespeicherte Pläne',
                  ),
            onTap: () => onOpen(_WorkspaceSection.plans),
          ),
          _HubTile(
            icon: Icons.science_outlined,
            title: _labsText(context, 'Biomarker catalog', 'Biomarkerkatalog'),
            detail: _labsText(
              context,
              '${controller.biomarkers.length} tests · ${controller.measurements.length} results',
              '${controller.biomarkers.length} Tests · ${controller.measurements.length} Ergebnisse',
            ),
            onTap: () => onOpen(_WorkspaceSection.catalog),
          ),
          _HubTile(
            icon: Icons.picture_as_pdf_outlined,
            title: _labsText(context, 'Lab documents', 'Labordokumente'),
            detail: _labsText(
              context,
              controller.documents.length == 1
                  ? '1 imported report'
                  : '${controller.documents.length} imported reports',
              controller.documents.length == 1
                  ? '1 importierter Bericht'
                  : '${controller.documents.length} importierte Berichte',
            ),
            onTap: () => onOpen(_WorkspaceSection.documents),
          ),
          // Only when something is actually due: an entry that always reads
          // "0 due" trains the reader to ignore it.
          if (due > 0)
            _HubTile(
              icon: Icons.event_repeat_outlined,
              title: _labsText(
                context,
                'Due for retest',
                'Erneute Messung fällig',
              ),
              detail: _labsText(
                context,
                due == 1 ? '1 biomarker due' : '$due biomarkers due',
                due == 1 ? '1 Biomarker fällig' : '$due Biomarker fällig',
              ),
              tone: Theme.of(context).colorScheme.error,
              onTap: () => onOpen(_WorkspaceSection.due),
            ),
          _HubTile(
            icon: Icons.inventory_2_outlined,
            title: _labsText(context, 'Test packages', 'Testpakete'),
            detail: _labsText(
              context,
              '${controller.biomarkerPackages.length} priced bundles',
              '${controller.biomarkerPackages.length} Pakete mit Preis',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BiomarkerPackageScreen(),
              ),
            ),
          ),
          _HubTile(
            icon: Icons.euro_outlined,
            title: _labsText(context, 'Lab prices', 'Laborpreise'),
            detail: _labsText(
              context,
              '${controller.biomarkers.where((item) => item.hasPrice).length} of ${controller.biomarkers.length} tests priced',
              '${controller.biomarkers.where((item) => item.hasPrice).length} von ${controller.biomarkers.length} Tests mit Preis',
            ),
            onTap: controller.busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LabPriceScreen(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
    this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: (tone ?? theme.colorScheme.primary).withValues(
            alpha: 0.14,
          ),
          child: Icon(icon, color: tone ?? theme.colorScheme.primary),
        ),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(detail),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// The parts of biomarker management, each its own page.
enum _WorkspaceSection { plans, due, documents, catalog }

/// The workspace, as a hub or as one of its sections.
///
/// It used to be a single scroll holding all four: the planner, what is due,
/// the reports, and the catalog — so reaching the catalog meant scrolling past
/// every saved plan and every PDF ever imported, and nothing on screen said
/// how much further it went. One page per section, reached from a hub that
/// names them and counts what is inside, replaces that.
class _BiomarkerWorkspaceScreen extends StatelessWidget {
  const _BiomarkerWorkspaceScreen({this.initialStatus, this.section});

  /// A status filter from a Today tile, which is a request for the catalog
  /// already filtered — so it opens that section directly rather than a hub
  /// the user would have to step through.
  final String? initialStatus;

  /// Null shows the hub.
  final _WorkspaceSection? section;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final now = DateTime.now();
    final activeProfile = controller.activeProfile;
    final latestByBiomarker = <String, Measurement>{};
    for (final measurement in controller.measurements) {
      final existing = latestByBiomarker[measurement.biomarkerId];
      if (existing == null || measurement.takenAt.isAfter(existing.takenAt)) {
        latestByBiomarker[measurement.biomarkerId] = measurement;
      }
    }
    final target =
        section ?? (initialStatus == null ? null : _WorkspaceSection.catalog);
    if (target == null) {
      return _WorkspaceHub(
        controller: controller,
        onOpen: (chosen) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _BiomarkerWorkspaceScreen(section: chosen),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _labsText(context, 'Biomarker management', 'Biomarkerverwaltung'),
        ),
      ),
      body: PageBody(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: switch (target) {
            _WorkspaceSection.plans => [
              SectionHeader(
                title: _labsText(
                  context,
                  'Lab visit planner',
                  'Laborbesuch planen',
                ),
                subtitle: _labsText(
                  context,
                  'Three cumulative tiers priced from your biomarker catalog',
                  'Drei aufeinander aufbauende Stufen mit Preisen aus deinem Biomarkerkatalog',
                ),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _labsText(
                        context,
                        'Import lab PDF',
                        'Labor-PDF importieren',
                      ),
                      onPressed: controller.busy
                          ? null
                          : () => _importLabPdf(context, controller),
                      icon: const Icon(Icons.document_scanner_outlined),
                    ),
                    // Packages and prices moved to the hub, which names them
                    // and says how many of each there are. Two unlabelled
                    // icons here were a second, worse door to the same rooms.
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      onPressed:
                          controller.busy || controller.biomarkers.isEmpty
                          ? null
                          : () => _generate(context, controller),
                      icon: const Icon(Icons.auto_awesome),
                      label: Text(_labsText(context, 'Plan', 'Planen')),
                    ),
                  ],
                ),
              ),
              if (controller.labPlanStage != null)
                _LabPlanProgressCard(
                  stage: controller.labPlanStage!,
                  startedAt: controller.labPlanStartedAt,
                  survivesBackground: controller.labPlanSurvivesBackground,
                  activity: controller.labPlanActivity,
                  activityAt: controller.labPlanActivityAt,
                ),
              if (controller.biomarkers.isEmpty)
                EmptyState(
                  icon: Icons.science_outlined,
                  title: _labsText(
                    context,
                    'Import or add your biomarker catalog first',
                    'Importiere oder ergänze zuerst deinen Biomarkerkatalog',
                  ),
                  message: _labsText(
                    context,
                    'The planner only selects known biomarkers and calculates tiers from stored EUR prices.',
                    'Die Planung wählt nur bekannte Biomarker und berechnet die Stufen aus den gespeicherten Euro-Preisen.',
                  ),
                  action: FilledButton.tonal(
                    onPressed: () =>
                        showAddBiomarkerDialog(context, controller),
                    child: Text(
                      _labsText(
                        context,
                        'Add biomarker',
                        'Biomarker hinzufügen',
                      ),
                    ),
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
                          SnackBar(
                            content: Text(
                              _labsText(
                                context,
                                'Lab plan saved.',
                                'Laborplan gespeichert.',
                              ),
                            ),
                          ),
                        );
                      }
                    } on Object catch (error) {
                      if (context.mounted) await showAppError(context, error);
                    }
                  },
                  onExport: () =>
                      _export(context, controller, draft.plan, saved: false),
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
                        Expanded(
                          child: Text(
                            _labsText(
                              context,
                              'The advisor will review the complete active profile, including past '
                                  'results, supplements, conditions, medicines, goals, symptoms, and prices.',
                              'Die Beratung prüft das vollständige aktive Profil einschließlich früherer '
                                  'Ergebnisse, Nahrungsergänzungen, Erkrankungen, Medikamente, Ziele, Symptome und Preise.',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (controller.labPlans.isNotEmpty) ...[
                SectionHeader(
                  title: _labsText(
                    context,
                    'Saved plans',
                    'Gespeicherte Pläne',
                  ),
                ),
                for (final plan in controller.labPlans)
                  _SavedPlanCard(
                    plan: plan,
                    onExport: () => _export(context, controller, plan),
                    onToggle: (items, checked) =>
                        controller.setLabPlanItemsChecked(plan, {
                          for (final item in items) item.id,
                        }, checked),
                    onDelete: () async {
                      final confirmed = await showConfirmAction(
                        context,
                        title: _labsText(
                          context,
                          'Delete ${plan.title}?',
                          '${plan.title} löschen?',
                        ),
                        message: _labsText(
                          context,
                          'The exported files, if any, are not affected.',
                          'Bereits exportierte Dateien bleiben erhalten.',
                        ),
                        confirmLabel: _labsText(context, 'Delete', 'Löschen'),
                        destructive: true,
                      );
                      if (confirmed) await controller.deleteLabPlan(plan);
                    },
                  ),
              ],
            ],
            _WorkspaceSection.due => [
              if (controller.dueBiomarkers.isNotEmpty) ...[
                SectionHeader(
                  title: _labsText(
                    context,
                    'Due for retest',
                    'Erneute Messung fällig',
                  ),
                  subtitle: _labsText(
                    context,
                    'From the active profile’s saved biomarker lists',
                    'Aus den gespeicherten Biomarkerlisten des aktiven Profils',
                  ),
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
                            '${listMembershipLabel(AppLocalizations.of(context), due.listNames)} · ${_labsText(context, 'every ${due.intervalDays} days', 'alle ${due.intervalDays} Tage')} · '
                            '${due.lastMeasuredAt == null ? _labsText(context, 'never measured', 'noch nie gemessen') : _labsText(context, '${due.daysOverdue} days overdue', '${due.daysOverdue} Tage überfällig')}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              showBiomarkerDetail(context, due.biomarker),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            _WorkspaceSection.documents => [
              if (controller.documents.isNotEmpty) ...[
                SectionHeader(
                  title: _labsText(context, 'Lab documents', 'Labordokumente'),
                  subtitle: _labsText(
                    context,
                    'Reviewed PDF imports and their extraction status',
                    'Geprüfte PDF-Importe und ihr Extraktionsstatus',
                  ),
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
                          onTap: () =>
                              _showDocument(context, controller, document),
                        ),
                    ],
                  ),
                ),
              ],
            ],
            _WorkspaceSection.catalog => [
              SectionHeader(
                title: _labsText(
                  context,
                  'Biomarker catalog',
                  'Biomarkerkatalog',
                ),
                subtitle: _labsText(
                  context,
                  '${controller.biomarkers.length} tests · ${controller.measurements.length} results',
                  '${controller.biomarkers.length} Tests · ${controller.measurements.length} Ergebnisse',
                ),
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: _labsText(
                        context,
                        'Saved biomarker lists',
                        'Gespeicherte Biomarkerlisten',
                      ),
                      onPressed: () =>
                          showBiomarkerListsSheet(context, controller),
                      icon: const Icon(Icons.checklist_outlined),
                    ),
                    if (controller.biomarkers.any(
                      (item) => item.isTemporary,
                    )) ...[
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: _labsText(
                          context,
                          'Resolve temporary biomarkers',
                          'Temporäre Biomarker zuordnen',
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const TemporaryBiomarkerResolutionScreen(),
                          ),
                        ),
                        icon: const Icon(Icons.merge_type_outlined),
                      ),
                    ],
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: _labsText(
                        context,
                        'Add biomarker',
                        'Biomarker hinzufügen',
                      ),
                      onPressed: () =>
                          showAddBiomarkerDialog(context, controller),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
              if (controller.biomarkers.isNotEmpty && activeProfile != null)
                _BiomarkerCatalog(
                  controller: controller,
                  latestByBiomarker: latestByBiomarker,
                  profile: activeProfile,
                  now: now,
                  statusRequest: initialStatus == null
                      ? null
                      : (token: -1, status: initialStatus!),
                ),
            ],
          },
        ),
      ),
    );
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
                _labsText(
                  context,
                  '${controller.measurements.where((item) => item.documentId == document.id).length} linked results',
                  '${controller.measurements.where((item) => item.documentId == document.id).length} verknüpfte Ergebnisse',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: Text(
                _labsText(context, 'View extraction', 'Extraktion ansehen'),
              ),
              subtitle: Text(
                _labsText(
                  context,
                  'Every result read from this PDF, and the PDF itself',
                  'Alle aus dieser PDF gelesenen Ergebnisse und die PDF selbst',
                ),
              ),
              onTap: () => Navigator.pop(context, 'view'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(
                _labsText(
                  context,
                  'Edit report metadata',
                  'Berichtsdaten bearbeiten',
                ),
              ),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                _labsText(
                  context,
                  'Delete report and linked results',
                  'Bericht und verknüpfte Ergebnisse löschen',
                ),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'view') {
      await showLabReport(context, document);
    } else if (action == 'edit') {
      await _editDocument(context, controller, document);
    } else {
      final confirmed = await showConfirmAction(
        context,
        title: _labsText(
          context,
          'Delete ${document.fileName}?',
          '${document.fileName} löschen?',
        ),
        message: _labsText(
          context,
          'The PDF record and every measurement imported from it will be removed.',
          'Der PDF-Datensatz und alle daraus importierten Messwerte werden entfernt.',
        ),
        confirmLabel: _labsText(context, 'Delete all', 'Alles löschen'),
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
          title: Text(
            _labsText(context, 'Edit lab report', 'Laborbericht bearbeiten'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lab,
                decoration: InputDecoration(
                  labelText: _labsText(context, 'Lab name', 'Laborname'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_labsText(context, 'Report date', 'Berichtsdatum')),
                subtitle: Text(
                  date == null
                      ? _labsText(context, 'Not set', 'Nicht festgelegt')
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
                decoration: InputDecoration(
                  labelText: _labsText(context, 'Comment', 'Kommentar'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_labsText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_labsText(context, 'Save', 'Speichern')),
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
          title: Text(
            _labsText(context, 'Plan a lab visit', 'Laborbesuch planen'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priorities,
                autofocus: true,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _labsText(
                    context,
                    'Priorities (optional)',
                    'Prioritäten (optional)',
                  ),
                  hintText: _labsText(
                    context,
                    'e.g. cardiometabolic risk, fatigue, 250 € upper budget',
                    'z. B. kardiometabolisches Risiko, Erschöpfung, höchstens 250 €',
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _labsText(
                    context,
                    'Target visit date',
                    'Geplanter Besuchstermin',
                  ),
                ),
                subtitle: Text(
                  targetDate == null
                      ? _labsText(context, 'Not set', 'Nicht festgelegt')
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lock_outline),
                title: Text(
                  _labsText(
                    context,
                    'Complete active-profile context',
                    'Vollständiger Kontext des aktiven Profils',
                  ),
                ),
                subtitle: Text(
                  _labsText(
                    context,
                    'No silent truncation; only the configured provider receives it.',
                    'Keine stille Kürzung; nur der konfigurierte Anbieter erhält den Kontext.',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_labsText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.auto_awesome),
              label: Text(
                _labsText(context, 'Generate draft', 'Entwurf erstellen'),
              ),
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
          notice: LongTaskNotice(
            title: _labsText(
              context,
              'Planning your lab visit',
              'Laborbesuch wird geplant',
            ),
            text: _labsText(
              context,
              'This takes a few minutes.',
              'Das dauert einige Minuten.',
            ),
          ),
        );
      } on Object catch (error) {
        if (context.mounted) await showAppError(context, error);
      }
    }
    priorities.dispose();
  }

  /// [saved] is false for the unsaved draft, whose tests cannot be ticked yet
  /// and so has nothing to build a doctor's request from.
  Future<void> _export(
    BuildContext context,
    AppController controller,
    LabPlan plan, {
    bool saved = true,
  }) async {
    final choice = await showModalBottomSheet<_ExportChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                _labsText(
                  context,
                  'Export checklist',
                  'Checkliste exportieren',
                ),
              ),
              subtitle: Text(
                _labsText(
                  context,
                  'You will choose the destination before a file is created.',
                  'Du wählst den Speicherort, bevor eine Datei erstellt wird.',
                ),
              ),
            ),
            if (saved) ...[
              ListTile(
                leading: const Icon(Icons.medical_information_outlined),
                title: Text(
                  _labsText(
                    context,
                    'PDF for the doctor',
                    'PDF für die Ärztin oder den Arzt',
                  ),
                ),
                subtitle: Text(
                  _labsText(
                    context,
                    'One tier, only the tests you ticked, without the planning notes.',
                    'Eine Stufe, nur die angehakten Tests, ohne die Planungshinweise.',
                  ),
                ),
                onTap: () =>
                    Navigator.pop(context, _ExportChoice.doctorRequest),
              ),
              const Divider(height: 1),
            ],
            for (final format in LabPlanExportFormat.values)
              ListTile(
                leading: Icon(switch (format) {
                  LabPlanExportFormat.pdf => Icons.picture_as_pdf_outlined,
                  LabPlanExportFormat.csv => Icons.table_chart_outlined,
                  LabPlanExportFormat.json => Icons.data_object,
                }),
                title: Text(
                  _labsText(
                    context,
                    'Full plan · ${format.name.toUpperCase()}',
                    'Vollständiger Plan · ${format.name.toUpperCase()}',
                  ),
                ),
                onTap: () => Navigator.pop(context, _ExportChoice.of(format)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == _ExportChoice.doctorRequest) {
      await _exportDoctorRequest(context, controller, plan);
      return;
    }
    final format = choice.format!;
    try {
      final file = await controller.exportService.build(plan, format);
      if (!context.mounted) return;
      final extension = format.name;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: _labsText(
          context,
          'Save ${file.fileName}',
          '${file.fileName} speichern',
        ),
        fileName: file.fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: file.bytes,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _labsText(
                context,
                '${format.name.toUpperCase()} export saved.',
                '${format.name.toUpperCase()}-Export gespeichert.',
              ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  /// Exports one tier's ticked tests as the page to hand over.
  ///
  /// The tier is asked for rather than assumed: the tiers are cumulative, so
  /// "the chosen one" is a decision about how much to request at this visit,
  /// and only the reader knows which they settled on.
  Future<void> _exportDoctorRequest(
    BuildContext context,
    AppController controller,
    LabPlan plan,
  ) async {
    final tier = await showDialog<LabTier>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_labsText(context, 'Which tier?', 'Welche Stufe?')),
        children: [
          for (final tier in LabTier.values)
            Builder(
              builder: (context) {
                final all = plan.itemsThrough(tier);
                final selected = plan.selectedItemsThrough(tier).length;
                return ListTile(
                  // A tier with nothing ticked would export an empty page, so
                  // it is offered as unavailable rather than as a choice that
                  // silently produces nothing.
                  enabled: selected > 0,
                  title: Text(_shortTierLabel(context, tier)),
                  subtitle: Text(
                    selected == 0
                        ? _labsText(
                            context,
                            'Nothing ticked yet',
                            'Noch nichts angehakt',
                          )
                        : _labsText(
                            context,
                            '$selected of ${all.length} tests',
                            '$selected von ${all.length} Tests',
                          ),
                  ),
                  onTap: () => Navigator.pop(context, tier),
                );
              },
            ),
        ],
      ),
    );
    if (tier == null || !context.mounted) return;
    try {
      final file = await controller.exportService.buildTierRequest(plan, tier);
      if (!context.mounted) return;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: _labsText(
          context,
          'Save ${file.fileName}',
          '${file.fileName} speichern',
        ),
        fileName: file.fileName,
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        bytes: file.bytes,
      );
      if (path != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _labsText(
                context,
                'Saved ${plan.selectedItemsThrough(tier).length} test(s) for the doctor.',
                '${plan.selectedItemsThrough(tier).length} Test(s) für die Praxis gespeichert.',
              ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (context.mounted) await showAppError(context, error);
    }
  }

  String _shortTierLabel(BuildContext context, LabTier tier) => switch (tier) {
    LabTier.core => _labsText(context, 'Core', 'Basis'),
    LabTier.advanced => _labsText(context, 'Advanced', 'Erweitert'),
    LabTier.comprehensive => _labsText(context, 'Comprehensive', 'Umfassend'),
  };
}

/// What the export sheet can produce.
///
/// The three formats export the whole plan and map straight onto
/// [LabPlanExportFormat]; the doctor's request is a different document with a
/// different audience, which is why it is not a fourth format.
enum _ExportChoice {
  doctorRequest(null),
  pdf(LabPlanExportFormat.pdf),
  csv(LabPlanExportFormat.csv),
  json(LabPlanExportFormat.json);

  const _ExportChoice(this.format);

  final LabPlanExportFormat? format;

  static _ExportChoice of(LabPlanExportFormat format) => switch (format) {
    LabPlanExportFormat.pdf => _ExportChoice.pdf,
    LabPlanExportFormat.csv => _ExportChoice.csv,
    LabPlanExportFormat.json => _ExportChoice.json,
  };
}

Map<String, Measurement> _latestMeasurements(
  Iterable<Measurement> measurements,
) {
  final latest = <String, Measurement>{};
  for (final measurement in measurements) {
    final existing = latest[measurement.biomarkerId];
    if (existing == null || measurement.takenAt.isAfter(existing.takenAt)) {
      latest[measurement.biomarkerId] = measurement;
    }
  }
  return latest;
}

Map<String, BiomarkerStatus> _biomarkerStatuses({
  required AppController controller,
  required Profile profile,
  required Map<String, Measurement> latestByBiomarker,
}) {
  final service = BiomarkerStatusService();
  final now = DateTime.now();
  return {
    for (final biomarker in controller.biomarkers)
      biomarker.id: service.evaluate(
        biomarker: biomarker,
        measurement: latestByBiomarker[biomarker.id],
        profile: profile,
        targets: controller.profileTargets,
        referenceRanges: controller.biomarkerRanges,
        now: now,
      ),
  };
}

/// Lab-report import, shared by the Labs home and the biomarker workspace.
///
/// Top-level rather than a method so both entry points call the same code.
/// The import is the bulk path — one PDF carries a whole panel — so it needs
/// to be reachable without first knowing it lives inside the workspace.

Future<void> _importLabPdf(
  BuildContext context,
  AppController controller,
) async {
  try {
    final selection = await FilePicker.platform.pickFiles(
      dialogTitle: _labsText(
        context,
        'Choose a lab report PDF',
        'Laborbericht als PDF auswählen',
      ),
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
    if (!context.mounted) return;
    if (bytes == null) {
      throw StateError(
        _labsText(
          context,
          'The selected PDF could not be read.',
          'Die ausgewählte PDF konnte nicht gelesen werden.',
        ),
      );
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
        title: Text(
          _labsText(
            context,
            'Review extracted lab report',
            'Extrahierten Laborbericht prüfen',
          ),
        ),
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
                title: Text(
                  _labsText(
                    context,
                    'Sample / report date *',
                    'Proben- / Berichtsdatum *',
                  ),
                ),
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
                decoration: InputDecoration(
                  labelText: _labsText(
                    context,
                    'Report comment',
                    'Kommentar zum Bericht',
                  ),
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
                _labsText(
                  context,
                  '${candidates.length} measurements',
                  '${candidates.length} Messwerte',
                ),
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
                              tooltip: _labsText(
                                context,
                                'Review and edit row',
                                'Zeile prüfen und bearbeiten',
                              ),
                              onPressed: () async {
                                final original = candidates[index];
                                final edited = await _editParsedMeasurement(
                                  context,
                                  original,
                                );
                                if (edited == null) return;
                                final currentIndex = candidates.indexOf(
                                  original,
                                );
                                if (currentIndex >= 0) {
                                  setState(
                                    () => candidates[currentIndex] = edited,
                                  );
                                }
                              },
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: _labsText(
                                context,
                                'Exclude row',
                                'Zeile ausschließen',
                              ),
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
                          decoration: InputDecoration(
                            labelText: _labsText(
                              context,
                              'Map to biomarker',
                              'Biomarker zuordnen',
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: temporary,
                              child: Text(
                                _labsText(
                                  context,
                                  'Create temporary biomarker',
                                  'Temporären Biomarker erstellen',
                                ),
                              ),
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
                              '${_labsText(context, 'Page', 'Seite')} ${candidates[index].page ?? '?'} · '
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
            child: Text(_labsText(context, 'Discard', 'Verwerfen')),
          ),
          FilledButton.icon(
            onPressed: report.errors.isNotEmpty || candidates.isEmpty
                ? null
                : () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _labsText(
                context,
                'Save PDF + results',
                'PDF und Ergebnisse speichern',
              ),
            ),
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
                  _labsText(
                    context,
                    'Saved ${candidates.length} measurements from ${report.fileName}.',
                    '${candidates.length} Messwerte aus ${report.fileName} gespeichert.',
                  ),
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

Future<ParsedMeasurementCandidate?> _editParsedMeasurement(
  BuildContext context,
  ParsedMeasurementCandidate candidate,
) async {
  final name = TextEditingController(text: candidate.reportedName);
  final value = TextEditingController(text: candidate.value.toString());
  final unit = TextEditingController(text: candidate.unit);
  final refLow = TextEditingController(
    text: candidate.refLow?.toString() ?? '',
  );
  final refHigh = TextEditingController(
    text: candidate.refHigh?.toString() ?? '',
  );
  final page = TextEditingController(text: candidate.page?.toString() ?? '');
  final notes = TextEditingController(text: candidate.notes);
  String? validationError;

  double? parseNumber(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  try {
    return await showDialog<ParsedMeasurementCandidate>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            _labsText(context, 'Review measurement', 'Messwert prüfen'),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: _labsText(
                        context,
                        'Reported biomarker name *',
                        'Angegebener Biomarkername *',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: value,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _labsText(context, 'Value *', 'Wert *'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: unit,
                          decoration: InputDecoration(
                            labelText: _labsText(
                              context,
                              'Reported unit *',
                              'Angegebene Einheit *',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: refLow,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _labsText(
                              context,
                              'Reference low',
                              'Referenzwert unten',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: refHigh,
                          keyboardType: const TextInputType.numberWithOptions(
                            signed: true,
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: _labsText(
                              context,
                              'Reference high',
                              'Referenzwert oben',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: page,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _labsText(
                              context,
                              'PDF page',
                              'PDF-Seite',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _labsText(context, 'Notes', 'Notizen'),
                    ),
                  ),
                  if (candidate.rowText?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _labsText(
                          context,
                          'Source row (read-only)',
                          'Quellzeile (schreibgeschützt)',
                        ),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(candidate.rowText!),
                    ),
                  ],
                  if (validationError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      validationError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_labsText(context, 'Cancel', 'Abbrechen')),
            ),
            FilledButton(
              onPressed: () {
                final parsedValue = parseNumber(value.text);
                final parsedLow = refLow.text.trim().isEmpty
                    ? null
                    : parseNumber(refLow.text);
                final parsedHigh = refHigh.text.trim().isEmpty
                    ? null
                    : parseNumber(refHigh.text);
                final parsedPage = page.text.trim().isEmpty
                    ? null
                    : int.tryParse(page.text.trim());
                String? error;
                if (name.text.trim().isEmpty) {
                  error = _labsText(
                    context,
                    'Enter the biomarker name.',
                    'Gib den Biomarkernamen ein.',
                  );
                } else if (parsedValue == null || !parsedValue.isFinite) {
                  error = _labsText(
                    context,
                    'Enter a valid finite measurement value.',
                    'Gib einen gültigen endlichen Messwert ein.',
                  );
                } else if (unit.text.trim().isEmpty) {
                  error = _labsText(
                    context,
                    'Enter the unit exactly as reported.',
                    'Gib die Einheit genau wie im Bericht an.',
                  );
                } else if (refLow.text.trim().isNotEmpty &&
                    (parsedLow == null || !parsedLow.isFinite)) {
                  error = _labsText(
                    context,
                    'Enter a valid lower reference bound or leave it blank.',
                    'Gib einen gültigen unteren Referenzwert ein oder lasse das Feld leer.',
                  );
                } else if (refHigh.text.trim().isNotEmpty &&
                    (parsedHigh == null || !parsedHigh.isFinite)) {
                  error = _labsText(
                    context,
                    'Enter a valid upper reference bound or leave it blank.',
                    'Gib einen gültigen oberen Referenzwert ein oder lasse das Feld leer.',
                  );
                } else if (parsedLow != null &&
                    parsedHigh != null &&
                    parsedLow > parsedHigh) {
                  error = _labsText(
                    context,
                    'The lower reference bound cannot exceed the upper bound.',
                    'Der untere Referenzwert darf nicht über dem oberen liegen.',
                  );
                } else if (page.text.trim().isNotEmpty &&
                    (parsedPage == null || parsedPage < 1)) {
                  error = _labsText(
                    context,
                    'Enter a PDF page of 1 or higher, or leave it blank.',
                    'Gib eine PDF-Seite ab 1 ein oder lasse das Feld leer.',
                  );
                }
                if (error != null) {
                  setState(() => validationError = error);
                  return;
                }
                Navigator.pop(
                  dialogContext,
                  candidate.copyWith(
                    reportedName: name.text.trim(),
                    value: parsedValue!,
                    unit: unit.text.trim(),
                    refLow: parsedLow,
                    clearRefLow: parsedLow == null,
                    refHigh: parsedHigh,
                    clearRefHigh: parsedHigh == null,
                    page: parsedPage,
                    clearPage: parsedPage == null,
                    notes: notes.text.trim(),
                  ),
                );
              },
              child: Text(_labsText(context, 'Apply', 'Übernehmen')),
            ),
          ],
        ),
      ),
    );
  } finally {
    name.dispose();
    value.dispose();
    unit.dispose();
    refLow.dispose();
    refHigh.dispose();
    page.dispose();
    notes.dispose();
  }
}

class _BiomarkerQuickActionCard extends StatelessWidget {
  const _BiomarkerQuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(
              icon,
              size: 32,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: onTap == null ? Theme.of(context).disabledColor : null,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BiomarkerStatusSummary extends StatelessWidget {
  const _BiomarkerStatusSummary({required this.statuses});

  final List<BiomarkerStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final below = statuses.where((item) => item.isBelow).length;
    final above = statuses.where((item) => item.isAbove).length;
    final inRange = statuses
        .where((item) => item.isTargetOrOptimal || item.isReferenceOrLab)
        .length;
    final unknown = statuses.length - below - above - inRange;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _labsText(context, 'Status summary', 'Statusübersicht'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                if (inRange > 0)
                  _BiomarkerStatusCount(
                    icon: Icons.check_circle,
                    color: _biomarkerOptimalColor(context),
                    count: inRange,
                    tooltip: _labsText(
                      context,
                      'Within selected range',
                      'Im gewählten Bereich',
                    ),
                  ),
                if (below > 0)
                  _BiomarkerStatusCount(
                    icon: Icons.arrow_downward,
                    color: _biomarkerOutOfRangeColor(context),
                    count: below,
                    tooltip: _labsText(context, 'Below', 'Unterhalb'),
                  ),
                if (above > 0)
                  _BiomarkerStatusCount(
                    icon: Icons.arrow_upward,
                    color: _biomarkerOutOfRangeColor(context),
                    count: above,
                    tooltip: _labsText(context, 'Above', 'Oberhalb'),
                  ),
                if (unknown > 0)
                  _BiomarkerStatusCount(
                    icon: Icons.help,
                    color: Colors.grey,
                    count: unknown,
                    tooltip: _labsText(
                      context,
                      'No usable comparison',
                      'Kein nutzbarer Vergleich',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BiomarkerStatusCount extends StatelessWidget {
  const _BiomarkerStatusCount({
    required this.icon,
    required this.color,
    required this.count,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final int count;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 4),
        Text('$count', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _BiomarkerHomeTile extends StatelessWidget {
  const _BiomarkerHomeTile({
    required this.biomarker,
    required this.measurement,
    required this.status,
    required this.controller,
  });

  final Biomarker biomarker;
  final Measurement measurement;
  final BiomarkerStatus status;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      leading: const Icon(Icons.analytics),
      title: Text(
        biomarker.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${measurement.value} ${measurement.unit}  •  '
        '${DateFormat('yyyy-MM-dd').format(measurement.takenAt)}',
      ),
      trailing: _BiomarkerStatusBadge(status: status),
      onTap: () => showBiomarkerDetail(context, biomarker),
    ),
  );
}

class _BiomarkerStatusBadge extends StatelessWidget {
  const _BiomarkerStatusBadge({required this.status});

  final BiomarkerStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (status.kind) {
      BiomarkerStatusKind.below => (
        Icons.arrow_downward,
        _biomarkerOutOfRangeColor(context),
      ),
      BiomarkerStatusKind.above => (
        Icons.arrow_upward,
        _biomarkerOutOfRangeColor(context),
      ),
      BiomarkerStatusKind.inPersonalTarget ||
      BiomarkerStatusKind.inStoredOptimal ||
      BiomarkerStatusKind.withinStoredReference ||
      BiomarkerStatusKind.withinLabRange => (
        Icons.check_circle,
        _biomarkerOptimalColor(context),
      ),
      BiomarkerStatusKind.neverMeasured ||
      BiomarkerStatusKind.noComparisonRange ||
      BiomarkerStatusKind.unavailable => (Icons.help, Colors.grey),
    };
    return Tooltip(
      message: _localizedStatusLabel(context, status),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 16),
      ),
    );
  }
}

class _BiomarkerDashboardScreen extends StatelessWidget {
  const _BiomarkerDashboardScreen();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final profile = controller.activeProfile;
    final latest = _latestMeasurements(controller.measurements);
    final statuses = profile == null
        ? const <String, BiomarkerStatus>{}
        : _biomarkerStatuses(
            controller: controller,
            profile: profile,
            latestByBiomarker: latest,
          );
    final groups = <String, List<Biomarker>>{};
    for (final biomarker in controller.biomarkers) {
      if (!latest.containsKey(biomarker.id)) continue;
      final category = biomarker.category.trim().isEmpty
          ? 'other'
          : biomarker.category.trim();
      groups.putIfAbsent(category, () => []).add(biomarker);
    }
    final languageCode = Localizations.localeOf(context).languageCode;
    final categories = groups.keys.toList()
      ..sort(
        (left, right) =>
            biomarkerCategoryLabel(left, languageCode).toLowerCase().compareTo(
              biomarkerCategoryLabel(right, languageCode).toLowerCase(),
            ),
      );

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: PageBody(
        child: RefreshIndicator(
          onRefresh: controller.refreshActiveData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              if (latest.isEmpty)
                EmptyState(
                  icon: Icons.insights,
                  title: _labsText(
                    context,
                    'No biomarker dashboard yet',
                    'Noch kein Biomarker-Dashboard',
                  ),
                  message: _labsText(
                    context,
                    'Add measurements to see category summaries.',
                    'Füge Messwerte hinzu, um Kategorieübersichten zu sehen.',
                  ),
                )
              else ...[
                _BiomarkerStatusSummary(
                  statuses: [
                    for (final biomarker in groups.values.expand(
                      (items) => items,
                    ))
                      statuses[biomarker.id]!,
                  ],
                ),
                const SizedBox(height: 8),
                for (final category in categories)
                  _BiomarkerCategoryCard(
                    category: category,
                    biomarkers: groups[category]!
                      ..sort((a, b) => a.displayName.compareTo(b.displayName)),
                    latest: latest,
                    statuses: statuses,
                    controller: controller,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BiomarkerCategoryCard extends StatelessWidget {
  const _BiomarkerCategoryCard({
    required this.category,
    required this.biomarkers,
    required this.latest,
    required this.statuses,
    required this.controller,
  });

  final String category;
  final List<Biomarker> biomarkers;
  final Map<String, Measurement> latest;
  final Map<String, BiomarkerStatus> statuses;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final categoryStatuses = [
      for (final biomarker in biomarkers) statuses[biomarker.id]!,
    ];
    final outOfRangeCount = categoryStatuses
        .where((item) => item.isBelow || item.isAbove)
        .length;
    final hasUnknown = categoryStatuses.any(
      (item) =>
          item.kind == BiomarkerStatusKind.noComparisonRange ||
          item.kind == BiomarkerStatusKind.unavailable ||
          item.kind == BiomarkerStatusKind.neverMeasured,
    );
    final isOptimal = outOfRangeCount == 0 && !hasUnknown;
    final color = outOfRangeCount > 0
        ? _biomarkerOutOfRangeColor(context)
        : hasUnknown
        ? Colors.grey
        : _biomarkerOptimalColor(context);
    final icon = outOfRangeCount > 0
        ? Icons.warning_amber_rounded
        : hasUnknown
        ? Icons.help_outline
        : Icons.check_circle_outline;
    final statusLabel = outOfRangeCount > 0
        ? _labsText(context, 'Out of range', 'Außerhalb des Bereichs')
        : isOptimal
        ? _labsText(context, 'Optimal', 'Optimal')
        : _labsText(
            context,
            'Comparison unavailable',
            'Vergleich nicht verfügbar',
          );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Icon(
              icon,
              key: ValueKey('biomarker-category-status-$category'),
              color: color,
              size: 23,
            ),
          ),
        ),
        title: Text(
          biomarkerCategoryLabel(
            category,
            Localizations.localeOf(context).languageCode,
          ),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          statusLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
        children: [
          for (final biomarker in biomarkers)
            _BiomarkerDashboardSection(
              biomarker: biomarker,
              latest: latest[biomarker.id]!,
              status: statuses[biomarker.id]!,
              controller: controller,
            ),
        ],
      ),
    );
  }
}

class _BiomarkerDashboardSection extends StatelessWidget {
  const _BiomarkerDashboardSection({
    required this.biomarker,
    required this.latest,
    required this.status,
    required this.controller,
  });

  final Biomarker biomarker;
  final Measurement latest;
  final BiomarkerStatus status;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final measurements = controller.measurements
        .where((item) => item.biomarkerId == biomarker.id)
        .toList(growable: false);
    final trend = _dashboardTrendData(
      biomarker: biomarker,
      measurements: measurements,
      status: status,
    );
    final underlay = trend.points.isEmpty
        ? const TrendDoseUnderlay(available: [])
        : resolveTrendDoseUnderlay(
            controller: controller,
            biomarkerId: biomarker.id,
            trendNames: [
              biomarker.displayName,
              biomarker.canonicalName,
              ...biomarker.synonyms,
            ],
            from: trend.points.first.day,
            through: trend.points.last.day,
          );
    return InkWell(
      onTap: () => showBiomarkerDetail(context, biomarker),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        biomarker.displayName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${latest.value} ${latest.unit} · '
                        '${DateFormat('yyyy-MM-dd').format(latest.takenAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _BiomarkerStatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _labsText(
                context,
                'Trend · ${trend.unit}',
                'Verlauf · ${trend.unit}',
              ),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 4),
            TrendChart(
              key: ValueKey('biomarker-trend-${biomarker.id}'),
              points: trend.points,
              dayLabel: (day) => DateFormat('MM/yy').format(day),
              semanticLabel: _labsText(
                context,
                '${biomarker.displayName} measurement trend in ${trend.unit}',
                'Messwertverlauf für ${biomarker.displayName} in ${trend.unit}',
              ),
              color: status.isBelow || status.isAbove
                  ? _biomarkerOutOfRangeColor(context)
                  : _biomarkerOptimalColor(context),
              rangeLow: trend.rangeLow,
              rangeHigh: trend.rangeHigh,
              rangeColor: Theme.of(context).colorScheme.secondaryContainer,
              noteLabel: (day) => _remarkOn(controller, biomarker, day),
              doseSeries: underlay.series,
              height: 150,
            ),
            if (underlay.hasChoice) ...[
              const SizedBox(height: 4),
              DoseUnderlayPicker(
                underlay: underlay,
                onChanged: (target) => controller.setTrendDoseLink(
                  biomarkerId: biomarker.id,
                  target: target,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

({
  List<({DateTime day, double value})> points,
  String unit,
  double? rangeLow,
  double? rangeHigh,
})
_dashboardTrendData({
  required Biomarker biomarker,
  required List<Measurement> measurements,
  required BiomarkerStatus status,
}) {
  final sorted = measurements.toList()
    ..sort((left, right) => left.takenAt.compareTo(right.takenAt));
  final latest = sorted.last;
  final conversions = UnitConversionService();
  final keys = <String>[
    biomarker.id,
    biomarker.canonicalName,
    biomarker.displayName,
    ...biomarker.synonyms,
  ];

  ({List<({DateTime day, double value})> points, String unit}) build(
    String unit,
  ) {
    final normalizedUnit = conversions.normalizeUnit(unit);
    final points = <({DateTime day, double value})>[];
    for (final measurement in sorted) {
      if (!measurement.value.isFinite) continue;
      final value = conversions.convertValueForBiomarkerKeys(
        measurement.value,
        measurement.unit,
        normalizedUnit,
        keys,
      );
      if (value?.isFinite == true) {
        points.add((day: measurement.takenAt, value: value!));
      }
    }
    return (points: points, unit: normalizedUnit);
  }

  ({List<({DateTime day, double value})> points, String unit}) selected;
  final preferredUnit = status.unit?.trim();
  if (preferredUnit != null && preferredUnit.isNotEmpty) {
    final preferred = build(preferredUnit);
    selected = preferred.points.isNotEmpty ? preferred : build(latest.unit);
  } else {
    selected = build(latest.unit);
  }
  final range = BiomarkerStatusService().convertUsedBand(
    status: status,
    biomarker: biomarker,
    toUnit: selected.unit,
  );
  return (
    points: selected.points,
    unit: selected.unit,
    rangeLow: range?.low,
    rangeHigh: range?.high,
  );
}

/// The remarks recorded for [biomarker] on [day], joined when a day holds more
/// than one reading.
///
/// The chart plots a day, not a measurement, so two results on the same date
/// share one point and would otherwise have to share one remark — the second
/// would simply vanish.
String? _remarkOn(AppController controller, Biomarker biomarker, DateTime day) {
  final notes = <String>[];
  for (final measurement in controller.measurements) {
    if (measurement.biomarkerId != biomarker.id) continue;
    final taken = measurement.takenAt;
    if (taken.year != day.year ||
        taken.month != day.month ||
        taken.day != day.day) {
      continue;
    }
    final note = measurement.notes.trim();
    if (note.isNotEmpty && !notes.contains(note)) notes.add(note);
  }
  return notes.isEmpty ? null : notes.join(' · ');
}

Color _biomarkerOptimalColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF56B4E9)
    : const Color(0xFF0072B2);

Color _biomarkerOutOfRangeColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFFFFC857)
    : const Color(0xFF9C6500);

Future<Biomarker?> _chooseBiomarker(
  BuildContext context,
  List<Biomarker> biomarkers,
) async {
  final search = TextEditingController();
  final result = await showModalBottomSheet<Biomarker>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) {
        final query = search.text.trim().toLowerCase();
        final filtered =
            biomarkers
                .where(
                  (item) =>
                      query.isEmpty ||
                      item.displayName.toLowerCase().contains(query) ||
                      item.synonyms.any(
                        (synonym) => synonym.toLowerCase().contains(query),
                      ),
                )
                .toList()
              ..sort((a, b) => a.displayName.compareTo(b.displayName));
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  controller: search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: _labsText(
                      context,
                      'Choose biomarker',
                      'Biomarker auswählen',
                    ),
                    prefixIcon: const Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final biomarker = filtered[index];
                    return ListTile(
                      leading: const Icon(Icons.science_outlined),
                      title: Text(biomarker.displayName),
                      subtitle: biomarker.category.isEmpty
                          ? null
                          : Text(biomarker.category),
                      onTap: () => Navigator.pop(sheetContext, biomarker),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  search.dispose();
  return result;
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
                  _labsText(
                    context,
                    'Unsaved draft · ${generation.plan.title}',
                    'Ungespeicherter Entwurf · ${generation.plan.title}',
                  ),
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
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              generation.verification.approved
                  ? Icons.verified_outlined
                  : Icons.gpp_bad_outlined,
            ),
            title: Text(
              generation.verification.approved
                  ? _labsText(
                      context,
                      'Independent verification passed',
                      'Unabhängige Prüfung bestanden',
                    )
                  : _labsText(
                      context,
                      'Independent verification rejected this draft',
                      'Unabhängige Prüfung hat diesen Entwurf abgelehnt',
                    ),
            ),
            subtitle: Text(generation.verification.summary),
          ),
          for (final issue in generation.verification.blockingIssues)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.block_outlined),
              title: Text(issue),
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
                  Builder(
                    builder: (context) {
                      final uri = _safeWebUri(generation.citations[index]);
                      return ActionChip(
                        avatar: const Icon(Icons.open_in_new, size: 16),
                        label: Text(
                          _labsText(
                            context,
                            'Source ${index + 1}',
                            'Quelle ${index + 1}',
                          ),
                        ),
                        onPressed: uri == null ? null : () => launchUrl(uri),
                      );
                    },
                  ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: generation.canSave ? onExport : null,
                icon: const Icon(Icons.ios_share_outlined),
                label: Text(_labsText(context, 'Export', 'Exportieren')),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: generation.canSave ? onSave : null,
                icon: const Icon(Icons.save_outlined),
                label: Text(_labsText(context, 'Save plan', 'Plan speichern')),
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
  final Future<void> Function(List<LabPlanItem>, bool) onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: Text(plan.title),
      subtitle: Text(
        '${DateFormat.yMMMd().format(plan.plannedFor ?? plan.createdAt)} · '
        '${_labsText(context, '${plan.items.length} tests', '${plan.items.length} Tests')} · '
        '${plan.provider ?? _labsText(context, 'manual', 'manuell')}',
      ),
      trailing: PopupMenuButton<String>(
        tooltip: _labsText(context, 'Plan actions', 'Planaktionen'),
        onSelected: (value) => value == 'export' ? onExport() : onDelete(),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'export',
            child: Text(_labsText(context, 'Export', 'Exportieren')),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text(_labsText(context, 'Delete', 'Löschen')),
          ),
        ],
      ),
      children: [
        if (plan.status == 'verified')
          ListTile(
            dense: true,
            leading: const Icon(Icons.verified_outlined),
            title: Text(
              _labsText(
                context,
                'Independent verification passed',
                'Unabhängige Prüfung bestanden',
              ),
            ),
            subtitle: Text(plan.verificationSummary),
          ),
        for (final warning in plan.verificationWarnings)
          ListTile(
            dense: true,
            leading: const Icon(Icons.warning_amber_outlined),
            title: Text(warning),
          ),
        if (plan.verificationCitations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              children: [
                for (
                  var index = 0;
                  index < plan.verificationCitations.length;
                  index++
                )
                  Builder(
                    builder: (context) {
                      final uri = _safeWebUri(
                        plan.verificationCitations[index],
                      );
                      return ActionChip(
                        avatar: const Icon(Icons.open_in_new, size: 16),
                        label: Text(
                          _labsText(
                            context,
                            'Source ${index + 1}',
                            'Quelle ${index + 1}',
                          ),
                        ),
                        onPressed: uri == null ? null : () => launchUrl(uri),
                      );
                    },
                  ),
              ],
            ),
          ),
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
  final Future<void> Function(List<LabPlanItem>, bool)? onToggle;

  @override
  Widget build(BuildContext context) {
    // Packages are read here rather than passed down, because the costing they
    // produce is what every tier line reports.
    final controller = context.watch<AppController>();
    return Column(
      children: [
        for (final tier in LabTier.values)
          Builder(
            builder: (context) {
              final costing = controller.costFor(plan, tier);
              final next = LabPlan.nextTierAfter(tier);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExpansionTile(
                    initiallyExpanded: tier == LabTier.core,
                    tilePadding: EdgeInsets.zero,
                    title: Text(_label(context, tier)),
                    subtitle: Text(
                      _labsText(
                        context,
                        '${plan.itemsThrough(tier).length} tests · '
                            '${costing.totalEur.toStringAsFixed(2)} € known'
                            '${costing.unpricedCount == 0 ? '' : ' + ${costing.unpricedCount} unpriced'}'
                            '${costing.appliedPackages.isEmpty ? '' : ' · ${costing.appliedPackages.length} package(s)'}',
                        '${plan.itemsThrough(tier).length} Tests · '
                            '${costing.totalEur.toStringAsFixed(2)} € bekannt'
                            '${costing.unpricedCount == 0 ? '' : ' + ${costing.unpricedCount} ohne Preis'}'
                            '${costing.appliedPackages.isEmpty ? '' : ' · ${costing.appliedPackages.length} Paket(e)'}',
                      ),
                    ),
                    children: [
                      // The ticks are what a doctor's request is built from, so
                      // setting them for a whole tier has to be one action
                      // rather than a scroll and a dozen taps.
                      if (onToggle case final toggle?)
                        _TierSelection(
                          items: plan.itemsThrough(tier),
                          onToggle: toggle,
                        ),
                      // Named before the tests, because a bundle changes what the tier
                      // costs and the reader has to see why the total is not the sum.
                      for (final applied in costing.appliedPackages)
                        _AppliedPackageTile(
                          applied: applied,
                          items: [
                            for (final item in plan.itemsThrough(tier))
                              if (applied.coveredBiomarkerIds.contains(
                                item.biomarkerId,
                              ))
                                item,
                          ],
                          onToggle: onToggle,
                        ),
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
                              !hasLabPrice(item.priceEur)
                                  ? _labsText(
                                      context,
                                      'Price unknown',
                                      'Preis unbekannt',
                                    )
                                  : '${item.priceEur!.toStringAsFixed(2)} €',
                            ].join(' · '),
                          ),
                          value: item.checked,
                          onChanged: onToggle == null
                              ? null
                              : (checked) =>
                                    onToggle!([item], checked ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                    ],
                  ),
                  // Outside the ExpansionTile on purpose. What a cheaper plan
                  // gives up is the reason to pick it or not, so it must be
                  // readable without expanding anything.
                  if (next != null)
                    _TierTradeoff(
                      plan: plan,
                      tier: tier,
                      next: next,
                      nextLabel: _shortLabel(context, next),
                      addedCostEur:
                          controller.costFor(plan, next).totalEur -
                          costing.totalEur,
                    ),
                ],
              );
            },
          ),
        // Said here, once, so the planner does not have to say it in every
        // rationale and every warning. Rendered for the draft card and the
        // saved plan alike, because both are read as advice.
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 4),
          child: StandingSafetyNotice(),
        ),
      ],
    );
  }

  /// The tier's own name, without the "includes …" note that only makes sense
  /// on its own header.
  String _shortLabel(BuildContext context, LabTier tier) => switch (tier) {
    LabTier.core => _labsText(context, 'Core', 'Basis'),
    LabTier.advanced => _labsText(context, 'Advanced', 'Erweitert'),
    LabTier.comprehensive => _labsText(context, 'Comprehensive', 'Umfassend'),
  };

  String _label(BuildContext context, LabTier tier) => switch (tier) {
    LabTier.core => _labsText(context, 'Core', 'Basis'),
    LabTier.advanced => _labsText(
      context,
      'Advanced (includes Core)',
      'Erweitert (enthält Basis)',
    ),
    LabTier.comprehensive => _labsText(
      context,
      'Comprehensive (includes all)',
      'Umfassend (enthält alle)',
    ),
  };
}

/// Ticks or clears every test in a tier, and says how many are ticked.
///
/// The count is the part that earns its place: the ticks decide what a
/// doctor's request contains, and a tier collapsed to its header would
/// otherwise give no sign that half of it was left out.
class _TierSelection extends StatelessWidget {
  const _TierSelection({required this.items, required this.onToggle});

  final List<LabPlanItem> items;
  final Future<void> Function(List<LabPlanItem>, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final selected = items.where((item) => item.checked).length;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _labsText(
                context,
                '$selected of ${items.length} selected',
                '$selected von ${items.length} ausgewählt',
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: selected == items.length
                ? null
                : () => onToggle(items, true),
            child: Text(_labsText(context, 'Select all', 'Alle auswählen')),
          ),
          TextButton(
            onPressed: selected == 0 ? null : () => onToggle(items, false),
            child: Text(_labsText(context, 'Clear', 'Zurücksetzen')),
          ),
        ],
      ),
    );
  }
}

/// A bundle the costing applied, presented as one of the tier's line items.
///
/// A package is a purchase decision exactly like a single test is, so it reads
/// like one: the same leading checkbox, the same explanatory subtitle. Ticking
/// it ticks every planned test it covers, and its box is half-filled while only
/// some of them are — otherwise the package and the tests it pays for could
/// disagree on screen with no way to tell which was true.
///
/// It also lists its contents. "89 € for 5 tests" is not something a reader can
/// check, act on, or compare against another lab's bundle; the names are.
class _AppliedPackageTile extends StatelessWidget {
  const _AppliedPackageTile({
    required this.applied,
    required this.items,
    this.onToggle,
  });

  final AppliedPackage applied;

  /// The tier's planned tests this package covers, in the order they are shown.
  final List<LabPlanItem> items;

  final Future<void> Function(List<LabPlanItem>, bool)? onToggle;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final theme = Theme.of(context);
    final checkedCount = items.where((item) => item.checked).length;
    // Null is Flutter's indeterminate box, which is the honest state when a
    // package's tests are partly ticked.
    final value = items.isEmpty
        ? false
        : checkedCount == items.length
        ? true
        : checkedCount == 0
        ? false
        : null;
    final memberIds =
        controller.biomarkerPackageMembers[applied.package.id] ??
        const <String>{};
    final plannedIds = applied.coveredBiomarkerIds.toSet();
    final names = _memberNames(controller, memberIds);
    final saving = applied.savingEur;
    final price = applied.package.priceEur!.toStringAsFixed(2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          dense: true,
          tristate: true,
          contentPadding: const EdgeInsets.only(left: 8),
          secondary: const Icon(Icons.inventory_2_outlined, size: 20),
          title: Text(applied.package.name),
          subtitle: Text(
            [
              _labsText(context, 'Package', 'Paket'),
              '$price €',
              _labsText(
                context,
                'covers ${applied.coveredBiomarkerIds.length} planned test(s)',
                'deckt ${applied.coveredBiomarkerIds.length} geplante(n) Test(s) ab',
              ),
              if (saving != null)
                _labsText(
                  context,
                  'saves ${saving.toStringAsFixed(2)} € against buying them singly',
                  'spart ${saving.toStringAsFixed(2)} € gegenüber Einzelkauf',
                )
              else
                _labsText(
                  context,
                  'prices a test that has none on its own',
                  'setzt einen Preis für einen Test ohne Einzelpreis',
                ),
            ].join(' · '),
          ),
          value: value,
          onChanged: onToggle == null || items.isEmpty
              ? null
              : (next) => onToggle!(items, next ?? false),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: ExpansionTile(
            dense: true,
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
            title: Text(
              _labsText(
                context,
                'Contains ${names.length} test(s)',
                'Enthält ${names.length} Test(s)',
              ),
              style: theme.textTheme.bodySmall,
            ),
            children: [
              for (final entry in names)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        plannedIds.contains(entry.id)
                            ? Icons.check_circle_outline
                            : Icons.remove_circle_outline,
                        size: 16,
                        color: plannedIds.contains(entry.id)
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.name,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      // A bundle usually carries tests this plan did not ask
                      // for. Saying so stops them reading as plan omissions.
                      if (!plannedIds.contains(entry.id))
                        Text(
                          _labsText(context, 'not planned', 'nicht geplant'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              if (names.isEmpty)
                Text(
                  _labsText(
                    context,
                    'This package has no tests recorded yet.',
                    'Für dieses Paket sind noch keine Tests hinterlegt.',
                  ),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Package members with a readable name, planned ones first then alphabetical.
  ///
  /// The catalog is the naming authority; a planned item's own label is the
  /// fallback, and the raw ID the last resort — a member the catalog has since
  /// lost is still part of what the package costs, so it is never dropped.
  List<({String id, String name})> _memberNames(
    AppController controller,
    Set<String> memberIds,
  ) {
    final catalog = {
      for (final biomarker in controller.biomarkers)
        biomarker.id: biomarker.displayName,
    };
    final planned = {for (final item in items) item.biomarkerId: item};
    final result = [
      for (final id in memberIds)
        (id: id, name: catalog[id] ?? planned[id]?.biomarkerName ?? id),
    ];
    final plannedIds = applied.coveredBiomarkerIds.toSet();
    result.sort((a, b) {
      final aPlanned = plannedIds.contains(a.id);
      if (aPlanned != plannedIds.contains(b.id)) return aPlanned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }
}

/// What a cheaper tier gives up against the next one, and why.
///
/// Three separate claims, and only one of them comes from the model: the count
/// and the names are derived from the plan, the added cost from the same
/// package-aware costing the tier headers use, and the reasoning is the
/// planner's own. When the planner did not record any, the panel says so
/// rather than leaving the reader to guess whether the omissions were
/// deliberate.
class _TierTradeoff extends StatelessWidget {
  const _TierTradeoff({
    required this.plan,
    required this.tier,
    required this.next,
    required this.nextLabel,
    required this.addedCostEur,
  });

  final LabPlan plan;
  final LabTier tier;
  final LabTier next;
  final String nextLabel;
  final double addedCostEur;

  @override
  Widget build(BuildContext context) {
    final omitted = plan.itemsOmittedVersusNext(tier);
    if (omitted.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reasoning = plan.tradeoffFor(tier);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.compare_arrows_outlined,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _labsText(
                    context,
                    'Not included versus $nextLabel: ${omitted.length} test(s)'
                        '${addedCostEur <= 0 ? '' : ' · +${addedCostEur.toStringAsFixed(2)} €'}',
                    'Nicht enthalten gegenüber $nextLabel: ${omitted.length} Test(s)'
                        '${addedCostEur <= 0 ? '' : ' · +${addedCostEur.toStringAsFixed(2)} €'}',
                  ),
                  style: theme.textTheme.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reasoning.isNotEmpty
                ? reasoning
                : _labsText(
                    context,
                    'This plan recorded no reasoning for leaving these out. '
                        'Regenerate it to get one.',
                    'Dieser Plan hat keine Begründung für die Auslassung '
                        'gespeichert. Erzeuge ihn neu, um eine zu erhalten.',
                  ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            omitted.map((item) => item.biomarkerName).join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BiomarkerCatalog extends StatefulWidget {
  const _BiomarkerCatalog({
    required this.controller,
    required this.latestByBiomarker,
    required this.profile,
    required this.now,
    this.statusRequest,
  });

  final AppController controller;
  final Map<String, Measurement> latestByBiomarker;
  final Profile profile;
  final DateTime now;

  /// A status filter asked for by a Today tile, with the request's token so a
  /// repeated tap on the same tile is applied again after a manual change.
  final ({int token, String status})? statusRequest;

  @override
  State<_BiomarkerCatalog> createState() => _BiomarkerCatalogState();
}

class _BiomarkerCatalogState extends State<_BiomarkerCatalog> {
  final _search = TextEditingController();
  String _category = 'All';
  String _status = 'All';
  int? _handledRequestToken;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applyStatusRequest() {
    final request = widget.statusRequest;
    if (request == null || request.token == _handledRequestToken) return;
    _handledRequestToken = request.token;
    if (request.status == _status) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _status = request.status);
    });
  }

  @override
  Widget build(BuildContext context) {
    _applyStatusRequest();
    final statusService = BiomarkerStatusService();
    final statusByBiomarker = {
      for (final biomarker in widget.controller.biomarkers)
        biomarker.id: statusService.evaluate(
          biomarker: biomarker,
          measurement: widget.latestByBiomarker[biomarker.id],
          profile: widget.profile,
          targets: widget.controller.profileTargets,
          referenceRanges: widget.controller.biomarkerRanges,
          now: widget.now,
        ),
    };
    final categories = {
      'All',
      ...widget.controller.biomarkers
          .map((item) => item.category.trim())
          .where((item) => item.isNotEmpty),
    }.toList()..sort();
    final query = _search.text.trim().toLowerCase();
    final filtered = widget.controller.biomarkers.where((biomarker) {
      final matchesQuery =
          query.isEmpty ||
          biomarker.displayName.toLowerCase().contains(query) ||
          biomarker.synonyms.any((item) => item.toLowerCase().contains(query));
      final matchesCategory =
          _category == 'All' || biomarker.category == _category;
      final matchesStatus = switch (_status) {
        'Due' => widget.controller.dueBiomarkers.any(
          (item) => item.biomarker.id == biomarker.id,
        ),
        'Below' => statusByBiomarker[biomarker.id]!.isBelow,
        'Above' => statusByBiomarker[biomarker.id]!.isAbove,
        'In target/optimal' =>
          statusByBiomarker[biomarker.id]!.isTargetOrOptimal,
        'Within reference/lab' =>
          statusByBiomarker[biomarker.id]!.isReferenceOrLab,
        'No comparison range' =>
          statusByBiomarker[biomarker.id]!.kind ==
              BiomarkerStatusKind.noComparisonRange,
        'Unavailable' =>
          statusByBiomarker[biomarker.id]!.kind ==
              BiomarkerStatusKind.unavailable,
        'Never measured' =>
          statusByBiomarker[biomarker.id]!.kind ==
              BiomarkerStatusKind.neverMeasured,
        'Missing price' => !biomarker.hasPrice,
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
            hintText: _labsText(
              context,
              'Search names and lab synonyms',
              'Namen und Laborsynonyme durchsuchen',
            ),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: _labsText(context, 'Clear', 'Leeren'),
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
                    DropdownMenuItem(
                      value: category,
                      child: Text(
                        category == 'All'
                            ? _labsText(context, 'All', 'Alle')
                            : category,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value!),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _status,
                items: [
                  DropdownMenuItem(
                    value: 'All',
                    child: Text(
                      _labsText(context, 'All statuses', 'Alle Status'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Due',
                    child: Text(_labsText(context, 'Due', 'Fällig')),
                  ),
                  DropdownMenuItem(
                    value: 'Below',
                    child: Text(_labsText(context, 'Below', 'Unterhalb')),
                  ),
                  DropdownMenuItem(
                    value: 'Above',
                    child: Text(_labsText(context, 'Above', 'Oberhalb')),
                  ),
                  DropdownMenuItem(
                    value: 'In target/optimal',
                    child: Text(
                      _labsText(
                        context,
                        'In target/optimal',
                        'Im Ziel-/Optimalbereich',
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Within reference/lab',
                    child: Text(
                      _labsText(
                        context,
                        'Within reference/lab',
                        'Im Referenz-/Laborbereich',
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'No comparison range',
                    child: Text(
                      _labsText(
                        context,
                        'No comparison range',
                        'Kein Vergleichsbereich',
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Unavailable',
                    child: Text(
                      _labsText(context, 'Unavailable', 'Nicht verfügbar'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Never measured',
                    child: Text(
                      _labsText(context, 'Never measured', 'Noch nie gemessen'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Missing price',
                    child: Text(
                      _labsText(context, 'Missing price', 'Preis fehlt'),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'Conversion issue',
                    child: Text(
                      _labsText(
                        context,
                        'Conversion issue',
                        'Umrechnungsproblem',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _status = value!),
              ),
              const SizedBox(width: 12),
              Text(
                _labsText(
                  context,
                  '${filtered.length} shown',
                  '${filtered.length} angezeigt',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          EmptyState(
            icon: Icons.filter_alt_off_outlined,
            title: _labsText(
              context,
              'No matching biomarkers',
              'Keine passenden Biomarker',
            ),
            message: _labsText(
              context,
              'Clear or change the catalog filters.',
              'Leere oder ändere die Katalogfilter.',
            ),
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
                    status: statusByBiomarker[biomarker.id]!,
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
    required this.status,
    required this.controller,
  });

  final Biomarker biomarker;
  final Measurement? latest;
  final BiomarkerStatus status;
  final AppController controller;

  @override
  Widget build(BuildContext context) => Semantics(
    label: _labsText(
      context,
      '${biomarker.displayName}. Status: ${status.label}. ${status.detail}',
      '${biomarker.displayName}. Status: ${_localizedStatusLabel(context, status)}. ${_localizedStatusDetail(context, status)}',
    ),
    child: ListTile(
      leading: CircleAvatar(child: Icon(_statusIcon(status))),
      title: Text(biomarker.displayName),
      subtitle: Text(
        [
          if (biomarker.category.isNotEmpty) biomarker.category,
          if (latest != null)
            '${latest!.value} ${latest!.unit} · ${DateFormat.yMMMd().format(latest!.takenAt)}'
          else
            _labsText(context, 'No result yet', 'Noch kein Ergebnis'),
          _localizedStatusLabel(context, status),
          if (latest?.conversionStatus == 'unsupported')
            _labsText(
              context,
              'No safe conversion to standard unit',
              'Keine sichere Umrechnung in die Standardeinheit',
            ),
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            !biomarker.hasPrice
                ? _labsText(context, 'No price', 'Kein Preis')
                : '${biomarker.priceEur!.toStringAsFixed(2)} €',
          ),
          const Icon(Icons.chevron_right, size: 18),
        ],
      ),
      onTap: () => showBiomarkerDetail(context, biomarker),
      onLongPress: () =>
          showAddBiomarkerDialog(context, controller, existing: biomarker),
    ),
  );

  IconData _statusIcon(BiomarkerStatus value) => switch (value.kind) {
    BiomarkerStatusKind.below => Icons.arrow_downward_outlined,
    BiomarkerStatusKind.above => Icons.arrow_upward_outlined,
    BiomarkerStatusKind.inPersonalTarget ||
    BiomarkerStatusKind.inStoredOptimal => Icons.track_changes_outlined,
    BiomarkerStatusKind.withinStoredReference ||
    BiomarkerStatusKind.withinLabRange => Icons.check_circle_outline,
    BiomarkerStatusKind.neverMeasured => Icons.remove_circle_outline,
    BiomarkerStatusKind.noComparisonRange => Icons.rule_folder_outlined,
    BiomarkerStatusKind.unavailable => Icons.help_outline,
  };
}

/// Says what a running lab plan is doing, and for how long.
///
/// Two model passes over a whole health context take minutes. A greyed-out
/// button reports only that something is happening, which is what a hang looks
/// like too — so the stage is named and the clock keeps moving.
class _LabPlanProgressCard extends StatefulWidget {
  const _LabPlanProgressCard({
    required this.stage,
    required this.startedAt,
    required this.survivesBackground,
    required this.activity,
    required this.activityAt,
  });

  final LabPlanStage stage;
  final DateTime? startedAt;

  /// Whether a foreground service is holding the run. Decides which promise the
  /// card is allowed to make about leaving the app.
  final bool survivesBackground;

  /// What the model is producing right now, or null before the first byte.
  final ProviderActivity? activity;

  /// When [activity] last moved, for the quiet check.
  final DateTime? activityAt;

  @override
  State<_LabPlanProgressCard> createState() => _LabPlanProgressCardState();
}

class _LabPlanProgressCardState extends State<_LabPlanProgressCard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Nothing else rebuilds between stages, and a stalled number is exactly
    // the impression this card exists to avoid.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final started = widget.startedAt;
    final elapsed = started == null ? null : now.difference(started);
    final activity = widget.activity;
    final quiet = labPlanHasGoneQuiet(
      lastActivityAt: widget.activityAt,
      now: now,
    );
    final quietFor = widget.activityAt == null
        ? 0
        : now.difference(widget.activityAt!).inSeconds;
    final stages = LabPlanStage.values;
    // The repair pass only happens when a draft fails validation, so counting
    // it into the total would understate progress on every healthy run.
    final ordinal = widget.stage == LabPlanStage.repairingDraft
        ? stages.indexOf(LabPlanStage.drafting) + 1
        : stages.indexOf(widget.stage) + 1;
    final total = stages.length - 1;

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _labsText(
                      context,
                      widget.stage.englishLabel,
                      widget.stage.germanLabel,
                    ),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (elapsed != null)
                  Text(
                    '${elapsed.inMinutes}:'
                    '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (ordinal / total).clamp(0.0, 1.0),
                minHeight: 5,
              ),
            ),
            if (activity != null) ...[
              const SizedBox(height: 10),
              Text(
                activity.isThinking
                    ? _labsText(
                        context,
                        'Reasoning — ${activity.thinkingChars} characters so '
                            'far',
                        'Denkt nach — bisher ${activity.thinkingChars} Zeichen',
                      )
                    : _labsText(
                        context,
                        'Writing the plan — ${activity.outputChars} characters '
                            'so far',
                        'Schreibt den Plan — bisher ${activity.outputChars} '
                            'Zeichen',
                      ),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSecondaryContainer,
                ),
              ),
              if (activity.thinkingTail.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                // The live tail of the model's reasoning. Bounded and dimmed:
                // it is evidence that work is happening, not something the user
                // is being asked to read.
                Text(
                  activity.thinkingTail.trim(),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
            if (quiet) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 16, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _labsText(
                        context,
                        'Nothing has arrived for ${quietFor}s. The connection '
                            'may have dropped — cancel and retry if it stays '
                            'silent.',
                        'Seit ${quietFor}s kam nichts an. Die Verbindung ist '
                            'womöglich abgebrochen — brich ab und versuch es '
                            'erneut, wenn es still bleibt.',
                      ),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              widget.survivesBackground
                  ? _labsText(
                      context,
                      'This takes a few minutes and runs on your device. You '
                          'can switch away — it keeps going in the background '
                          'and shows a notification until it finishes.',
                      'Das dauert einige Minuten und läuft auf deinem Gerät. '
                          'Du kannst die App verlassen — sie arbeitet im '
                          'Hintergrund weiter und zeigt bis zum Ende eine '
                          'Benachrichtigung.',
                    )
                  : _labsText(
                      context,
                      'This takes a few minutes and runs on your device. Keep '
                          'the app open — the screen is held awake until it '
                          'finishes.',
                      'Das dauert einige Minuten und läuft auf deinem Gerät. '
                          'Lass die App offen — der Bildschirm bleibt bis zum '
                          'Ende aktiv.',
                    ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
