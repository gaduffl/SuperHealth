import '../data/unit_conversion_registry.dart';

/// Service for handling unit conversions between different biomarker units
class UnitConversionService {
  static const Map<String, double> _massPrefixes = {
    'pg': 1e-12,
    'ng': 1e-9,
    'ug': 1e-6,
    'mg': 1e-3,
    'g': 1.0,
  };

  static const Map<String, double> _amountPrefixes = {
    'pmol': 1e-12,
    'nmol': 1e-9,
    'umol': 1e-6,
    'mmol': 1e-3,
    'mol': 1.0,
  };

  static const Map<String, double> _volumeUnits = {
    'uL': 1e-6,
    'mL': 1e-3,
    'dL': 1e-1,
    'L': 1.0,
  };

  /// Conversion factors that require biomarker-specific context
  static const Map<String, Map<String, double>> _conversionFactors =
      unitConversionRegistry;

  static const Map<String, String> _unitAliases = {
    'mg/dl': 'mg/dL',
    'mmol/l': 'mmol/L',
    'mg/l': 'mg/L',
    'g/dl': 'g/dL',
    'g/l': 'g/L',
    'ug/dl': 'ug/dL',
    'ug/l': 'ug/L',
    'ug/ml': 'ug/mL',
    'ng/dl': 'ng/dL',
    'ng/l': 'ng/L',
    'ng/ml': 'ng/mL',
    'pg/ml': 'pg/mL',
    'pmol/l': 'pmol/L',
    'nmol/l': 'nmol/L',
    'uiu/ml': 'uIU/mL',
    'miu/l': 'mIU/L',
    'meq/l': 'mEq/L',
    'umol/l': 'umol/L',
    'umol/dl': 'umol/dL',
    'mmol/l rbc': 'mmol/L RBC',
    'mg/l rbc': 'mg/L RBC',
    'umol/l rbc': 'umol/L RBC',
    '10^3/ul': '10^3/uL',
    '10^6/ul': '10^6/uL',
    '10^9/l': '10^9/L',
    '10^12/l': '10^12/L',
    'cells/ul': 'cells/uL',
    'cells/mm^3': 'cells/uL',
    'tsd/ul': '10^3/uL',
    'mio/ul': '10^6/uL',
    '/nl': '10^9/L',
    '/pl': '10^12/L',
    'fl': 'fL',
    'pl': 'pL',
    'u/l': 'U/L',
    'u/ml': 'U/mL',
    'iu/l': 'IU/L',
    'iu/ml': 'IU/mL',
    'mu/l': 'mU/L',
    'uu/ml': 'uU/mL',
    'ukat/l': 'ukat/L',
    'ml/min': 'mL/min',
    'ml/min/1,73m2kof': 'mL/min/1.73 m^2',
    'ml/min/1.73m2': 'mL/min/1.73 m^2',
    'ml/min/1.73 m^2': 'mL/min/1.73 m^2',
    'mg2/dl2': 'mg^2/dL^2',
    'mg^2/dl^2': 'mg^2/dL^2',
    'umol trolox-eq./l': 'umol/L Trolox-eq.',
    'mg trolox/l': 'mg/L Trolox',
    'ratio': 'ratio',
    '1/1': 'ratio',
    'l/l': 'ratio',
    '%': '%',
  };

