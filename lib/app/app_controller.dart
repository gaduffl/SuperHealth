// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/advisor_service.dart';
import '../ai/ai_models.dart';
import '../ai/ai_settings.dart';
import '../ai/api_key_store.dart';
import '../ai/document_parsing_service.dart';
import '../ai/ai_trace.dart';
import '../ai/ai_trace_store.dart';
import '../ai/lab_planner_service.dart';
import '../ai/lab_price_service.dart';
import '../ai/provider_clients.dart';
import '../ai/supplement_label_service.dart';
import '../analysis/correlation_service.dart';
import '../analysis/lab_plan_pricing.dart';
import 'feature_visibility.dart';
import 'long_task_guard.dart';
import '../analysis/supplement_insights.dart';
import '../backup/portable_backup_service.dart';
import '../data/app_database.dart';
import '../data/health_repository.dart';
import '../domain/entities.dart';
import '../export/lab_plan_export_service.dart';
import '../import/legacy_import_service.dart';
import '../reminders/reminder_service.dart';
import '../reminders/reminder_planner.dart';
import '../sync/one_drive_service.dart';
import '../sync/restore_sync_gate.dart';
import '../sync/snapshot_service.dart';
import '../sync/sync_status.dart';
import '../workspace/safe_workspace_service.dart';
import 'appearance_settings.dart';
import 'initial_setup_progress.dart';

