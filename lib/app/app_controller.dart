// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai/advisor_service.dart';
import '../ai/ai_models.dart';
import '../ai/ai_settings.dart';
import '../ai/api_key_store.dart';
import '../ai/document_parsing_service.dart';
import '../ai/lab_planner_service.dart';
import '../ai/provider_clients.dart';
import '../analysis/correlation_service.dart';
import '../data/app_database.dart';
import '../data/health_repository.dart';
import '../domain/entities.dart';
import '../export/lab_plan_export_service.dart';
import '../import/legacy_import_service.dart';
import '../sync/one_drive_service.dart';
import '../workspace/safe_workspace_service.dart';

class AppController extends ChangeNotifier {
  AppController({
    required AppDatabase database,
    required HealthRepository repository,
    required ApiKeyStore keyStore,
    required AiSettingsStore aiSettingsStore,
    required AdvisorService advisorService,
    required LabPlannerService labPlannerService,
    required DocumentParsingService documentParsingService,
    required CorrelationService correlationService,
    required LegacyImportService importService,
    required OneDriveService oneDriveService,
    required SafeWorkspaceService workspaceService,
    required LabPlanExportService exportService,
    required AiProviderClientFactory clientFactory,
    ProviderCapabilityRegistry? capabilityRegistry,
  }) : _database = database,
       repository = repository,
       keyStore = keyStore,
       _aiSettingsStore = aiSettingsStore,
       _advisorService = advisorService,
       _labPlannerService = labPlannerService,
       _documentParsingService = documentParsingService,
       _correlationService = correlationService,
       importService = importService,
       oneDriveService = oneDriveService,
       workspaceService = workspaceService,
       exportService = exportService,
       _clientFactory = clientFactory,
       capabilityRegistry = capabilityRegistry ?? ProviderCapabilityRegistry();

  final AppDatabase _database;
  final HealthRepository repository;
  final ApiKeyStore keyStore;
  final AiSettingsStore _aiSettingsStore;
  final AdvisorService _advisorService;
  final LabPlannerService _labPlannerService;
  final DocumentParsingService _documentParsingService;
  final CorrelationService _correlationService;
  final LegacyImportService importService;
  final OneDriveService oneDriveService;
  final SafeWorkspaceService workspaceService;
  final LabPlanExportService exportService;
  final AiProviderClientFactory _clientFactory;
  final ProviderCapabilityRegistry capabilityRegistry;

  bool initialized = false;
  bool busy = false;
  String? initializationError;
  Profile? activeProfile;
  List<Profile> profiles = const [];
  List<Supplement> supplements = const [];
  List<SupplementSchedule> schedules = const [];
  List<SupplementIntake> intakes = const [];
  List<HealthEvent> events = const [];
  List<Biomarker> biomarkers = const [];
  List<Measurement> measurements = const [];
  List<HealthDocument> documents = const [];
  List<NamedHealthRecord> namedRecords = const [];
  List<LabPlan> labPlans = const [];
  List<AdvisorMessage> advisorMessages = const [];
  List<CorrelationResult> correlations = const [];
  LabPlanGeneration? draftLabPlan;
  ParsedLabReport? pendingLabReport;
  int? lastContextBytes;
  int? lastContextTokens;
  AiTaskSettings? advisorSettings;
  AiTaskSettings? parsingSettings;
  final Map<AiProvider, bool> hasApiKey = {};
  final Map<AiProvider, List<AiModelInfo>> availableModels = {};

  List<WorkspaceProposal> get workspaceProposals => workspaceService.pending
      .where((item) => item.profileId == activeProfile?.id)
      .toList(growable: false);

