import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_models.dart';
import '../ai/ai_settings.dart';
import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../app/appearance_settings.dart';
import '../domain/entities.dart';
import '../import/legacy_import_service.dart';
import '../data/unit_migration_planner.dart';
import '../reminders/reminder_planner.dart';
import '../reminders/reminder_service.dart';
import '../sync/one_drive_service.dart';
import '../sync/restore_sync_gate.dart';
import 'common.dart';
import 'dialogs.dart';
import 'initial_setup_widgets.dart';
import 'sync_conflicts_screen.dart';
import 'unit_migration_screen.dart';

String _settingsText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _oneDriveSignedIn;
  OneDriveStorageMode? _oneDriveMode;
  OneDriveFolder? _oneDriveFolder;
  final _advisorSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _refreshOneDriveStatus();
  }

  Future<void> _refreshOneDriveStatus() async {
    final controller = context.read<AppController>();
    final service = controller.oneDriveService;
    final signedIn = await service.isSignedIn();
    final mode = signedIn ? await service.currentStorageMode() : null;
    final folder = mode == OneDriveStorageMode.sharedFolder
        ? await service.selectedFolder()
        : null;
    if (!mounted) return;
    setState(() {
      _oneDriveSignedIn = signedIn;
      _oneDriveMode = mode;
      _oneDriveFolder = folder;
    });
    await controller.refreshInitialSetupProgress();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final strings = AppLocalizations.of(context);
    final oneDriveReady =
        _oneDriveSignedIn == true &&
        (_oneDriveMode == OneDriveStorageMode.appFolder ||
            _oneDriveFolder != null);
    return PageBody(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 110),
        children: [
          if (!controller.initialSetupProgress.isComplete) ...[
            InitialSetupChecklistCard(
              progress: controller.initialSetupProgress,
              onCreateProfile: () => showAddProfileDialog(context, controller),
              onImportJson: () async {
                if (controller.activeProfile != null) {
                  await _importData(controller);
                }
              },
              onSkipJson: () => _runSetupAction(
                () => controller.markLegacyJsonImportSkipped(),
              ),
              onAttachPdfs: () async {
                if (controller.activeProfile != null) {
                  await _importPdfs(controller);
                }
              },
              onSkipPdfs: () => _runSetupAction(
                () => controller.markLegacyPdfsImportSkipped(),
              ),
              onSetUpCloud: () =>
                  _runSetupAction(() => _setUpCloud(controller)),
              onSkipCloud: () =>
                  _runSetupAction(() => controller.markCloudSetupSkipped()),
              onSetUpAdvisor: _scrollToAdvisor,
              onSkipAdvisor: () =>
                  _runSetupAction(() => controller.markAiSetupSkipped()),
            ),
            const SizedBox(height: 8),
          ],
          if (controller.restoreSyncDecisionPending) ...[
            _RestoreSyncDecisionCard(
              onResumeAndMerge: () => _resumeAndMerge(controller),
              onPublishRestoredData: () => _publishRestoredData(controller),
            ),
            const SizedBox(height: 8),
          ],
          SectionHeader(
            title: _settingsText(context, 'Profiles', 'Profile'),
            subtitle: _settingsText(
              context,
              'Every profile is isolated in storage, sync, exports, and AI context',
              'Jedes Profil ist in Speicher, Synchronisierung, Exporten und KI-Kontext getrennt',
            ),
            action: IconButton.filledTonal(
              tooltip: _settingsText(
                context,
                'Add profile',
                'Profil hinzufügen',
              ),
              onPressed: controller.busy
                  ? null
                  : () => showAddProfileDialog(context, controller),
              icon: const Icon(Icons.person_add_outlined),
            ),
          ),
          Card(
            child: Column(
              children: [
                for (final profile in controller.profiles)
                  _ProfileRow(
                    profile: profile,
                    active: profile.id == controller.activeProfile?.id,
                    actionsEnabled: !controller.busy,
                    onSelect: () => _selectProfile(controller, profile),
                    onEdit: () =>
                        showEditProfileDialog(context, controller, profile),
                    onDelete: () => _deleteProfile(controller, profile),
                  ),
              ],
            ),
          ),
          if (controller.profiles.length == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Text(
                _settingsText(
                  context,
                  'Create another profile before deleting this one.',
                  'Erstelle ein weiteres Profil, bevor du dieses löschst.',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          SectionHeader(
            title: strings.appearanceAccessibility,
            subtitle: strings.deviceWideAppearance,
          ),
          _AppearanceCard(
            controller: controller,
            onThemeModeChanged: (value) =>
                _saveAppearance(() => controller.setThemeMode(value)),
            onColorModeChanged: (value) =>
                _saveAppearance(() => controller.setColorMode(value)),
            onHighContrastChanged: (value) =>
                _saveAppearance(() => controller.setHighContrast(value)),
            onLanguageChanged: (value) =>
                _saveAppearance(() => controller.setLanguage(value)),
          ),
          SectionHeader(
            key: _advisorSectionKey,
            title: _settingsText(context, 'AI providers', 'KI-Anbieter'),
            subtitle: _settingsText(
              context,
              'Bring your own key; keys stay in encrypted device storage',
              'Eigener API-Schlüssel; Schlüssel bleiben verschlüsselt auf dem Gerät',
            ),
          ),
          for (final provider in AiProvider.values)
            _ApiKeyCard(provider: provider),
          SectionHeader(
            title: _settingsText(context, 'AI roles', 'KI-Rollen'),
            subtitle: _settingsText(
              context,
              'Choose separate models for the main advisor and document parsing',
              'Wähle getrennte Modelle für Beratung und Dokumentanalyse',
            ),
          ),
          _ModelConfigurationCard(
            key: ValueKey('advisor-${controller.advisorSettings?.model}'),
            task: AiTask.advisor,
            title: _settingsText(context, 'Main advisor', 'Hauptberatung'),
            settings: controller.advisorSettings,
            allowTools: true,
          ),
          _ModelConfigurationCard(
            key: ValueKey('parsing-${controller.parsingSettings?.model}'),
            task: AiTask.parsing,
            title: _settingsText(
              context,
              'Lab document parser',
              'Analyse von Labordokumenten',
            ),
            settings: controller.parsingSettings,
            allowTools: false,
          ),
          SectionHeader(
            title: _settingsText(
              context,
              'OneDrive storage',
              'OneDrive-Speicher',
            ),
            subtitle: _settingsText(
              context,
              'Choose a private AppFolder or an explicitly selected shared folder',
              'Wähle einen privaten App-Ordner oder ausdrücklich einen freigegebenen Ordner',
            ),
            action: _oneDriveSignedIn == true
                ? Chip(
                    avatar: Icon(
                      oneDriveReady ? Icons.check : Icons.warning_amber,
                      size: 16,
                    ),
                    label: Text(
                      oneDriveReady
                          ? _settingsText(context, 'Ready', 'Bereit')
                          : _settingsText(
                              context,
                              'Needs folder',
                              'Ordner erforderlich',
                            ),
                    ),
                  )
                : null,
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_outlined),
                  title: Text(
                    _oneDriveSignedIn == null
                        ? _settingsText(
                            context,
                            'Checking connection…',
                            'Verbindung wird geprüft…',
                          )
                        : _oneDriveSignedIn != true
                        ? _settingsText(
                            context,
                            'Connect OneDrive',
                            'OneDrive verbinden',
                          )
                        : oneDriveReady
                        ? _settingsText(
                            context,
                            'OneDrive is ready',
                            'OneDrive ist bereit',
                          )
                        : _settingsText(
                            context,
                            'Choose a shared folder',
                            'Freigegebenen Ordner wählen',
                          ),
                  ),
                  subtitle: Text(_oneDriveDescription(context)),
                  trailing: _oneDriveSignedIn == null
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : _oneDriveSignedIn != true
                      ? TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => _connectOneDrive(controller),
                          child: Text(
                            _settingsText(context, 'Connect', 'Verbinden'),
                          ),
                        )
                      : oneDriveReady
                      ? TextButton(
                          onPressed:
                              controller.busy ||
                                  controller.restoreSyncDecisionPending
                              ? null
                              : () => _sync(controller),
                          child: Text(
                            _settingsText(
                              context,
                              'Sync now',
                              'Jetzt synchronisieren',
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: controller.busy
                              ? null
                              : () => _chooseSharedFolder(controller),
                          child: Text(
                            _settingsText(context, 'Choose', 'Auswählen'),
                          ),
                        ),
                ),
                if (_oneDriveMode == OneDriveStorageMode.sharedFolder &&
                    _oneDriveFolder != null) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.folder_shared_outlined),
                    title: Text(_oneDriveFolder!.name),
                    subtitle: Text(
                      _settingsText(
                        context,
                        'SuperHealth uses only the SuperHealth subfolder here.',
                        'SuperHealth verwendet hier ausschließlich den Unterordner SuperHealth.',
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => _chooseSharedFolder(controller),
                      child: Text(_settingsText(context, 'Change', 'Ändern')),
                    ),
                  ),
                ],
                if (_oneDriveSignedIn == true) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.link_off),
                    title: Text(
                      _settingsText(
                        context,
                        'Disconnect this device',
                        'Dieses Gerät trennen',
                      ),
                    ),
                    onTap: controller.busy
                        ? null
                        : () async {
                            await controller.oneDriveService.signOut();
                            await _refreshOneDriveStatus();
                          },
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.warning_amber_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Review sync conflicts',
                      'Synchronisierungskonflikte prüfen',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Choose whether to keep local records or accept incoming OneDrive records.',
                      'Entscheide, ob lokale oder eingehende OneDrive-Datensätze behalten werden.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SyncConflictsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: _settingsText(
              context,
              'Reminders & alerts',
              'Erinnerungen und Warnungen',
            ),
            subtitle: _settingsText(
              context,
              'Device notifications for scheduled doses and low stock',
              'Gerätebenachrichtigungen für geplante Einnahmen und niedrigen Bestand',
            ),
          ),
          _ReminderStatusCard(controller: controller),
          SectionHeader(
            title: _settingsText(
              context,
              'Portable backup',
              'Portables Backup',
            ),
            subtitle: _settingsText(
              context,
              'A self-contained copy for safekeeping or moving devices',
              'Eine eigenständige Kopie zur Aufbewahrung oder für den Gerätewechsel',
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.ios_share_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Export portable backup',
                      'Portables Backup exportieren',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Includes health data and locally available PDFs. API keys, '
                          'OneDrive credentials, remote IDs, and sync state are excluded.',
                      'Enthält Gesundheitsdaten und lokal verfügbare PDFs. API-Schlüssel, '
                          'OneDrive-Anmeldedaten, Remote-IDs und Synchronisierungsstatus sind ausgeschlossen.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.busy
                      ? null
                      : () => _exportPortableBackup(controller),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Restore portable backup',
                      'Portables Backup wiederherstellen',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Replaces all health records on this device after verification. '
                          'Device API keys remain unchanged.',
                      'Ersetzt nach Prüfung alle Gesundheitsdaten auf diesem Gerät. '
                          'API-Schlüssel auf dem Gerät bleiben unverändert.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.busy
                      ? null
                      : () => _restorePortableBackup(controller),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: _settingsText(
              context,
              'Legacy data import',
              'Altdaten importieren',
            ),
            subtitle: _settingsText(
              context,
              'Previewed, deduplicated, audited, and rollback-capable',
              'Mit Vorschau, Deduplizierung, Protokollierung und Rücksetzung',
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.straighten_outlined),
              title: Text(
                _settingsText(context, 'Tidy up units', 'Einheiten aufräumen'),
              ),
              subtitle: Text(
                _settingsText(
                  context,
                  'Find the same unit or ingredient stored under different '
                      'spellings, and choose what to correct.',
                  'Findet dieselbe Einheit oder Zutat in verschiedenen '
                      'Schreibweisen und lässt dich auswählen, was korrigiert '
                      'wird.',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: controller.busy ? null : () => _tidyUnits(controller),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.move_to_inbox_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Import legacy JSON data',
                      'JSON-Altdaten importieren',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Supplement Manager and Biomarkers exports, including '
                          'user_overrides.json.',
                      'Exporte aus Supplement Manager und Biomarkers einschließlich '
                          'user_overrides.json.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.busy || controller.activeProfile == null
                      ? null
                      : () => _importData(controller),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Attach Biomarkers PDF files',
                      'Biomarkers-PDFs anhängen',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'After importing documents.json, select the PDFs from the '
                          'former Biomarkers documents folder.',
                      'Wähle nach dem Import von documents.json die PDFs aus dem '
                          'früheren Biomarkers-Dokumentordner.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: controller.busy || controller.activeProfile == null
                      ? null
                      : () => _importPdfs(controller),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: _settingsText(
              context,
              'Safety & privacy',
              'Sicherheit und Datenschutz',
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Local-first SQLite record',
                      'Lokaler SQLite-Datensatz',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'The AI has no SQL, repository, or database tool.',
                      'Die KI besitzt kein SQL-, Repository- oder Datenbankwerkzeug.',
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Mode-specific OneDrive permission',
                      'Modusspezifische OneDrive-Berechtigung',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Private mode is AppFolder-only. Shared mode receives Files.ReadWrite, '
                          'while app operations stay inside the selected folder’s SuperHealth subfolder.',
                      'Der private Modus nutzt nur den App-Ordner. Der gemeinsame Modus erhält Files.ReadWrite, '
                          'während App-Vorgänge im SuperHealth-Unterordner des gewählten Ordners bleiben.',
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'File changes require approval',
                      'Dateiänderungen erfordern Zustimmung',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Provider sandboxes are isolated. Every local or OneDrive workspace write is previewed '
                          'with its exact operation and path before it can be applied.',
                      'Anbieter-Sandboxes sind isoliert. Jeder lokale oder OneDrive-Schreibvorgang wird '
                          'mit genauer Aktion und Pfad angezeigt, bevor er ausgeführt werden kann.',
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: Text(
                    _settingsText(
                      context,
                      'Planning support, not diagnosis',
                      'Planungshilfe, keine Diagnose',
                    ),
                  ),
                  subtitle: Text(
                    _settingsText(
                      context,
                      'Evidence labels and safety warnings are required, including for longevity-oriented checks.',
                      'Evidenzkennzeichnungen und Sicherheitshinweise sind auch für langlebigkeitsorientierte Tests erforderlich.',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 22),
            child: Text(
              _settingsText(
                context,
                'SuperHealth 0.5.0 · Personal-use Android build',
                'SuperHealth 0.5.0 · Android-Build für den persönlichen Gebrauch',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveAppearance(Future<void> Function() save) async {
    try {
      await save();
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _runSetupAction(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _setUpCloud(AppController controller) async {
    if (_oneDriveSignedIn != true) {
      await _connectOneDrive(controller);
      return;
    }
    if (_oneDriveMode == OneDriveStorageMode.sharedFolder &&
        _oneDriveFolder == null) {
      await _chooseSharedFolder(controller);
      return;
    }
    if (controller.restoreSyncDecisionPending) {
      throw RestoreSyncDecisionRequiredError();
    }
    await _sync(controller);
  }

  void _scrollToAdvisor() {
    final target = _advisorSectionKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }

  Future<void> _resumeAndMerge(AppController controller) async {
    final strings = AppLocalizations.of(context);
    final confirmed = await showConfirmAction(
      context,
      title: strings.resumeAndMerge,
      message: strings.resumeAndMergeDescription,
      confirmLabel: strings.resumeAndMerge,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.resumeRestoredDataAndMerge();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.resumeAndMerge)));
      await _refreshOneDriveStatus();
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _publishRestoredData(AppController controller) async {
    final confirmed = await _confirmPublishRestoredData();
    if (!confirmed || !mounted) return;
    final strings = AppLocalizations.of(context);
    try {
      await controller.publishRestoredDataToOneDrive();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.publishRestoredData)));
      await _refreshOneDriveStatus();
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<bool> _confirmPublishRestoredData() async {
    final strings = AppLocalizations.of(context);
    final confirmation = TextEditingController();
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text(strings.confirmPublishTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.confirmPublishDescription),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmation,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: strings.publishConfirmationLabel,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(strings.cancel),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: confirmation.text == 'PUBLISH'
                        ? () => Navigator.pop(dialogContext, true)
                        : null,
                    child: Text(strings.publishRestoredData),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      confirmation.dispose();
    }
  }

  Future<void> _selectProfile(AppController controller, Profile profile) async {
    try {
      await controller.selectProfile(profile.id);
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _deleteProfile(AppController controller, Profile profile) async {
    if (controller.profiles.length <= 1) {
      try {
        // Keep the controller as the source of truth for this safety rule.
        await controller.deleteProfile(profile);
      } on Object catch (error) {
        if (mounted) await showAppError(context, error);
      }
      return;
    }
    final confirmed = await showConfirmAction(
      context,
      title: _settingsText(
        context,
        'Delete ${profile.displayName}?',
        '${profile.displayName} löschen?',
      ),
      message: _settingsText(
        context,
        'This permanently removes this profile from the app. Its profile-scoped '
            'health records will be deleted or tombstoned for sync. The shared '
            'supplement catalog and stock remain available to other profiles.',
        'Dadurch wird dieses Profil dauerhaft aus der App entfernt. Profilspezifische '
            'Gesundheitsdaten werden gelöscht oder als Löschmarker synchronisiert. Der gemeinsame '
            'Nahrungsergänzungs-Katalog und Bestand bleiben für andere Profile verfügbar.',
      ),
      confirmLabel: _settingsText(context, 'Delete profile', 'Profil löschen'),
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await controller.deleteProfile(profile);
      if (!mounted) return;
      final activeName = controller.activeProfile?.displayName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activeName == null
                ? _settingsText(context, 'Profile deleted.', 'Profil gelöscht.')
                : _settingsText(
                    context,
                    'Profile deleted. Active profile: $activeName.',
                    'Profil gelöscht. Aktives Profil: $activeName.',
                  ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  String _oneDriveDescription(BuildContext context) {
    if (_oneDriveSignedIn != true) {
      return _settingsText(
        context,
        'Private AppFolder or shared family folder.',
        'Privater App-Ordner oder gemeinsamer Familienordner.',
      );
    }
    if (_oneDriveMode == OneDriveStorageMode.appFolder) {
      return _settingsText(
        context,
        'Private: OneDrive/Apps/SuperHealth',
        'Privat: OneDrive/Apps/SuperHealth',
      );
    }
    final folder = _oneDriveFolder;
    if (folder == null) {
      return _settingsText(
        context,
        'Shared-folder access is approved; select the folder to use.',
        'Der Zugriff auf freigegebene Ordner ist genehmigt; wähle den Ordner aus.',
      );
    }
    return _settingsText(
      context,
      'Shared: ${folder.name}/SuperHealth',
      'Gemeinsam: ${folder.name}/SuperHealth',
    );
  }

  Future<OneDriveStorageMode?>
  _chooseStorageMode() => showDialog<OneDriveStorageMode>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Text(
        _settingsText(
          context,
          'Choose OneDrive storage',
          'OneDrive-Speicher wählen',
        ),
      ),
      children: [
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(dialogContext, OneDriveStorageMode.sharedFolder),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_shared_outlined),
            title: Text(
              _settingsText(
                context,
                'Shared family folder',
                'Gemeinsamer Familienordner',
              ),
            ),
            subtitle: Text(
              _settingsText(
                context,
                'Separate Microsoft accounts select the same shared folder. '
                    'Requests Files.ReadWrite.',
                'Getrennte Microsoft-Konten wählen denselben freigegebenen Ordner. '
                    'Erfordert Files.ReadWrite.',
              ),
            ),
          ),
        ),
        SimpleDialogOption(
          onPressed: () =>
              Navigator.pop(dialogContext, OneDriveStorageMode.appFolder),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.lock_outline),
            title: Text(
              _settingsText(
                context,
                'Private AppFolder',
                'Privater App-Ordner',
              ),
            ),
            subtitle: Text(
              _settingsText(
                context,
                'Least privilege. Multiple devices must use the same '
                    'Microsoft account.',
                'Minimale Berechtigung. Mehrere Geräte müssen dasselbe '
                    'Microsoft-Konto verwenden.',
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _connectOneDrive(AppController controller) async {
    try {
      final mode = await _chooseStorageMode();
      if (mode == null) return;
      final code = await controller.oneDriveService.startDeviceCodeSignIn(mode);
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            _settingsText(context, 'Connect OneDrive', 'OneDrive verbinden'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mode == OneDriveStorageMode.sharedFolder
                    ? _settingsText(
                        context,
                        'Microsoft will request Files.ReadWrite so you can select '
                            'a shared folder.',
                        'Microsoft fordert Files.ReadWrite an, damit du einen '
                            'freigegebenen Ordner auswählen kannst.',
                      )
                    : _settingsText(
                        context,
                        'Microsoft will grant access only to the SuperHealth '
                            'AppFolder.',
                        'Microsoft gewährt nur Zugriff auf den SuperHealth-App-Ordner.',
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                _settingsText(
                  context,
                  'Open Microsoft sign-in and enter this one-time code:',
                  'Öffne die Microsoft-Anmeldung und gib diesen Einmalcode ein:',
                ),
              ),
              const SizedBox(height: 14),
              SelectableText(
                code.userCode,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(code.verificationUri.toString()),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_settingsText(context, 'Cancel', 'Abbrechen')),
            ),
            OutlinedButton.icon(
              onPressed: () => launchUrl(code.verificationUri),
              icon: const Icon(Icons.open_in_new),
              label: Text(
                _settingsText(context, 'Open sign-in', 'Anmeldung öffnen'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                _settingsText(context, 'I approved it', 'Ich habe zugestimmt'),
              ),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      final success = await controller.oneDriveService.pollForSignIn(code);
      if (!mounted) return;
      if (!success) {
        throw StateError(
          _settingsText(
            context,
            'OneDrive authorization did not complete.',
            'Die OneDrive-Autorisierung wurde nicht abgeschlossen.',
          ),
        );
      }
      await _refreshOneDriveStatus();
      if (mode == OneDriveStorageMode.sharedFolder) {
        final selected = await _chooseSharedFolder(controller);
        if (!selected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _settingsText(
                  context,
                  'Connected. Choose a shared folder before sync.',
                  'Verbunden. Wähle vor der Synchronisierung einen freigegebenen Ordner.',
                ),
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _settingsText(
                context,
                'OneDrive connected.',
                'OneDrive verbunden.',
              ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<bool> _chooseSharedFolder(AppController controller) async {
    try {
      final folders = await controller.oneDriveService.listAvailableFolders();
      if (!mounted) return false;
      if (folders.isEmpty) {
        throw StateError(
          _settingsText(
            context,
            'No OneDrive folders were found. Create or share a folder first.',
            'Keine OneDrive-Ordner gefunden. Erstelle oder teile zuerst einen Ordner.',
          ),
        );
      }
      final chosen = await showDialog<OneDriveFolder>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            _settingsText(
              context,
              'Select the family data folder',
              'Familiendatenordner auswählen',
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 420),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: folders.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final folder = folders[index];
                return ListTile(
                  leading: Icon(
                    folder.isShared
                        ? Icons.folder_shared_outlined
                        : Icons.folder_outlined,
                  ),
                  title: Text(folder.name),
                  subtitle: Text(
                    folder.isShared
                        ? _settingsText(
                            context,
                            'Shared with me',
                            'Mit mir geteilt',
                          )
                        : _settingsText(
                            context,
                            'My OneDrive',
                            'Mein OneDrive',
                          ),
                  ),
                  onTap: () => Navigator.pop(dialogContext, folder),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_settingsText(context, 'Cancel', 'Abbrechen')),
            ),
          ],
        ),
      );
      if (chosen == null) return false;
      await controller.oneDriveService.selectSharedFolder(chosen);
      await _refreshOneDriveStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _settingsText(
                context,
                'Using ${chosen.name}/SuperHealth for shared data.',
                '${chosen.name}/SuperHealth wird für gemeinsame Daten verwendet.',
              ),
            ),
          ),
        );
      }
      return true;
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
      return false;
    }
  }

  Future<void> _sync(AppController controller) async {
    try {
      final result = await controller.synchronizeOneDrive();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.conflicts > 0
                  ? _settingsText(
                      context,
                      'Sync paused: ${result.conflicts} conflict(s) need review. '
                          'No OneDrive changes were uploaded.',
                      'Synchronisierung pausiert: ${result.conflicts} Konflikt(e) müssen geprüft werden. '
                          'Es wurden keine OneDrive-Änderungen hochgeladen.',
                    )
                  : _settingsText(
                      context,
                      'Synced ${result.uploadedBytes} bytes · '
                          '${result.appliedRows} remote changes · '
                          '${result.uploadedDocuments} PDFs uploaded · '
                          '${result.downloadedDocuments} PDFs downloaded',
                      '${result.uploadedBytes} Bytes synchronisiert · '
                          '${result.appliedRows} Remote-Änderungen · '
                          '${result.uploadedDocuments} PDFs hochgeladen · '
                          '${result.downloadedDocuments} PDFs heruntergeladen',
                    ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _exportPortableBackup(AppController controller) async {
    try {
      final file = await controller.exportPortableBackup();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: _settingsText(
            context,
            'SuperHealth portable backup',
            'Portables SuperHealth-Backup',
          ),
          text: _settingsText(
            context,
            'Encrypted device secrets are not included in this backup.',
            'Verschlüsselte Geräteschlüssel sind nicht in diesem Backup enthalten.',
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _restorePortableBackup(AppController controller) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: _settingsText(
          context,
          'Select SuperHealth portable backup',
          'Portables SuperHealth-Backup auswählen',
        ),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      if (!mounted) return;
      final sourcePath = picked.files.single.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        throw StateError(
          _settingsText(
            context,
            'The selected backup is not available as a file path.',
            'Das ausgewählte Backup ist nicht als Dateipfad verfügbar.',
          ),
        );
      }
      final file = File(sourcePath);
      final fileExists = await file.exists();
      if (!mounted) return;
      if (!fileExists) {
        throw StateError(
          _settingsText(
            context,
            'The selected backup file is no longer available.',
            'Die ausgewählte Backup-Datei ist nicht mehr verfügbar.',
          ),
        );
      }
      final initialConfirmation = await showConfirmAction(
        context,
        title: _settingsText(
          context,
          'Replace current health data?',
          'Aktuelle Gesundheitsdaten ersetzen?',
        ),
        message: _settingsText(
          context,
          'All current profiles, supplements, biomarkers, documents, and '
              'OneDrive sync baseline on this device will be replaced. This cannot '
              'be undone from this device.',
          'Alle aktuellen Profile, Nahrungsergänzungen, Biomarker, Dokumente und '
              'die OneDrive-Synchronisierungsbasis auf diesem Gerät werden ersetzt. '
              'Dies kann auf diesem Gerät nicht rückgängig gemacht werden.',
        ),
        confirmLabel: _settingsText(context, 'Continue', 'Fortfahren'),
        destructive: true,
      );
      if (!initialConfirmation || !mounted) return;
      final typedConfirmation = await _confirmTypedRestore();
      if (!typedConfirmation || !mounted) return;
      final source = await file.readAsString();
      await controller.restorePortableBackup(source);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _settingsText(
                context,
                'Portable backup restored.',
                'Portables Backup wiederhergestellt.',
              ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<bool> _confirmTypedRestore() async {
    final text = TextEditingController();
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text(
                  _settingsText(
                    context,
                    'Final restore confirmation',
                    'Letzte Wiederherstellungsbestätigung',
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _settingsText(
                        context,
                        'Type RESTORE to replace the current health data.',
                        'Gib RESTORE ein, um die aktuellen Gesundheitsdaten zu ersetzen.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: text,
                      autofocus: true,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _settingsText(
                          context,
                          'Confirmation',
                          'Bestätigung',
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(_settingsText(context, 'Cancel', 'Abbrechen')),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    onPressed: text.text == 'RESTORE'
                        ? () => Navigator.pop(dialogContext, true)
                        : null,
                    child: Text(
                      _settingsText(
                        context,
                        'Restore data',
                        'Daten wiederherstellen',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ) ??
          false;
    } finally {
      text.dispose();
    }
  }

  Future<void> _tidyUnits(AppController controller) async {
    final planner = UnitMigrationPlanner(controller.database);
    final messenger = ScaffoldMessenger.of(context);
    final strings = AppLocalizations.of(context);
    try {
      final plan = await planner.plan();
      if (!mounted) return;
      if (plan.isEmpty) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                strings.pick(
                  'Nothing to tidy — every unit is already consistent.',
                  'Nichts aufzuräumen — alle Einheiten sind bereits '
                      'einheitlich.',
                ),
              ),
            ),
          );
        return;
      }
      final applied = await Navigator.of(context).push<int>(
        MaterialPageRoute(
          builder: (_) => UnitMigrationScreen(planner: planner, plan: plan),
        ),
      );
      if (applied == null || !mounted) return;
      await controller.refreshActiveData();
      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              strings.pick(
                'Applied $applied correction(s).',
                '$applied Korrektur(en) angewendet.',
              ),
            ),
          ),
        );
    } on Object catch (error) {
      if (!mounted) return;
      await showAppError(context, error);
    }
  }

  Future<void> _importData(AppController controller) async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        dialogTitle: _settingsText(
          context,
          'Select legacy JSON files',
          'JSON-Altdaten auswählen',
        ),
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: true,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final files = <ImportSourceFile>[];
      for (final selected in selection.files) {
        final bytes =
            selected.bytes ??
            (selected.path == null
                ? null
                : await File(selected.path!).readAsBytes());
        if (bytes != null) {
          files.add(ImportSourceFile(name: selected.name, bytes: bytes));
        }
      }
      if (!mounted) return;
      if (files.isEmpty) {
        throw StateError(
          _settingsText(
            context,
            'The selected files could not be read.',
            'Die ausgewählten Dateien konnten nicht gelesen werden.',
          ),
        );
      }
      final preview = await controller.previewImport(files);
      if (!mounted) return;
      final approved = await _showImportPreview(preview);
      if (approved == true) {
        final result = await controller.commitImport(preview);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _settingsText(
                  context,
                  'Import completed: ${result.inserted.values.fold(0, (a, b) => a + b)} rows.',
                  'Import abgeschlossen: ${result.inserted.values.fold(0, (a, b) => a + b)} Zeilen.',
                ),
              ),
            ),
          );
        }
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _importPdfs(AppController controller) async {
    try {
      final selection = await FilePicker.platform.pickFiles(
        dialogTitle: _settingsText(
          context,
          'Select Biomarkers PDF files',
          'Biomarkers-PDFs auswählen',
        ),
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        allowMultiple: true,
        withData: true,
      );
      if (selection == null || selection.files.isEmpty) return;
      final files = <ImportSourceFile>[];
      for (final selected in selection.files) {
        final bytes =
            selected.bytes ??
            (selected.path == null
                ? null
                : await File(selected.path!).readAsBytes());
        if (bytes != null) {
          files.add(ImportSourceFile(name: selected.name, bytes: bytes));
        }
      }
      if (!mounted) return;
      if (files.isEmpty) {
        throw StateError(
          _settingsText(
            context,
            'The selected PDFs could not be read.',
            'Die ausgewählten PDFs konnten nicht gelesen werden.',
          ),
        );
      }
      final preview = await controller.previewLegacyPdfs(files);
      if (!mounted) return;
      final approved = await _showPdfImportPreview(preview);
      if (approved == true) {
        final result = await controller.commitLegacyPdfs(preview);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _settingsText(
                  context,
                  'Attached ${result.attachedDocuments} PDFs. '
                      'They will be copied to shared OneDrive on the next sync.',
                  '${result.attachedDocuments} PDFs angehängt. '
                      'Sie werden bei der nächsten Synchronisierung ins gemeinsame OneDrive kopiert.',
                ),
              ),
            ),
          );
        }
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<bool?> _showPdfImportPreview(
    LegacyPdfImportPreview preview,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        _settingsText(context, 'Review PDF migration', 'PDF-Übernahme prüfen'),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _settingsText(
                    context,
                    'Selected PDF files',
                    'Ausgewählte PDF-Dateien',
                  ),
                ),
                trailing: Text('${preview.selectedFiles}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _settingsText(
                    context,
                    'Matched document records',
                    'Passende Dokumentdatensätze',
                  ),
                ),
                trailing: Text('${preview.matchedDocuments}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _settingsText(
                    context,
                    'Already available',
                    'Bereits vorhanden',
                  ),
                ),
                trailing: Text('${preview.alreadyAvailable}'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _settingsText(
                    context,
                    'Unmatched files',
                    'Nicht zugeordnete Dateien',
                  ),
                ),
                trailing: Text('${preview.unmatchedFiles}'),
              ),
              if (preview.warnings.isNotEmpty) ...[
                const Divider(),
                Text(
                  _settingsText(context, 'Warnings', 'Warnungen'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final item in preview.warnings) Text('• $item'),
              ],
              const SizedBox(height: 8),
              Text(
                _settingsText(
                  context,
                  'Matched PDFs are verified by SHA-256 before they are attached.',
                  'Zugeordnete PDFs werden vor dem Anhängen per SHA-256 geprüft.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_settingsText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: preview.canImport
              ? () => Navigator.pop(dialogContext, true)
              : null,
          child: Text(_settingsText(context, 'Attach PDFs', 'PDFs anhängen')),
        ),
      ],
    ),
  );

  Future<bool?> _showImportPreview(
    LegacyImportPreview preview,
  ) => showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(_settingsText(context, 'Review import', 'Import prüfen')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _settingsText(
                  context,
                  'Detected: ${preview.sourceKinds.join(', ')}',
                  'Erkannt: ${preview.sourceKinds.join(', ')}',
                ),
              ),
              if (preview.authoritativeSupplementImport) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.sync_problem_outlined),
                    title: Text(
                      _settingsText(
                        context,
                        'Supplement Manager replaces SuperHealth supplement data',
                        'Supplement Manager ersetzt die Ergänzungsdaten in SuperHealth',
                      ),
                    ),
                    subtitle: Text(
                      _settingsText(
                        context,
                        'Catalog, stock, schedules, intakes, symptoms, and tags '
                            'will be reset to this export. Profiles and biomarker '
                            'data are preserved.',
                        'Katalog, Bestand, Einnahmepläne, Einnahmen, Symptome und '
                            'Tags werden auf diesen Export zurückgesetzt. Profile '
                            'und Biomarker-Daten bleiben erhalten.',
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final entry in preview.counts.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.key.replaceAll('_', ' ')),
                  trailing: Text('${entry.value}'),
                ),
              if (preview.duplicates.isNotEmpty) ...[
                const Divider(),
                Text(
                  _settingsText(
                    context,
                    'Duplicates / merges',
                    'Duplikate / Zusammenführungen',
                  ),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final item in preview.duplicates) Text('• $item'),
              ],
              if (preview.warnings.isNotEmpty) ...[
                const Divider(),
                Text(
                  _settingsText(context, 'Warnings', 'Warnungen'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                for (final item in preview.warnings) Text('• $item'),
              ],
              if (preview.alreadyImported)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    _settingsText(
                      context,
                      'This exact source has already been imported.',
                      'Diese exakte Quelle wurde bereits importiert.',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_settingsText(context, 'Cancel', 'Abbrechen')),
        ),
        FilledButton(
          onPressed: preview.canImport
              ? () => Navigator.pop(dialogContext, true)
              : null,
          child: Text(_settingsText(context, 'Import', 'Importieren')),
        ),
      ],
    ),
  );
}

class _RestoreSyncDecisionCard extends StatelessWidget {
  const _RestoreSyncDecisionCard({
    required this.onResumeAndMerge,
    required this.onPublishRestoredData,
  });

  final VoidCallback onResumeAndMerge;
  final VoidCallback onPublishRestoredData;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.errorContainer,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.sync_lock_outlined,
              color: colors.onErrorContainer,
            ),
            title: Text(
              strings.restoreSyncDecisionTitle,
              style: TextStyle(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              strings.restoreSyncDecisionDescription,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.merge_outlined),
            title: Text(strings.resumeAndMerge),
            subtitle: Text(strings.resumeAndMergeDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: onResumeAndMerge,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: Text(strings.publishRestoredData),
            subtitle: Text(strings.publishRestoredDataDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: onPublishRestoredData,
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.controller,
    required this.onThemeModeChanged,
    required this.onColorModeChanged,
    required this.onHighContrastChanged,
    required this.onLanguageChanged,
  });

  final AppController controller;
  final ValueChanged<AppThemeMode> onThemeModeChanged;
  final ValueChanged<AppColorMode> onColorModeChanged;
  final ValueChanged<bool> onHighContrastChanged;
  final ValueChanged<AppLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final disabled = controller.appearanceSaving;
    final strings = AppLocalizations.of(context);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(strings.themeMode),
            subtitle: Text(
              disabled
                  ? strings.savingAppearance
                  : strings.themeModeDescription,
            ),
            trailing: disabled
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
          ),
          _AppearanceRadio<AppThemeMode>(
            value: AppThemeMode.system,
            groupValue: controller.themeMode,
            title: strings.system,
            enabled: !disabled,
            onChanged: onThemeModeChanged,
          ),
          _AppearanceRadio<AppThemeMode>(
            value: AppThemeMode.light,
            groupValue: controller.themeMode,
            title: strings.light,
            enabled: !disabled,
            onChanged: onThemeModeChanged,
          ),
          _AppearanceRadio<AppThemeMode>(
            value: AppThemeMode.dark,
            groupValue: controller.themeMode,
            title: strings.dark,
            enabled: !disabled,
            onChanged: onThemeModeChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: Text(strings.colorVision),
          ),
          _AppearanceRadio<AppColorMode>(
            value: AppColorMode.standard,
            groupValue: controller.colorMode,
            title: strings.standard,
            enabled: !disabled,
            onChanged: onColorModeChanged,
          ),
          _AppearanceRadio<AppColorMode>(
            value: AppColorMode.deuteranomalyFriendly,
            groupValue: controller.colorMode,
            title: strings.deuteranomalyFriendly,
            enabled: !disabled,
            onChanged: onColorModeChanged,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
            child: Text(
              strings.colorVisionExplanation,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.contrast_outlined),
            title: Text(strings.highContrast),
            subtitle: Text(strings.highContrastDescription),
            value: controller.highContrast,
            onChanged: disabled ? null : onHighContrastChanged,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language_outlined),
            title: Text(strings.language),
          ),
          _AppearanceRadio<AppLanguage>(
            value: AppLanguage.system,
            groupValue: controller.language,
            title: strings.system,
            enabled: !disabled,
            onChanged: onLanguageChanged,
          ),
          _AppearanceRadio<AppLanguage>(
            value: AppLanguage.english,
            groupValue: controller.language,
            title: 'English',
            enabled: !disabled,
            onChanged: onLanguageChanged,
          ),
          _AppearanceRadio<AppLanguage>(
            value: AppLanguage.german,
            groupValue: controller.language,
            title: 'Deutsch',
            enabled: !disabled,
            onChanged: onLanguageChanged,
          ),
        ],
      ),
    );
  }
}