  static const Map<String, String> _biomarkerCategories = {
    'glu': 'glucose',
    'glucose': 'glucose',
    'eag': 'glucose',
    'chol': 'cholesterol',
    'cholesterol': 'cholesterol',
    'cholesterol_total': 'cholesterol',
    'total_cholesterol': 'cholesterol',
    'hdl': 'cholesterol',
    'hdl_c': 'cholesterol',
    'ldl': 'cholesterol',
    'ldl_c': 'cholesterol',
    'ldl_friedewald': 'cholesterol',
    'non_hdl': 'cholesterol',
    'non_hdl_c': 'cholesterol',
    'apob': 'apolipoprotein',
    'apo_b': 'apolipoprotein',
    'apolipoprotein_b': 'apolipoprotein',
    'tg': 'triglycerides',
    'triglyceride': 'triglycerides',
    'triglycerides': 'triglycerides',
    'crea': 'creatinine',
    'u_crea': 'creatinine',
    'hb': 'hemoglobin',
    'hemoglobin': 'hemoglobin',
    'mchc': 'hemoglobin',
    'alb': 'albumin',
    'bilirubin': 'bilirubin',
    'ca': 'calcium',
    'calcium': 'calcium',
    'phosphate': 'phosphorus',
    'mg': 'magnesium',
    'magnesium_serum': 'magnesium',
    'rbc_mg': 'rbc_magnesium',
    'urea': 'urea',
    'uric_acid': 'uric_acid',
    'cysc': 'cystatin_c',
    'crp': 'crp',
    'hscrp': 'crp',
    'hcy': 'homocysteine',
    'ins': 'insulin',
    'cort': 'cortisol',
    'dhea_s': 'dhea_s',
    'prog': 'progesterone',
    'e2': 'estradiol',
    'estradiol': 'estradiol',
    'testo': 'testosterone',
    'vitb12': 'vitamin_b12',
    'vitb2': 'vitamin_b2',
    'vitamin_b2': 'vitamin_b2',
    'vitamin_e': 'vitamin_e',
    'alpha_tocopherol': 'vitamin_e',
    'fol': 'folate',
    '25_oh_d3': 'vitamin_d',
    'i': 'iodine',
    'se': 'selenium',
    'selenium': 'selenium',
    'zn': 'zinc',
    'zinc': 'zinc',
    'tibc': 'iron',
    'ts': 'iron',
    'transferrin_saturation': 'iron',
    'ferritin': 'ferritin',
    'oxldl': 'oxldl',
    'tac': 'tac',
    'tm': 'tumor_marker_umL',
    'tumor_markers_general': 'tumor_marker_umL',
    'fpsa': 'psa',
    'tpsa': 'psa',
    'ck': 'enzyme_activity',
    'creatine_kinase': 'enzyme_activity',
    'alt': 'enzyme_activity',
    'ast': 'enzyme_activity',
    'ggt': 'enzyme_activity',
    'wbc': 'cell_count_10e9',
    'neut': 'cell_count_10e9',
    'lymphs': 'cell_count_10e9',
    'monos': 'cell_count_10e9',
    'eos': 'cell_count_10e9',
    'basos': 'cell_count_10e9',
    'plt': 'cell_count_10e9',
    'rbc': 'cell_count_10e12',
    'mcv': 'volume_fL',
    'mpv': 'volume_fL',
    'mch': 'mch',
    'na': 'sodium',
    'sodium': 'sodium',
    'k': 'potassium',
    'potassium': 'potassium',
    'u_alb': 'urine_albumin',
    'acr': 'acr',
    'tsh': 'thyroid_tsh',
    'ft4': 'thyroid_ft4',
    'ft3': 'thyroid_ft3',
    'gfr': 'egfr',
    'gfr_capa': 'egfr',
  };
  double? convertValue(
    double value,
    String fromUnit,
    String toUnit,
    String biomarkerId,
  ) {
    final normalizedFrom = normalizeUnit(fromUnit);
    final normalizedTo = normalizeUnit(toUnit);

    if (normalizedFrom == normalizedTo) {
      return value;
    }

    if (normalizedFrom == 'ratio' && normalizedTo == '%') {
      return value * 100.0;
    }
    if (normalizedFrom == '%' && normalizedTo == 'ratio') {
      return value / 100.0;
    }

    final category = getBiomarkerCategory(biomarkerId);
    final categoryResult = _convertUsingCategory(
      value,
      normalizedFrom,
      normalizedTo,
      category,
    );
    if (categoryResult != null) {
      return categoryResult;
    }

    final massResult = _convertMassPerVolume(
      value,
      normalizedFrom,
      normalizedTo,
    );
    if (massResult != null) {
      return massResult;
    }

    final amountResult = _convertAmountPerVolume(
      value,
      normalizedFrom,
      normalizedTo,
    );
    if (amountResult != null) {
      return amountResult;
    }

    final unitResult = _convertUnitsPerVolume(
      value,
      normalizedFrom,
      normalizedTo,
    );
    if (unitResult != null) {
      return unitResult;
    }

    return null;
  }

