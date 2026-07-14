// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import '../data/health_repository.dart';
import '../domain/entities.dart';
import 'advisor_service.dart';
import 'ai_models.dart';
import 'ai_settings.dart';
import 'api_key_store.dart';
import 'health_context_builder.dart';
import 'provider_clients.dart';

class LabPlanGeneration {
  const LabPlanGeneration({
    required this.plan,
    required this.context,
    required this.warnings,
    required this.citations,
  });

  final LabPlan plan;
  final HealthContextEnvelope context;
  final List<String> warnings;
  final List<String> citations;
}

class LabPlanFormatException implements Exception {
  const LabPlanFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LabPlannerService {
  LabPlannerService({
    required HealthRepository repository,
    required ApiKeyStore keyStore,
    required AiProviderClientFactory clientFactory,
    required HealthContextBuilder contextBuilder,
    ProviderCapabilityRegistry? capabilities,
  }) : _repository = repository,
       _keyStore = keyStore,
       _clientFactory = clientFactory,
       _contextBuilder = contextBuilder,
       _capabilities = capabilities ?? ProviderCapabilityRegistry();

  final HealthRepository _repository;
  final ApiKeyStore _keyStore;
  final AiProviderClientFactory _clientFactory;
  final HealthContextBuilder _contextBuilder;
  final ProviderCapabilityRegistry _capabilities;

  static const _schemaInstructions = '''
Return exactly one JSON object and no markdown. Use this shape:
{
  "title": "string",
  "planned_for": "YYYY-MM-DD or null",
  "warnings": ["string"],
  "tiers": [
    {"tier":"core","items":[ITEM...]},
    {"tier":"advanced","items":[ITEM...]},
    {"tier":"comprehensive","items":[ITEM...]}
  ]
}
ITEM is {"biomarker_id":"exact catalog id","biomarker_name":"exact catalog display name","priority":1,"rationale":"profile-specific concise rationale","evidence_class":"guideline|longevity|experimental|unclassified","preparation":"concise preparation/timing note"}.

Each biomarker must appear exactly once, in the first tier where it is added. The app makes tiers cumulative: Advanced includes Core, and Comprehensive includes both. Use only biomarkers present in biomarker_catalog. Never invent prices or identifiers; the app resolves prices from the catalog. Put the highest-value, most actionable checks in Core. Include meaningful additions in all three tiers. Account for existing results, result age, conditions, medicines, supplements, goals, symptoms, and duplicate/redundant tests. This is a draft checklist, not a diagnosis.
''';

  Future<LabPlanGeneration> generate({
    required String profileId,
    required AiTaskSettings settings,
    DateTime? targetDate,
    String priorities = '',
  }) async {
    final key = await _keyStore.read(settings.provider);
    if (key == null || key.trim().isEmpty) {
      throw StateError(
        'Add a ${settings.provider.name} API key in Settings first.',
      );
    }
    final context = await _contextBuilder.build(profileId);
    const maxOutputTokens = 12000;
    _contextBuilder.ensureFits(
      context: context,
      capabilities: _capabilities.forModel(settings.provider, settings.model),
      maxOutputTokens: maxOutputTokens,
    );
    final dateText =
        targetDate?.toIso8601String().split('T').first ?? 'not set';
    final userPrompt =
        '''
Create a three-tier German lab visit checklist for this profile.
Target date: $dateText
User priorities: ${priorities.trim().isEmpty ? 'Use the stored goals and health context.' : priorities.trim()}

$_schemaInstructions
''';
    final client = _clientFactory.create(settings.provider);
    var response = await client.respond(
      key,
      ProviderRequest(
        model: settings.model,
        systemPrompt: AdvisorService.systemPrompt,
        userPrompt: userPrompt,
        contextJson: context.json,
        reasoningLevel: settings.reasoningLevel,
        webSearch: settings.webSearch,
        codeExecution: settings.codeExecution,
        maxOutputTokens: maxOutputTokens,
        requireJson: true,
      ),
    );

    try {
      return await _parse(
        response,
        profileId: profileId,
        settings: settings,
        context: context,
        targetDate: targetDate,
      );
    } on LabPlanFormatException catch (firstError) {
      response = await client.respond(
        key,
        ProviderRequest(
          model: settings.model,
          systemPrompt: AdvisorService.systemPrompt,
          userPrompt:
              'Repair the prior lab-plan response. Validation failed: '
              '${firstError.message}\n\nPrior response:\n${response.text}\n\n'
              '$_schemaInstructions',
          contextJson: context.json,
          reasoningLevel: settings.reasoningLevel,
          webSearch: false,
          codeExecution: false,
          maxOutputTokens: maxOutputTokens,
          requireJson: true,
        ),
      );
      return _parse(
        response,
        profileId: profileId,
        settings: settings,
        context: context,
        targetDate: targetDate,
      );
    }
  }

  Future<LabPlanGeneration> _parse(
    ProviderResponse response, {
    required String profileId,
    required AiTaskSettings settings,
    required HealthContextEnvelope context,
    required DateTime? targetDate,
  }) async {
    final decoded = _decodeObject(response.text);
    final tiers = decoded['tiers'];
    if (tiers is! List) {
      throw const LabPlanFormatException('The tiers array is missing.');
    }
    final biomarkerCatalog = await _repository.biomarkers();
    final byId = {for (final item in biomarkerCatalog) item.id: item};
    final byName = <String, Biomarker>{};
    for (final item in biomarkerCatalog) {
      byName[HealthRepository.normalizeName(item.displayName)] = item;
      byName[item.canonicalName] = item;
      for (final synonym in item.synonyms) {
        byName[HealthRepository.normalizeName(synonym)] = item;
      }
    }

    final planId = _repository.newId();
    final items = <LabPlanItem>[];
    final seen = <String>{};
    final presentTiers = <LabTier>{};
    for (final rawTier in tiers.whereType<Map>()) {
      final tierName = rawTier['tier']?.toString();
      final tier = LabTier.values.where((item) => item.name == tierName);
      if (tier.isEmpty) {
        throw LabPlanFormatException('Unknown tier “$tierName”.');
      }
      if (!presentTiers.add(tier.first)) {
        throw LabPlanFormatException(
          'Tier “$tierName” appears more than once.',
        );
      }
      final rawItems = rawTier['items'];
      if (rawItems is! List || rawItems.isEmpty) {
        throw LabPlanFormatException(
          'Tier “$tierName” must add at least one item.',
        );
      }
      for (final raw in rawItems.whereType<Map>()) {
        final requestedId = raw['biomarker_id']?.toString();
        final requestedName = raw['biomarker_name']?.toString() ?? '';
        final biomarker =
            byId[requestedId] ??
            byName[HealthRepository.normalizeName(requestedName)];
        if (biomarker == null) {
          throw LabPlanFormatException(
            '“${requestedName.isEmpty ? requestedId : requestedName}” is not in the catalog.',
          );
        }
        if (!seen.add(biomarker.id)) {
          throw LabPlanFormatException(
            'Biomarker “${biomarker.displayName}” appears more than once.',
          );
        }
        final evidenceName = raw['evidence_class']?.toString() ?? '';
        final evidence = EvidenceClass.values.where(
          (item) => item.name == evidenceName,
        );
        if (evidence.isEmpty) {
          throw LabPlanFormatException(
            'Invalid evidence class for ${biomarker.displayName}.',
          );
        }
        final rationale = raw['rationale']?.toString().trim() ?? '';
        if (rationale.isEmpty) {
          throw LabPlanFormatException(
            'Missing rationale for ${biomarker.displayName}.',
          );
        }
        items.add(
          LabPlanItem(
            id: _repository.newId(),
            planId: planId,
            biomarkerId: biomarker.id,
            biomarkerName: biomarker.displayName,
            tier: tier.first,
            priority: (raw['priority'] as num?)?.toInt() ?? items.length + 1,
            rationale: rationale,
            evidenceClass: evidence.first,
            priceEur: biomarker.priceEur,
            preparation: raw['preparation']?.toString().trim() ?? '',
          ),
        );
      }
    }
    if (presentTiers.length != LabTier.values.length) {
      throw const LabPlanFormatException(
        'Core, advanced, and comprehensive tiers are all required.',
      );
    }
    items.sort((a, b) {
      final tierCompare = a.tier.index.compareTo(b.tier.index);
      return tierCompare != 0 ? tierCompare : a.priority.compareTo(b.priority);
    });

    final parsedDate = DateTime.tryParse(
      decoded['planned_for']?.toString() ?? '',
    );
    final now = DateTime.now();
    final plan = LabPlan(
      id: planId,
      profileId: profileId,
      title: decoded['title']?.toString().trim().isNotEmpty == true
          ? decoded['title'].toString().trim()
          : 'Lab visit plan',
      createdAt: now,
      updatedAt: now,
      plannedFor: targetDate ?? parsedDate,
      contextHash: context.sha256,
      provider: settings.provider.name,
      model: settings.model,
      items: items,
    );
    final rawWarnings = decoded['warnings'];
    final warnings = rawWarnings is List
        ? rawWarnings.map((item) => item.toString()).toList(growable: false)
        : const <String>[];
    return LabPlanGeneration(
      plan: plan,
      context: context,
      warnings: warnings,
      citations: response.citations,
    );
  }

  Map<String, Object?> _decodeObject(String text) {
    var candidate = text.trim();
    if (candidate.startsWith('```')) {
      candidate = candidate
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    try {
      final value = jsonDecode(candidate);
      if (value is Map) return Map<String, Object?>.from(value);
    } on FormatException {
      final start = candidate.indexOf('{');
      final end = candidate.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          final value = jsonDecode(candidate.substring(start, end + 1));
          if (value is Map) return Map<String, Object?>.from(value);
        } on FormatException {
          // The consistent validation error below is more useful to the model.
        }
      }
    }
    throw const LabPlanFormatException('Response is not a valid JSON object.');
  }
}
