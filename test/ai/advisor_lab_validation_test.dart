import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/ai/advisor_service.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/ai_settings.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/document_parsing_service.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/ai/lab_price_service.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/app/app_controller.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';
import 'package:super_health/import/legacy_import_service.dart';
import 'package:super_health/sync/one_drive_service.dart';
import 'package:super_health/sync/snapshot_service.dart';
import 'package:super_health/workspace/safe_workspace_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'stages one delete proposal and removes its block from advisor output',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final workspace = _Workspace();
      final service = AdvisorService(
        repository: fixture.repository,
        keyStore: _KeyStore(),
        clientFactory: _Factory(
          _Client(
            (request) => ProviderResponse(
              text:
                  '${_coverage(request)}\nVisible answer.\n'
                  '```superhealth-file-proposal\n'
                  '{"operation":"delete","path":"notes.txt","summary":"remove stale note"}\n'
                  '```',
              raw: const {},
            ),
          ),
        ),
        contextBuilder: HealthContextBuilder(fixture.repository),
        workspaceService: workspace,
      );

      final turn = await service.ask(
        profileId: fixture.profile.id,
        conversationId: 'primary',
        question: 'Please clean this up.',
        settings: _settings,
      );

      expect(workspace.deleteCalls, 1);
      expect(turn.fileProposals, hasLength(1));
      expect(turn.assistantMessage.content, 'Visible answer.');
      expect(
        turn.assistantMessage.content,
        isNot(contains('superhealth-file-proposal')),
      );
    },
  );

  test(
    'advisor rejects non-integer coverage record counts after one repair',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      for (final invalid in [1.2, -1, true, '1']) {
        final client = _Client(
          (request) => ProviderResponse(
            text: _coverage(request, recordCount: invalid),
            raw: const {},
          ),
        );
        final service = AdvisorService(
          repository: fixture.repository,
          keyStore: _KeyStore(),
          clientFactory: _Factory(client),
          contextBuilder: HealthContextBuilder(fixture.repository),
        );
        await expectLater(
          service.ask(
            profileId: fixture.profile.id,
            conversationId: 'coverage-$invalid',
            question: 'Check coverage.',
            settings: _settings,
          ),
          throwsA(isA<AdvisorCoverageException>()),
        );
        expect(client.calls, 2);
      }
    },
  );

  test('lab planner accepts a valid exact catalog plan', () async {
    final fixture = await _Fixture.create(withBiomarker: true);
    addTearDown(fixture.dispose);
    final client = _Client(_validLabResponse);
    final service = _planner(fixture, client);

    final result = await service.generate(
      profileId: fixture.profile.id,
      settings: _settings,
    );

    expect(result.plan.items, hasLength(3));
    expect(result.plan.items.map((item) => item.biomarkerId).toSet(), {
      'bio-1',
      'bio-2',
      'bio-3',
    });
    expect(result.verification.approved, isTrue);
    expect(result.canSave, isTrue);
    expect(result.plan.status, 'verified');
    expect(result.plan.verificationSummary, isNotEmpty);
    expect(result.plan.verifiedAt, isNotNull);
    expect(client.calls, 2);
    expect(client.requests[1].contextJson, client.requests[0].contextJson);
    expect(client.requests[1].contextFile, client.requests[0].contextFile);
    expect(
      client.requests[1].contextFileSha256,
      client.requests[0].contextFileSha256,
    );
  });

  test(
    'lab planner retains a rejected draft but does not approve saving',
    () async {
      final fixture = await _Fixture.create(withBiomarker: true);
      addTearDown(fixture.dispose);
      final client = _Client(
        (request) => ProviderResponse(
          text: jsonEncode(
            request.userPrompt.contains('Independently verify')
                ? _verificationBody(
                    request,
                    approved: false,
                    blockingIssues: const [
                      'Review the current medication first.',
                    ],
                  )
                : _labBody(
                    request,
                    warnings: const ['Candidate caveat for the reviewer.'],
                  ),
          ),
          raw: const {},
        ),
      );

      final result = await _planner(
        fixture,
        client,
      ).generate(profileId: fixture.profile.id, settings: _settings);

      expect(result.verification.approved, isFalse);
      expect(result.verification.blockingIssues, isNotEmpty);
      expect(result.canSave, isFalse);
      expect(result.plan.status, 'draft');
      expect(client.calls, 2);
      expect(
        client.requests[1].userPrompt,
        contains('Candidate caveat for the reviewer.'),
      );
    },
  );

  test(
    'lab planner fails closed when a rejected verification has no issue',
    () async {
      final fixture = await _Fixture.create(withBiomarker: true);
      addTearDown(fixture.dispose);
      final client = _Client(
        (request) => ProviderResponse(
          text: jsonEncode(
            request.userPrompt.contains('Independently verify')
                ? _verificationBody(request, approved: false)
                : _labBody(request),
          ),
          raw: const {},
        ),
      );

      final result = await _planner(
        fixture,
        client,
      ).generate(profileId: fixture.profile.id, settings: _settings);

      expect(result.verification.approved, isFalse);
      expect(result.canSave, isFalse);
      expect(result.plan.items, isNotEmpty);
      expect(client.calls, 2);
    },
  );

  test(
    'an unreadable verification blocks the save but keeps the draft',
    () async {
      final fixture = await _Fixture.create(withBiomarker: true);
      addTearDown(fixture.dispose);
      final client = _Client(
        (request) => ProviderResponse(
          text: request.userPrompt.contains('Independently verify')
              ? '{"approved":true}'
              : jsonEncode(_labBody(request)),
          raw: const {},
        ),
      );

      final result = await _planner(
        fixture,
        client,
      ).generate(profileId: fixture.profile.id, settings: _settings);

      // An unreadable review means unverified, not worthless. Throwing here
      // discarded a complete, paid-for plan over a formatting slip in the
      // second pass; `approved: false` already stops it being saved.
      expect(result.verification.approved, isFalse);
      expect(result.canSave, isFalse);
      expect(result.plan.items, isNotEmpty);
      expect(result.verification.blockingIssues.single, contains('Unreadable'));
      expect(client.calls, 2);
    },
  );

  test(
    'a mismatched verification receipt blocks the save but keeps the draft',
    () async {
      final fixture = await _Fixture.create(withBiomarker: true);
      addTearDown(fixture.dispose);
      final client = _Client(
        (request) => ProviderResponse(
          text: jsonEncode(
            request.userPrompt.contains('Independently verify')
                ? _verificationBody(request, receiptPatch: {'sha256': 'wrong'})
                : _labBody(request),
          ),
          raw: const {},
        ),
      );

      final result = await _planner(
        fixture,
        client,
      ).generate(profileId: fixture.profile.id, settings: _settings);

      expect(result.verification.approved, isFalse);
      expect(result.canSave, isFalse);
      expect(result.plan.items, isNotEmpty);
      expect(client.calls, 2);
    },
  );

  test('a verification receipt without section hashes is accepted', () async {
    final fixture = await _Fixture.create(withBiomarker: true);
    addTearDown(fixture.dispose);
    final client = _Client(
      (request) => ProviderResponse(
        text: jsonEncode(
          request.userPrompt.contains('Independently verify')
              ? _verificationBody(request)
              : _labBody(request),
        ),
        raw: const {},
      ),
    );

    final result = await _planner(
      fixture,
      client,
    ).generate(profileId: fixture.profile.id, settings: _settings);

    // `_receipt` emits no `section_hashes` at all. Neither pass may demand one:
    // the model copies those digests rather than computing them, so the echo
    // was transcription risk with no evidential value.
    expect(result.verification.approved, isTrue);
    expect(result.canSave, isTrue);
    for (final request in client.requests) {
      expect(request.userPrompt, isNot(contains('section_hashes')));
      expect(jsonEncode(request.jsonSchema), isNot(contains('section_hashes')));
    }
  });

  test(
    'a draft receipt with a wrong section digest is still accepted',
    () async {
      final fixture = await _Fixture.create(withBiomarker: true);
      addTearDown(fixture.dispose);
      final client = _Client(
        (request) => ProviderResponse(
          text: jsonEncode(
            request.userPrompt.contains('Independently verify')
                ? _verificationBody(
                    request,
                    receiptPatch: const {
                      'section_hashes': {'measurements': 'nonsense'},
                    },
                  )
                : _labBody(
                    request,
                    receiptPatch: const {
                      'section_hashes': {'measurements': 'nonsense'},
                    },
                  ),
          ),
          raw: const {},
        ),
      );

      final result = await _planner(
        fixture,
        client,
      ).generate(profileId: fixture.profile.id, settings: _settings);

      // The digest that broke a real run was 63 characters instead of 64. A
      // stray or wrong one must not be a gate any more, in either pass.
      expect(result.verification.approved, isTrue);
      expect(result.canSave, isTrue);
    },
  );

  test('controller rejects saving an independently rejected draft', () async {
    final fixture = await _Fixture.create(withBiomarker: true);
    addTearDown(fixture.dispose);
    final rejected = await _planner(
      fixture,
      _Client(
        (request) => ProviderResponse(
          text: jsonEncode(
            request.userPrompt.contains('Independently verify')
                ? _verificationBody(
                    request,
                    approved: false,
                    blockingIssues: const ['Needs clinician review.'],
                  )
                : _labBody(request),
          ),
          raw: const {},
        ),
      ),
    ).generate(profileId: fixture.profile.id, settings: _settings);
    final controller = _controller(fixture);
    addTearDown(controller.dispose);
    controller.draftLabPlan = rejected;

    await expectLater(
      controller.saveDraftLabPlan(),
      throwsA(isA<StateError>()),
    );
    expect(await fixture.repository.labPlans(fixture.profile.id), isEmpty);
  });

  test('approved verification audit survives saving and reloading', () async {
    final fixture = await _Fixture.create(withBiomarker: true);
    addTearDown(fixture.dispose);
    final generated = await _planner(
      fixture,
      _Client(
        (request) => ProviderResponse(
          text: jsonEncode(
            request.userPrompt.contains('Independently verify')
                ? _verificationBody(
                    request,
                    warnings: const ['Confirm fasting requirements.'],
                  )
                : _labBody(request),
          ),
          raw: const {},
          citations: const ['https://example.test/evidence'],
        ),
      ),
    ).generate(profileId: fixture.profile.id, settings: _settings);
    final controller = _controller(fixture)
      ..activeProfile = fixture.profile
      ..draftLabPlan = generated;
    addTearDown(controller.dispose);

    await controller.saveDraftLabPlan();

    final saved = (await fixture.repository.labPlans(
      fixture.profile.id,
    )).single;
    expect(saved.status, 'verified');
    expect(saved.verificationSummary, generated.verification.summary);
    expect(saved.verificationWarnings, ['Confirm fasting requirements.']);
    expect(saved.verificationCitations, ['https://example.test/evidence']);
    expect(saved.verifiedAt, isNotNull);

    await controller.setLabPlanItemChecked(saved, saved.items.first, true);
    final updated = (await fixture.repository.labPlans(
      fixture.profile.id,
    )).single;
    expect(updated.items.first.checked, isTrue);
    expect(updated.verificationSummary, saved.verificationSummary);
    expect(updated.verificationWarnings, saved.verificationWarnings);
    expect(updated.verificationCitations, saved.verificationCitations);
    expect(updated.verifiedAt, saved.verifiedAt);
  });

  test(
    'lab planner rejects invalid receipt counts and malformed identities',
    () async {
      final fixture = await _Fixture.create(withBiomarker: true);
      addTearDown(fixture.dispose);
      final invalidPlans = <Map<String, Object?> Function(ProviderRequest)>[
        (request) => _labBody(request, recordCount: 1.2),
        (request) => _labBody(request, recordCount: -1),
        (request) => _labBody(request, recordCount: true),
        (request) => _labBody(request, recordCount: '1'),
        (request) => _labBody(request, tiers: ['not an object']),
        (request) => _labBody(
          request,
          tiers: [
            {
              'tier': 'core',
              'items': ['not an object'],
            },
            _tier('advanced'),
            _tier('comprehensive'),
          ],
        ),
        (request) => _labBody(request, itemPatch: {'priority': 1.2}),
        (request) => _labBody(request, itemPatch: {'priority': 0}),
        (request) => _labBody(request, itemPatch: {'biomarker_id': 'unknown'}),
        (request) => _labBody(request, itemPatch: {'biomarker_name': 'Wrong'}),
        (request) => _labBody(request, itemPatch: {'biomarker_id': ''}),
        (request) => _labBody(request, itemPatch: {'biomarker_name': ''}),
      ];
      for (final body in invalidPlans) {
        final client = _Client(
          (request) =>
              ProviderResponse(text: jsonEncode(body(request)), raw: const {}),
        );
        await expectLater(
          _planner(
            fixture,
            client,
          ).generate(profileId: fixture.profile.id, settings: _settings),
          throwsA(isA<LabPlanFormatException>()),
        );
        expect(client.calls, 2);
      }
    },
  );
}