  /// Tries all stable IDs and aliases known for one biomarker.
  ///
  /// Legacy exports localized the display name but retained their stable
  /// catalog ID among the synonyms. Trying those keys keeps biomarker-specific
  /// conversions deterministic without guessing from the display language.
  double? convertValueForBiomarkerKeys(
    double value,
    String fromUnit,
    String toUnit,
    Iterable<String> biomarkerKeys,
  ) {
    final seen = <String>{};
    for (final key in biomarkerKeys) {
      final normalizedKey = key.trim().toLowerCase();
      if (normalizedKey.isEmpty || !seen.add(normalizedKey)) continue;
      final converted = convertValue(value, fromUnit, toUnit, normalizedKey);
      if (converted != null) return converted;
    }
    return null;
  }

  double? _convertUsingCategory(
    double value,
    String fromUnit,
    String toUnit,
    String? category,
  ) {
    if (category == null) return null;
    final factors = _conversionFactors[category];
    if (factors == null) return null;

    final directKey = '${fromUnit}_to_$toUnit';
    if (factors.containsKey(directKey)) {
      return value * factors[directKey]!;
    }

    final reverseKey = '${toUnit}_to_$fromUnit';
    if (factors.containsKey(reverseKey)) {
      return value / factors[reverseKey]!;
    }

    return null;
  }

  double? _convertMassPerVolume(double value, String from, String to) {
    final fromMatch = _matchMassPerVolume(from);
    final toMatch = _matchMassPerVolume(to);
    if (fromMatch == null || toMatch == null) return null;
    if (fromMatch.suffix != toMatch.suffix) return null;

    final fromMass = _massPrefixes[fromMatch.mass];
    final toMass = _massPrefixes[toMatch.mass];
    final fromVol = _volumeUnits[fromMatch.volume];
    final toVol = _volumeUnits[toMatch.volume];
    if (fromMass == null ||
        toMass == null ||
        fromVol == null ||
        toVol == null) {
      return null;
    }

    final gramsPerLiter = value * fromMass / fromVol;
    return gramsPerLiter * toVol / toMass;
  }

  double? _convertAmountPerVolume(double value, String from, String to) {
    final fromMatch = _matchAmountPerVolume(from);
    final toMatch = _matchAmountPerVolume(to);
    if (fromMatch == null || toMatch == null) return null;
    if (fromMatch.suffix != toMatch.suffix) return null;

    final fromAmount = _amountPrefixes[fromMatch.amount];
    final toAmount = _amountPrefixes[toMatch.amount];
    final fromVol = _volumeUnits[fromMatch.volume];
    final toVol = _volumeUnits[toMatch.volume];
    if (fromAmount == null ||
        toAmount == null ||
        fromVol == null ||
        toVol == null) {
      return null;
    }

    final molPerLiter = value * fromAmount / fromVol;
    return molPerLiter * toVol / toAmount;
  }

  double? _convertUnitsPerVolume(double value, String from, String to) {
    final fromMatch = _matchUnitsPerVolume(from);
    final toMatch = _matchUnitsPerVolume(to);
    if (fromMatch == null || toMatch == null) return null;
    if (fromMatch.suffix != toMatch.suffix) return null;

    final fromVol = _volumeUnits[fromMatch.volume];
    final toVol = _volumeUnits[toMatch.volume];
    if (fromVol == null || toVol == null) return null;

    final unitsPerLiter = value / fromVol;
    return unitsPerLiter * toVol;
  }

  _MassUnit? _matchMassPerVolume(String unit) {
    final match = RegExp(
      r'^(pg|ng|ug|mg|g)/(uL|mL|dL|L)(.*)$',
    ).firstMatch(unit);
    if (match == null) return null;
    return _MassUnit(match.group(1)!, match.group(2)!, match.group(3)!);
  }

  _AmountUnit? _matchAmountPerVolume(String unit) {
    final match = RegExp(
      r'^(pmol|nmol|umol|mmol|mol)/(uL|mL|dL|L)(.*)$',
    ).firstMatch(unit);
    if (match == null) return null;
    return _AmountUnit(match.group(1)!, match.group(2)!, match.group(3)!);
  }

