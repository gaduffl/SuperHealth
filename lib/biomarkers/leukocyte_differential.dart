import 'package:collection/collection.dart';

import '../domain/entities.dart';
import '../domain/name_matching.dart';
import 'unit_conversion_service.dart';

/// The five leukocyte types a differential blood count reports.
///
/// [catalogId] is the id the legacy catalog gave the type's *absolute* count.
/// The unit registry already converts those ids as cell counts, and an absolute
/// series created here reuses it, so a catalog that later arrives by sync or
/// restore carrying the legacy row merges into it instead of doubling it.
enum LeukocyteType {
  neutrophils(
    catalogId: 'neut',
    german: 'Neutrophile',
    english: 'neutrophils',
    names: {
      'neutrophile',
      'neutrophilen',
      'neutrophil',
      'neutrophils',
      'neutrophile granulozyten',
      'neutrophilic granulocytes',
      'neut',
      'neutro',
      'neu',
      'anc',
    },
    absoluteSynonyms: [
      'NEUT#',
      'Neutrophile absolut',
      'Neutrophile Granulozyten absolut',
      'Neutrophils (absolute)',
      'Absolute neutrophil count',
    ],
  ),
  lymphocytes(
    catalogId: 'lymphs',
    german: 'Lymphozyten',
    english: 'lymphocytes',
    names: {
      'lymphozyten',
      'lymphocytes',
      'lymphocyte',
      'lymph',
      'lymphs',
      'lym',
    },
    absoluteSynonyms: [
      'LYMPH#',
      'Lymphozyten absolut',
      'Lymphocytes (absolute)',
      'Absolute lymphocyte count',
    ],
  ),
  monocytes(
    catalogId: 'monos',
    german: 'Monozyten',
    english: 'monocytes',
    names: {'monozyten', 'monocytes', 'monocyte', 'mono', 'monos'},
    absoluteSynonyms: [
      'MONO#',
      'Monozyten absolut',
      'Monocytes (absolute)',
      'Absolute monocyte count',
    ],
  ),
  eosinophils(
    catalogId: 'eos',
    german: 'Eosinophile',
    english: 'eosinophils',
    names: {
      'eosinophile',
      'eosinophilen',
      'eosinophil',
      'eosinophils',
      'eosinophile granulozyten',
      'eosinophilic granulocytes',
      'eos',
      'eo',
      'eosino',
    },
    absoluteSynonyms: [
      'EO#',
      'Eosinophile absolut',
      'Eosinophile Granulozyten absolut',
      'Eosinophils (absolute)',
      'Absolute eosinophil count',
    ],
  ),
  basophils(
    catalogId: 'basos',
    german: 'Basophile',
    english: 'basophils',
    names: {
      'basophile',
      'basophilen',
      'basophil',
      'basophils',
      'basophile granulozyten',
      'basophilic granulocytes',
      'baso',
      'basos',
    },
    absoluteSynonyms: [
      'BASO#',
      'Basophile absolut',
      'Basophile Granulozyten absolut',
      'Basophils (absolute)',
      'Absolute basophil count',
    ],
  );

  const LeukocyteType({
    required this.catalogId,
    required this.german,
    required this.english,
    required this.names,
    required this.absoluteSynonyms,
  });

  final String catalogId;
  final String german;
  final String english;

  /// Whole names, compared after folding and with parentheticals and
  /// [LeukocyteDifferential]'s kind words removed. Two-letter analyser codes
  /// other than `eo` are left out on purpose: `mo` and `ba` are also the
  /// element symbols a trace-element panel prints.
  final Set<String> names;
  final List<String> absoluteSynonyms;
}

/// Absolute leukocyte counts implied by a differential blood count.
///
/// A lab that prints only the percentages has still printed everything the
/// absolute counts need: the total leukocyte count times each percentage. They
/// are derived on read, like HOMA1-IR, so every past report gains them and an
/// edited or deleted source recalculates them rather than leaving a stale copy.
///
/// Whether a result is relative or absolute is read from its unit, never from
/// its name: reports print "Neutrophile" for both, and a parser that mapped
/// both rows onto one biomarker has left the unit as the only honest witness.
class LeukocyteDifferential {
  LeukocyteDifferential({
    UnitConversionService? unitConversions,
    this.pairWindow = const Duration(hours: 6),
  }) : _units = unitConversions ?? UnitConversionService();

  static const flag = 'calculated:leukocyte_absolute';
  static const _idPrefix = 'calculated_leukocyte_absolute';

  /// How far apart a total and a percentage outside one report may be taken.
  final Duration pairWindow;
  final UnitConversionService _units;