const _settings = AiTaskSettings(provider: AiProvider.openai, model: 'gpt-5.6');

LabPlannerService _planner(_Fixture fixture, _Client client) =>
    LabPlannerService(
      repository: fixture.repository,
      keyStore: _KeyStore(),
      clientFactory: _Factory(client),
      contextBuilder: HealthContextBuilder(fixture.repository),
    );

ProviderResponse _validLabResponse(ProviderRequest request) => ProviderResponse(
  text: jsonEncode(
    request.userPrompt.contains('Independently verify')
        ? _verificationBody(request)
        : _labBody(request),
  ),
  raw: const {},
);

Map<String, Object?> _labBody(
  ProviderRequest request, {
  Object? recordCount,
  List<Object?>? tiers,
  Map<String, Object?>? itemPatch,
  List<String> warnings = const [],
  Map<String, Object?> receiptPatch = const {},
}) => {
  'title': 'Plan',
  'planned_for': null,
  'warnings': warnings,
  'context_receipt': {
    ..._receipt(request, recordCount: recordCount),
    ...receiptPatch,
  },
  'tiers':
      tiers ??
      [
        _tier('core', itemPatch: itemPatch),
        _tier('advanced', itemPatch: itemPatch),
        _tier('comprehensive', itemPatch: itemPatch),
      ],
};

