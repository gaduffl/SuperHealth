import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/advisor_tools.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  const openAi = AiTaskSettings(provider: AiProvider.openai, model: 'gpt-5.6');

  test('a plan made from the digest sends the digest and the tools, and '
      'never the package or a receipt', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client(_compliant);

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    expect(client.calls, 2);
    for (final request in client.requests) {
      expect(request.contextJson, isEmpty);
      expect(request.contextFile, isFalse);
      expect(request.digestText, isNotNull);
      expect(request.systemPrompt, AdvisorService.labPlannerSystemPrompt);
      expect(
        request.tools.map((tool) => tool.name),
        AdvisorToolbox.specs.map((tool) => tool.name),
      );
      expect(
        request.promptCacheKey,
        labPlanDigestCacheKeyFor(fixture.profile.id),
      );
      final schema = jsonEncode(request.jsonSchema);
      expect(schema, isNot(contains('context_receipt')));
      expect(request.userPrompt, isNot(contains('Required context receipt')));
    }
    expect(jsonEncode(client.requests.first.jsonSchema), contains('coverage'));
    // The planner chooses from the catalog, so the digest carries all of it —
    // including a test this person has never had.
    final digest = jsonDecode(client.requests.first.digestText!) as Map;
    final catalog = [
      for (final row in digest['test_catalog'] as List) (row as Map)['id'],
    ];
    expect(catalog, containsAll(['tsh', 'ferritin', 'ldl']));
    expect(result.plan.contextHash, startsWith('digest:'));
    expect(result.context, isNull);
    expect(result.contextBytes, result.digest.byteLength);
    expect(result.verification.approved, isTrue);
  });

  test(
    'the checklist holds every current substance, medicine, condition, '
    'goal, family history entry and finding — and nothing resolved',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final client = _Client(_compliant);

      final result = await _planner(
        fixture,
        client,
      ).generate(profileId: fixture.profile.id, settings: openAi);

      final kinds = {
        for (final entry in result.plan.coverage!) entry.label: entry.kind,
      };
      expect(kinds['Biotin'], 'substance');
      expect(kinds['L-Thyroxin 50'], 'medication');
      expect(kinds['Hashimoto'], 'condition');
      expect(kinds['Mehr Energie'], 'goal');
      expect(kinds['Diabetes (Vater)'], 'family_history');
      expect(kinds.values, contains('finding'));
      expect(kinds.keys, isNot(contains('Alte Gastritis')));
      // Every item was answered, so nothing is left as not considered.
      expect(result.plan.notConsidered, isEmpty);
    },
  );

  test('an optional overdue test needs a verdict; a mandatory one is '
      'enforced instead', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    await fixture.overdueFerritin();

    final optional = _Client(_compliant);
    final relaxed = await _planner(fixture, optional).generate(
      profileId: fixture.profile.id,
      settings: openAi,
      includeOverdueBiomarkers: false,
    );
    expect(
      relaxed.plan.coverage!.map((entry) => entry.id),
      contains('due:ferritin'),
    );

    final mandatory = _Client(
      (request) => _compliant(request, extraTests: const ['ferritin']),
    );
    final strict = await _planner(
      fixture,
      mandatory,
    ).generate(profileId: fixture.profile.id, settings: openAi);
    expect(
      strict.plan.coverage!.map((entry) => entry.id),
      isNot(contains('due:ferritin')),
    );
  });

  test('tools answer from the record while the plan is drafted', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final results = <AgentToolResult>[];
    final client = _Client(
      _compliant,
      beforeAnswer: (handler) async {
        results.addAll(
          await handler(const [
            AgentToolCall(
              id: 'call-1',
              name: 'biomarker_history',
              input: {'biomarker': 'tsh'},
            ),
          ], 1),
        );
      },
    );

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    expect(results, isNotEmpty);
    for (final result in results) {
      expect(result.isError, isFalse);
      expect(result.content, contains('0.3'));
    }
    // Draft and review both looked it up.
    expect(result.toolCalls, 2);
  });

  test('a whole-record plan sends the package and its receipt beside the '
      'digest and the tools', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client(_compliant);

    final result = await _planner(fixture, client).generate(
      profileId: fixture.profile.id,
      settings: openAi,
      wholeRecord: true,
    );

    for (final request in client.requests) {
      expect(request.contextJson, isNotEmpty);
      expect(request.digestText, isNotNull);
      expect(request.tools, isNotEmpty);
      expect(jsonEncode(request.jsonSchema), contains('context_receipt'));
    }
    expect(result.context, isNotNull);
    expect(result.plan.contextHash, result.context!.sha256);
  });

  test(
    'a provider without a tool loop gets the package and no tools',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final client = _Client(_compliant);

      await _planner(fixture, client).generate(
        profileId: fixture.profile.id,
        settings: const AiTaskSettings(
          provider: AiProvider.gemini,
          model: 'gemini-3.1-pro-preview',
        ),
      );

      for (final request in client.requests) {
        expect(request.tools, isEmpty);
        expect(request.contextJson, isNotEmpty);
        expect(request.digestText, isNotNull);
      }
    },
  );

  test('an item the draft leaves out is asked about once, with the same '
      'tools and schema, and the complete answer is kept', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client(
      (request) => request.userPrompt.contains('Your plan did not account')
          ? _compliant(request)
          : _compliant(request, skip: const ['exp:biotin']),
    );

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    expect(client.calls, 3);
    final draft = client.requests[0];
    final followUp = client.requests[1];
    expect(followUp.userPrompt, contains('exp:biotin (Biotin)'));
    expect(followUp.systemPrompt, draft.systemPrompt);
    expect(followUp.jsonSchema, draft.jsonSchema);
    expect(followUp.webSearch, draft.webSearch);
    expect(
      followUp.tools.map((tool) => tool.name),
      draft.tools.map((tool) => tool.name),
    );
    expect(followUp.promptCacheKey, draft.promptCacheKey);
    expect(result.plan.notConsidered, isEmpty);
  });

  test('a follow-up that fails keeps the draft and shows the gap', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client((request) {
      if (request.userPrompt.contains('Your plan did not account')) {
        throw const AiProviderException('Connection dropped.');
      }
      return _compliant(request, skip: const ['exp:biotin']);
    });

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    expect(client.calls, 3);
    expect(result.plan.items, isNotEmpty);
    expect(result.plan.notConsidered.single.id, 'exp:biotin');
    expect(
      result.plan.notConsidered.single.verdict,
      PlanCoverageVerdict.notConsidered,
    );
  });

  test('a follow-up that covers less than the draft is discarded', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client(
      (request) => request.userPrompt.contains('Your plan did not account')
          ? _compliant(request, skip: const ['exp:biotin', 'med:levo'])
          : _compliant(request, skip: const ['exp:biotin']),
    );

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    expect(result.plan.notConsidered.map((entry) => entry.id), ['exp:biotin']);
  });

  test('the reviewer sees every coverage claim, gaps included', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client((request) {
      if (request.userPrompt.contains('Your plan did not account')) {
        throw const AiProviderException('Connection dropped.');
      }
      return _compliant(request, skip: const ['exp:biotin']);
    });

    await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    final review = client.requests.last.userPrompt;
    expect(review, contains('"verdict":"not_considered"'));
    expect(review, contains('"item":"Biotin"'));
    expect(review, contains('"verdict":"not_needed"'));
    expect(review, contains('item marked not_considered'));
  });

  test('a usage limit during the review keeps the finished draft, readable '
      'but unverified', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client((request) {
      if (request.userPrompt.contains('Independently verify')) {
        throw ProviderUsageLimitException(
          resetsAt: DateTime.utc(2026, 10, 3, 14, 30),
        );
      }
      return _compliant(request);
    });

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    expect(client.calls, 2);
    expect(result.plan.items, isNotEmpty);
    expect(result.verification.approved, isFalse);
    expect(result.verification.summary, contains('usage limit'));
    expect(result.verification.blockingIssues.single, contains('Usage limit'));
  });

  test(
    'a review that fails for any other reason still fails the run',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final client = _Client((request) {
        if (request.userPrompt.contains('Independently verify')) {
          throw const AiProviderException('Connection dropped.');
        }
        return _compliant(request);
      });

      await expectLater(
        _planner(
          fixture,
          client,
        ).generate(profileId: fixture.profile.id, settings: openAi),
        throwsA(isA<AiProviderException>()),
      );
    },
  );

  test('coverage survives saving and reloading the plan', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final client = _Client(
      (request) => _compliant(
        request,
        addressed: const {
          'exp:biotin': ['tsh'],
        },
      ),
    );
    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: openAi);

    await fixture.repository.saveLabPlan(result.plan);
    final reloaded = (await fixture.repository.labPlans(
      fixture.profile.id,
    )).single;

    final biotin = reloaded.coverage!.singleWhere(
      (entry) => entry.id == 'exp:biotin',
    );
    expect(biotin.verdict, PlanCoverageVerdict.addressed);
    expect(biotin.biomarkerIds, ['tsh']);
    expect(biotin.kind, 'substance');
    expect(
      reloaded.coverage!.map((entry) => entry.id),
      result.plan.coverage!.map((entry) => entry.id),
    );
  });

  test('an external response without coverage imports with every item not '
      'considered', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final service = _planner(fixture, _Client(_compliant));
    final exported = await service.buildExternalPrompt(
      profileId: fixture.profile.id,
    );
    expect(exported.text, contains('--- BEGIN CLINICAL DIGEST ---'));
    expect(exported.text, contains('"coverage"'));
    final context = exported.context;

    final result = await service.importExternalPlan(
      profileId: fixture.profile.id,
      responseText: jsonEncode({
        'title': 'External plan',
        'planned_for': null,
        'warnings': const <String>[],
        'context_receipt': {
          'sha256': context.sha256,
          'file_sha256': context.fileSha256,
          'record_count': context.recordCount,
          'reviewed_sections': context.sectionNames,
        },
        'tiers': [
          for (final tier in ['core', 'advanced', 'comprehensive'])
            _tier(tier, _testFor(tier)),
        ],
      }),
    );

    expect(result.canSave, isTrue);
    expect(result.plan.coverage, isNotEmpty);
    expect(
      result.plan.coverage!.every(
        (entry) => entry.verdict == PlanCoverageVerdict.notConsidered,
      ),
      isTrue,
    );
  });
}