  Future<void> initialize() async {
    try {
      advisorSettings = await _aiSettingsStore.load(AiTask.advisor);
      parsingSettings = await _aiSettingsStore.load(AiTask.parsing);
      await refreshKeyStatus();
      await refreshProfiles();
    } on Object catch (error) {
      initializationError = error.toString();
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> refreshKeyStatus() async {
    for (final provider in AiProvider.values) {
      hasApiKey[provider] = await keyStore.hasKey(provider);
    }
    notifyListeners();
  }

  Future<void> refreshProfiles() async {
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
    notifyListeners();
  }

  Future<Profile> createProfile({
    required String name,
    DateTime? dateOfBirth,
    String? sex,
    double? weightKg,
    String notes = '',
  }) async {
    final profile = await repository.createProfile(
      displayName: name,
      dateOfBirth: dateOfBirth,
      sex: sex,
      weightKg: weightKg,
      notes: notes,
    );
    await refreshProfiles();
    await selectProfile(profile.id);
    return profile;
  }

  Future<void> selectProfile(String profileId) async {
    final selected = profiles.where((item) => item.id == profileId).firstOrNull;
    if (selected == null) return;
    activeProfile = selected;
    draftLabPlan = null;
    correlations = const [];
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('active_profile_id', profileId);
    await refreshActiveData();
    notifyListeners();
  }

  Future<void> refreshActiveData() async {
    final profile = activeProfile;
    if (profile == null) return;
    final values = await Future.wait<Object>([
      repository.supplements(profile.id),
      repository.schedules(profile.id),
      repository.intakes(profile.id),
      repository.events(profile.id),
      repository.biomarkers(),
      repository.measurements(profile.id),
      repository.documents(profile.id),
      repository.namedRecords(profile.id),
      repository.labPlans(profile.id),
      repository.messages(profile.id, 'primary'),
    ]);
    supplements = values[0] as List<Supplement>;
    schedules = values[1] as List<SupplementSchedule>;
    intakes = values[2] as List<SupplementIntake>;
    events = values[3] as List<HealthEvent>;
    biomarkers = values[4] as List<Biomarker>;
    measurements = values[5] as List<Measurement>;
    documents = values[6] as List<HealthDocument>;
    namedRecords = values[7] as List<NamedHealthRecord>;
    labPlans = values[8] as List<LabPlan>;
    advisorMessages = values[9] as List<AdvisorMessage>;
    notifyListeners();
  }

  Future<void> _clearActiveData() async {
    supplements = const [];
    schedules = const [];
    intakes = const [];
    events = const [];
    biomarkers = await repository.biomarkers();
    measurements = const [];
    documents = const [];
    namedRecords = const [];
    labPlans = const [];
    advisorMessages = const [];
    correlations = const [];
    draftLabPlan = null;
  }

  Future<void> addSupplement({
    required String name,
    String brand = '',
    String form = '',
    double? priceEur,
    List<Map<String, Object?>> ingredients = const [],
  }) async {
    final profileId = _profileId;
    final now = DateTime.now();
    await repository.saveSupplement(
      Supplement(
        id: repository.newId(),
        profileId: profileId,
        name: name.trim(),
        brand: brand.trim(),
        form: form.trim(),
        priceEur: priceEur,
        ingredients: ingredients,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
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
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> logIntake({
    required Supplement supplement,
    required double dose,
    required String unit,
    DateTime? takenAt,
    String notes = '',
  }) async {
    final now = DateTime.now();
    await repository.saveIntake(
      SupplementIntake(
        id: repository.newId(),
        profileId: _profileId,
        supplementId: supplement.id,
        takenAt: takenAt ?? now,
        dose: dose,
        unit: unit.trim(),
        notes: notes.trim(),
        ingredientSnapshot: supplement.ingredients,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> addEvent({
    required EventKind kind,
    required String name,
    int? score,
    double? value,
    String? unit,
    DateTime? observedAt,
    String notes = '',
  }) async {
    final now = DateTime.now();
    await repository.saveEvent(
      HealthEvent(
        id: repository.newId(),
        profileId: _profileId,
        kind: kind,
        name: name.trim(),
        observedAt: observedAt ?? now,
        score: score,
        numericValue: value,
        unit: unit?.trim(),
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
  }

  Future<void> addBiomarker({
    required String name,
    String category = '',
    String unit = '',
    double? priceEur,
    String? labName,
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
        createdAt: now,
        updatedAt: now,
      ),
    );
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

  Future<void> addNamedRecord({
    required String kind,
    required String name,
    String status = 'active',
    double? dose,
    String? unit,
    String? schedule,
    int? priority,
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
        notes: notes.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
    await refreshActiveData();
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
    if (task == AiTask.advisor) {
      advisorSettings = settings;
    } else {
      parsingSettings = settings;
    }
    notifyListeners();
  }

  Future<void> askAdvisor(String question) async {
    final settings = advisorSettings;
    if (settings == null) {
      throw StateError('Configure the advisor model first.');
    }
    await _withBusy(() async {
      final turn = await _advisorService.ask(
        profileId: _profileId,
        conversationId: 'primary',
        question: question,
        settings: settings,
      );
      lastContextBytes = turn.context.byteLength;
      lastContextTokens = turn.context.estimatedTokens;
      advisorMessages = await repository.messages(_profileId, 'primary');
    });
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

  Future<LabPlanGeneration> generateLabPlan({
    DateTime? targetDate,
    String priorities = '',
  }) async {
    final settings = advisorSettings;
    if (settings == null) {
      throw StateError('Configure the advisor model first.');
    }
    return _withBusy(() async {
      final result = await _labPlannerService.generate(
        profileId: _profileId,
        settings: settings,
        targetDate: targetDate,
        priorities: priorities,
      );
      draftLabPlan = result;
      lastContextBytes = result.context.byteLength;
      lastContextTokens = result.context.estimatedTokens;
      return result;
    });
  }

  Future<void> saveDraftLabPlan() async {
    final draft = draftLabPlan;
    if (draft == null) throw StateError('There is no draft plan to save.');
    await repository.saveLabPlan(draft.plan);
    draftLabPlan = null;
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
      await refreshProfiles();
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
      await refreshActiveData();
      return result;
    });
  }

  Future<OneDriveSyncResult> synchronizeOneDrive() async {
    return _withBusy(() async {
      final result = await oneDriveService.synchronize();
      await refreshProfiles();
      return result;
    });
  }

  String get _profileId {
    final profile = activeProfile;
    if (profile == null) throw StateError('Create or select a profile first.');
    return profile.id;
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
