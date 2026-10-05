import '../domain/entities.dart';

/// Resolves one laboratory's prices without borrowing from another one.
/// Catalog identity and package membership are independent of their prices.
class LabCatalogPricing {
  LabCatalogPricing({
    required this.prices,
    this.labName,
    this.packageOffers = const [],
    this.packageMembers = const {},
  });

  final List<LabPrice> prices;
  final String? labName;
  final List<BiomarkerPackage> packageOffers;
  final Map<String, Set<String>> packageMembers;

  static List<String> labNames(List<LabPrice> prices) {
    final names = <String, String>{};
    for (final price in prices) {
      if (!price.deleted) {
        names.putIfAbsent(labKey(price.labName), () => price.labName);
      }
    }
    return names.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  LabPrice? priceFor(String targetId, {bool isPackage = false, String? lab}) {
    final key = labKey(lab ?? labName ?? '');
    final matches =
        prices
            .where(
              (price) =>
                  (isPackage ? price.packageId : price.biomarkerId) ==
                      targetId &&
                  labKey(price.labName) == key,
            )
            .toList()
          ..sort((a, b) {
            final byDate = b.updatedAt.compareTo(a.updatedAt);
            return byDate != 0 ? byDate : b.id.compareTo(a.id);
          });
    final latest = matches.firstOrNull;
    return latest == null || latest.deleted ? null : latest;
  }

  Map<String, Object?> _priceFields(
    String id,
    String? originalLab, {
    bool isPackage = false,
    double? originalPrice,
    DateTime? originalCheckedAt,
  }) {
    final selected = labName ?? originalLab;
    if (selected == null || selected.trim().isEmpty) return const {};
    final price = priceFor(id, isPackage: isPackage, lab: selected);
    final recorded = prices.any(
      (row) =>
          (isPackage ? row.packageId : row.biomarkerId) == id &&
          labKey(row.labName) == labKey(selected),
    );
    final legacy = !recorded && labKey(originalLab ?? '') == labKey(selected);
    return {
      'price_eur': price?.priceEur ?? (legacy ? originalPrice : null),
      'lab_name': selected,
      'price_checked_at':
          (price?.checkedAt ?? (legacy ? originalCheckedAt : null))
              ?.toUtc()
              .toIso8601String(),
    };
  }

  List<Biomarker> catalog(List<Biomarker> items) => [
    for (final item in items)
      Biomarker.fromMap({
        ...item.toMap(),
        ..._priceFields(
          item.id,
          item.labName,
          originalPrice: item.priceEur,
          originalCheckedAt: item.priceCheckedAt,
        ),
      }),
  ];

  List<BiomarkerPackage> packages(List<BiomarkerPackage> items) => [
    for (final item in items)
      BiomarkerPackage.fromMap({
        ...item.toMap(),
        ..._priceFields(
          item.id,
          item.labName,
          isPackage: true,
          originalPrice: item.priceEur,
          originalCheckedAt: item.priceCheckedAt,
        ),
      }),
  ];

  /// Applies the same prices to the digest, tools and complete evidence package.
  /// The selected lab is a row so an empty catalog still changes the receipt.
  Map<String, Object?> projectSnapshot(Map<String, Object?> source) {
    final raw = source['data'];
    if (raw is! Map) return source;
    final data = Map<String, Object?>.from(raw);
    final rows = data['biomarker_catalog'];
    if (rows is List) {
      data['biomarker_catalog'] = catalog([
        for (final row in rows)
          if (row is Map) Biomarker.fromMap(Map<String, Object?>.from(row)),
      ]).map((item) => item.toMap()).toList();
    }
    if (packageOffers.isNotEmpty) {
      data['lab_package_offers'] = [
        for (final offer in packageOffers)
          {
            ...offer.toMap(),
            'biomarker_ids':
                (packageMembers[offer.id] ?? const <String>{}).toList()..sort(),
          },
      ];
    }
    if (labName != null) {
      data['lab_pricing'] = [
        {'id': 'selected-lab', 'lab_name': labName},
      ];
    }
    final manifest = source['manifest'];
    return {
      ...source,
      'data': data,
      if (manifest is Map)
        'manifest': {
          ...manifest,
          'counts': {
            for (final entry in data.entries)
              if (entry.value is List) entry.key: (entry.value as List).length,
          },
        },
    };
  }
}