class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required HealthRepository repository,
    required ApiKeyStore keyStore,
    required AiSettingsStore aiSettingsStore,
    required AdvisorService advisorService,
    required LabPlannerService labPlannerService,
    required LabPriceService labPriceService,
    required DocumentParsingService documentParsingService,
    required CorrelationService correlationService,
    required LegacyImportService importService,
    required OneDriveService oneDriveService,
    required SafeWorkspaceService workspaceService,
    required LabPlanExportService exportService,
    required AiProviderClientFactory clientFactory,
    SupplementLabelService? supplementLabelService,
    ProviderCapabilityRegistry? capabilityRegistry,
    ReminderService? reminderService,
    PortableBackupService? portableBackupService,
    DocumentsDirectory? documentsDirectory,
    AppearanceSettingsStore? appearanceSettingsStore,
    InitialSetupProgressStore? initialSetupProgressStore,
    RestoreSyncGateStore? restoreSyncGateStore,
    SyncStatusStore? syncStatusStore,
    LongTaskGuard? longTaskGuard,
    AiTraceStore? labPlanTraceStore,
    AiTraceStore? advisorTraceStore,
  }) : _database = database,
       repository = repository,
       keyStore = keyStore,
       _aiSettingsStore = aiSettingsStore,
       _advisorService = advisorService,
       _labPlannerService = labPlannerService,
       _labPriceService = labPriceService,
       _documentParsingService = documentParsingService,
       _correlationService = correlationService,
       importService = importService,
       oneDriveService = oneDriveService,
       workspaceService = workspaceService,
       exportService = exportService,
       _clientFactory = clientFactory,
       _supplementLabelService =
           supplementLabelService ??
           SupplementLabelService(
             keyStore: keyStore,
             clientFactory: clientFactory,
             capabilities: capabilityRegistry,
           ),
       capabilityRegistry = capabilityRegistry ?? ProviderCapabilityRegistry(),
       _reminderService = reminderService ?? ReminderService(),
       _portableBackupService = portableBackupService,
       _documentsDirectory = documentsDirectory,
       _appearanceSettingsStore =
           appearanceSettingsStore ?? AppearanceSettingsStore(),
       _initialSetupProgressStore =
           initialSetupProgressStore ?? InitialSetupProgressStore(),
       _restoreSyncGateStore = restoreSyncGateStore ?? RestoreSyncGateStore(),
       _syncStatusStore = syncStatusStore ?? SyncStatusStore(),
       _longTaskGuard = longTaskGuard ?? LongTaskGuard(),
       _labPlanTraceStore = labPlanTraceStore,
       _advisorTraceStore = advisorTraceStore;

  final AppDatabase _database;

  /// Exposed for the one-time unit clean-up, which surveys stored rows across
  /// tables rather than through any single repository accessor.
  AppDatabase get database => _database;

  final HealthRepository repository;
  final ApiKeyStore keyStore;
  final AiSettingsStore _aiSettingsStore;
  final AdvisorService _advisorService;
  final LabPlannerService _labPlannerService;
  final LabPriceService _labPriceService;
  final DocumentParsingService _documentParsingService;
  final CorrelationService _correlationService;
  final LegacyImportService importService;
  final OneDriveService oneDriveService;
  final SafeWorkspaceService workspaceService;
  final LabPlanExportService exportService;
  final AiProviderClientFactory _clientFactory;
  final SupplementLabelService _supplementLabelService;
  final ProviderCapabilityRegistry capabilityRegistry;
  final ReminderService _reminderService;
  final LongTaskGuard _longTaskGuard;

  /// Null in builds and tests that have no writable documents directory. The
  /// diagnostics section reports that rather than offering an export that
  /// cannot work.
  final AiTraceStore? _labPlanTraceStore;
  final AiTraceStore? _advisorTraceStore;
  final PortableBackupService? _portableBackupService;
  final DocumentsDirectory? _documentsDirectory;
  final AppearanceSettingsStore _appearanceSettingsStore;
  final InitialSetupProgressStore _initialSetupProgressStore;
  final RestoreSyncGateStore _restoreSyncGateStore;
  final SyncStatusStore _syncStatusStore;

  bool initialized = false;
  bool busy = false;
  bool appearanceSaving = false;
  AppearanceSettings appearanceSettings = AppearanceSettings.defaults;
  InitialSetupProgress initialSetupProgress =
      const InitialSetupProgress.empty();
  bool restoreSyncDecisionPending = false;

  /// When this device last uploaded a complete snapshot, or null for never.
  ///
  /// A run that stopped at unresolved conflicts uploads nothing, so it never
  /// advances this. That is the point: the value answers "is the cloud copy
  /// current", not "did a sync run".
  DateTime? lastSuccessfulSyncAt;

  /// Why the most recent automatic sync failed, or null when none has.
  ///
  /// A background attempt has no dialog to fail into. Without somewhere to
  /// surface the reason, a phone that has been unable to reach OneDrive for a
  /// week looks exactly like one that simply has nothing to upload.
  String? lastAutoSyncError;

  bool _autoSyncInFlight = false;
  DateTime? _lastAutoSyncAttempt;

  String? initializationError;
  Profile? activeProfile;
  List<Profile> profiles = const [];
  List<Supplement> supplements = const [];
  List<SupplementSchedule> schedules = const [];
  List<SupplementSchedule> householdSchedules = const [];
  List<BiomarkerPackage> biomarkerPackages = const [];
  Map<String, Set<String>> biomarkerPackageMembers = const {};
  List<SupplementIntake> intakes = const [];
  List<InventoryMovement> inventoryMovements = const [];
  Map<String, double> stockLevels = const {};
  List<HealthEventDefinition> eventDefinitions = const [];
  List<HealthEvent> events = const [];
  List<Biomarker> biomarkers = const [];
  List<BiomarkerReferenceRange> biomarkerRanges = const [];
  List<ProfileBiomarkerTarget> profileTargets = const [];
  List<Measurement> measurements = const [];
  List<HealthDocument> documents = const [];
  List<NamedHealthRecord> namedRecords = const [];
  List<BiomarkerList> biomarkerLists = const [];
  List<DueBiomarker> dueBiomarkers = const [];
  List<LabPlan> labPlans = const [];
  List<AdvisorMessage> advisorMessages = const [];

  /// Every conversation this profile has, most recently used first.
  List<AdvisorConversation> advisorConversations = const [];

  /// The question currently being answered, or null when nothing is in flight.
  ///
  /// Nothing is written to the database until the answer arrives, which is what
  /// keeps a failed turn out of the history — but it also meant the question
  /// vanished the moment it was sent: cleared from the input box, absent from
  /// the thread, and in a new conversation the welcome screen still showing. A
  /// chat has to show what you just said while it is being answered.
  String? pendingAdvisorQuestion;

  /// Null until a refresh resolves it; never null to a caller.
  ///
  /// The distinction matters. "Unresolved" means land on the most recent
  /// conversation, which is where the user left off. Once anything has chosen
  /// one — the user opening it, a delete falling back, a new one starting — the
  /// choice is deliberate and a later refresh must not overrule it. Inferring
  /// that from an empty message list instead got it wrong for every install
  /// whose oldest thread is the pre-feature `primary`: a restart would land
  /// there rather than on the newest.
  String? _activeConversationId;

  /// The conversation the advisor screen is showing and will ask into.
  ///
  /// Not persisted. The most recent conversation *is* where the user left off,
  /// so a stored id would say the same thing and then have to be kept honest
  /// across profile switches, deletions and restores. A brand-new conversation
  /// exists only in this field until it has been spoken in, so abandoning one
  /// leaves nothing behind.
  String get activeConversationId =>
      _activeConversationId ?? defaultConversationId;

  /// The conversation every install had before there was more than one.
  static const defaultConversationId = 'primary';
  List<CorrelationResult> correlations = const [];
  List<TrendDoseLink> trendDoseLinks = const [];
  LabPlanGeneration? draftLabPlan;
  ParsedLabReport? pendingLabReport;
  int? lastContextBytes;
  int? lastContextTokens;

  /// What the provider reported the last exchange actually cost. Null until a
  /// message has been sent, or when the provider reported no usage.
  TokenUsage? lastTokenUsage;
  AiTaskSettings? advisorSettings;
  AiTaskSettings? parsingSettings;
  AiTaskSettings? pricingSettings;

  /// The lab planner's own model. Falls back to the advisor's on load, because
  /// that is what every existing install has been using — showing it as the
  /// current value is the truth, and lets the setting be changed from there.
  AiTaskSettings? labPlannerSettings;

  /// The stage a lab plan is at, or null when none is running. A greyed-out
  /// button says only that something is happening; these calls run for minutes.
  LabPlanStage? labPlanStage;

  /// When the running generation started, so the screen can show elapsed time.
  /// A long wait with a moving number reads as work; a still one reads as a
  /// hang, and the two are otherwise indistinguishable.
  DateTime? labPlanStartedAt;

  /// What the model is currently producing, or null before the first byte of
  /// the current call arrives.
  ProviderActivity? labPlanActivity;

  /// When [labPlanActivity] last changed.
  ///
  /// This is the only thing that distinguishes a slow model from a dead
  /// connection. The stage label and the elapsed clock both keep looking
  /// healthy through a stall; a byte count that stopped moving does not.
  DateTime? labPlanActivityAt;

  /// Whether the running generation is held by a foreground service, and so
  /// survives the app leaving the foreground.
  ///
  /// False when the service could not be started — the plan still generates,
  /// but only for as long as the process lives. The screen has to be able to
  /// tell the two apart, because "you can switch away" is a promise the app
  /// cannot keep without this.
  bool get labPlanSurvivesBackground => _longTaskGuard.hasForegroundService;

  final Map<AiProvider, bool> hasApiKey = {};
  final Map<AiProvider, List<AiModelInfo>> availableModels = {};
  ReminderPermissionStatus reminderPermissionStatus =
      ReminderPermissionStatus.unknown;
  String? reminderStatusMessage;
  int scheduledReminderCount = 0;
  int omittedReminderOccurrenceCount = 0;

  /// Whether Android currently lets the app post exact alarms. Null on
  /// platforms without the concept, and before reminders are first initialised.
  bool? get exactAlarmsAllowed => _reminderService.exactAlarmsAllowed;
  DateTime? reminderCoverageThrough;
  ReminderCoverageReason? reminderCoverageReason;
  int lastLowStockAlertCount = 0;

  AppThemeMode get themeMode => appearanceSettings.themeMode;
  AppColorPalette get colorPalette => appearanceSettings.palette;
  AppColorMode get colorMode => appearanceSettings.colorMode;
  bool get highContrast => appearanceSettings.highContrast;
  AppLanguage get language => appearanceSettings.language;

  List<WorkspaceProposal> get workspaceProposals => workspaceService.pending
      .where((item) => item.profileId == activeProfile?.id)
      .toList(growable: false);

  Future<void> initialize() async {
    // Appearance is loaded before opening the initialized-app gate. Its values
    // are intentionally device-wide, and corrupt preference values fall back
    // harmlessly rather than blocking access to the health record.
    try {
      appearanceSettings = await _appearanceSettingsStore.load();
    } on Object {
      appearanceSettings = AppearanceSettings.defaults;
    }
    try {
      advisorSettings = await _aiSettingsStore.load(AiTask.advisor);
      parsingSettings = await _aiSettingsStore.load(AiTask.parsing);
      pricingSettings = await _aiSettingsStore.load(AiTask.pricing);
      labPlannerSettings =
          await _aiSettingsStore.load(AiTask.labPlanner) ?? advisorSettings;
      await refreshKeyStatus();
      restoreSyncDecisionPending = await _restoreSyncGateStore.isPending();
      lastSuccessfulSyncAt = await _syncStatusStore.lastSuccessfulSync();
      await refreshProfiles();
      await _reconcileReminders();
    } on Object catch (error) {
      initializationError = error.toString();
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(AppThemeMode value) =>
      _saveAppearance(appearanceSettings.copyWith(themeMode: value));

  Future<void> setColorPalette(AppColorPalette value) =>
      _saveAppearance(appearanceSettings.copyWith(palette: value));

  Future<void> setColorMode(AppColorMode value) =>
      _saveAppearance(appearanceSettings.copyWith(colorMode: value));

  Future<void> setHighContrast(bool value) =>
      _saveAppearance(appearanceSettings.copyWith(highContrast: value));

  Future<void> setLanguage(AppLanguage value) =>
      _saveAppearance(appearanceSettings.copyWith(language: value));

  Future<void> _saveAppearance(AppearanceSettings next) async {
    if (appearanceSaving || next == appearanceSettings) return;
    final previous = appearanceSettings;
    appearanceSettings = next;
    appearanceSaving = true;
    notifyListeners();
    try {
      if (!await _appearanceSettingsStore.save(next)) {
        throw StateError('Could not save appearance settings on this device.');
      }
    } on Object {
      appearanceSettings = previous;
      rethrow;
    } finally {
      appearanceSaving = false;
      notifyListeners();
    }
  }

  Future<void> refreshKeyStatus() async {
    for (final provider in AiProvider.values) {
      hasApiKey[provider] = await keyStore.hasKey(provider);
    }
    await refreshInitialSetupProgress();
  }

  /// Refreshes device-local setup progress from persisted action facts and
  /// current profile, OneDrive, and advisor configuration state.
  ///
  /// UI flows that directly connect or select OneDrive storage can call this
  /// after their action succeeds. Refreshing alone never records completion.
  Future<void> refreshInitialSetupProgress({bool notify = true}) async {
    final facts = await _initialSetupProgressStore.loadFacts();
    var oneDriveReady = false;
    try {
      final signedIn = await oneDriveService.isSignedIn();
      if (signedIn) {
        final mode = await oneDriveService.currentStorageMode();
        oneDriveReady =
            mode == OneDriveStorageMode.appFolder ||
            (mode == OneDriveStorageMode.sharedFolder &&
                await oneDriveService.selectedFolder() != null);
      }
    } on Object {
      // Setup progress must not turn a transient cloud status read into an app
      // initialization failure. The next explicit refresh can recover it.
      oneDriveReady = false;
    }
    final advisor = advisorSettings;
    initialSetupProgress = InitialSetupProgress(
      profileExists: profiles.isNotEmpty,
      legacyJsonImported: facts.legacyJsonImported,
      legacyJsonSkipped: facts.legacyJsonSkipped,
      legacyPdfsAttached: facts.legacyPdfsAttached,
      legacyPdfsSkipped: facts.legacyPdfsSkipped,
      dataRestored: facts.dataRestored,
      oneDriveReady: oneDriveReady,
      firstSuccessfulSync: facts.firstSuccessfulSync,
      cloudSkipped: facts.cloudSkipped,
      advisorReady: advisor != null && hasApiKey[advisor.provider] == true,
      aiSkipped: facts.aiSkipped,
    );
    if (notify) notifyListeners();
  }

  Future<void> markLegacyJsonImportSkipped() async {
    await _initialSetupProgressStore.recordLegacyJsonSkipped();
    await refreshInitialSetupProgress();
  }

  Future<void> markLegacyPdfsImportSkipped() async {
    await _initialSetupProgressStore.recordLegacyPdfsSkipped();
    await refreshInitialSetupProgress();
  }

  Future<void> markCloudSetupSkipped() async {
    await _initialSetupProgressStore.recordCloudSkipped();
    await refreshInitialSetupProgress();
  }

  Future<void> markAiSetupSkipped() async {
    await _initialSetupProgressStore.recordAiSkipped();
    await refreshInitialSetupProgress();
  }

  /// Requests Android 13+ notification permission from an explicit settings
  /// action. This is never requested at startup.
  Future<ReminderPermissionStatus> requestReminderPermission() async {
    try {
      reminderPermissionStatus = await _reminderService.requestPermission();
      reminderStatusMessage = switch (reminderPermissionStatus) {
        ReminderPermissionStatus.granted => null,
        ReminderPermissionStatus.denied =>
          'Notification permission is not granted.',
        ReminderPermissionStatus.unsupported =>
          'Dose reminders are currently available on Android only.',
        ReminderPermissionStatus.unknown => 'Notification status is unknown.',
      };
      if (reminderPermissionStatus == ReminderPermissionStatus.granted) {
        await _reconcileReminders();
      }
    } on Object catch (error) {
      reminderPermissionStatus = ReminderPermissionStatus.unknown;
      reminderStatusMessage = 'Could not request notifications: $error';
    }
    notifyListeners();
    return reminderPermissionStatus;
  }

  /// Asks Android for the exact-alarm right, then reschedules so pending
  /// reminders are re-registered under the mode the answer allows.
  Future<bool> requestExactAlarmPermission() async {
    try {
      final allowed = await _reminderService.requestExactAlarms();
      await _reconcileReminders();
      notifyListeners();
      return allowed;
    } on Object catch (error) {
      reminderStatusMessage = 'Could not request exact alarms: $error';
      notifyListeners();
      return false;
    }
  }

  /// Posts a notification straight away so delivery can be checked end to end.
  ///
  /// Returns false when the OS would not accept it, which is the answer that
  /// matters: it separates "nothing was scheduled" from "nothing gets through".
  Future<bool> sendTestNotification() async {
    try {
      final delivered = await _reminderService.sendTestNotification();
      reminderStatusMessage = delivered
          ? null
          : 'Could not post a test notification. Check that notifications are '
                'allowed for SuperHealth in Android settings.';
      notifyListeners();
      return delivered;
    } on Object catch (error) {
      reminderStatusMessage = 'Could not post a test notification: $error';
      notifyListeners();
      return false;
    }
  }

  /// Rebuilds the OS notification plan without requesting permission.
  Future<void> refreshReminderStatus() =>
      _withBusy(() async => _reconcileReminders());

  /// Writes a self-contained portable backup to app storage for sharing.
  /// API keys, Microsoft credentials and remote IDs are never included.
  Future<File> exportPortableBackup() {
    return _withBusy(() async {
      final service = _portableBackupService;
      final directoryProvider = _documentsDirectory;
      if (service == null || directoryProvider == null) {
        throw StateError('Portable backup is not available in this build.');
      }
      final source = await service.createJson();
      final base = await directoryProvider();
      final directory = Directory(
        '${base.path}${Platform.pathSeparator}exports',
      );
      await directory.create(recursive: true);
      final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[^0-9]'),
        '',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'superhealth-backup-$timestamp-${repository.newId()}.json',
      );
      await file.writeAsString(source, flush: true);
      return file;
    });
  }

  /// Replaces synchronized health data only after the UI has collected its
  /// explicit destructive confirmations. Device secrets remain untouched.
  Future<void> restorePortableBackup(String source) {
    return _withBusy(() async {
      final service = _portableBackupService;
      if (service == null) {
        throw StateError('Portable backup is not available in this build.');
      }
      // Arm the durable safety gate before changing the database. If device
      // preferences cannot persist it, do not risk producing restored data
      // that could automatically synchronize on the next app launch.
      await _restoreSyncGateStore.requireDecision();
      restoreSyncDecisionPending = true;
      try {
        await service.restoreJson(source, confirmedReplaceCurrentData: true);
      } on Object catch (error, stackTrace) {
        // The restore service validates before replacing rows. If it fails,
        // return to ordinary sync behavior when possible. If local settings
        // cannot clear the gate, keep it visibly and durably fail-closed while
        // preserving the original restore error for the caller.
        try {
          await _restoreSyncGateStore.clearDecision();
          restoreSyncDecisionPending = false;
        } on Object {
          restoreSyncDecisionPending = true;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
      await _initialSetupProgressStore.recordDataRestored();
      await refreshProfiles();
      await _reconcileReminders();
    });
  }

  Future<void> refreshProfiles() async {
    await repository.repairUnsupportedMeasurementConversions();
    profiles = await repository.profiles();
    final preferences = await SharedPreferences.getInstance();
    final preferredId = preferences.getString('active_profile_id');
    if (profiles.isEmpty) {
      activeProfile = null;
      await _clearActiveData();
    } else {
      activeProfile =
          profiles.where((item) => item.id == preferredId).firstOrNull ??
          profiles.first;
      await preferences.setString('active_profile_id', activeProfile!.id);
      await refreshActiveData();
    }
    await refreshInitialSetupProgress(notify: false);
    notifyListeners();
  }

  Future<Profile> createProfile({
    required String name,
    DateTime? dateOfBirth,
    String? sex,
    double? heightCm,
    double? weightKg,
    String notes = '',
  }) async {
    final profile = await repository.createProfile(
      displayName: name,
      dateOfBirth: dateOfBirth,
      sex: sex,
      heightCm: heightCm,
      weightKg: weightKg,
      notes: notes,
    );
    await refreshProfiles();
    await selectProfile(profile.id);
    await _reconcileReminders();
    return profile;
  }

  Future<void> updateProfile(Profile profile) async {
    await repository.saveProfile(
      Profile(
        id: profile.id,
        displayName: profile.displayName.trim(),
        dateOfBirth: profile.dateOfBirth,
        sex: profile.sex,
        heightCm: profile.heightCm,
        weightKg: profile.weightKg,
        notes: profile.notes.trim(),
        createdAt: profile.createdAt,
        updatedAt: DateTime.now(),
        deleted: profile.deleted,
      ),
    );
    await refreshProfiles();
    await _reconcileReminders();
  }

  Future<void> deleteProfile(Profile profile) async {
    if (profiles.length <= 1) {
      throw StateError('Create another profile before deleting this one.');
    }
    await repository.softDelete('profiles', profile.id);
    await refreshProfiles();
    await _reconcileReminders();
  }

  Future<void> selectProfile(String profileId) async {
    final selected = profiles.where((item) => item.id == profileId).firstOrNull;
    if (selected == null) return;
    activeProfile = selected;
    draftLabPlan = null;
    // Another person's conversation id must not survive the switch. Back to
    // unresolved, so the refresh below lands on this profile's most recent.
    _activeConversationId = null;
    advisorMessages = const [];
    correlations = const [];
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('active_profile_id', profileId);
    await refreshActiveData();
    await _reconcileReminders();
    notifyListeners();
  }

  Future<void> refreshActiveData() async {
    final profile = activeProfile;
    if (profile == null) return;
    final values = await Future.wait<Object>([
      repository.supplements(profile.id),
      repository.schedules(profile.id),
      repository.intakes(profile.id),
      repository.inventoryMovements(),
      repository.stockLevels(),
      repository.eventDefinitions(profile.id),
      repository.events(profile.id),
      repository.biomarkers(),
      repository.biomarkerRanges(),
      repository.profileTargets(profile.id),
      repository.measurements(profile.id),
      repository.documents(profile.id),
      repository.namedRecords(profile.id),
      repository.biomarkerLists(profile.id),
      repository.dueBiomarkers(profile.id),
      repository.labPlans(profile.id),
      repository.advisorConversations(profile.id),
      repository.householdSchedules(),
      repository.trendDoseLinks(profile.id),
      repository.biomarkerPackages(),
      repository.biomarkerPackageMembers(),
    ]);
    supplements = values[0] as List<Supplement>;
    schedules = values[1] as List<SupplementSchedule>;
    intakes = values[2] as List<SupplementIntake>;
    inventoryMovements = values[3] as List<InventoryMovement>;
    stockLevels = values[4] as Map<String, double>;
    eventDefinitions = values[5] as List<HealthEventDefinition>;
    events = values[6] as List<HealthEvent>;
    biomarkers = values[7] as List<Biomarker>;
    biomarkerRanges = values[8] as List<BiomarkerReferenceRange>;
    profileTargets = values[9] as List<ProfileBiomarkerTarget>;
    measurements = values[10] as List<Measurement>;
    documents = values[11] as List<HealthDocument>;
    namedRecords = values[12] as List<NamedHealthRecord>;
    biomarkerLists = values[13] as List<BiomarkerList>;
    dueBiomarkers = values[14] as List<DueBiomarker>;
    labPlans = values[15] as List<LabPlan>;
    advisorConversations = values[16] as List<AdvisorConversation>;
    householdSchedules = values[17] as List<SupplementSchedule>;
    trendDoseLinks = values[18] as List<TrendDoseLink>;
    biomarkerPackages = values[19] as List<BiomarkerPackage>;
    biomarkerPackageMembers = values[20] as Map<String, Set<String>>;
    // Resolved before the messages are read, because which conversation to
    // read *is* the question — which is why this one query is sequential
    // rather than part of the batch above.
    _activeConversationId ??=
        advisorConversations.firstOrNull?.id ?? defaultConversationId;
    advisorMessages = await repository.messages(
      profile.id,
      activeConversationId,
    );
    notifyListeners();
  }

  Future<void> _clearActiveData() async {
    supplements = const [];
    schedules = const [];
    householdSchedules = const [];
    biomarkerPackages = const [];
    biomarkerPackageMembers = const {};
    intakes = const [];
    inventoryMovements = const [];
    stockLevels = const {};
    eventDefinitions = const [];
    events = const [];
    biomarkers = await repository.biomarkers();
    biomarkerRanges = await repository.biomarkerRanges();
    profileTargets = const [];
    measurements = const [];
    documents = const [];
    namedRecords = const [];
    biomarkerLists = const [];
    dueBiomarkers = const [];
    labPlans = const [];
    advisorMessages = const [];
    advisorConversations = const [];
    // Unresolved, so nothing points at a conversation belonging to a profile
    // that is no longer active.
    _activeConversationId = null;
    correlations = const [];
    trendDoseLinks = const [];
    draftLabPlan = null;
  }

  /// Records which supplement ingredient is drawn beneath a trend, replacing
  /// any previous choice for that biomarker or definition.
  ///
  /// Passing a null [ingredient] removes the underlay. The unit travels with
  /// the name because the same ingredient logged in IU and in µg are separate
  /// series that must never be combined.
  Future<void> setTrendDoseLink({
    String? biomarkerId,
    String? definitionId,
    DoseTarget? target,
  }) async {
    assert(
      (biomarkerId == null) != (definitionId == null),
      'A dose underlay belongs to exactly one biomarker or definition.',
    );
    final profile = activeProfile;
    if (profile == null) return;
    final existing = trendDoseLinks.firstWhereOrNull(
      (link) => biomarkerId != null
          ? link.biomarkerId == biomarkerId
          : link.definitionId == definitionId,
    );
    if (existing != null) {
      await repository.softDelete('trend_dose_links', existing.id);
    }
    if (target != null) {
      final now = DateTime.now();
      await repository.saveTrendDoseLink(
        TrendDoseLink(
          id: repository.newId(),
          profileId: profile.id,
          biomarkerId: biomarkerId,
          definitionId: definitionId,
          supplementId: target.supplementId,
          ingredientName: target.name,
          ingredientUnit: target.unit,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await refreshActiveData();
  }

  Future<void> addSupplement({
    required String name,
    String brand = '',
    String form = '',
    double? priceEur,
    List<Map<String, Object?>> ingredients = const [],
    int? unitsPerContainer,
    double? initialContainers,
    String stockUnit = 'unit',
    double? lowStockThresholdUnits,
    String bioavailability = '',
    String notes = '',
  }) async {
    final now = DateTime.now();
    final supplement = Supplement(
      id: repository.newId(),
      name: name.trim(),
      brand: brand.trim(),
      form: form.trim(),
      priceEur: priceEur,
      ingredients: ingredients,
      unitsPerContainer: unitsPerContainer,
      containerCount: initialContainers,
      bioavailability: bioavailability.trim(),
      notes: notes.trim(),
      lowStockThresholdUnits: lowStockThresholdUnits,
      stockUnit: stockUnit.trim().isEmpty ? 'unit' : stockUnit.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveSupplement(supplement);
    final initialUnits = unitsPerContainer == null || initialContainers == null
        ? 0.0
        : unitsPerContainer * initialContainers;
    if (initialUnits != 0) {
      await repository.saveInventoryMovement(
        InventoryMovement(
          id: repository.newId(),
          supplementId: supplement.id,
          quantityUnits: initialUnits,
          occurredAt: now,
          reason: 'initial',
          notes: 'Initial stock',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await refreshActiveData();
    await _reconcileReminders();
  }

  Future<void> updateSupplement(Supplement supplement) async {
    await repository.saveSupplement(
      Supplement(
        id: supplement.id,
        name: supplement.name.trim(),
        brand: supplement.brand.trim(),
        form: supplement.form.trim(),
        ingredients: supplement.ingredients,
        unitsPerContainer: supplement.unitsPerContainer,
        containerCount: supplement.containerCount,
        priceEur: supplement.priceEur,
        bioavailability: supplement.bioavailability.trim(),
        notes: supplement.notes.trim(),
        active: supplement.active,
        lowStockAlerts: supplement.lowStockAlerts,
        lowStockThresholdUnits: supplement.lowStockThresholdUnits,
        stockUnit: supplement.stockUnit.trim().isEmpty
            ? 'unit'
            : supplement.stockUnit.trim(),
        sourceId: supplement.sourceId,
        createdAt: supplement.createdAt,
        updatedAt: DateTime.now(),
        deleted: supplement.deleted,
      ),
    );
    await refreshActiveData();
    await _reconcileReminders();
  }

  Future<void> adjustStock({
    required Supplement supplement,
    required double quantityUnits,
    required String reason,
    String notes = '',
    DateTime? occurredAt,
  }) async {
    if (quantityUnits == 0) return;
    final now = DateTime.now();
    await repository.saveInventoryMovement(
      InventoryMovement(
        id: repository.newId(),
        supplementId: supplement.id,
        quantityUnits: quantityUnits,
        occurredAt: occurredAt ?? now,
        reason: reason,
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
    await _reconcileReminders();
  }

  Future<void> deleteSupplement(Supplement supplement) async {
    await repository.deleteSupplementWithSchedules(supplement.id);
    await refreshActiveData();
    await _reconcileReminders();
  }

  Future<void> addSchedule({
    required Supplement supplement,
    required double dose,
    required String unit,
    required String timeOfDay,
    List<String> weekdays = const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ],
    String instructions = '',
    DateTime? startDate,
    DateTime? endDate,
    bool reminderEnabled = false,
  }) async {
    final now = DateTime.now();
    await repository.saveSchedule(
      SupplementSchedule(
        id: repository.newId(),
        profileId: _profileId,
        supplementId: supplement.id,
        dose: dose,
        unit: unit.trim(),
        timeOfDay: timeOfDay.trim(),
        weekdays: weekdays,
        instructions: instructions.trim(),
        startDate: startDate,
        endDate: endDate,
        reminderEnabled: reminderEnabled,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
    await _reconcileReminders();
  }

  Future<void> updateSchedule(SupplementSchedule schedule) async {
    await repository.saveSchedule(
      SupplementSchedule(
        id: schedule.id,
        profileId: schedule.profileId,
        supplementId: schedule.supplementId,
        dose: schedule.dose,
        unit: schedule.unit.trim(),
        timeOfDay: schedule.timeOfDay.trim(),
        weekdays: schedule.weekdays,
        instructions: schedule.instructions.trim(),
        startDate: schedule.startDate,
        endDate: schedule.endDate,
        active: schedule.active,
        reminderEnabled: schedule.reminderEnabled,
        createdAt: schedule.createdAt,
        updatedAt: DateTime.now(),
        deleted: schedule.deleted,
      ),
    );
    await refreshActiveData();
    await _reconcileReminders();
  }

  /// Turns reminders on for every active schedule that does not have one.
  ///
  /// Returns how many were switched on, and how many of those carry a time the
  /// planner cannot read — those record the intent but produce no notification
  /// until the time is corrected, and the schedule row flags them.
  Future<({int enabled, int needingTimeFix})> enableAllScheduleReminders() =>
      _withBusy(() async {
        final pending = householdSchedules
            .where(
              (item) => !item.deleted && item.active && !item.reminderEnabled,
            )
            .toList();
        for (final schedule in pending) {
          await repository.saveSchedule(
            SupplementSchedule(
              id: schedule.id,
              profileId: schedule.profileId,
              supplementId: schedule.supplementId,
              dose: schedule.dose,
              unit: schedule.unit,
              timeOfDay: schedule.timeOfDay,
              weekdays: schedule.weekdays,
              instructions: schedule.instructions,
              startDate: schedule.startDate,
              endDate: schedule.endDate,
              active: schedule.active,
              reminderEnabled: true,
              createdAt: schedule.createdAt,
              updatedAt: DateTime.now(),
              deleted: schedule.deleted,
            ),
          );
        }
        await refreshActiveData();
        await _reconcileReminders();
        return (
          enabled: pending.length,
          needingTimeFix: pending
              .where(
                (item) => !ReminderPlanner.canScheduleReminder(item.timeOfDay),
              )
              .length,
        );
      });

  /// Active schedules whose reminder is on but whose time the planner cannot
  /// read, so no notification is ever produced for them.
  List<SupplementSchedule> get schedulesWithUnreadableReminderTime =>
      householdSchedules
          .where(
            (item) =>
                !item.deleted &&
                item.active &&
                item.reminderEnabled &&
                !ReminderPlanner.canScheduleReminder(item.timeOfDay),
          )
          .toList();

  Future<void> deleteSchedule(SupplementSchedule schedule) async {
    await repository.softDelete('supplement_schedules', schedule.id);
    await refreshActiveData();
    await _reconcileReminders();
  }

  Future<void> logIntake({
    required Supplement supplement,
    required double dose,
    required String unit,
    DateTime? takenAt,
    String notes = '',
    SupplementSchedule? schedule,
    bool skipped = false,
  }) async {
    final now = DateTime.now();
    final intake = SupplementIntake(
      id: repository.newId(),
      profileId: _profileId,
      supplementId: supplement.id,
      scheduleId: schedule?.id,
      takenAt: takenAt ?? now,
      dose: dose,
      unit: unit.trim(),
      skipped: skipped,
      notes: notes.trim(),
      ingredientSnapshot: supplement.ingredients,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveIntake(
      intake,
      inventoryUnits: skipped
          ? null
          : _stockUnitsForDose(supplement, dose, unit),
    );
    await refreshActiveData();
    await _reconcileStockAlerts();
  }

  Future<void> updateIntake(SupplementIntake intake) async {
    final supplement = supplements
        .where((item) => item.id == intake.supplementId)
        .firstOrNull;
    await repository.saveIntake(
      SupplementIntake(
        id: intake.id,
        profileId: intake.profileId,
        supplementId: intake.supplementId,
        scheduleId: intake.scheduleId,
        takenAt: intake.takenAt,
        dose: intake.dose,
        unit: intake.unit.trim(),
        skipped: intake.skipped,
        notes: intake.notes.trim(),
        ingredientSnapshot: intake.ingredientSnapshot,
        createdAt: intake.createdAt,
        updatedAt: DateTime.now(),
        deleted: intake.deleted,
      ),
      inventoryUnits: supplement == null || intake.skipped || intake.deleted
          ? null
          : _stockUnitsForDose(supplement, intake.dose, intake.unit),
    );
    await refreshActiveData();
    await _reconcileStockAlerts();
  }

  Future<void> deleteIntake(SupplementIntake intake) async {
    await updateIntake(
      SupplementIntake(
        id: intake.id,
        profileId: intake.profileId,
        supplementId: intake.supplementId,
        scheduleId: intake.scheduleId,
        takenAt: intake.takenAt,
        dose: intake.dose,
        unit: intake.unit,
        skipped: intake.skipped,
        notes: intake.notes,
        ingredientSnapshot: intake.ingredientSnapshot,
        createdAt: intake.createdAt,
        updatedAt: DateTime.now(),
        deleted: true,
      ),
    );
  }

  Future<void> addEvent({
    required EventKind kind,
    required String name,
    HealthEventDefinition? definition,
    int? score,
    double? value,
    String? unit,
    DateTime? observedAt,
    int? durationMinutes,
    int? colorValue,
    String notes = '',
  }) async {
    final now = DateTime.now();
    var resolvedDefinition = definition;
    resolvedDefinition ??= eventDefinitions.firstWhereOrNull(
      (item) =>
          item.kind == kind &&
          item.name.trim().toLowerCase() == name.trim().toLowerCase(),
    );
    if (resolvedDefinition == null) {
      resolvedDefinition = HealthEventDefinition(
        id: repository.newId(),
        profileId: _profileId,
        kind: kind,
        name: name.trim(),
        defaultUnit: unit?.trim().isEmpty == true ? null : unit?.trim(),
        useScore: score != null,
        colorValue: colorValue,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveEventDefinition(resolvedDefinition);
    }
    await repository.saveEvent(
      HealthEvent(
        id: repository.newId(),
        profileId: _profileId,
        definitionId: resolvedDefinition.id,
        kind: kind,
        name: resolvedDefinition.name,
        observedAt: observedAt ?? now,
        score: score,
        numericValue: value,
        unit: unit?.trim(),
        durationMinutes: durationMinutes,
        colorValue: colorValue ?? resolvedDefinition.colorValue,
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> updateEvent(HealthEvent event) async {
    await repository.saveEvent(
      HealthEvent(
        id: event.id,
        profileId: event.profileId,
        definitionId: event.definitionId,
        kind: event.kind,
        name: event.name.trim(),
        observedAt: event.observedAt,
        score: event.score,
        numericValue: event.numericValue,
        unit: event.unit?.trim(),
        durationMinutes: event.durationMinutes,
        notes: event.notes.trim(),
        colorValue: event.colorValue,
        archived: event.archived,
        createdAt: event.createdAt,
        updatedAt: DateTime.now(),
        deleted: event.deleted,
      ),
    );
    await refreshActiveData();
  }

  Future<void> deleteEvent(HealthEvent event) async {
    await repository.softDelete('health_events', event.id);
    await refreshActiveData();
  }

  Future<void> saveEventDefinition(HealthEventDefinition definition) async {
    await repository.saveEventDefinition(
      HealthEventDefinition(
        id: definition.id,
        profileId: definition.profileId,
        kind: definition.kind,
        name: definition.name.trim(),
        defaultUnit: definition.defaultUnit?.trim(),
        // useScore is redundant with valueMode but kept in sync for anything
        // still reading it; intensity mode is exactly what useScore meant.
        useScore: definition.valueMode == TagValueMode.intensity,
        valueMode: definition.valueMode,
        portionAmount: definition.portionAmount,
        portionLabel: definition.portionLabel?.trim(),
        includeInCheckIn: definition.includeInCheckIn,
        colorValue: definition.colorValue,
        archived: definition.archived,
        createdAt: definition.createdAt,
        updatedAt: DateTime.now(),
        deleted: definition.deleted,
      ),
    );
    await refreshActiveData();
  }

  /// Reinterprets every existing entry for [definition] under a new value
  /// mode, unit, or portion — e.g. converting felt-strength scores to real
  /// amounts, or amounts in an old unit to a new one.
  ///
  /// This is a deliberate, reviewed, one-time rewrite of one definition's
  /// history, mirroring the rename/kind-change cascade already used when
  /// editing a definition. It never touches other definitions' events.
  Future<void> reinterpretEventHistory({
    required HealthEventDefinition definition,
    required double factor,
    required String newUnit,
  }) async {
    final affected = events.where(
      (event) =>
          !event.deleted &&
          event.definitionId == definition.id &&
          (event.score != null || event.numericValue != null) &&
          event.unit?.trim().toLowerCase() != newUnit.trim().toLowerCase(),
    );
    for (final event in affected) {
      final source = event.numericValue ?? event.score!.toDouble();
      await repository.saveEvent(
        HealthEvent(
          id: event.id,
          profileId: event.profileId,
          definitionId: event.definitionId,
          kind: event.kind,
          name: event.name,
          observedAt: event.observedAt,
          score: null,
          numericValue: source * factor,
          unit: newUnit,
          durationMinutes: event.durationMinutes,
          notes: event.notes,
          colorValue: event.colorValue,
          archived: event.archived,
          createdAt: event.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
    }
    await refreshActiveData();
  }

  Future<void> addBiomarker({
    required String name,
    String category = '',
    String unit = '',
    double? priceEur,
    String? labName,
    String description = '',
    List<String> synonyms = const [],
  }) async {
    final now = DateTime.now();
    await repository.saveBiomarker(
      Biomarker(
        id: repository.newId(),
        canonicalName: HealthRepository.normalizeName(name),
        displayName: name.trim(),
        category: category.trim(),
        defaultUnit: unit.trim(),
        priceEur: priceEur,
        labName: labName?.trim(),
        priceCheckedAt: priceEur == null ? null : now,
        description: description.trim(),
        synonyms: synonyms,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> updateBiomarker(Biomarker biomarker) async {
    await repository.saveBiomarker(
      Biomarker(
        id: biomarker.id,
        canonicalName: HealthRepository.normalizeName(biomarker.displayName),
        displayName: biomarker.displayName.trim(),
        category: biomarker.category.trim(),
        defaultUnit: biomarker.defaultUnit.trim(),
        priceEur: biomarker.priceEur,
        labName: biomarker.labName?.trim(),
        priceCheckedAt: biomarker.priceCheckedAt,
        description: biomarker.description.trim(),
        synonyms: biomarker.synonyms,
        isTemporary: biomarker.isTemporary,
        createdAt: biomarker.createdAt,
        updatedAt: DateTime.now(),
        deleted: biomarker.deleted,
      ),
    );
    await refreshActiveData();
  }

  Future<void> deleteBiomarker(Biomarker biomarker) async {
    if (measurements.any((item) => item.biomarkerId == biomarker.id)) {
      throw StateError(
        'This biomarker has measurements. Reassign or delete those results first.',
      );
    }
    await repository.softDelete('biomarkers', biomarker.id);
    await refreshActiveData();
  }

  /// Reads a price page so the owner can see what will be sent before it is.
  Future<String> fetchLabPriceSource(String url) =>
      _labPriceService.fetchSource(Uri.parse(url.trim()));

  /// Asks the pricing model what the catalog should cost. Writes nothing.
  Future<LabPriceProposalSet> proposeLabPrices({
    String? sourceText,
    String? sourceUrl,
    String? instructions,
  }) async {
    final settings = pricingSettings;
    if (settings == null) {
      throw const LabPriceException(
        'Choose a provider and model for price updates in Settings first.',
      );
    }
    return _withBusy(
      () => _labPriceService.propose(
        catalog: biomarkers.where((item) => !item.deleted).toList(),
        packages: biomarkerPackages,
        packageMembers: biomarkerPackageMembers,
        settings: settings,
        sourceText: sourceText,
        sourceUrl: sourceUrl,
        instructions: instructions,
      ),
    );
  }

  /// Applies exactly the proposals given.
  ///
  /// Takes a list rather than re-deriving one, so what was approved on screen
  /// is what gets written. Declining a row leaves its `priceCheckedAt` alone —
  /// declining is not checking.
  Future<int> applyLabPrices(List<LabPriceProposal> approved) =>
      _withBusy(() async {
        if (approved.isEmpty) return 0;
        final byId = {for (final item in biomarkers) item.id: item};
        final packagesById = {
          for (final item in biomarkerPackages) item.id: item,
        };
        final now = DateTime.now();
        var applied = 0;
        for (final proposal in approved) {
          if (proposal.isPackage) {
            final package = packagesById[proposal.targetId];
            if (package == null) continue;
            await repository.saveBiomarkerPackage(
              BiomarkerPackage(
                id: package.id,
                name: package.name,
                priceEur: proposal.newPriceEur,
                labName: proposal.labName.isEmpty
                    ? package.labName
                    : proposal.labName,
                priceCheckedAt: now,
                notes: package.notes,
                createdAt: package.createdAt,
                updatedAt: now,
              ),
              // Membership is not the model's business: it priced the bundle,
              // it did not redefine what is in it.
              biomarkerPackageMembers[package.id] ?? const <String>{},
            );
            applied++;
            continue;
          }
          final biomarker = byId[proposal.targetId];
          if (biomarker == null) continue;
          await repository.saveBiomarker(
            Biomarker(
              id: biomarker.id,
              canonicalName: biomarker.canonicalName,
              displayName: biomarker.displayName,
              category: biomarker.category,
              defaultUnit: biomarker.defaultUnit,
              priceEur: proposal.newPriceEur,
              labName: proposal.labName.isEmpty
                  ? biomarker.labName
                  : proposal.labName,
              priceCheckedAt: now,
              description: biomarker.description,
              synonyms: biomarker.synonyms,
              isTemporary: biomarker.isTemporary,
              createdAt: biomarker.createdAt,
              updatedAt: now,
              deleted: biomarker.deleted,
            ),
          );
          applied++;
        }
        await refreshActiveData();
        return applied;
      });

  /// What a tier costs once packages replace the parts they cover.
  LabPlanCosting costFor(LabPlan plan, LabTier tier) =>
      const LabPlanPricing().cost(
        items: plan.itemsThrough(tier),
        packages: biomarkerPackages,
        membersByPackageId: biomarkerPackageMembers,
      );

  Future<void> saveBiomarkerPackage(
    BiomarkerPackage package,
    Set<String> biomarkerIds,
  ) async {
    await repository.saveBiomarkerPackage(package, biomarkerIds);
    await refreshActiveData();
  }

  /// What the active profile can see. Screens ask this rather than testing
  /// `easyMode` inline, so the mode means the same thing in every corner.
  FeatureVisibility get visibility =>
      FeatureVisibility.forProfile(easyMode: activeProfile?.easyMode ?? true);

  Future<void> setEasyMode(bool enabled) async {
    final profile = activeProfile;
    if (profile == null || profile.easyMode == enabled) return;
    await repository.saveProfile(
      Profile(
        id: profile.id,
        displayName: profile.displayName,
        dateOfBirth: profile.dateOfBirth,
        sex: profile.sex,
        heightCm: profile.heightCm,
        weightKg: profile.weightKg,
        notes: profile.notes,
        easyMode: enabled,
        createdAt: profile.createdAt,
        updatedAt: DateTime.now(),
        deleted: profile.deleted,
      ),
    );
    await refreshProfiles();
    notifyListeners();
  }

  Future<void> deleteBiomarkerPackage(BiomarkerPackage package) async {
    await repository.softDelete('biomarker_packages', package.id);
    await refreshActiveData();
  }

  Future<void> saveBiomarkerRange(BiomarkerReferenceRange range) async {
    await repository.saveBiomarkerRange(range);
    await refreshActiveData();
  }

  Future<void> saveProfileTarget(ProfileBiomarkerTarget target) async {
    final existing = profileTargets.firstWhereOrNull(
      (item) => item.biomarkerId == target.biomarkerId,
    );
    await repository.saveProfileTarget(
      ProfileBiomarkerTarget(
        id: existing?.id ?? target.id,
        profileId: _profileId,
        biomarkerId: target.biomarkerId,
        low: target.low,
        high: target.high,
        borderlineLow: target.borderlineLow,
        borderlineHigh: target.borderlineHigh,
        unit: target.unit.trim(),
        source: target.source.trim(),
        notes: target.notes.trim(),
        createdAt: existing?.createdAt ?? target.createdAt,
        updatedAt: DateTime.now(),
      ),
    );
    await refreshActiveData();
  }

  Future<void> deleteProfileTarget(ProfileBiomarkerTarget target) async {
    await repository.softDelete('profile_biomarker_targets', target.id);
    await refreshActiveData();
  }

  Future<void> addMeasurement({
    required Biomarker biomarker,
    required double value,
    required String unit,
    required DateTime takenAt,
    double? refLow,
    double? refHigh,
    String notes = '',
  }) async {
    final now = DateTime.now();
    await repository.saveMeasurement(
      Measurement(
        id: repository.newId(),
        profileId: _profileId,
        biomarkerId: biomarker.id,
        takenAt: takenAt,
        value: value,
        unit: unit.trim(),
        labRefLow: refLow,
        labRefHigh: refHigh,
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> updateMeasurement(Measurement measurement) async {
    await repository.saveMeasurement(
      Measurement(
        id: measurement.id,
        profileId: measurement.profileId,
        biomarkerId: measurement.biomarkerId,
        documentId: measurement.documentId,
        takenAt: measurement.takenAt,
        value: measurement.value,
        unit: measurement.unit.trim(),
        labRefLow: measurement.labRefLow,
        labRefHigh: measurement.labRefHigh,
        page: measurement.page,
        rowText: measurement.rowText,
        extractionConfidence: measurement.extractionConfidence,
        flags: measurement.flags,
        notes: measurement.notes.trim(),
        createdAt: measurement.createdAt,
        updatedAt: DateTime.now(),
        deleted: measurement.deleted,
      ),
    );
    await refreshActiveData();
  }

  Future<void> deleteMeasurement(Measurement measurement) async {
    await repository.softDelete('measurements', measurement.id);
    await refreshActiveData();
  }

  Future<void> addNamedRecord({
    required String kind,
    required String name,
    String status = 'active',
    double? dose,
    String? unit,
    String? schedule,
    int? priority,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? targetDate,
    String notes = '',
  }) async {
    final now = DateTime.now();
    await repository.saveNamedRecord(
      NamedHealthRecord(
        id: repository.newId(),
        profileId: _profileId,
        name: name.trim(),
        kind: kind,
        status: status,
        dose: dose,
        unit: unit?.trim(),
        schedule: schedule?.trim(),
        priority: priority,
        startDate: startDate,
        endDate: endDate,
        targetDate: targetDate,
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> updateNamedRecord(NamedHealthRecord record) async {
    await repository.saveNamedRecord(
      NamedHealthRecord(
        id: record.id,
        profileId: record.profileId,
        name: record.name.trim(),
        kind: record.kind,
        status: record.status,
        dose: record.dose,
        unit: record.unit?.trim(),
        schedule: record.schedule?.trim(),
        startDate: record.startDate,
        endDate: record.endDate,
        priority: record.priority,
        targetDate: record.targetDate,
        notes: record.notes.trim(),
        createdAt: record.createdAt,
        updatedAt: DateTime.now(),
        deleted: record.deleted,
      ),
    );
    await refreshActiveData();
  }

  Future<void> deleteNamedRecord(NamedHealthRecord record) async {
    await repository.softDelete('named_health_records', record.id);
    await refreshActiveData();
  }

  Future<BiomarkerList> createBiomarkerList({
    required String name,
    String description = '',
  }) async {
    final now = DateTime.now();
    final list = BiomarkerList(
      id: repository.newId(),
      profileId: _profileId,
      name: name.trim(),
      description: description.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveBiomarkerList(list);
    await refreshActiveData();
    return list;
  }

  Future<void> updateBiomarkerList(BiomarkerList list) async {
    await repository.saveBiomarkerList(
      BiomarkerList(
        id: list.id,
        profileId: list.profileId,
        name: list.name.trim(),
        description: list.description.trim(),
        createdAt: list.createdAt,
        updatedAt: DateTime.now(),
        items: list.items,
        deleted: list.deleted,
      ),
    );
    await refreshActiveData();
  }

  Future<void> setBiomarkerListItem({
    required BiomarkerList list,
    required Biomarker biomarker,
    int? dueIntervalDays,
    String notes = '',
  }) async {
    final existing = list.items.firstWhereOrNull(
      (item) => item.biomarkerId == biomarker.id,
    );
    final now = DateTime.now();
    await repository.saveBiomarkerListItem(
      BiomarkerListItem(
        id: existing?.id ?? repository.newId(),
        listId: list.id,
        biomarkerId: biomarker.id,
        dueIntervalDays: dueIntervalDays,
        notes: notes.trim(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  /// Adds every member of [package] to [list], skipping the ones already in it.
  ///
  /// The package is expanded rather than stored as a unit. A list is a recall
  /// schedule and "due" is a per-marker question — ferritin every six months,
  /// TSH every twelve — so collapsing a bundle into one interval would throw
  /// away information the list already holds. The bundle matters at purchase
  /// time, which is where the planner applies it.
  ///
  /// Returns how many were added and how many were already present, because
  /// "nothing happened" and "it was already complete" look identical otherwise.
  Future<({int added, int alreadyPresent})> addPackageToBiomarkerList({
    required BiomarkerList list,
    required BiomarkerPackage package,
    int? dueIntervalDays,
  }) => _withBusy(() async {
    final memberIds = biomarkerPackageMembers[package.id] ?? const <String>{};
    final byId = {for (final item in biomarkers) item.id: item};
    var added = 0;
    var present = 0;
    for (final memberId in memberIds) {
      final biomarker = byId[memberId];
      if (biomarker == null) continue;
      // An existing entry keeps its own interval and notes: the owner set
      // those deliberately, and a bulk add is not the place to overwrite them.
      if (list.items.any((item) => item.biomarkerId == memberId)) {
        present++;
        continue;
      }
      await repository.saveBiomarkerListItem(
        BiomarkerListItem(
          id: repository.newId(),
          listId: list.id,
          biomarkerId: biomarker.id,
          dueIntervalDays: dueIntervalDays,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      added++;
    }
    await refreshActiveData();
    return (added: added, alreadyPresent: present);
  });

  Future<void> removeBiomarkerListItem(BiomarkerListItem item) async {
    await repository.softDelete('biomarker_list_items', item.id);
    await refreshActiveData();
  }

  Future<void> deleteBiomarkerList(BiomarkerList list) async {
    await repository.softDelete('biomarker_lists', list.id);
    for (final item in list.items) {
      await repository.softDelete('biomarker_list_items', item.id);
    }
    await refreshActiveData();
  }

  /// Reads a pasted product label into ingredient rows for review.
  ///
  /// Nothing is written: the rows are handed back so a person can correct them
  /// in the editor and save the product themselves, the same review-before-save
  /// rule the lab-document parser follows.
  Future<ParsedSupplementLabel> parseSupplementLabel({
    required String labelText,
    required int servingSize,
    String stockUnit = 'unit',
  }) {
    final settings = parsingSettings;
    if (settings == null) {
      throw StateError('Configure the lab document parser model first.');
    }
    return _withBusy(
      () => _supplementLabelService.parse(
        labelText: labelText,
        servingSize: servingSize,
        settings: settings,
        stockUnit: stockUnit,
      ),
    );
  }

  Future<void> analyzeCorrelations() async {
    await _withBusy(() async {
      correlations = await _correlationService.analyze(_profileId);
    });
  }

  Future<void> saveApiKey(AiProvider provider, String value) async {
    await keyStore.save(provider, value);
    availableModels.remove(provider);
    await refreshKeyStatus();
  }

  Future<List<AiModelInfo>> loadModels(AiProvider provider) async {
    final key = await keyStore.read(provider);
    if (key == null || key.isEmpty) {
      throw StateError('Add a ${provider.name} API key first.');
    }
    return _withBusy(() async {
      final models = await _clientFactory.create(provider).listModels(key);
      availableModels[provider] = models;
      return models;
    });
  }

  Future<void> saveTaskSettings(AiTask task, AiTaskSettings settings) async {
    final capabilities = capabilityRegistry.forModel(
      settings.provider,
      settings.model,
    );
    if (settings.reasoningLevel != null &&
        !capabilities.reasoningLevels.contains(settings.reasoningLevel)) {
      throw StateError('Unsupported reasoning level for this model.');
    }
    if (settings.webSearch && !capabilities.webSearch) {
      throw StateError('Web search is not documented for this model.');
    }
    if (settings.codeExecution && !capabilities.codeExecution) {
      throw StateError('Code execution is not documented for this model.');
    }
    await _aiSettingsStore.save(task, settings);
    switch (task) {
      case AiTask.pricing:
        pricingSettings = settings;
      case AiTask.advisor:
        advisorSettings = settings;
        // Until the planner is configured in its own right it mirrors the
        // advisor, so changing the advisor must not leave the planner showing
        // a model it is no longer using.
        labPlannerSettings ??= settings;
      case AiTask.labPlanner:
        labPlannerSettings = settings;
      case AiTask.parsing:
        parsingSettings = settings;
    }
    await refreshInitialSetupProgress();
  }

  Future<void> askAdvisor(String question) async {
    final settings = advisorSettings;
    if (settings == null) {
      throw StateError('Configure the advisor model first.');
    }
    await _withBusy(() async {
      // Before the turn, so the file stays bounded without ever trimming the
      // run in progress.
      await _advisorTraceStore?.trim();
      final conversationId = activeConversationId;
      // Visible before the first byte leaves, so the thread shows the question
      // rather than an empty screen with a progress bar over it.
      pendingAdvisorQuestion = question.trim();
      notifyListeners();
      try {
        final turn = await _advisorService.ask(
          profileId: _profileId,
          conversationId: conversationId,
          question: question,
          settings: settings,
          brief: visibility.briefAnswers,
        );
        lastContextBytes = turn.context.byteLength;
        lastContextTokens = turn.context.estimatedTokens;
        lastTokenUsage = turn.usage;
        advisorMessages = await repository.messages(_profileId, conversationId);
        // The first answer in a new conversation is what makes it exist.
        advisorConversations = await repository.advisorConversations(
          _profileId,
        );
      } finally {
        // Cleared either way: on success the stored message replaces it, and on
        // failure the screen puts the question back in the input box.
        pendingAdvisorQuestion = null;
        // However the turn ended — and a failed one is the interesting case —
        // the log now has something new to say about it.
        await refreshAiLogSummaries();
      }
    });
  }

  /// Opens an empty conversation without storing anything.
  ///
  /// Nothing is written until the first question is answered, so backing out
  /// of a fresh conversation leaves no trace — and the list never fills with
  /// empty entries someone has to tidy up.
  void startNewAdvisorConversation() {
    if (advisorMessages.isEmpty &&
        !advisorConversations.any((item) => item.id == activeConversationId)) {
      // Already sitting in an unused one. Handing out a second id would look
      // identical and throw away nothing, so do not pretend anything happened.
      return;
    }
    _activeConversationId = repository.newId();
    advisorMessages = const [];
    notifyListeners();
  }

  /// Puts the active conversation back to unresolved, as a restart would.
  ///
  /// Only a test has any reason to do this — the field is in memory, so the
  /// real path is the process ending.
  @visibleForTesting
  void forgetActiveConversationForTest() => _activeConversationId = null;

  Future<void> openAdvisorConversation(String conversationId) async {
    _activeConversationId = conversationId;
    advisorMessages = await repository.messages(_profileId, conversationId);
    notifyListeners();
  }

  /// Deletes a conversation and lands somewhere sensible.
  ///
  /// Deleting the one being read has to leave the screen on something real, so
  /// it falls back to the most recent survivor and otherwise to an empty new
  /// conversation.
  Future<void> deleteAdvisorConversation(String conversationId) async {
    await repository.deleteAdvisorConversation(_profileId, conversationId);
    advisorConversations = await repository.advisorConversations(_profileId);
    if (activeConversationId == conversationId) {
      final newest = advisorConversations.firstOrNull;
      _activeConversationId = newest?.id ?? repository.newId();
      advisorMessages = newest == null
          ? const []
          : await repository.messages(_profileId, newest.id);
    }
    notifyListeners();
  }

  Future<void> approveWorkspaceProposal(String proposalId) async {
    await _withBusy(() async {
      await workspaceService.applyAfterExplicitApproval(
        proposalId,
        userConfirmed: true,
      );
    });
  }

  void rejectWorkspaceProposal(String proposalId) {
    workspaceService.reject(proposalId);
    notifyListeners();
  }

  /// [notice] is what the ongoing notification says while this runs. It is
  /// required rather than defaulted because the controller cannot resolve the
  /// device locale — under [AppLanguage.system] only the widget tree knows
  /// which language the user is reading, and a silent English fallback is
  /// exactly the untranslated string this app does not allow.
  Future<LabPlanGeneration> generateLabPlan({
    required LongTaskNotice notice,
    DateTime? targetDate,
    String priorities = '',
  }) async {
    // Its own setting. This used to read advisorSettings, so a planner run
    // silently used whatever the advisor was set to — on the most expensive
    // call this app makes, with no way to tell from the screen.
    final settings = labPlannerSettings ?? advisorSettings;
    if (settings == null) {
      throw StateError('Configure the lab planner model first.');
    }
    return _withBusy(() async {
      // Bound the log before the run appends to it, never after — trimming a
      // finished run away is how the evidence for the last failure disappears.
      try {
        await _labPlanTraceStore?.trim();
      } on Object {
        // A log that cannot be tidied must not stop a plan being generated.
      }
      labPlanStartedAt = DateTime.now();
      // Minutes of work on the main isolate. Backgrounding the app does not
      // stop it, but a sleeping device suspends it and a reclaimed process
      // kills it outright — the guard answers both.
      await _longTaskGuard.hold(notice);
      try {
        final result = await _labPlannerService.generate(
          profileId: _profileId,
          settings: settings,
          targetDate: targetDate,
          priorities: priorities,
          onProgress: (update) {
            labPlanStage = update.stage;
            final activity = update.activity;
            if (activity != null) {
              labPlanActivity = activity;
              labPlanActivityAt = DateTime.now();
            } else {
              // A stage change with no activity starts a fresh call, so the
              // previous call's counts must not carry over and look live.
              labPlanActivity = null;
            }
            notifyListeners();
          },
        );
        draftLabPlan = result;
        lastContextBytes = result.context.byteLength;
        lastContextTokens = result.context.estimatedTokens;
        return result;
      } finally {
        // Cleared however this ends. A stage left behind after a failure would
        // leave the screen claiming work that stopped.
        labPlanStage = null;
        labPlanStartedAt = null;
        labPlanActivity = null;
        labPlanActivityAt = null;
        await _longTaskGuard.release();
        // However this ended, the log now has something new to say about it.
        await refreshAiLogSummaries();
      }
    });
  }

  /// Whether a diagnostic log can be produced at all on this build.
  bool aiLogAvailable(AiLogKind kind) => _traceStore(kind) != null;

  /// A one-line account of the most recent recorded runs, per log, for the
  /// settings screen. Absent when nothing has been recorded yet.
  final Map<AiLogKind, String> aiLogSummaries = {};

  String aiLogSummary(AiLogKind kind) => aiLogSummaries[kind] ?? '';

  AiTraceStore? _traceStore(AiLogKind kind) => switch (kind) {
    AiLogKind.labPlanner => _labPlanTraceStore,
    AiLogKind.advisor => _advisorTraceStore,
  };

  Future<void> refreshAiLogSummaries() async {
    for (final kind in AiLogKind.values) {
      await _refreshAiLogSummary(kind);
    }
    notifyListeners();
  }

  Future<void> _refreshAiLogSummary(AiLogKind kind) async {
    final store = _traceStore(kind);
    if (store == null) return;
    try {
      final runs = parseTraceRuns(await store.read());
      if (runs.isEmpty) {
        aiLogSummaries.remove(kind);
        return;
      }
      final newest = runs.first;
      final ended = newest
          .where((entry) => entry['event'] == 'run_end')
          .toList();
      final outcome = ended.isEmpty
          // No run_end means the run never returned — the app was killed, or
          // it is still going. Worth naming, since it is the failure the log
          // exists to catch.
          ? 'did not finish'
          : (ended.last['data'] as Map?)?['success'] == true
          ? 'succeeded'
          : 'failed';
      aiLogSummaries[kind] =
          '${runs.length} run(s) recorded; most recent '
          '$outcome';
    } on Object {
      aiLogSummaries.remove(kind);
    }
  }

  /// The diagnostic log as a readable report, ready to write to a file.
  ///
  /// Contains model responses — which name biomarkers and supplements — so the
  /// caller must present it as health data, not as an anonymous crash dump.
  Future<ExportedFile> exportAiLog(AiLogKind kind) async {
    final store = _traceStore(kind);
    if (store == null) {
      throw StateError('Diagnostics are not available in this build.');
    }
    final report = formatTraceReport(
      await store.read(),
      generatedAt: DateTime.now(),
      title: 'SuperHealth ${kind.logTitle} diagnostic log',
      emptyMessage: 'No ${kind.runNoun} has been recorded yet.',
    );
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return ExportedFile(
      fileName: 'superhealth-${kind.fileSlug}-log-$stamp.txt',
      mimeType: 'text/plain',
      bytes: Uint8List.fromList(utf8.encode(report)),
    );
  }

  Future<void> clearAiLog(AiLogKind kind) async {
    await _traceStore(kind)?.clear();
    aiLogSummaries.remove(kind);
    notifyListeners();
  }

  Future<void> saveDraftLabPlan() async {
    final draft = draftLabPlan;
    if (draft == null) throw StateError('There is no draft plan to save.');
    if (!draft.canSave) {
      throw StateError(
        'This lab-plan draft was not approved by the independent verification.',
      );
    }
    await repository.saveLabPlan(draft.plan);
    draftLabPlan = null;
    await refreshActiveData();
  }

  Future<void> setLabPlanItemChecked(
    LabPlan plan,
    LabPlanItem item,
    bool checked,
  ) => setLabPlanItemsChecked(plan, {item.id}, checked);

  /// Ticks or unticks several planned tests as one edit.
  ///
  /// A package covers many tests at once, and saving the plan once per test
  /// would write the whole plan N times and reload between each — leaving the
  /// list visibly half-toggled while it worked.
  Future<void> setLabPlanItemsChecked(
    LabPlan plan,
    Set<String> itemIds,
    bool checked,
  ) async {
    if (itemIds.isEmpty) return;
    final now = DateTime.now();
    final updatedItems = [
      for (final current in plan.items)
        itemIds.contains(current.id) && current.checked != checked
            ? LabPlanItem(
                id: current.id,
                planId: current.planId,
                biomarkerId: current.biomarkerId,
                biomarkerName: current.biomarkerName,
                tier: current.tier,
                priority: current.priority,
                rationale: current.rationale,
                evidenceClass: current.evidenceClass,
                priceEur: current.priceEur,
                preparation: current.preparation,
                checked: checked,
                createdAt: current.createdAt,
                updatedAt: now,
              )
            : current,
    ];
    await repository.saveLabPlan(
      plan.copyWith(updatedAt: now, items: updatedItems),
    );
    await refreshActiveData();
  }

  Future<void> deleteLabPlan(LabPlan plan) async {
    await repository.softDelete('lab_plans', plan.id);
    for (final item in plan.items) {
      await repository.softDelete('lab_plan_items', item.id);
    }
    await refreshActiveData();
  }

  Future<ParsedLabReport> parseLabPdf({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final settings = parsingSettings;
    if (settings == null) {
      throw StateError('Configure the lab document parser model first.');
    }
    return _withBusy(() async {
      final report = await _documentParsingService.parse(
        profileId: _profileId,
        fileName: fileName,
        pdfBytes: bytes,
        settings: settings,
      );
      pendingLabReport = report;
      return report;
    });
  }

  Future<DocumentSaveResult> saveReviewedLabReport({
    required ParsedLabReport report,
    required List<ParsedMeasurementCandidate> measurements,
    required DateTime reportDate,
    required String reportComment,
  }) async {
    return _withBusy(() async {
      final result = await _documentParsingService.saveAfterExplicitReview(
        report: report,
        reviewedMeasurements: measurements,
        reportDate: reportDate,
        reportComment: reportComment,
        userConfirmed: true,
      );
      pendingLabReport = null;
      await refreshActiveData();
      return result;
    });
  }

  Future<void> updateDocument(HealthDocument document) async {
    await repository.saveDocument(
      HealthDocument(
        id: document.id,
        profileId: document.profileId,
        fileName: document.fileName,
        mimeType: document.mimeType,
        sha256: document.sha256,
        localPath: document.localPath,
        oneDriveItemId: document.oneDriveItemId,
        documentDate: document.documentDate,
        parsedAt: document.parsedAt,
        parserProvider: document.parserProvider,
        parserModel: document.parserModel,
        labName: document.labName?.trim(),
        reportComment: document.reportComment.trim(),
        parseStatus: document.parseStatus,
        warnings: document.warnings,
        errors: document.errors,
        createdAt: document.createdAt,
        updatedAt: DateTime.now(),
        deleted: document.deleted,
      ),
    );
    await refreshActiveData();
  }

  Future<void> deleteDocument(HealthDocument document) async {
    await repository.deleteDocumentWithMeasurements(document.id);
    await refreshActiveData();
  }

  Future<LegacyImportPreview> previewImport(
    List<ImportSourceFile> files,
  ) async {
    return _withBusy(
      () => importService.preview(files, fallbackProfile: activeProfile!),
    );
  }

  Future<LegacyImportResult> commitImport(LegacyImportPreview preview) async {
    return _withBusy(() async {
      final result = await importService.commit(preview);
      await _initialSetupProgressStore.recordLegacyJsonImported();
      await refreshProfiles();
      await _reconcileReminders();
      return result;
    });
  }

  Future<LegacyPdfImportPreview> previewLegacyPdfs(
    List<ImportSourceFile> files,
  ) => _withBusy(() => importService.previewPdfs(files));

  Future<LegacyPdfImportResult> commitLegacyPdfs(
    LegacyPdfImportPreview preview,
  ) {
    return _withBusy(() async {
      final result = await importService.commitPdfs(preview);
      await _initialSetupProgressStore.recordLegacyPdfsAttached();
      await refreshActiveData();
      await refreshInitialSetupProgress();
      return result;
    });
  }

  Future<OneDriveSyncResult> synchronizeOneDrive() async {
    return _withBusy(() async {
      if (await _restoreSyncGateStore.isPending()) {
        restoreSyncDecisionPending = true;
        throw RestoreSyncDecisionRequiredError();
      }
      return _synchronizeOneDriveNormally();
    });
  }

  /// Explicitly resumes the standard conflict-aware sync after a restore.
  ///
  /// The guard is opened only while beginning that sync. Any exception closes
  /// it again, so a transient cloud failure cannot turn into an implicit later
  /// publish or merge.
  Future<OneDriveSyncResult> resumeRestoredDataAndMerge() {
    return _withBusy(() async {
      if (!await _restoreSyncGateStore.isPending()) {
        throw StateError('There is no restored-data sync decision pending.');
      }
      await _restoreSyncGateStore.clearDecision();
      restoreSyncDecisionPending = false;
      try {
        return await _synchronizeOneDriveNormally();
      } on Object {
        await _restoreSyncGateStore.requireDecision();
        restoreSyncDecisionPending = true;
        rethrow;
      }
    });
  }

  /// Explicitly publishes the restored local record without merging the remote
  /// snapshot. The OneDrive service uses ETag preconditions and uploads PDFs
  /// only after the snapshot has been conditionally accepted.
  Future<OneDriveSyncResult> publishRestoredDataToOneDrive() {
    return _withBusy(() async {
      if (!await _restoreSyncGateStore.isPending()) {
        throw StateError('There is no restored-data sync decision pending.');
      }
      restoreSyncDecisionPending = true;
      final result = await oneDriveService.publishRestoredDataAuthoritatively();
      await _restoreSyncGateStore.clearDecision();
      restoreSyncDecisionPending = false;
      await _afterSuccessfulOneDriveSync(result);
      return result;
    });
  }

  /// The shortest gap between two automatic syncs.
  ///
  /// Resuming the app is a frequent event — glancing at a dose and switching
  /// away again can happen a dozen times in an hour — and each sync is a full
  /// snapshot upload. This bounds that cost while still keeping the cloud copy
  /// within an hour of the record in ordinary use.
  static const autoSyncInterval = Duration(minutes: 15);

  /// Synchronizes in the background when the app comes to the foreground.
  ///
  /// Returns whether a sync actually ran. Every guard below is a reason not to
  /// start one: an automatic run must never pre-empt work already in flight,
  /// bypass the post-restore decision, or turn a transient network failure into
  /// a modal error the user did not ask for. Anything it declines is still one
  /// tap away under "Sync now".
  Future<bool> maybeAutoSynchronize() async {
    if (!initialized || busy || _autoSyncInFlight) return false;
    if (initializationError != null || restoreSyncDecisionPending) return false;

    final now = DateTime.now();
    final lastSuccess = lastSuccessfulSyncAt;
    if (lastSuccess != null && now.difference(lastSuccess) < autoSyncInterval) {
      return false;
    }
    // Failures are throttled on their own attempt marker. Without it a phone
    // that cannot reach OneDrive would retry on every single resume, because a
    // failed attempt never advances the success timestamp.
    final lastAttempt = _lastAutoSyncAttempt;
    if (lastAttempt != null && now.difference(lastAttempt) < autoSyncInterval) {
      return false;
    }

    _autoSyncInFlight = true;
    _lastAutoSyncAttempt = now;
    try {
      // Re-read the durable gate rather than trusting the cached flag. A
      // restore performed in this session must stop an automatic sync even if
      // nothing has refreshed the field since.
      if (await _restoreSyncGateStore.isPending()) {
        restoreSyncDecisionPending = true;
        notifyListeners();
        return false;
      }
      if (!await oneDriveService.isStorageConfigured()) return false;
      await _withBusy(_synchronizeOneDriveNormally);
      return true;
    } on Object catch (error) {
      lastAutoSyncError = error.toString();
      notifyListeners();
      return false;
    } finally {
      _autoSyncInFlight = false;
    }
  }

  Future<OneDriveSyncResult> _synchronizeOneDriveNormally() async {
    final result = await oneDriveService.synchronize();
    await _afterSuccessfulOneDriveSync(result);
    return result;
  }

  Future<void> _afterSuccessfulOneDriveSync(OneDriveSyncResult result) async {
    if (result.conflicts == 0) {
      await _initialSetupProgressStore.recordFirstSuccessfulSync();
      // Conflicts mean the run returned before uploading anything, so only a
      // clean run may claim the cloud copy is current.
      final syncedAt = DateTime.now().toUtc();
      await _syncStatusStore.recordSuccessfulSync(syncedAt);
      lastSuccessfulSyncAt = syncedAt;
      lastAutoSyncError = null;
    }
    await refreshProfiles();
    if (result.conflicts == 0 &&
        result.remoteFound &&
        result.appliedRows > 0 &&
        profiles.isNotEmpty) {
      await _initialSetupProgressStore.recordDataRestored();
      await refreshInitialSetupProgress();
    }
    await _reconcileReminders();
  }

  Future<List<SnapshotConflict>> unresolvedSyncConflicts() =>
      oneDriveService.unresolvedSyncConflicts();

  Future<void> resolveSyncConflict({
    required int conflictId,
    required SyncConflictResolution resolution,
  }) {
    return _withBusy(() async {
      await oneDriveService.resolveSyncConflict(
        conflictId: conflictId,
        resolution: resolution,
      );
      await refreshProfiles();
      await _reconcileReminders();
    });
  }

  String get _profileId {
    final profile = activeProfile;
    if (profile == null) throw StateError('Create or select a profile first.');
    return profile.id;
  }

  Future<void> _reconcileReminders() async {
    try {
      reminderPermissionStatus = await _reminderService.initialize();
      final plan = await _reminderService.reconcile(
        profiles: profiles,
        supplements: supplements,
        schedules: householdSchedules,
      );
      scheduledReminderCount = plan.reminders.length;
      omittedReminderOccurrenceCount = plan.omittedOccurrenceCount;
      reminderCoverageThrough = plan.coverageThrough;
      reminderCoverageReason = plan.coverageReason;
      lastLowStockAlertCount = await _reminderService.reconcileLowStockAlerts(
        supplements: supplements,
        stockLevels: stockLevels,
      );
      reminderStatusMessage = switch (reminderPermissionStatus) {
        ReminderPermissionStatus.granted => null,
        ReminderPermissionStatus.denied =>
          'Notification permission is not granted.',
        ReminderPermissionStatus.unsupported =>
          'Dose reminders are currently available on Android only.',
        ReminderPermissionStatus.unknown => 'Notification status is unknown.',
      };
    } on Object catch (error) {
      reminderPermissionStatus = ReminderPermissionStatus.unknown;
      reminderStatusMessage = 'Could not synchronize dose reminders: $error';
    }
  }

  Future<void> _reconcileStockAlerts() async {
    try {
      lastLowStockAlertCount = await _reminderService.reconcileLowStockAlerts(
        supplements: supplements,
        stockLevels: stockLevels,
      );
    } on Object catch (error) {
      reminderStatusMessage = 'Could not synchronize low-stock alerts: $error';
    }
  }

  double? _stockUnitsForDose(
    Supplement supplement,
    double dose,
    String intakeUnit,
  ) {
    String normalized(String value) {
      var result = value.trim().toLowerCase();
      if (result.endsWith('s') && result.length > 1) {
        result = result.substring(0, result.length - 1);
      }
      const discrete = {
        'unit',
        'capsule',
        'tablet',
        'softgel',
        'scoop',
        'drop',
        'packet',
      };
      return discrete.contains(result) ? 'unit' : result;
    }

    final stockUnit = normalized(supplement.stockUnit);
    final doseUnit = normalized(intakeUnit);
    return stockUnit == doseUnit ? dose : null;
  }

  Future<T> _withBusy<T>(Future<T> Function() action) async {
    busy = true;
    notifyListeners();
    try {
      return await action();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_database.close());
    super.dispose();
  }
}