  _UnitsPerVolume? _matchUnitsPerVolume(String unit) {
    final match = RegExp(r'^(U)/(uL|mL|dL|L)(.*)$').firstMatch(unit);
    if (match == null) return null;
    return _UnitsPerVolume(match.group(1)!, match.group(2)!, match.group(3)!);
  }

  Set<String> _collectMassTargets(String source) {
    final match = _matchMassPerVolume(source);
    if (match == null) return {source};
    final targets = <String>{};
    for (final mass in _massPrefixes.keys) {
      for (final volume in _volumeUnits.keys) {
        targets.add('$mass/$volume${match.suffix}');
      }
    }
    return targets;
  }

  Set<String> _collectAmountTargets(String source) {
    final match = _matchAmountPerVolume(source);
    if (match == null) return {source};
    final targets = <String>{};
    for (final amount in _amountPrefixes.keys) {
      for (final volume in _volumeUnits.keys) {
        targets.add('$amount/$volume${match.suffix}');
      }
    }
    return targets;
  }

  Set<String> _collectUnitTargets(String source) {
    final match = _matchUnitsPerVolume(source);
    if (match == null) return {source};
    final targets = <String>{};
    for (final volume in _volumeUnits.keys) {
      targets.add('U/$volume${match.suffix}');
    }
    return targets;
  }

  String normalizeUnit(String unit) {
    final replaced = unit.trim().replaceAll(RegExp(r'[µμ]'), 'u');
    final lower = replaced.toLowerCase();
    return _unitAliases[lower] ?? replaced;
  }

  String? getBiomarkerCategory(String biomarkerId) {
    final key = biomarkerId.trim().toLowerCase();
    return _biomarkerCategories[key];
  }

  bool canConvert(String fromUnit, String toUnit, String biomarkerId) {
    final result = convertValue(1.0, fromUnit, toUnit, biomarkerId);
    return result != null;
  }

  List<String> getPossibleTargetUnits(String sourceUnit, String biomarkerId) {
    final normalizedSource = normalizeUnit(sourceUnit);
    final targets = <String>{normalizedSource};

    if (normalizedSource == 'ratio') {
      targets.add('%');
    } else if (normalizedSource == '%') {
      targets.add('ratio');
    }

    final category = getBiomarkerCategory(biomarkerId);
    if (category != null) {
      final factors = _conversionFactors[category];
      if (factors != null) {
        for (final entry in factors.entries) {
          final parts = entry.key.split('_to_');
          if (parts.length == 2) {
            if (parts[0] == normalizedSource) targets.add(parts[1]);
            if (parts[1] == normalizedSource) targets.add(parts[0]);
          }
        }
      }
    }

    targets.addAll(_collectMassTargets(normalizedSource));
    targets.addAll(_collectAmountTargets(normalizedSource));
    targets.addAll(_collectUnitTargets(normalizedSource));

    return targets.toList();
  }

  Map<String, double?> convertRange(
    double? low,
    double? high,
    String fromUnit,
    String toUnit,
    String biomarkerId,
  ) {
    return {
      'low': low != null
          ? convertValue(low, fromUnit, toUnit, biomarkerId)
          : null,
      'high': high != null
          ? convertValue(high, fromUnit, toUnit, biomarkerId)
          : null,
    };
  }

  double? getConversionFactor(
    String fromUnit,
    String toUnit,
    String biomarkerId,
  ) {
    return convertValue(1.0, fromUnit, toUnit, biomarkerId);
  }