Map<String, Object?> _tier(String name, {Map<String, Object?>? itemPatch}) => {
  'tier': name,
  'items': [
    {
      'biomarker_id': _tierBiomarker(name).$1,
      'biomarker_name': _tierBiomarker(name).$2,
      'priority': 1,
      'rationale': 'Useful for this profile.',
      'evidence_class': 'guideline',
      'preparation': '',
      ...?itemPatch,
    },
  ],
};

Map<String, Object?> _verificationBody(
  ProviderRequest request, {
  bool approved = true,
  List<String> blockingIssues = const [],
  List<String> warnings = const [],
  Map<String, Object?> receiptPatch = const {},
}) => {
  'approved': approved,
  'summary': approved
      ? 'The candidate is suitable.'
      : 'The draft needs review.',
  'blocking_issues': blockingIssues,
  'warnings': warnings,
  'context_receipt': {..._receipt(request), ...receiptPatch},
};

(String, String) _tierBiomarker(String tier) => switch (tier) {
  'core' => ('bio-1', 'ApoB'),
  'advanced' => ('bio-2', 'Lp(a)'),
  'comprehensive' => ('bio-3', 'HbA1c'),
  _ => ('bio-1', 'ApoB'),
};

String _coverage(ProviderRequest request, {Object? recordCount}) =>
    '<context_coverage>${jsonEncode(_receipt(request, recordCount: recordCount))}</context_coverage>';