  /// Absolute counts for every differential percentage that has an
  /// unambiguous leukocyte total from the same blood count.
  ///
  /// A count the lab reported for that type on that date suppresses the
  /// calculation entirely: the reported value is evidence, the product is not.
  /// A type whose catalog has no absolute series gets nothing here; see
  /// [missingBiomarkers].
  List<Measurement> derive({
    required List<Biomarker> biomarkers,
    required List<Measurement> measurements,
  }) {
    final roles = _roles(biomarkers);
    final targets = _targets(biomarkers, roles);
    if (targets.isEmpty) return const [];
    return [
      for (final slot in _slots(roles, measurements))
        if (targets[slot.type] case final target?) _absolute(slot, target),
    ];
  }

  /// The absolute-count biomarkers a stored differential needs and the catalog
  /// lacks, ordered by type.
  ///
  /// Each uses its type's [LeukocyteType.catalogId], so two devices that both
  /// create one create the same row.
  List<Biomarker> missingBiomarkers({
    required List<Biomarker> biomarkers,
    required List<Measurement> measurements,
    required DateTime now,
  }) {
    final roles = _roles(biomarkers);
    final targets = _targets(biomarkers, roles);
    final byId = {for (final biomarker in biomarkers) biomarker.id: biomarker};
    final needed = <LeukocyteType, Biomarker?>{};
    for (final slot in _slots(roles, measurements)) {
      if (targets.containsKey(slot.type)) continue;
      needed.putIfAbsent(
        slot.type,
        () => byId[slot.total.measurement.biomarkerId],
      );
    }
    return [
      for (final type in LeukocyteType.values)
        if (needed.containsKey(type))
          Biomarker(
            id: type.catalogId,
            canonicalName: type.catalogId,
            displayName: '${type.german} (absolut)',
            // Beside the leukocyte count it is calculated from, wherever the
            // owner filed that.
            category: needed[type]?.category ?? '',
            defaultUnit: '10^9/L',
            description:
                'Absolute ${type.english} count. A blood count that reported '
                'only the percentage has it calculated from the leukocyte '
                'count recorded on the same date; a count the lab reported is '
                'kept as reported.',
            synonyms: type.absoluteSynonyms,
            createdAt: now,
            updatedAt: now,
          ),
    ];
  }

  Measurement _absolute(_Slot slot, Biomarker target) {
    final percentage = slot.percentage.measurement;
    final total = slot.total.measurement;
    final targetFactor = _cellsPerNanolitre(target.defaultUnit);
    final unit = targetFactor == null
        ? '10^9/L'
        : _units.normalizeUnit(target.defaultUnit);
    final factor = targetFactor ?? 1.0;
    final exact = slot.total.value * slot.percentage.value / 100 / factor;
    // Reports print counts per nanolitre to two decimals and counts per
    // microlitre as whole cells; more digits would be precision the two inputs
    // never had.
    final value = factor < 1
        ? exact.roundToDouble()
        : (exact * 100).roundToDouble() / 100;
    DateTime later(DateTime left, DateTime right) =>
        left.isAfter(right) ? left : right;
    return Measurement(
      id: '$_idPrefix:${percentage.id}:${total.id}',
      profileId: percentage.profileId,
      biomarkerId: target.id,
      takenAt: later(percentage.takenAt, total.takenAt),
      value: value,
      unit: unit,
      canonicalValue: value,
      canonicalUnit: unit,
      conversionStatus: 'calculated',
      flags: const [flag],
      notes:
          'Calculated from leukocytes (${_plain(total.value)} ${total.unit}) '
          'and ${slot.type.english} (${_plain(percentage.value)} '
          '${percentage.unit}) recorded on the same date: leukocytes × '
          'percentage / 100. The lab did not report this absolute count.',
      createdAt: later(percentage.createdAt, total.createdAt),
      updatedAt: later(percentage.updatedAt, total.updatedAt),
    );
  }

