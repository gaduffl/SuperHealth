import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/biomarkers/calculated_biomarker_service.dart';
import 'package:super_health/biomarkers/leukocyte_differential.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  final service = CalculatedBiomarkerService();
  final day = DateTime(2026, 3, 9);

  final leukocytes = _marker('wbc', 'Leukozyten', unit: '10^9/L');
  final neutrophilShare = _marker('neut-rel', 'Neutrophile (relativ)');
  final lymphocyteShare = _marker('lymph-rel', 'Lymphozyten', unit: '%');
  final neutrophilCount = _marker(
    'neut',
    'Neutrophile (absolut)',
    unit: '10^9/L',
  );
  final lymphocyteCount = _marker(
    'lymphs',
    'Lymphozyten (absolut)',
    unit: '10^9/L',
  );
  final catalog = [
    leukocytes,
    neutrophilShare,
    lymphocyteShare,
    neutrophilCount,
    lymphocyteCount,
  ];

  test(
    'a differential with only percentages gains absolute counts from the leukocyte total of the same report',
    () {
      final derived = service.derive(
        biomarkers: catalog,
        measurements: [
          _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
          _result('neut-share', 'neut-rel', 58.2, '%', day, document: 'report'),
          _result(
            'lymph-share',
            'lymph-rel',
            30.1,
            '%',
            day,
            document: 'report',
          ),
        ],
      );

      final byMarker = {for (final row in derived) row.biomarkerId: row};
      expect(byMarker.keys, unorderedEquals(['neut', 'lymphs']));
      final neutrophils = byMarker['neut']!;
      expect(neutrophils.value, 3.78);
      expect(neutrophils.unit, '10^9/L');
      expect(neutrophils.canonicalValue, 3.78);
      expect(neutrophils.isCalculated, isTrue);
      expect(neutrophils.documentId, isNull);
      expect(
        CalculatedBiomarkerService.isDerivedLeukocyteCount(neutrophils),
        isTrue,
      );
      expect(neutrophils.notes, contains('leukocytes (6.5 10^9/L)'));
      expect(neutrophils.notes, contains('neutrophils (58.2 %)'));
      expect(byMarker['lymphs']!.value, 1.96);
    },
  );

  test('a count the lab reported is never replaced by a calculated one', () {
    final derived = service.derive(
      biomarkers: catalog,
      measurements: [
        _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
        _result('neut-share', 'neut-rel', 58.2, '%', day, document: 'report'),
        _result('neut-count', 'neut', 3.9, '10^9/L', day, document: 'report'),
        _result('lymph-share', 'lymph-rel', 30.1, '%', day, document: 'report'),
      ],
    );

    expect(derived.map((row) => row.biomarkerId), ['lymphs']);
  });

  test(
    'relative and absolute are told apart by unit, so one marker can hold both',
    () {
      // A parser that met "Neutrophile" twice in one report filed the share
      // and the count under the same provisional marker.
      final mixed = _marker('neutrophile', 'Neutrophile', unit: '%');
      final derived = service.derive(
        biomarkers: [leukocytes, mixed, neutrophilCount],
        measurements: [
          _result('total', 'wbc', 6.5, '10^9/L', day, document: 'first'),
          _result('share', 'neutrophile', 58.2, '%', day, document: 'first'),
          _result('count', 'neutrophile', 3.9, 'G/l', day, document: 'first'),
          _result('later-total', 'wbc', 5, '10^9/L', day.add(_week)),
          _result('later-share', 'neutrophile', 60, '%', day.add(_week)),
        ],
      );

      expect(derived.single.biomarkerId, 'neut');
      expect(derived.single.value, 3);
    },
  );

  test(
    'G/l is read as giga per litre and a per-microlitre series gets whole cells',
    () {
      final perMicrolitre = _marker(
        'neut',
        'Neutrophile (absolut)',
        unit: 'cells/uL',
      );
      final derived = service.derive(
        biomarkers: [leukocytes, neutrophilShare, perMicrolitre],
        measurements: [
          // How normalizeUnit stores a printed "G/l".
          _result('total', 'wbc', 6.5, 'g/L', day, document: 'report'),
          _result('share', 'neut-rel', 58.2, '%', day, document: 'report'),
        ],
      );

      expect(derived.single.value, 3783);
      expect(derived.single.unit, 'cells/uL');
    },
  );

  test(
    'urine leukocytes, another day, a distant draw and unknown cell types calculate nothing',
    () {
      final urine = _marker('urine', 'Leukozyten (Urin)', unit: '/µl');
      final segmented = _marker('seg', 'Segmentkernige', unit: '%');
      final atypical = _marker('atyp', 'Atypische Lymphozyten', unit: '%');
      List<Measurement> derive(List<Measurement> measurements) =>
          service.derive(
            biomarkers: [...catalog, urine, segmented, atypical],
            measurements: measurements,
          );

      expect(
        derive([
          _result('urine-total', 'urine', 25, '/µl', day, document: 'report'),
          _result('share', 'neut-rel', 58.2, '%', day, document: 'report'),
        ]),
        isEmpty,
      );
      expect(
        derive([
          _result('total', 'wbc', 6.5, '10^9/L', day.add(_week)),
          _result('share', 'neut-rel', 58.2, '%', day),
        ]),
        isEmpty,
      );
      expect(
        derive([
          _result('total', 'wbc', 6.5, '10^9/L', day.add(_hours(8))),
          _result('share', 'neut-rel', 58.2, '%', day),
        ]),
        isEmpty,
      );
      expect(
        derive([
          _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
          _result('seg-share', 'seg', 55, '%', day, document: 'report'),
          _result('atyp-share', 'atyp', 2, '%', day, document: 'report'),
          _result('bad-share', 'neut-rel', 120, '%', day, document: 'report'),
        ]),
        isEmpty,
      );
    },
  );

  test(
    'two different totals or two different shares in one report are left uncalculated',
    () {
      expect(
        service.derive(
          biomarkers: catalog,
          measurements: [
            _result('blood', 'wbc', 6.5, '10^9/L', day, document: 'report'),
            // A urine status the parser mapped onto the blood count's marker.
            _result('urine', 'wbc', 25, '/µl', day, document: 'report'),
            _result('share', 'neut-rel', 58.2, '%', day, document: 'report'),
          ],
        ),
        isEmpty,
      );
      expect(
        service.derive(
          biomarkers: catalog,
          measurements: [
            _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
            _result('first', 'neut-rel', 58.2, '%', day, document: 'report'),
            _result('second', 'neut-rel', 61, '%', day, document: 'report'),
          ],
        ),
        isEmpty,
      );
      expect(
        service.derive(
          biomarkers: catalog,
          measurements: [
            _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
            _result('first', 'neut-rel', 58.2, '%', day, document: 'report'),
            _result('again', 'neut-rel', 58.2, '%', day, document: 'report'),
          ],
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a differential whose catalog lacks an absolute series is given one under the legacy id',
    () {
      final filed = _marker(
        'wbc',
        'Leukozyten',
        unit: '10^9/L',
        category: 'Blutbild',
      );
      final monocyteShare = _marker('mono-rel', 'Monozyten %');
      final eosinophilShare = _marker('eos-rel', 'Eosinophile rel.');
      final missing = service.missingBiomarkers(
        biomarkers: [
          filed,
          neutrophilShare,
          monocyteShare,
          eosinophilShare,
          lymphocyteShare,
          lymphocyteCount,
        ],
        measurements: [
          _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
          _result('neut', 'neut-rel', 58.2, '%', day, document: 'report'),
          _result('mono', 'mono-rel', 8, '%', day, document: 'report'),
          _result('lymph', 'lymph-rel', 30, '%', day, document: 'report'),
          // No leukocyte total that day: nothing to calculate, nothing needed.
          _result('eos', 'eos-rel', 3, '%', day.add(_week)),
        ],
        now: day,
      );

      expect(missing.map((item) => item.id), ['neut', 'monos']);
      final neutrophils = missing.first;
      expect(neutrophils.canonicalName, 'neut');
      expect(neutrophils.displayName, 'Neutrophile (absolut)');
      expect(neutrophils.defaultUnit, '10^9/L');
      expect(neutrophils.category, 'Blutbild');
      expect(neutrophils.isCalculated, isFalse);
      expect(neutrophils.synonyms, LeukocyteType.neutrophils.absoluteSynonyms);

      final derived = service.derive(
        biomarkers: [filed, neutrophilShare, ...missing],
        measurements: [
          _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
          _result('neut', 'neut-rel', 58.2, '%', day, document: 'report'),
        ],
      );
      expect(derived.single.biomarkerId, 'neut');
    },
  );

  test(
    'the note on a calculated count and a created series read in German on request',
    () {
      final measurements = [
        _result('total', 'wbc', 6.5, '10^9/L', day, document: 'report'),
        _result('share', 'neut-rel', 58.2, '%', day, document: 'report'),
      ];
      final derived = service.derive(
        biomarkers: catalog,
        measurements: measurements,
        german: true,
      );
      final missing = service.missingBiomarkers(
        biomarkers: [leukocytes, neutrophilShare],
        measurements: measurements,
        now: day,
        german: true,
      );

      expect(
        derived.single.notes,
        'Berechnet aus Leukozyten (6.5 10^9/L) und Neutrophilen (58.2 %) vom '
        'selben Tag: Leukozyten × Anteil / 100. Das Labor hat diesen '
        'Absolutwert nicht angegeben.',
      );
      expect(missing.single.description, startsWith('Absolutwert der '));
      expect(missing.single.displayName, 'Neutrophile (absolut)');
    },
  );
}

const _week = Duration(days: 7);

Duration _hours(int hours) => Duration(hours: hours);

Biomarker _marker(
  String id,
  String displayName, {
  String unit = '',
  String category = '',
}) => Biomarker(
  id: id,
  canonicalName: id,
  displayName: displayName,
  defaultUnit: unit,
  category: category,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Measurement _result(
  String id,
  String biomarkerId,
  double value,
  String unit,
  DateTime takenAt, {
  String? document,
}) => Measurement(
  id: id,
  profileId: 'profile',
  biomarkerId: biomarkerId,
  documentId: document,
  takenAt: takenAt,
  value: value,
  unit: unit,
  createdAt: takenAt,
  updatedAt: takenAt,
);