LabPlannerService _planner(_Fixture fixture, _Client client) =>
    LabPlannerService(
      repository: fixture.repository,
      keyStore: _KeyStore(),
      clientFactory: _Factory(client),
      contextBuilder: HealthContextBuilder(fixture.repository),
    );

/// A model that does what it is told: a valid three-tier plan whose coverage
/// answers every checklist item except [skip], and an approving review.
ProviderResponse _compliant(
  ProviderRequest request, {
  List<String> skip = const [],
  List<String> extraTests = const [],
  Map<String, List<String>> addressed = const {},
}) {
  if (request.userPrompt.contains('Independently verify')) {
    return ProviderResponse(
      text: jsonEncode({
        'approved': true,
        'summary': 'Passt.',
        'blocking_issues': const <String>[],
        'warnings': const <String>[],
        if (request.contextJson.isNotEmpty)
          'context_receipt': _receipt(request),
      }),
      raw: const {},
    );
  }
  final digest = jsonDecode(request.digestText!) as Map<String, Object?>;
  final ids = [
    for (final item in digest['review_checklist']! as List)
      '${(item as Map)['id']}',
  ];
  return ProviderResponse(
    text: jsonEncode({
      'title': 'Plan',
      'planned_for': null,
      'warnings': const <String>[],
      if (request.contextJson.isNotEmpty) 'context_receipt': _receipt(request),
      'tiers': [
        _tier('core', _testFor('core'), extra: extraTests),
        _tier('advanced', _testFor('advanced')),
        _tier('comprehensive', _testFor('comprehensive')),
      ],
      'coverage': [
        for (final id in ids)
          if (!skip.contains(id))
            addressed.containsKey(id)
                ? {
                    'id': id,
                    'verdict': 'addressed',
                    'biomarker_ids': addressed[id],
                    'why': 'Vorbereitung im Plan.',
                  }
                : {
                    'id': id,
                    'verdict': 'not_needed',
                    'biomarker_ids': const <String>[],
                    'why': 'Für diesen Plan nicht nötig.',
                  },
      ],
    }),
    raw: const {},
  );
}

