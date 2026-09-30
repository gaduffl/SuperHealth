import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/exposure_analysis.dart';
import 'package:super_health/analysis/interaction_findings.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/domain/units.dart';

final _created = DateTime.utc(2025, 1, 1);
final _now = DateTime.utc(2026, 9, 30, 12);

Supplement _supplement(
  String id,
  String name, {
  List<Map<String, Object?>> ingredients = const [],
}) => Supplement(
  id: id,
  name: name,
  ingredients: ingredients,
  createdAt: _created,
  updatedAt: _created,
);

SupplementIntake _intake(
  String supplementId,
  DateTime at, {
  double dose = 1,
  List<Map<String, Object?>> snapshot = const [],
  bool skipped = false,
}) => SupplementIntake(
  id: '$supplementId-${at.toIso8601String()}',
  profileId: 'p',
  supplementId: supplementId,
  takenAt: at,
  dose: dose,
  unit: 'capsule',
  skipped: skipped,
  ingredientSnapshot: snapshot,
  createdAt: _created,
  updatedAt: _created,
);

/// One intake per day for [days] days ending the morning of [until].
List<SupplementIntake> _daily(
  String supplementId,
  int days, {
  DateTime? until,
}) {
  final end = until ?? _now;
  return [
    for (var i = 0; i < days; i++)
      _intake(
        supplementId,
        DateTime.utc(
          end.year,
          end.month,
          end.day,
          7,
        ).subtract(Duration(days: i)),
      ),
  ];
}

Biomarker _marker(String id, String name) => Biomarker(
  id: id,
  canonicalName: name,
  displayName: name,
  createdAt: _created,
  updatedAt: _created,
);

Measurement _measurement(String biomarkerId, DateTime at, double value) =>
    Measurement(
      id: '$biomarkerId-${at.toIso8601String()}',
      profileId: 'p',
      biomarkerId: biomarkerId,
      takenAt: at,
      value: value,
      unit: 'mU/L',
      createdAt: _created,
      updatedAt: _created,
    );

NamedHealthRecord _medication(String name, {String status = 'active'}) =>
    NamedHealthRecord(
      id: 'med-${name.hashCode}',
      profileId: 'p',
      name: name,
      kind: 'medication',
      status: status,
      createdAt: _created,
      updatedAt: _created,
    );

HealthEvent _event(String name, DateTime at) => HealthEvent(
  id: 'event-$name-${at.toIso8601String()}',
  profileId: 'p',
  kind: EventKind.tag,
  name: name,
  observedAt: at,
  createdAt: _created,
  updatedAt: _created,
);

final _catalog = [
  _marker('tsh', 'TSH'),
  _marker('ft4', 'fT4'),
  _marker('ck', 'CK'),
  _marker('crp', 'CRP'),
  _marker('ferritin', 'Ferritin'),
];

List<InteractionFinding> _findings({
  List<Supplement> supplements = const [],
  List<SupplementIntake> intakes = const [],
  List<SupplementSchedule> schedules = const [],
  List<NamedHealthRecord> records = const [],
  List<Measurement> measurements = const [],
  List<HealthEvent> events = const [],
}) {
  final exposure = ExposureAnalysis.build(
    supplements: supplements,
    schedules: schedules,
    intakes: intakes,
    records: records,
    now: _now,
  );
  return const InteractionFindingsEngine().evaluate(
    exposure: exposure,
    biomarkers: _catalog,
    measurements: measurements,
    events: events,
  );
}

InteractionFinding? _byId(List<InteractionFinding> findings, String id) =>
    findings.where((finding) => finding.id == id).firstOrNull;

const _biotinCurrent = 'finding:biotin-streptavidin-immunoassay';
const _biotinTsh = 'finding:biotin-streptavidin-immunoassay@tsh';

final _hairVitamins = _supplement(
  'hair',
  'Haut, Haare & Nägel',
  ingredients: const [
    {'name': 'Biotin', 'amount': 10, 'unit': 'mg'},
    {'name': 'Zink', 'amount': 10, 'unit': 'mg'},
  ],
);