  String? getPreferredUnit(String biomarkerId) {
    switch (getBiomarkerCategory(biomarkerId)) {
      case 'glucose':
      case 'cholesterol':
      case 'triglycerides':
        return 'mg/dL';
      case 'creatinine':
        return 'mg/dL';
      case 'urine_albumin':
      case 'cystatin_c':
        return 'mg/L';
      case 'hemoglobin':
        return 'g/dL';
      case 'albumin':
        return 'g/dL';
      case 'bilirubin':
        return 'mg/dL';
      case 'urea':
        return 'mg/dL';
      case 'crp':
        return 'mg/L';
      case 'calcium':
        return 'mg/dL';
      case 'phosphorus':
        return 'mg/dL';
      case 'magnesium':
        return 'mg/dL';
      case 'iron':
        return 'ug/dL';
      case 'apolipoprotein':
        return 'mg/dL';
      case 'insulin':
        return 'uIU/mL';
      case 'vitamin_d':
        return 'ng/mL';
      case 'vitamin_b12':
        return 'pg/mL';
      case 'vitamin_b2':
        return 'ug/L';
      case 'folate':
        return 'ng/mL';
      case 'estradiol':
        return 'pg/mL';
      case 'progesterone':
        return 'ng/mL';
      case 'testosterone':
        return 'ng/dL';
      case 'cortisol':
        return 'ug/dL';
      case 'dhea_s':
        return 'ug/dL';
      case 'homocysteine':
        return 'umol/L';
      case 'uric_acid':
        return 'mg/dL';
      case 'iodine':
      case 'selenium':
        return 'ug/L';
      case 'zinc':
        return 'ug/dL';
      case 'rbc_magnesium':
        return 'mmol/L RBC';
      case 'cell_count_10e9':
        return '10^9/L';
      case 'cell_count_10e12':
        return '10^12/L';
      case 'volume_fL':
        return 'fL';
      case 'mch':
        return 'pg';
      case 'psa':
        return 'ng/mL';
      case 'ferritin':
        return 'ng/mL';
      case 'tac':
        return 'umol/L Trolox-eq.';
      case 'tumor_marker_umL':
        return 'U/mL';
      case 'enzyme_activity':
      case 'oxldl':
        return 'U/L';
      case 'sodium':
      case 'potassium':
        return 'mmol/L';
      case 'acr':
        return 'mg/g';
      case 'thyroid_tsh':
        return 'mIU/L';
      case 'thyroid_ft4':
        return 'ng/dL';
      case 'thyroid_ft3':
        return 'pg/mL';
      default:
        return null;
    }
  }

  String formatValueWithUnit(double value, String unit) {
    final normalized = normalizeUnit(unit);
    final lower = normalized.toLowerCase();
    int decimals = 1;

    if (lower.contains('mmol/l') ||
        lower.contains('umol/l') ||
        lower.contains('pmol/l')) {
      decimals = value < 10 ? 2 : 1;
    } else if (lower.contains('ng/ml') ||
        lower.contains('pg/ml') ||
        lower.contains('ug/l')) {
      decimals = value < 10 ? 2 : 1;
    } else if (lower.contains('uiu/ml') || lower.contains('miu/l')) {
      decimals = value < 10 ? 2 : 1;
    } else if (lower.contains('u/l') ||
        lower.contains('u/ml') ||
        lower.contains('ukat/l')) {
      decimals = value < 10 ? 2 : 1;
    } else if (lower.contains('10^') || lower.contains('cells/ul')) {
      decimals = value < 10 ? 3 : 0;
    } else if (lower.contains('g/l') ||
        lower.contains('mg/dl') ||
        lower.contains('mg/l')) {
      decimals = value < 10 ? 2 : 1;
    }

    return '${value.toStringAsFixed(decimals)} $normalized';
  }

  /// Checks if a unit is a ratio type (1/1, l/l, ratio) that should display as %.
  bool isRatioUnit(String unit) {
    final normalized = normalizeUnit(unit);
    // All ratio variants (1/1, l/l) are normalized to 'ratio'
    return normalized == 'ratio';
  }

  /// Returns the value and unit adjusted for display purposes.
  /// Ratio units (ratio, 1/1, l/l) are converted to % for better readability.
  ({double value, String unit, bool converted}) getDisplayValueAndUnit(
    double value,
    String unit,
  ) {
    final normalized = normalizeUnit(unit);
    if (isRatioUnit(normalized)) {
      return (value: value * 100.0, unit: '%', converted: true);
    }
    return (value: value, unit: normalized, converted: false);
  }
}

class _MassUnit {
  final String mass;
  final String volume;
  final String suffix;
  _MassUnit(this.mass, this.volume, this.suffix);
}

class _AmountUnit {
  final String amount;
  final String volume;
  final String suffix;
  _AmountUnit(this.amount, this.volume, this.suffix);
}

class _UnitsPerVolume {
  final String unit;
  final String volume;
  final String suffix;
  _UnitsPerVolume(this.unit, this.volume, this.suffix);
}