(String, String) _testFor(String tier) => switch (tier) {
  'core' => ('tsh', 'TSH'),
  'advanced' => ('ldl', 'LDL'),
  _ => ('hba1c', 'HbA1c'),
};

Map<String, Object?> _tier(
  String name,
  (String, String) test, {
  List<String> extra = const [],
}) => {
  'tier': name,
  'tradeoff_versus_next': name == 'comprehensive' ? '' : 'Kann warten.',
  'items': [
    for (final (id, display) in [
      test,
      for (final id in extra) (id, id == 'ferritin' ? 'Ferritin' : id),
    ])
      {
        'biomarker_id': id,
        'biomarker_name': display,
        'priority': 1,
        'rationale': 'Für dieses Profil sinnvoll.',
        'evidence_class': 'guideline',
        'preparation': '',
      },
  ],
};

Map<String, Object?> _receipt(ProviderRequest request) {
  final package = jsonDecode(request.contextJson) as Map<String, Object?>;
  final manifest = package['manifest']! as Map<String, Object?>;
  final sections = manifest['sections']! as Map<String, Object?>;
  return {
    'sha256': manifest['context_sha256'],
    'file_sha256': _sha(request.contextJson),
    'record_count': manifest['record_count'],
    'reviewed_sections': sections.keys.toList(),
  };
}

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