Map<String, Object?> _receipt(ProviderRequest request, {Object? recordCount}) {
  final package = Map<String, Object?>.from(
    jsonDecode(request.contextJson) as Map,
  );
  final manifest = Map<String, Object?>.from(package['manifest'] as Map);
  final sections = Map<String, Object?>.from(manifest['sections'] as Map);
  return {
    'sha256': manifest['context_sha256'],
    'file_sha256': sha256.convert(utf8.encode(request.contextJson)).toString(),
    'record_count': recordCount ?? manifest['record_count'],
    'reviewed_sections': sections.keys.toList(),
  };
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

class _Client implements AiProviderClient {
  _Client(this._response);

  final ProviderResponse Function(ProviderRequest request) _response;
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
  }) async {
    calls++;
    requests.add(request);
    return _response(request);
  }
}

class _Workspace extends SafeWorkspaceService {
  int deleteCalls = 0;

  @override
  Future<Map<String, Object?>> contextSnapshot(String profileId) async => {
    'schema': 'test',
  };

  @override
  Future<WorkspaceProposal> proposeDelete({
    required String profileId,
    required String relativePath,
    required String summary,
  }) async {
    deleteCalls++;
    return WorkspaceProposal(
      id: 'delete-$deleteCalls',
      profileId: profileId,
      relativePath: relativePath,
      operation: WorkspaceOperation.delete,
      summary: summary,
      createdAt: DateTime.now(),
    );
  }
}