  /// One calculation per type and leukocyte total, ordered by percentage id.
  ///
  /// Every ambiguity is dropped rather than resolved: two different totals
  /// equally close to a percentage (a urine status mapped onto the blood
  /// count's leukocytes, say), or two different percentages for one type
  /// against one total. Picking either would present a guess as a result.
  List<_Slot> _slots(Map<String, _Role> roles, List<Measurement> measurements) {
    final totalsByDay = <String, List<_Reading>>{};
    final percentages = <_Reading>[];
    final reportedAbsolute = <String>{};
    for (final measurement in measurements) {
      if (measurement.deleted ||
          measurement.isCalculated ||
          !measurement.value.isFinite) {
        continue;
      }
      final role = roles[measurement.biomarkerId];
      if (role == null) continue;
      final day = _dayKey(measurement);
      final cells = _cellsPerNanolitre(measurement.unit);
      final type = role.type;
      if (type == null) {
        if (cells != null && measurement.value > 0) {
          totalsByDay
              .putIfAbsent(day, () => [])
              .add(_Reading(measurement, measurement.value * cells));
        }
      } else if (cells != null) {
        reportedAbsolute.add('$day|${type.name}');
      } else if (_percentFactor(measurement.unit) case final factor?) {
        final percent = measurement.value * factor;
        if (percent >= 0 && percent <= 100) {
          percentages.add(_Reading(measurement, percent, type));
        }
      }
    }

    final bySlot = <String, List<({_Reading percentage, _Reading total})>>{};
    for (final percentage in percentages.sortedBy(
      (item) => item.measurement.id,
    )) {
      final measurement = percentage.measurement;
      final type = percentage.type!;
      final day = _dayKey(measurement);
      if (reportedAbsolute.contains('$day|${type.name}')) continue;
      final candidates = <({_Reading total, bool sameDocument, Duration gap})>[
        for (final total in totalsByDay[day] ?? const <_Reading>[])
          (
            total: total,
            sameDocument:
                measurement.documentId != null &&
                measurement.documentId == total.measurement.documentId,
            gap: measurement.takenAt
                .difference(total.measurement.takenAt)
                .abs(),
          ),
      ].where((item) => item.sameDocument || item.gap <= pairWindow).toList();
      if (candidates.isEmpty) continue;
      candidates.sort((left, right) {
        if (left.sameDocument != right.sameDocument) {
          return left.sameDocument ? -1 : 1;
        }
        final gap = left.gap.compareTo(right.gap);
        return gap != 0
            ? gap
            : left.total.measurement.id.compareTo(right.total.measurement.id);
      });
      final best = candidates.first;
      final tied = candidates.where(
        (item) =>
            item.sameDocument == best.sameDocument && item.gap == best.gap,
      );
      if (tied.any((item) => !_same(item.total.value, best.total.value))) {
        continue;
      }
      bySlot
          .putIfAbsent('${type.name}|${best.total.measurement.id}', () => [])
          .add((percentage: percentage, total: best.total));
    }

    return [
      for (final readings in bySlot.values)
        if (readings.every(
          (item) =>
              _same(item.percentage.value, readings.first.percentage.value),
        ))
          _Slot(readings.first.percentage, readings.first.total),
    ];
  }

  Map<String, _Role> _roles(List<Biomarker> biomarkers) => {
    for (final biomarker in biomarkers)
      if (!biomarker.deleted) biomarker.id: ?_roleOf(biomarker),
  };

  /// The absolute series each type's calculated counts join: a curated row
  /// before an import's provisional one, then the oldest, so the series does
  /// not move when another candidate appears later.
  Map<LeukocyteType, Biomarker> _targets(
    List<Biomarker> biomarkers,
    Map<String, _Role> roles,
  ) {
    final candidates = <LeukocyteType, List<Biomarker>>{};
    for (final biomarker in biomarkers) {
      final type = roles[biomarker.id]?.type;
      if (type == null ||
          biomarker.isCalculated ||
          _kindOf(biomarker) != _Kind.absolute) {
        continue;
      }
      candidates.putIfAbsent(type, () => []).add(biomarker);
    }
    return {
      for (final MapEntry(key: type, value: items) in candidates.entries)
        type: items.sorted((left, right) {
          if (left.isTemporary != right.isTemporary) {
            return left.isTemporary ? 1 : -1;
          }
          final created = left.createdAt.compareTo(right.createdAt);
          return created != 0 ? created : left.id.compareTo(right.id);
        }).first,
    };
  }

  static _Role? _roleOf(Biomarker biomarker) {
    final names = _names(biomarker);
    // A urine strip reports leukocytes too, and so can a puncture fluid; none
    // of them is the blood count the percentages are shares of.
    if (names.any(
      (name) => _otherSpecimens.any((word) => containsWordPrefix(name, word)),
    )) {
      return null;
    }
    for (final name in names) {
      final core = _core(name);
      if (_totalNames.contains(core)) return const _Role(null);
      for (final type in LeukocyteType.values) {
        if (type.names.contains(core)) return _Role(type);
      }
    }
    return null;
  }