class _Fixture {
  _Fixture(this.database, this.repository, this.profile);

  final AppDatabase database;
  final HealthRepository repository;
  final Profile profile;

  /// Biotin taken daily, a TSH drawn after it, a thyroid medicine, current
  /// and resolved conditions, a goal, a family history entry, and a catalog
  /// with tests never measured. Seed values only.
  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Alex');
    final now = DateTime.now();
    for (final (id, name) in const [
      ('tsh', 'TSH'),
      ('ferritin', 'Ferritin'),
      ('ldl', 'LDL'),
      ('hba1c', 'HbA1c'),
    ]) {
      await repository.saveBiomarker(
        Biomarker(
          id: id,
          canonicalName: id,
          displayName: name,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await repository.saveSupplement(
      Supplement(
        id: 'hair',
        name: 'Haut, Haare & Nägel',
        ingredients: const [
          {'name': 'Biotin', 'amount': 10, 'unit': 'mg'},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (var day = 0; day < 10; day++) {
      await repository.saveIntake(
        SupplementIntake(
          id: 'hair-$day',
          profileId: profile.id,
          supplementId: 'hair',
          takenAt: now.subtract(Duration(days: day, hours: 2)),
          dose: 1,
          unit: 'capsule',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await repository.saveMeasurement(
      Measurement(
        id: 'tsh-1',
        profileId: profile.id,
        biomarkerId: 'tsh',
        takenAt: now.subtract(const Duration(days: 2)),
        value: 0.3,
        unit: 'mU/L',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (final (id, kind, name, status) in const [
      ('levo', 'medication', 'L-Thyroxin 50', 'active'),
      ('hashimoto', 'condition', 'Hashimoto', 'active'),
      ('gastritis', 'condition', 'Alte Gastritis', 'resolved'),
      ('energy', 'goal', 'Mehr Energie', 'active'),
      ('father', 'family_history', 'Diabetes (Vater)', 'active'),
    ]) {
      await repository.saveNamedRecord(
        NamedHealthRecord(
          id: id,
          profileId: profile.id,
          name: name,
          kind: kind,
          status: status,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return _Fixture(database, repository, profile);
  }

  /// Ferritin on a yearly list and never measured, so it is due now.
  Future<void> overdueFerritin() async {
    final now = DateTime.now();
    await repository.saveBiomarkerList(
      BiomarkerList(
        id: 'yearly',
        profileId: profile.id,
        name: 'Jährlich',
        dueIntervalDays: 365,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveBiomarkerListItem(
      BiomarkerListItem(
        id: 'yearly-ferritin',
        listId: 'yearly',
        biomarkerId: 'ferritin',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> dispose() async => (await database.database).close();
}

class _Client implements AiProviderClient {
  _Client(this._response, {this.beforeAnswer});

  final ProviderResponse Function(ProviderRequest request) _response;

  /// Runs tool calls through the service's handler before answering, the way
  /// a provider's tool loop would.
  final Future<void> Function(AgentToolHandler handler)? beforeAnswer;
  int calls = 0;
  final List<ProviderRequest> requests = [];

  @override
  AiProvider get provider => AiProvider.openai;

  @override
  Future<List<AiModelInfo>> listModels(String apiKey) async => const [];

  @override
  Future<int?> countContextTokens(
    String apiKey, {
    required String model,
    required String contextJson,
  }) async => null;

  @override
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
    AgentToolHandler? onToolCalls,
  }) async {
    calls++;
    requests.add(request);
    if (beforeAnswer != null && onToolCalls != null) {
      await beforeAnswer!(onToolCalls);
    }
    return _response(request);
  }
}

class _KeyStore extends ApiKeyStore {
  @override
  Future<String?> read(AiProvider provider) async => 'test-key';
}

class _Factory extends AiProviderClientFactory {
  _Factory(this.client) : super(dio: Dio());

  final AiProviderClient client;

  @override
  AiProviderClient create(AiProvider provider) => client;
}