AppController _controller(_Fixture fixture) {
  final keyStore = _KeyStore();
  final clientFactory = AiProviderClientFactory();
  final contextBuilder = HealthContextBuilder(fixture.repository);
  final snapshot = SnapshotService(fixture.database, fixture.repository);
  final oneDrive = _TestOneDriveService(snapshot);
  final workspace = SafeWorkspaceService(oneDriveService: oneDrive);
  return AppController(
    database: fixture.database,
    repository: fixture.repository,
    keyStore: keyStore,
    aiSettingsStore: AiSettingsStore(),
    advisorService: AdvisorService(
      repository: fixture.repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: contextBuilder,
      workspaceService: workspace,
    ),
    labPriceService: LabPriceService(keyStore, clientFactory),
    labPlannerService: LabPlannerService(
      repository: fixture.repository,
      keyStore: keyStore,
      clientFactory: clientFactory,
      contextBuilder: contextBuilder,
    ),
    documentParsingService: DocumentParsingService(
      repository: fixture.repository,
      keyStore: keyStore,
      oneDriveService: oneDrive,
    ),
    correlationService: CorrelationService(fixture.repository),
    importService: LegacyImportService(fixture.database, fixture.repository),
    oneDriveService: oneDrive,
    workspaceService: workspace,
    exportService: LabPlanExportService(),
    clientFactory: clientFactory,
  );
}

class _TestOneDriveService extends OneDriveService {
  _TestOneDriveService(super.snapshotService);

  @override
  Future<bool> isSignedIn() async => false;
}

class _Fixture {
  _Fixture(this.database, this.repository, this.profile);

  final AppDatabase database;
  final HealthRepository repository;
  final Profile profile;

  static Future<_Fixture> create({bool withBiomarker = false}) async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Alice');
    if (withBiomarker) {
      final now = DateTime.now();
      for (final (id, canonicalName, displayName) in const [
        ('bio-1', 'apob', 'ApoB'),
        ('bio-2', 'lpa', 'Lp(a)'),
        ('bio-3', 'hba1c', 'HbA1c'),
      ]) {
        await repository.saveBiomarker(
          Biomarker(
            id: id,
            canonicalName: canonicalName,
            displayName: displayName,
            createdAt: now,
            updatedAt: now,
            synonyms: id == 'bio-1' ? const ['Apolipoprotein B'] : const [],
          ),
        );
      }
    }
    return _Fixture(database, repository, profile);
  }

  Future<void> dispose() async => (await database.database).close();
}