  /// Whether a biomarker holds absolute counts, judged by what its names say
  /// and then by its unit. The legacy ids come last: they only ever named the
  /// absolute counts, but a row's current names and unit say more about what
  /// it holds now.
  _Kind _kindOf(Biomarker biomarker) {
    var absolute = false;
    var relative = false;
    for (final name in _names(biomarker)) {
      final words = foldForMatching(name).split(' ');
      if (name.contains('#') ||
          words.contains('anc') ||
          words.any(_absoluteWords.contains)) {
        absolute = true;
      }
      if (name.contains('%') || words.any(_relativeWords.contains)) {
        relative = true;
      }
    }
    if (absolute != relative) return absolute ? _Kind.absolute : _Kind.relative;
    if (_cellsPerNanolitre(biomarker.defaultUnit) != null) {
      return _Kind.absolute;
    }
    if (_percentFactor(biomarker.defaultUnit) != null) return _Kind.relative;
    final id = biomarker.id.toLowerCase();
    return LeukocyteType.values.any((type) => type.catalogId == id)
        ? _Kind.absolute
        : _Kind.unknown;
  }

  /// The factor from [unit] to 10^9/L, or null when it is not a cell count.
  ///
  /// `g/L` is here because [UnitConversionService.normalizeUnit] folds case,
  /// and German reports print the leukocyte count in G/l — giga per litre. A
  /// leukocyte count has no mass, so for one the folded spelling can only
  /// mean that.
  double? _cellsPerNanolitre(String unit) =>
      _cellCountFactors[_units
          .normalizeUnit(unit)
          .toLowerCase()
          .replaceAll(' ', '')];

  double? _percentFactor(String unit) => switch (_units.normalizeUnit(unit)) {
    '%' => 1.0,
    'ratio' => 100.0,
    _ => null,
  };

  static const _cellCountFactors = <String, double>{
    '10^9/l': 1,
    'x10^9/l': 1,
    '10e9/l': 1,
    'x10e9/l': 1,
    '10*9/l': 1,
    'g/l': 1,
    'gpt/l': 1,
    'giga/l': 1,
    '1/nl': 1,
    '10^3/ul': 1,
    'x10^3/ul': 1,
    '10e3/ul': 1,
    'tsd./ul': 1,
    'k/ul': 1,
    '10^3/mm^3': 1,
    '10^3/mm3': 1,
    'cells/ul': 0.001,
    '/ul': 0.001,
    '1/ul': 0.001,
    'zellen/ul': 0.001,
    '/mm^3': 0.001,
    '/mm3': 0.001,
  };

  static const _totalNames = {
    'leukozyten',
    'leukocytes',
    'leucocytes',
    'leukozytenzahl',
    'leukos',
    'leuko',
    'wbc',
    'white blood cells',
    'white blood cell',
    'white cells',
  };

  /// Words that say which kind of count a name is, removed before the name is
  /// compared with the type names. `anc` also says absolute, but it is the
  /// whole name rather than a qualifier, so it stays a neutrophil name.
  static const _absoluteWords = {'absolut', 'absolute', 'abs'};
  static const _relativeWords = {
    'relativ',
    'relative',
    'rel',
    'prozent',
    'prozentual',
    'percent',
    'percentage',
    'pct',
    'anteil',
  };
  static const _neutralWords = {
    'anzahl',
    'zahl',
    'count',
    'gesamt',
    'total',
    'im',
    'blut',
    'maschinell',
  };

  static const _otherSpecimens = [
    'urin',
    'harn',
    'liquor',
    'csf',
    'punktat',
    'sediment',
    'stuhl',
    'sputum',
    'lavage',
    'synovia',
    'pleura',
    'aszites',
  ];

  static List<String> _names(Biomarker biomarker) => [
    biomarker.id,
    biomarker.canonicalName,
    biomarker.displayName,
    ...biomarker.synonyms,
  ];

  static String _core(String name) =>
      foldForMatching(withoutParentheticals(name))
          .split(' ')
          .where(
            (word) =>
                word.isNotEmpty &&
                !_absoluteWords.contains(word) &&
                !_relativeWords.contains(word) &&
                !_neutralWords.contains(word),
          )
          .join(' ');

  static String _dayKey(Measurement measurement) {
    final value = measurement.takenAt;
    return '${measurement.profileId}|${value.year}-${value.month}-${value.day}';
  }

  static bool _same(double left, double right) => (left - right).abs() < 1e-9;

  static String _plain(double value) => value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toString();
}

enum _Kind { absolute, relative, unknown }

/// A biomarker's part in a differential: the leukocyte total when [type] is
/// null, else that type's count.
class _Role {
  const _Role(this.type);

  final LeukocyteType? type;
}

class _Reading {
  const _Reading(this.measurement, this.value, [this.type]);

  final Measurement measurement;

  /// A total in 10^9/L, or a share in percent.
  final double value;
  final LeukocyteType? type;
}

class _Slot {
  const _Slot(this.percentage, this.total);

  final _Reading percentage;
  final _Reading total;

  LeukocyteType get type => percentage.type!;
}
