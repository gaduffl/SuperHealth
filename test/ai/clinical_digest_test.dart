import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/advisor_tools.dart';
import 'package:super_health/ai/agent_snapshot.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/ai/clinical_digest.dart';
import 'package:super_health/analysis/exposure_analysis.dart';
import 'package:super_health/analysis/interaction_findings.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

/// A small but complete record: current and past products, one without
/// ingredients, active and resolved medications, measured and unmeasured
/// tests, a lab comment, symptoms and tags, and a retest list.
class _Record {
  _Record(this.database, this.repository, this.profile, this.now);

  final AppDatabase database;
  final HealthRepository repository;
  final Profile profile;
  final DateTime now;

  static Future<_Record> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(
      displayName: 'Robin',
      dateOfBirth: DateTime(1980, 6, 1),
      sex: 'female',
      notes: 'Works night shifts.',
    );
    final now = DateTime.now();
    final record = _Record(database, repository, profile, now);
    await record._seed();
    return record;
  }

  Future<void> _seed() async {
    Supplement product(
      String id,
      String name, [
      List<Map<String, Object?>> ingredients = const [],
    ]) => Supplement(
      id: id,
      name: name,
      ingredients: ingredients,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveSupplement(
      product('hair', 'Haut, Haare & Nägel', const [
        {'name': 'Biotin', 'amount': 10, 'unit': 'mg'},
        {'name': 'Zink', 'amount': 10, 'unit': 'mg'},
      ]),
    );
    await repository.saveSupplement(product('mystery', 'Beauty Complex'));
    await repository.saveSupplement(
      product('old', 'Vitamin C 500', const [
        {'name': 'Vitamin C', 'amount': 500, 'unit': 'mg'},
      ]),
    );
    var dose = 0;
    Future<void> take(String id, Duration ago) => repository.saveIntake(
      SupplementIntake(
        id: 'dose-${dose++}',
        profileId: profile.id,
        supplementId: id,
        takenAt: now.subtract(ago),
        dose: 1,
        unit: 'capsule',
        notes: id == 'mystery' ? 'with breakfast' : '',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (var day = 0; day < 5; day++) {
      await take('hair', Duration(days: day, hours: 1));
    }
    for (var day = 0; day < 3; day++) {
      await take('mystery', Duration(days: day, hours: 2));
    }
    for (var day = 60; day < 65; day++) {
      await take('old', Duration(days: day));
    }

    NamedHealthRecord named(
      String id,
      String kind,
      String name, {
      String status = 'active',
      String notes = '',
    }) => NamedHealthRecord(
      id: id,
      profileId: profile.id,
      name: name,
      kind: kind,
      status: status,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveNamedRecord(
      named('lt4', 'medication', 'L-Thyroxin 75'),
    );
    await repository.saveNamedRecord(
      named('ppi', 'medication', 'Pantoprazol 20', status: 'resolved'),
    );
    await repository.saveNamedRecord(
      named('hashi', 'condition', 'Hashimoto', notes: 'Diagnosed 2019.'),
    );
    await repository.saveNamedRecord(
      named('fam', 'family_history', 'Type 2 diabetes (father)'),
    );

    Biomarker marker(String id, String name) => Biomarker(
      id: id,
      canonicalName: id,
      displayName: name,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveBiomarker(marker('tsh', 'TSH'));
    await repository.saveBiomarker(marker('ferritin', 'Ferritin'));
    await repository.saveBiomarker(marker('psa', 'PSA'));
    await repository.saveDocument(
      HealthDocument(
        id: 'report',
        profileId: profile.id,
        fileName: 'labor.pdf',
        documentDate: now.subtract(const Duration(days: 2)),
        labName: 'Labor Nord',
        reportComment: 'Befund unauffällig, Kontrolle in 6 Monaten.',
        createdAt: now,
        updatedAt: now,
      ),
    );
    Measurement result(
      String id,
      String biomarkerId,
      Duration ago,
      double value, {
      String notes = '',
    }) => Measurement(
      id: id,
      profileId: profile.id,
      biomarkerId: biomarkerId,
      documentId: 'report',
      takenAt: now.subtract(ago),
      value: value,
      unit: biomarkerId == 'tsh' ? 'mU/L' : 'ng/mL',
      labRefLow: biomarkerId == 'tsh' ? 0.4 : 15,
      labRefHigh: biomarkerId == 'tsh' ? 4.0 : 150,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveMeasurement(
      result('tsh-1', 'tsh', const Duration(days: 2), 0.3, notes: 'Fasting.'),
    );
    await repository.saveMeasurement(
      result('fer-1', 'ferritin', const Duration(days: 200), 40),
    );
    await repository.saveMeasurement(
      result('fer-2', 'ferritin', const Duration(days: 2), 35),
    );

    HealthEvent event(String name, EventKind kind, Duration ago, String note) =>
        HealthEvent(
          id: 'event-$name-${ago.inHours}',
          profileId: profile.id,
          kind: kind,
          name: name,
          observedAt: now.subtract(ago),
          score: kind == EventKind.symptom ? 6 : null,
          notes: note,
          createdAt: now,
          updatedAt: now,
        );
    await repository.saveEvent(
      event('Müdigkeit', EventKind.symptom, const Duration(days: 1), 'Tired.'),
    );
    await repository.saveEvent(
      event('Krafttraining', EventKind.tag, const Duration(days: 3), 'Legs.'),
    );
    await repository.saveBiomarkerList(
      BiomarkerList(
        id: 'thyroid',
        profileId: profile.id,
        name: 'Schilddrüse',
        dueIntervalDays: 180,
        createdAt: now,
        updatedAt: now,
        items: [
          BiomarkerListItem(
            id: 'thyroid-tsh',
            listId: 'thyroid',
            biomarkerId: 'tsh',
            createdAt: now,
            updatedAt: now,
          ),
        ],
      ),
    );
  }

  Future<({AgentSnapshot snapshot, ExposureAnalysis exposure})> load() async {
    final snapshot = AgentSnapshot.fromSnapshot(
      await repository.completeProfileSnapshot(
        profile.id,
        scope: HealthContextScope.agent,
      ),
      profileId: profile.id,
    );
    final exposure = ExposureAnalysis.build(
      supplements: snapshot.supplements,
      schedules: snapshot.schedules,
      intakes: snapshot.intakes,
      records: snapshot.records,
      now: now,
    );
    return (snapshot: snapshot, exposure: exposure);
  }

  Future<ClinicalDigest> digest({
    ClinicalDigestPurpose purpose = ClinicalDigestPurpose.advisor,
    List<DueBiomarker> overdueTests = const [],
  }) async {
    final loaded = await load();
    return const ClinicalDigestBuilder().build(
      snapshot: loaded.snapshot,
      exposure: loaded.exposure,
      findings: const InteractionFindingsEngine().evaluate(
        exposure: loaded.exposure,
        biomarkers: loaded.snapshot.biomarkers,
        measurements: loaded.snapshot.measurements,
        events: loaded.snapshot.events,
      ),
      purpose: purpose,
      overdueTests: overdueTests,
    );
  }

  Future<void> dispose() => database.close();
}

void main() {
  setUpAll(sqfliteFfiInit);

  group('the clinical digest', () {
    test('lists every entity in the record, however small', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final digest = jsonDecode((await record.digest()).json) as Map;

      final products = {
        for (final item in digest['supplements'] as List) (item as Map)['id'],
      };
      expect(products, {'hair', 'mystery', 'old'});
      final records = {
        for (final item in digest['health_records'] as List)
          (item as Map)['name'],
      };
      expect(records, {
        'L-Thyroxin 75',
        'Pantoprazol 20',
        'Hashimoto',
        'Type 2 diabetes (father)',
      });
      final biomarkers = {
        for (final item in digest['biomarkers'] as List) (item as Map)['id'],
      };
      // Measured tests only; the rest of the catalog is a tool call away.
      expect(biomarkers, {'tsh', 'ferritin'});
      final series = {
        for (final item in digest['symptoms_and_tags'] as List)
          (item as Map)['name'],
      };
      expect(series, {'Müdigkeit', 'Krafttraining'});
      expect(digest['retest_lists'], hasLength(1));
    });

    test('carries free-text remarks verbatim', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final json = (await record.digest()).json;

      for (final remark in [
        'Befund unauffällig, Kontrolle in 6 Monaten.',
        'Diagnosed 2019.',
        'Works night shifts.',
        'Fasting.',
        'Tired.',
        'Legs.',
      ]) {
        expect(json, contains(remark));
      }
    });

    test(
      'shows a product without ingredients as contents not recorded',
      () async {
        final record = await _Record.create();
        addTearDown(record.dispose);
        final digest = jsonDecode((await record.digest()).json) as Map;

        final mystery = (digest['exposures'] as List).cast<Map>().singleWhere(
          (item) => item['id'] == 'exp:product:mystery',
        );
        expect(mystery['contents_recorded'], isFalse);
        expect(mystery['current'], isTrue);
      },
    );

    test('asks for a verdict on everything current and nothing past', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final digest = await record.digest();
      final ids = {for (final item in digest.checklist) item.id};

      expect(ids, containsAll(['exp:biotin', 'exp:zinc', 'med:lt4']));
      expect(ids, contains('exp:product:mystery'));
      expect(ids, contains('finding:biotin-streptavidin-immunoassay'));
      expect(ids, contains('finding:biotin-streptavidin-immunoassay@tsh'));
      // Stopped two months ago, and a resolved medication.
      expect(ids, isNot(contains('exp:vitamin-c')));
      expect(ids, isNot(contains('med:ppi')));
      // Labels are for the reader: names, never ids.
      expect(
        digest.checklist.singleWhere((item) => item.id == 'med:lt4').label,
        'L-Thyroxin 75',
      );
    });

    test('the advisor judges what is taken and found, and reaches the '
        'catalog through a tool', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final digest = await record.digest();
      final json = jsonDecode(digest.json) as Map;

      expect(digest.checklist.map((item) => item.kind).toSet(), {
        'substance',
        'medication',
        'finding',
      });
      expect(json.containsKey('test_catalog'), isFalse);
      expect(
        (json['not_in_this_digest'] as Map).values,
        contains('biomarker_catalog'),
      );
    });

    test('the planner also accounts for conditions, goals, family history and '
        'optional overdue tests, and carries the whole catalog', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final psa = (await record.repository.biomarkers()).singleWhere(
        (item) => item.id == 'psa',
      );
      final digest = await record.digest(
        purpose: ClinicalDigestPurpose.labPlanner,
        overdueTests: [
          DueBiomarker(
            biomarker: psa,
            listNames: const ['Vorsorge'],
            dueDate: record.now,
            intervalDays: 365,
          ),
        ],
      );
      final kinds = {for (final item in digest.checklist) item.id: item.kind};

      expect(kinds['hashi'], 'condition');
      expect(kinds['fam'], 'family_history');
      expect(kinds['due:psa'], 'overdue_test');
      expect(kinds['med:lt4'], 'medication');
      // Resolved is not current, for a condition as for a medicine.
      expect(kinds, isNot(contains('med:ppi')));
      final json = jsonDecode(digest.json) as Map;
      final catalog = [
        for (final row in json['test_catalog'] as List) (row as Map)['id'],
      ];
      // Never measured, and still a test the planner can propose.
      expect(catalog, contains('psa'));
      expect(
        (json['not_in_this_digest'] as Map).values,
        isNot(contains('biomarker_catalog')),
      );
      // A finding about one past draw names the test, so two of them do not
      // read like the same item listed twice.
      expect(
        digest.checklist
            .singleWhere(
              (item) =>
                  item.id == 'finding:biotin-streptavidin-immunoassay@tsh',
            )
            .label,
        endsWith('(TSH)'),
      );
    });

    test('is deterministic and leaves out who the person is', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final first = await record.digest();
      final second = await record.digest();

      expect(second.json, first.json);
      expect(second.sha256, first.sha256);
      // The display name identifies nobody's biology; minimal data.
      expect(first.json, isNot(contains('Robin')));
    });

    test('links a biomarker to the findings that touch it', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final digest = jsonDecode((await record.digest()).json) as Map;

      final tsh = (digest['biomarkers'] as List).cast<Map>().singleWhere(
        (item) => item['id'] == 'tsh',
      );
      expect(
        tsh['findings'],
        contains('finding:biotin-streptavidin-immunoassay@tsh'),
      );
      expect((tsh['latest'] as Map)['flag'], 'below reference');
    });
  });

  group('advisor tools', () {
    Future<AdvisorToolbox> toolbox(_Record record) async {
      final loaded = await record.load();
      return AdvisorToolbox(
        snapshot: loaded.snapshot,
        exposure: loaded.exposure,
      );
    }

    Map<String, Object?> run(
      AdvisorToolbox tools,
      String name,
      Map<String, Object?> input,
    ) {
      final result = tools.run(
        AgentToolCall(id: 'c', name: name, input: input),
      );
      return jsonDecode(result.content) as Map<String, Object?>;
    }

    test('what was taken before a draw, anchored on the measurement', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final tools = await toolbox(record);

      final result = run(tools, 'exposure_before', {
        'measurement_id': 'tsh-1',
        'hours': 72,
      });

      final substances = jsonEncode(result['substances']);
      expect(substances, contains('Biotin'));
      expect(substances, contains('Beauty Complex (contents not recorded)'));
      expect(
        jsonEncode(result['medications_recorded_as_current_then']),
        contains('L-Thyroxin 75'),
      );
    });

    test('doses of one substance across products carry its amount', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final tools = await toolbox(record);

      final result = run(tools, 'supplement_intakes', {'substance': 'biotin'});

      expect(result['doses_found'], 5);
      final first = (result['doses']! as List).first as Map;
      expect(first['amount'], 10);
      expect(first['unit'], 'mg');
      expect(first['product'], 'Haut, Haare & Nägel');
    });

    test(
      'a biomarker resolves by name and returns every measurement',
      () async {
        final record = await _Record.create();
        addTearDown(record.dispose);
        final tools = await toolbox(record);

        final result = run(tools, 'biomarker_history', {
          'biomarker': 'Ferritin',
        });

        expect(result['measurements'], hasLength(2));
        expect(jsonEncode(result['measurements']), contains('Labor Nord'));
      },
    );

    test('the catalog includes tests never measured', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final tools = await toolbox(record);

      final result = run(tools, 'biomarker_catalog', {'query': 'psa'});

      final psa = (result['tests']! as List).single as Map;
      expect(psa['measured'], isFalse);
    });

    test('search finds a note anywhere in the record', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final tools = await toolbox(record);

      final result = run(tools, 'search_records', {'query': 'breakfast'});

      expect(result['matches_found'], 3);
      expect(((result['matches']! as List).first as Map)['section'], 'dose');
    });

    test('bad input is an error the model can read, never a throw', () async {
      final record = await _Record.create();
      addTearDown(record.dispose);
      final tools = await toolbox(record);

      for (final call in [
        const AgentToolCall(id: 'a', name: 'no_such_tool', input: {}),
        const AgentToolCall(id: 'b', name: 'biomarker_history', input: {}),
        const AgentToolCall(
          id: 'c',
          name: 'lab_report',
          input: {'report_id': 'missing'},
        ),
        const AgentToolCall(
          id: 'd',
          name: 'biomarker_history',
          input: {},
          inputError: 'Unexpected end of input',
        ),
      ]) {
        final result = tools.run(call);
        expect(result.isError, isTrue, reason: call.name);
        expect(result.callId, call.id);
        expect(jsonDecode(result.content), contains('error'));
      }
    });
  });
}