void main() {
  group('biotin and immunoassays', () {
    test('a daily 10 mg biotin product raises a current finding that names '
        'TSH, with a 72 hour window', () {
      final findings = _findings(
        supplements: [_hairVitamins],
        intakes: _daily('hair', 20),
      );
      final finding = _byId(findings, _biotinCurrent)!;
      expect(finding.scope, FindingScope.current);
      expect(finding.doseKnown, isTrue);
      expect(finding.dailyAmount, 10);
      expect(finding.amountUnit, CanonicalUnit.milligram);
      expect(finding.window, const Duration(hours: 72));
      expect(finding.affectedBiomarkerIds, containsAll(['tsh', 'ft4']));
      expect(finding.supplementIds, {'hair'});
    });

    test('biotin hidden in a product whose name does not say so is found '
        'through its ingredients, even when the intake has no snapshot', () {
      // The intake carries no snapshot, as 94% of real ones do; the product's
      // current ingredients stand in for it.
      final findings = _findings(
        supplements: [_hairVitamins],
        intakes: [_intake('hair', _now.subtract(const Duration(days: 1)))],
      );
      expect(_byId(findings, _biotinCurrent), isNotNull);
    });

    test('a TSH drawn 14 hours after a dose is flagged as possibly falsely '
        'low, one drawn five days after the last dose is not', () {
      final lastDose = DateTime.utc(2026, 3, 1, 18);
      final findings = _findings(
        supplements: [_hairVitamins],
        intakes: _daily('hair', 10, until: lastDose),
        measurements: [
          _measurement('tsh', lastDose.add(const Duration(hours: 14)), 0.3),
          _measurement('tsh', lastDose.add(const Duration(days: 5)), 1.8),
        ],
      );
      final finding = _byId(findings, _biotinTsh)!;
      expect(finding.scope, FindingScope.pastMeasurement);
      expect(finding.measurements, hasLength(1));
      final affected = finding.measurements.single;
      expect(affected.measurement.value, 0.3);
      expect(affected.exposureBeforeDraw, const Duration(hours: 25));
    });

    test('a megadose counts for a week before the draw', () {
      final megadose = _supplement(
        'mega',
        'Biotin 300',
        ingredients: const [
          {'name': 'Biotin', 'amount': 300, 'unit': 'mg'},
        ],
      );
      final lastDose = DateTime.utc(2026, 3, 1, 8);
      final findings = _findings(
        supplements: [megadose],
        intakes: _daily('mega', 5, until: lastDose),
        measurements: [
          _measurement('tsh', lastDose.add(const Duration(days: 5)), 0.2),
        ],
      );
      final finding = _byId(findings, _biotinTsh)!;
      expect(finding.window, const Duration(days: 7));
    });

    test('a multivitamin amount of biotin is below the threshold', () {
      final multi = _supplement(
        'multi',
        'Multivitamin',
        ingredients: const [
          {'name': 'Biotin', 'amount': 50, 'unit': 'µg'},
        ],
      );
      final findings = _findings(
        supplements: [multi],
        intakes: _daily('multi', 20),
        measurements: [
          _measurement('tsh', _now.subtract(const Duration(hours: 3)), 1.1),
        ],
      );
      expect(_byId(findings, _biotinCurrent), isNull);
      expect(_byId(findings, _biotinTsh), isNull);
    });

    test('micrograms are converted before comparing, never summed raw', () {
      final micro = _supplement(
        'micro',
        'Biotin 5000',
        ingredients: const [
          {'name': 'D-Biotin', 'amount': 5000, 'unit': 'µg'},
        ],
      );
      final finding = _byId(
        _findings(supplements: [micro], intakes: _daily('micro', 3)),
        _biotinCurrent,
      )!;
      expect(finding.dailyAmount, closeTo(5, 1e-9));
    });

    test('a product named for biotin but without ingredients still fires, '
        'marked as an unknown dose', () {
      final bare = _supplement('bare', 'Biotin forte');
      final finding = _byId(
        _findings(supplements: [bare], intakes: _daily('bare', 3)),
        _biotinCurrent,
      )!;
      expect(finding.doseKnown, isFalse);
    });

    test('an amount in a unit that cannot be converted is unknown, not '
        'zero', () {
      final odd = _supplement(
        'odd',
        'Biotin caps',
        ingredients: const [
          {'name': 'Biotin', 'amount': 1, 'unit': 'capsule'},
        ],
      );
      final finding = _byId(
        _findings(supplements: [odd], intakes: _daily('odd', 3)),
        _biotinCurrent,
      )!;
      expect(finding.doseKnown, isFalse);
    });

    test('a schedule with nothing logged still counts as taking it', () {
      final schedule = SupplementSchedule(
        id: 's1',
        profileId: 'p',
        supplementId: 'hair',
        dose: 1,
        unit: 'capsule',
        timeOfDay: '08:00',
        weekdays: const [
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
          'saturday',
          'sunday',
        ],
        createdAt: _created,
        updatedAt: _created,
      );
      final exposure = ExposureAnalysis.build(
        supplements: [_hairVitamins],
        schedules: [schedule],
        intakes: const [],
        records: const [],
        now: _now,
      );
      final biotin = exposure.substances.singleWhere(
        (item) => item.key == 'biotin',
      );
      expect(biotin.current, isTrue);
      expect(biotin.plannedOnly, isTrue);
      expect(
        _byId(
          _findings(supplements: [_hairVitamins], schedules: [schedule]),
          _biotinCurrent,
        ),
        isNotNull,
      );
    });
  });

  group('exposure summary', () {
    test('a product without ingredients is listed as contents unknown '
        'rather than dropped', () {
      final exposure = ExposureAnalysis.build(
        supplements: [_supplement('mystery', 'Beauty Complex')],
        schedules: const [],
        intakes: _daily('mystery', 5),
        records: const [],
        now: _now,
      );
      final entry = exposure.substances.single;
      expect(entry.key, 'product:mystery');
      expect(entry.ingredientsRecorded, isFalse);
      expect(entry.current, isTrue);
      expect(entry.displayName, 'Beauty Complex');
    });

    test('amounts are kept per unit and skipped doses do not count', () {
      final both = _supplement(
        'd',
        'D3',
        ingredients: const [
          {'name': 'Vitamin D3', 'amount': 1000, 'unit': 'IU'},
        ],
      );
      final other = _supplement(
        'd2',
        'D3 drops',
        ingredients: const [
          {'name': 'Cholecalciferol', 'amount': 25, 'unit': 'µg'},
        ],
      );
      final exposure = ExposureAnalysis.build(
        supplements: [both, other],
        schedules: const [],
        intakes: [
          ..._daily('d', 4),
          ..._daily('d2', 4),
          _intake('d', _now.subtract(const Duration(hours: 1)), skipped: true),
        ],
        records: const [],
        now: _now,
      );
      final vitaminD = exposure.substances.singleWhere(
        (item) => item.key == 'vitamin-d',
      );
      expect(vitaminD.recentDailyAmountByUnit, {'IU': 1000, 'µg': 25});
      expect(vitaminD.recentDaysTaken, 4);
    });
  });

  group('upper intake levels', () {
    test('vitamin D in IU is converted through the substance table', () {
      final high = _supplement(
        'dhigh',
        'D3 5000',
        ingredients: const [
          {'name': 'Vitamin D3', 'amount': 5000, 'unit': 'IU'},
        ],
      );
      final low = _supplement(
        'dlow',
        'D3 2000',
        ingredients: const [
          {'name': 'Vitamin D3', 'amount': 2000, 'unit': 'IU'},
        ],
      );
      const id = 'finding:vitamin-d-above-upper-level';
      final highFinding = _byId(
        _findings(supplements: [high], intakes: _daily('dhigh', 5)),
        id,
      )!;
      expect(highFinding.dailyAmount, closeTo(125, 1e-9));
      expect(
        _byId(_findings(supplements: [low], intakes: _daily('dlow', 5)), id),
        isNull,
      );
    });

    test('potassium iodide counts as its iodine share, seaweed as unknown', () {
      final iodide = _supplement(
        'jodid',
        'Jodid 200',
        ingredients: const [
          {'name': 'Kaliumiodid', 'amount': 262, 'unit': 'µg'},
        ],
      );
      final kelp = _supplement(
        'kelp',
        'Algenkapseln',
        ingredients: const [
          {'name': 'Kelp', 'amount': 1, 'unit': 'capsule'},
        ],
      );
      const id = 'finding:iodine-excess-thyroid';
      expect(
        _byId(
          _findings(supplements: [iodide], intakes: _daily('jodid', 5)),
          id,
        ),
        isNull,
      );
      final seaweed = _byId(
        _findings(supplements: [kelp], intakes: _daily('kelp', 5)),
        id,
      )!;
      expect(seaweed.doseKnown, isFalse);
    });
  });

  group('medications', () {
    test('an active medication fires its rule and a resolved one does not', () {
      expect(
        _byId(
          _findings(records: [_medication('Metformin 1000')]),
          'finding:metformin-lowers-b12',
        ),
        isNotNull,
      );
      expect(
        _byId(
          _findings(records: [_medication('Metformin', status: 'resolved')]),
          'finding:metformin-lowers-b12',
        ),
        isNull,
      );
    });

    test('calcium with a recorded thyroid tablet is an absorption finding', () {
      final calcium = _supplement(
        'ca',
        'Calcium 500',
        ingredients: const [
          {'name': 'Calcium', 'amount': 500, 'unit': 'mg'},
        ],
      );
      final finding = _byId(
        _findings(
          supplements: [calcium],
          intakes: _daily('ca', 5),
          records: [_medication('L-Thyroxin 75 µg')],
        ),
        'finding:minerals-reduce-thyroid-hormone-absorption',
      )!;
      expect(finding.partners, ['L-Thyroxin 75 µg']);
      // Recorded as a medication, the tablet has no logged times.
      expect(finding.spacing, isNull);
    });

    test('when both are logged, the actual spacing is checked', () {
      final calcium = _supplement(
        'ca',
        'Calcium 500',
        ingredients: const [
          {'name': 'Calcium', 'amount': 500, 'unit': 'mg'},
        ],
      );
      final thyroxine = _supplement(
        'lt4',
        'Euthyrox',
        ingredients: const [
          {'name': 'Levothyroxin-Natrium', 'amount': 75, 'unit': 'µg'},
        ],
      );
      final days = [
        for (var i = 0; i < 4; i++) DateTime.utc(2026, 9, 26 + i, 6),
      ];
      final finding = _byId(
        _findings(
          supplements: [calcium, thyroxine],
          intakes: [
            for (final day in days) _intake('lt4', day),
            // Two mornings together with the tablet, two with a proper gap.
            _intake('ca', days[0].add(const Duration(hours: 1))),
            _intake('ca', days[1].add(const Duration(minutes: 30))),
            _intake('ca', days[2].add(const Duration(hours: 6))),
            _intake('ca', days[3].add(const Duration(hours: 8))),
          ],
        ),
        'finding:minerals-reduce-thyroid-hormone-absorption',
      )!;
      expect(finding.spacing!.daysTogether, 4);
      expect(finding.spacing!.daysTooClose, 2);
    });

    test(
      'a logged thyroid tablet shortly before a thyroid draw is flagged',
      () {
        final thyroxine = _supplement(
          'lt4',
          'Euthyrox',
          ingredients: const [
            {'name': 'Levothyroxin-Natrium', 'amount': 75, 'unit': 'µg'},
          ],
        );
        final dose = DateTime.utc(2026, 5, 4, 6);
        final findings = _findings(
          supplements: [thyroxine],
          intakes: [_intake('lt4', dose)],
          measurements: [
            _measurement('ft4', dose.add(const Duration(hours: 2)), 1.9),
          ],
        );
        final finding = _byId(
          findings,
          'finding:thyroid-hormone-before-draw@ft4',
        )!;
        expect(
          finding.measurements.single.exposureBeforeDraw,
          const Duration(hours: 2),
        );
      },
    );
  });

  group('events before a draw', () {
    test('strength training the day before a CK test is flagged', () {
      final draw = DateTime.utc(2026, 6, 10, 8);
      final findings = _findings(
        events: [
          _event('Krafttraining', draw.subtract(const Duration(hours: 20))),
        ],
        measurements: [_measurement('ck', draw, 900)],
      );
      final finding = _byId(
        findings,
        'finding:strenuous-exercise-before-draw@ck',
      )!;
      expect(finding.subjects, ['Krafttraining']);
    });

    test('a runny nose counts as illness, not as exercise', () {
      final draw = DateTime.utc(2026, 6, 10, 8);
      final findings = _findings(
        events: [_event('Laufnase', draw.subtract(const Duration(days: 3)))],
        measurements: [
          _measurement('ck', draw, 150),
          _measurement('ferritin', draw, 300),
        ],
      );
      expect(
        _byId(findings, 'finding:strenuous-exercise-before-draw@ck'),
        isNull,
      );
      expect(
        _byId(findings, 'finding:recent-illness-acute-phase@ferritin'),
        isNotNull,
      );
    });
  });

  test('findings are deterministic and ordered by severity', () {
    List<String> run() => [
      for (final finding in _findings(
        supplements: [_hairVitamins],
        intakes: _daily('hair', 10),
        records: [_medication('Metformin'), _medication('Atorvastatin 20')],
      ))
        finding.id,
    ];
    final first = run();
    expect(run(), first);
    final findings = _findings(
      supplements: [_hairVitamins],
      intakes: _daily('hair', 10),
      records: [_medication('Metformin'), _medication('Atorvastatin 20')],
    );
    for (var i = 1; i < findings.length; i++) {
      expect(
        findings[i].severity.index,
        greaterThanOrEqualTo(findings[i - 1].severity.index),
      );
    }
    expect(findings.first.id, _biotinCurrent);
  });
}