class _AppearanceRadio<T> extends StatelessWidget {
  const _AppearanceRadio({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.enabled,
    required this.onChanged,
  });

  final T value;
  final T groupValue;
  final String title;
  final bool enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: groupValue,
    onChanged: (value) {
      if (enabled && value != null) onChanged(value);
    },
    child: RadioListTile<T>(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      dense: true,
      value: value,
      title: Text(title),
      enabled: enabled,
    ),
  );
}

class _ReminderStatusCard extends StatelessWidget {
  const _ReminderStatusCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final omitted = controller.omittedReminderOccurrenceCount;
    final coverage = _coverageText(
      context,
      controller.reminderCoverageThrough,
      controller.reminderCoverageReason,
    );
    final permission = switch (controller.reminderPermissionStatus) {
      ReminderPermissionStatus.granted => _settingsText(
        context,
        'Allowed',
        'Erlaubt',
      ),
      ReminderPermissionStatus.denied => _settingsText(
        context,
        'Permission needed',
        'Berechtigung erforderlich',
      ),
      ReminderPermissionStatus.unsupported => _settingsText(
        context,
        'Android only',
        'Nur Android',
      ),
      ReminderPermissionStatus.unknown => _settingsText(
        context,
        'Checking status',
        'Status wird geprüft',
      ),
    };
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              controller.reminderPermissionStatus ==
                      ReminderPermissionStatus.granted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: Text(
              _settingsText(
                context,
                'Notification permission',
                'Benachrichtigungsberechtigung',
              ),
            ),
            subtitle: Text(
              controller.reminderStatusMessage ?? '$permission · $coverage',
            ),
            trailing:
                controller.reminderPermissionStatus ==
                    ReminderPermissionStatus.granted
                ? const Icon(Icons.check_circle_outline)
                : TextButton(
                    onPressed:
                        controller.busy ||
                            controller.reminderPermissionStatus ==
                                ReminderPermissionStatus.unsupported
                        ? null
                        : () async {
                            await controller.requestReminderPermission();
                          },
                    child: Text(_settingsText(context, 'Allow', 'Erlauben')),
                  ),
          ),
          const Divider(height: 1),
          // Exact alarms are what make a reminder land at its time. Android 12
          // and 13 let the owner revoke the right, and a revoked one turns
          // every reminder into an approximate hint, so it needs saying.
          if (controller.exactAlarmsAllowed == false)
            ListTile(
              leading: Icon(Icons.schedule_outlined, color: scheme.error),
              title: Text(
                _settingsText(
                  context,
                  'Reminders may arrive late',
                  'Erinnerungen können verspätet ankommen',
                ),
              ),
              subtitle: Text(
                _settingsText(
                  context,
                  'Android is not allowing exact alarms, so the system may hold '
                      'a reminder for hours past its time.',
                  'Android erlaubt keine exakten Alarme, daher kann das System '
                      'eine Erinnerung Stunden über ihre Zeit hinaus zurückhalten.',
                ),
              ),
              trailing: FilledButton(
                onPressed: controller.busy
                    ? null
                    : () async {
                        await controller.requestExactAlarmPermission();
                      },
                child: Text(_settingsText(context, 'Fix', 'Beheben')),
              ),
            ),
          // Scheduling fails silently — permissions, channels, OEM battery
          // managers — and none of it is visible from inside the app. One tap
          // separates "nothing was scheduled" from "nothing gets through".
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(
              _settingsText(
                context,
                'Send a test notification',
                'Testbenachrichtigung senden',
              ),
            ),
            subtitle: Text(
              _settingsText(
                context,
                'Posts one now, exactly the way a dose reminder is delivered.',
                'Sendet jetzt eine — genau so, wie eine Dosis-Erinnerung zugestellt wird.',
              ),
            ),
            trailing: FilledButton.tonal(
              onPressed:
                  controller.busy ||
                      controller.reminderPermissionStatus ==
                          ReminderPermissionStatus.unsupported
                  ? null
                  : () async {
                      // Both messages are resolved before the await: the
                      // context must not be read across the gap.
                      final messenger = ScaffoldMessenger.of(context);
                      final sent = _settingsText(
                        context,
                        'Sent. If it does not appear, check SuperHealth in Android notification settings.',
                        'Gesendet. Falls nichts erscheint, prüfe SuperHealth in den Android-Benachrichtigungseinstellungen.',
                      );
                      final refused = _settingsText(
                        context,
                        'Android refused the notification. Allow notifications for SuperHealth first.',
                        'Android hat die Benachrichtigung abgelehnt. Erlaube zuerst Benachrichtigungen für SuperHealth.',
                      );
                      final delivered = await controller.sendTestNotification();
                      messenger.showSnackBar(
                        SnackBar(content: Text(delivered ? sent : refused)),
                      );
                    },
              child: Text(_settingsText(context, 'Send', 'Senden')),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(
              _settingsText(
                context,
                '${controller.scheduledReminderCount} scheduled reminder(s)',
                '${controller.scheduledReminderCount} geplante Erinnerung(en)',
              ),
            ),
            subtitle: Text(coverage),
            trailing: IconButton(
              tooltip: _settingsText(
                context,
                'Refresh reminder schedule',
                'Erinnerungsplan aktualisieren',
              ),
              onPressed: controller.busy
                  ? null
                  : () async {
                      await controller.refreshReminderStatus();
                    },
              icon: const Icon(Icons.refresh),
            ),
          ),
          Semantics(
            liveRegion: true,
            label: _settingsText(
              context,
              '$omitted reminder occurrences are not scheduled',
              '$omitted Erinnerungstermine sind nicht geplant',
            ),
            child: Container(
              width: double.infinity,
              color: omitted == 0
                  ? scheme.surfaceContainerHighest
                  : scheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                omitted == 0
                    ? _settingsText(
                        context,
                        'All currently planned occurrences fit the device schedule.',
                        'Alle derzeit geplanten Termine passen in den Geräteplan.',
                      )
                    : _settingsText(
                        context,
                        '$omitted occurrence(s) are not scheduled. Open the app and refresh reminders; '
                            'reduce overlapping bounded schedules if this persists.',
                        '$omitted Termin(e) sind nicht geplant. Öffne die App und aktualisiere die Erinnerungen; '
                            'reduziere bei Bedarf überlappende befristete Pläne.',
                      ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: omitted == 0
                      ? scheme.onSurfaceVariant
                      : scheme.onErrorContainer,
                  fontWeight: omitted == 0 ? null : FontWeight.w700,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(
              _settingsText(
                context,
                'Low-stock alerts',
                'Warnungen bei niedrigem Bestand',
              ),
            ),
            subtitle: Text(
              controller.lastLowStockAlertCount == 0
                  ? _settingsText(
                      context,
                      'No new low-stock alerts on the last refresh.',
                      'Bei der letzten Aktualisierung gab es keine neuen Bestandswarnungen.',
                    )
                  : _settingsText(
                      context,
                      '${controller.lastLowStockAlertCount} new low-stock alert(s) on the last refresh.',
                      '${controller.lastLowStockAlertCount} neue Bestandswarnung(en) bei der letzten Aktualisierung.',
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
            child: Text(
              _settingsText(
                context,
                'Notifications are scheduled by Android itself, exactly when the right is granted. Open-ended schedules repeat weekly; '
                    'date-bounded schedules are kept in a rolling window and renew when the app opens. '
                    'No background worker runs on your device.',
                'Benachrichtigungen plant Android selbst — exakt, sofern die Berechtigung erteilt ist. Unbefristete Pläne wiederholen sich wöchentlich; '
                    'befristete Pläne werden in einem rollierenden Fenster gehalten und beim Öffnen der App erneuert. '
                    'Auf deinem Gerät läuft kein Hintergrunddienst.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _coverageText(
    BuildContext context,
    DateTime? date,
    ReminderCoverageReason? reason,
  ) {
    if (date == null) {
      return _settingsText(
        context,
        'Coverage will be calculated on refresh.',
        'Die Abdeckung wird bei der Aktualisierung berechnet.',
      );
    }
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return switch (reason) {
      ReminderCoverageReason.complete => _settingsText(
        context,
        'All planned occurrences covered.',
        'Alle geplanten Termine abgedeckt.',
      ),
      ReminderCoverageReason.rollingHorizon => _settingsText(
        context,
        'Coverage through $day (rolling window).',
        'Abdeckung bis $day (rollierendes Fenster).',
      ),
      ReminderCoverageReason.alarmBudget => _settingsText(
        context,
        'Coverage through $day (device alarm budget).',
        'Abdeckung bis $day (Gerätealarm-Budget).',
      ),
      null => _settingsText(
        context,
        'Coverage through $day.',
        'Abdeckung bis $day.',
      ),
    };
  }
}

enum _ProfileAction { edit, delete }

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.profile,
    required this.active,
    required this.actionsEnabled,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  final Profile profile;
  final bool active;
  final bool actionsEnabled;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (active) _settingsText(context, 'Active profile', 'Aktives Profil'),
      if (profile.age != null)
        _settingsText(context, 'Age ${profile.age}', 'Alter ${profile.age}'),
      if (profile.sex?.isNotEmpty == true)
        _profileSexLabel(context, profile.sex!),
      if (profile.heightCm != null) '${profile.heightCm} cm',
      if (profile.weightKg != null) '${profile.weightKg} kg',
    ];
    return Semantics(
      selected: active,
      label: [
        profile.displayName,
        if (active) _settingsText(context, 'active profile', 'aktives Profil'),
        ...details.where(
          (detail) =>
              detail !=
              _settingsText(context, 'Active profile', 'Aktives Profil'),
        ),
      ].join(', '),
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(
          active ? Icons.check_circle : Icons.circle_outlined,
          color: active ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(
          profile.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          details.isEmpty
              ? _settingsText(
                  context,
                  'No optional details',
                  'Keine optionalen Angaben',
                )
              : details.join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<_ProfileAction>(
          tooltip: _settingsText(
            context,
            'Actions for ${profile.displayName}',
            'Aktionen für ${profile.displayName}',
          ),
          enabled: actionsEnabled,
          onSelected: (action) {
            switch (action) {
              case _ProfileAction.edit:
                onEdit();
                break;
              case _ProfileAction.delete:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _ProfileAction.edit,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: Text(
                  _settingsText(context, 'Edit profile', 'Profil bearbeiten'),
                ),
              ),
            ),
            PopupMenuItem(
              value: _ProfileAction.delete,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: Text(
                  _settingsText(context, 'Delete profile', 'Profil löschen'),
                ),
              ),
            ),
          ],
        ),
        onTap: actionsEnabled ? onSelect : null,
      ),
    );
  }
}

String _profileSexLabel(BuildContext context, String sex) => switch (sex) {
  'female' => _settingsText(context, 'Female', 'Weiblich'),
  'male' => _settingsText(context, 'Male', 'Männlich'),
  'intersex' => _settingsText(context, 'Intersex', 'Intergeschlechtlich'),
  'other' => _settingsText(
    context,
    'Other / self-described',
    'Andere / selbst beschrieben',
  ),
  _ => sex,
};

class _ApiKeyCard extends StatefulWidget {
  const _ApiKeyCard({required this.provider});

  final AiProvider provider;

  @override
  State<_ApiKeyCard> createState() => _ApiKeyCardState();
}

class _ApiKeyCardState extends State<_ApiKeyCard> {
  final _key = TextEditingController();
  bool _visible = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final configured = controller.hasApiKey[widget.provider] == true;
    return Card(
      child: ExpansionTile(
        leading: Icon(configured ? Icons.key : Icons.key_off_outlined),
        title: Text(_providerLabel(widget.provider)),
        subtitle: Text(
          configured
              ? _settingsText(
                  context,
                  'Key configured',
                  'Schlüssel eingerichtet',
                )
              : _settingsText(
                  context,
                  'No key configured',
                  'Kein Schlüssel eingerichtet',
                ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          TextField(
            controller: _key,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: configured
                  ? _settingsText(
                      context,
                      'Replace API key',
                      'API-Schlüssel ersetzen',
                    )
                  : _settingsText(context, 'API key', 'API-Schlüssel'),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _visible = !_visible),
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (configured)
                TextButton(
                  onPressed: () async {
                    await controller.saveApiKey(widget.provider, '');
                    _key.clear();
                  },
                  child: Text(_settingsText(context, 'Remove', 'Entfernen')),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _key.text.trim().isEmpty
                    ? null
                    : () async {
                        try {
                          await controller.saveApiKey(
                            widget.provider,
                            _key.text,
                          );
                          _key.clear();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _settingsText(
                                    context,
                                    '${_providerLabel(widget.provider)} key saved.',
                                    '${_providerLabel(widget.provider)}-Schlüssel gespeichert.',
                                  ),
                                ),
                              ),
                            );
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            await showAppError(context, error);
                          }
                        }
                      },
                child: Text(
                  _settingsText(context, 'Save key', 'Schlüssel speichern'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _providerLabel(AiProvider provider) => switch (provider) {
    AiProvider.openai => 'OpenAI',
    AiProvider.anthropic => 'Anthropic',
    AiProvider.gemini => 'Google Gemini',
  };
}

class _ModelConfigurationCard extends StatefulWidget {
  const _ModelConfigurationCard({
    required this.task,
    required this.title,
    required this.settings,
    required this.allowTools,
    super.key,
  });

  final AiTask task;
  final String title;
  final AiTaskSettings? settings;
  final bool allowTools;

  @override
  State<_ModelConfigurationCard> createState() =>
      _ModelConfigurationCardState();
}

class _ModelConfigurationCardState extends State<_ModelConfigurationCard> {
  late AiProvider _provider;
  String? _model;
  String? _reasoning;
  bool _web = false;
  bool _code = false;

  @override
  void initState() {
    super.initState();
    _provider = widget.settings?.provider ?? AiProvider.openai;
    _model = widget.settings?.model;
    _reasoning = widget.settings?.reasoningLevel;
    _web = widget.settings?.webSearch ?? false;
    _code = widget.settings?.codeExecution ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final models =
        controller.availableModels[_provider] ?? const <AiModelInfo>[];
    final modelIds = models.map((item) => item.id).toSet();
    final selectedModel =
        modelIds.contains(_model) || (models.isEmpty && _model != null)
        ? _model
        : null;
    final capabilities = selectedModel == null
        ? const ModelCapabilities()
        : controller.capabilityRegistry.forModel(_provider, selectedModel);
    if (_reasoning != null &&
        !capabilities.reasoningLevels.contains(_reasoning)) {
      _reasoning = null;
    }
    if (!capabilities.webSearch) _web = false;
    if (!capabilities.codeExecution) _code = false;

    return Card(
      child: ExpansionTile(
        leading: Icon(
          widget.task == AiTask.advisor
              ? Icons.psychology_outlined
              : Icons.document_scanner_outlined,
        ),
        title: Text(widget.title),
        subtitle: Text(
          widget.settings == null
              ? _settingsText(context, 'Not configured', 'Nicht eingerichtet')
              : '${widget.settings!.provider.name} · ${widget.settings!.model}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          DropdownButtonFormField<AiProvider>(
            initialValue: _provider,
            decoration: InputDecoration(
              labelText: _settingsText(context, 'Provider', 'Anbieter'),
            ),
            items: [
              for (final provider in AiProvider.values)
                DropdownMenuItem(value: provider, child: Text(provider.name)),
            ],
            onChanged: (value) => setState(() {
              _provider = value ?? _provider;
              _model = null;
              _reasoning = null;
              _web = false;
              _code = false;
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'model-${_provider.name}-$selectedModel-${models.length}',
                  ),
                  initialValue: selectedModel,
                  decoration: InputDecoration(
                    labelText: _settingsText(context, 'Model', 'Modell'),
                  ),
                  isExpanded: true,
                  items: [
                    if (models.isEmpty && _model != null)
                      DropdownMenuItem(value: _model, child: Text(_model!)),
                    for (final model in models)
                      DropdownMenuItem(
                        value: model.id,
                        child: Text(
                          model.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _model = value;
                    _reasoning = null;
                    _web = false;
                    _code = false;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: _settingsText(
                  context,
                  'Load current models from provider',
                  'Aktuelle Modelle vom Anbieter laden',
                ),
                onPressed:
                    controller.busy || controller.hasApiKey[_provider] != true
                    ? null
                    : () async {
                        try {
                          final loaded = await controller.loadModels(_provider);
                          if (mounted) {
                            setState(() {
                              if (_model == null && loaded.isNotEmpty) {
                                _model = loaded.first.id;
                              }
                            });
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            await showAppError(context, error);
                          }
                        }
                      },
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (capabilities.reasoningLevels.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: ValueKey('reasoning-$_model-$_reasoning'),
              initialValue: _reasoning,
              decoration: InputDecoration(
                labelText: _settingsText(
                  context,
                  'Reasoning level',
                  'Reasoning-Stufe',
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    _settingsText(
                      context,
                      'Provider default',
                      'Anbieterstandard',
                    ),
                  ),
                ),
                for (final level in capabilities.reasoningLevels)
                  DropdownMenuItem<String?>(value: level, child: Text(level)),
              ],
              onChanged: (value) => setState(() => _reasoning = value),
            ),
          ],
          if (widget.allowTools && selectedModel != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _settingsText(
                  context,
                  'Provider web search',
                  'Websuche des Anbieters',
                ),
              ),
              subtitle: Text(
                capabilities.webSearch
                    ? _settingsText(
                        context,
                        'Available for this documented model',
                        'Für dieses dokumentierte Modell verfügbar',
                      )
                    : _settingsText(
                        context,
                        'Not enabled for this model',
                        'Für dieses Modell nicht aktiviert',
                      ),
              ),
              value: _web,
              onChanged: capabilities.webSearch
                  ? (value) => setState(() => _web = value)
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                _settingsText(
                  context,
                  'Provider code sandbox',
                  'Code-Sandbox des Anbieters',
                ),
              ),
              subtitle: Text(
                capabilities.codeExecution
                    ? _settingsText(
                        context,
                        'Can calculate and create temporary provider files; no app database access',
                        'Kann rechnen und temporäre Anbieterdateien erstellen; kein Zugriff auf die App-Datenbank',
                      )
                    : _settingsText(
                        context,
                        'Not enabled for this model',
                        'Für dieses Modell nicht aktiviert',
                      ),
              ),
              value: _code,
              onChanged: capabilities.codeExecution
                  ? (value) => setState(() => _code = value)
                  : null,
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: selectedModel == null
                  ? null
                  : () async {
                      try {
                        await controller.saveTaskSettings(
                          widget.task,
                          AiTaskSettings(
                            provider: _provider,
                            model: selectedModel,
                            reasoningLevel: _reasoning,
                            webSearch: widget.allowTools && _web,
                            codeExecution: widget.allowTools && _code,
                          ),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                _settingsText(
                                  context,
                                  '${widget.title} settings saved.',
                                  'Einstellungen für ${widget.title} gespeichert.',
                                ),
                              ),
                            ),
                          );
                        }
                      } on Object catch (error) {
                        if (context.mounted) await showAppError(context, error);
                      }
                    },
              child: Text(
                _settingsText(
                  context,
                  'Save configuration',
                  'Konfiguration speichern',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
