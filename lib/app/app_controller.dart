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
  List<SupplementSchedule> householdSchedules = const [];
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

  Future<void> updateProfile(Profile profile) async {
    await repository.saveProfile(
      Profile(
        id: profile.id,
        displayName: profile.displayName.trim(),
        dateOfBirth: profile.dateOfBirth,
        sex: profile.sex,
        weightKg: profile.weightKg,
        notes: profile.notes.trim(),
        createdAt: profile.createdAt,
        updatedAt: DateTime.now(),
        deleted: profile.deleted,
      ),
    );
    await refreshProfiles();
  }

  Future<void> deleteProfile(Profile profile) async {
    if (profiles.length <= 1) {
      throw StateError('Create another profile before deleting this one.');
    }
    await repository.softDelete('profiles', profile.id);
    await refreshProfiles();
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
      repository.messages(profile.id, 'primary'),
      repository.householdSchedules(),
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
    advisorMessages = values[16] as List<AdvisorMessage>;
    householdSchedules = values[17] as List<SupplementSchedule>;
    notifyListeners();
  }

  Future<void> _clearActiveData() async {
    supplements = const [];
    schedules = const [];
    householdSchedules = const [];
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
    correlations = const [];
    draftLabPlan = null;
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
  }

  Future<void> deleteSupplement(Supplement supplement) async {
    await repository.softDelete('supplements', supplement.id);
    for (final schedule in schedules.where(
      (item) => item.supplementId == supplement.id,
    )) {
      await repository.softDelete('supplement_schedules', schedule.id);
    }
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
  }

  Future<void> deleteSchedule(SupplementSchedule schedule) async {
    await repository.softDelete('supplement_schedules', schedule.id);
    await refreshActiveData();
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
        useScore: definition.useScore,
        colorValue: definition.colorValue,
        archived: definition.archived,
        createdAt: definition.createdAt,
        updatedAt: DateTime.now(),
        deleted: definition.deleted,
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

  Future<void> setLabPlanItemChecked(
    LabPlan plan,
    LabPlanItem item,
    bool checked,
  ) async {
    final now = DateTime.now();
    final updatedItems = [
      for (final current in plan.items)
        current.id == item.id
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
      LabPlan(
        id: plan.id,
        profileId: plan.profileId,
        title: plan.title,
        createdAt: plan.createdAt,
        updatedAt: now,
        plannedFor: plan.plannedFor,
        currency: plan.currency,
        contextHash: plan.contextHash,
        provider: plan.provider,
        model: plan.model,
        status: plan.status,
        items: updatedItems,
      ),
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
