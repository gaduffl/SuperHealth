// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../data/app_database.dart';
import '../data/health_repository.dart';
import '../domain/entities.dart';

class ImportSourceFile {
  const ImportSourceFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class LegacyImportPreview {
  // The parsed bundle remains private to the import workflow.
  LegacyImportPreview._({
    required this.sourceHash,
    required this.sourceKinds,
    required this.counts,
    required this.warnings,
    required this.duplicates,
    required this.alreadyImported,
    required _LegacyBundle bundle,
  }) : _bundle = bundle;

  final String sourceHash;
  final List<String> sourceKinds;
  final Map<String, int> counts;
  final List<String> warnings;
  final List<String> duplicates;
  final bool alreadyImported;
  final _LegacyBundle _bundle;

  bool get canImport =>
      !alreadyImported && counts.values.any((value) => value > 0);

  Map<String, Object?> toJson() => {
    'source_hash': sourceHash,
    'source_kinds': sourceKinds,
    'counts': counts,
    'warnings': warnings,
    'duplicates': duplicates,
    'already_imported': alreadyImported,
  };
}

class LegacyImportResult {
  const LegacyImportResult({required this.importId, required this.inserted});

  final String importId;
  final Map<String, int> inserted;
}

class LegacyPdfImportPreview {
  LegacyPdfImportPreview._({
    required this.selectedFiles,
    required this.matchedDocuments,
    required this.alreadyAvailable,
    required this.unmatchedFiles,
    required this.warnings,
    required List<_LegacyPdfMatch> matches,
  }) : _matches = matches;

  final int selectedFiles;
  final int matchedDocuments;
  final int alreadyAvailable;
  final int unmatchedFiles;
  final List<String> warnings;
  final List<_LegacyPdfMatch> _matches;

  int get pendingDocuments => matchedDocuments - alreadyAvailable;
  bool get canImport => pendingDocuments > 0;
}

class LegacyPdfImportResult {
  const LegacyPdfImportResult({
    required this.attachedDocuments,
    required this.alreadyAvailable,
    required this.unmatchedFiles,
  });

  final int attachedDocuments;
  final int alreadyAvailable;
  final int unmatchedFiles;
}

class LegacyImportService {
  LegacyImportService(
    this._database,
    this._repository, {
    Uuid? uuid,
    Future<Directory> Function()? documentsDirectory,
  }) : _uuid = uuid ?? const Uuid(),
       _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  final AppDatabase _database;
  final HealthRepository _repository;
  final Uuid _uuid;
  final Future<Directory> Function() _documentsDirectory;

  Future<LegacyImportPreview> preview(
    List<ImportSourceFile> files, {
    required Profile fallbackProfile,
  }) async {
    if (files.isEmpty) {
      throw ArgumentError('At least one import file is required');
    }
    final ordered = [...files]..sort((a, b) => a.name.compareTo(b.name));
    final hashBytes = BytesBuilder(copy: false);
    for (final file in ordered) {
      hashBytes
        ..add(utf8.encode(file.name))
        ..addByte(0)
        ..add(file.bytes)
        ..addByte(0);
    }
    final sourceHash = sha256.convert(hashBytes.takeBytes()).toString();

    final db = await _database.database;
    final imported = await db.query(
      'import_runs',
      where: 'source_hash = ? AND rolled_back_at IS NULL',
      whereArgs: [sourceHash],
      limit: 1,
    );

    final bundle = _LegacyBundle(
      sourceHash: sourceHash,
      fallbackProfileId: fallbackProfile.id,
      fallbackProfileName: fallbackProfile.displayName,
    );
    for (final file in ordered) {
      _parseFile(bundle, file);
    }
    _finalizeSupplementData(bundle);

    final existingProfiles = await _repository.profiles();
    final existingSupplements = <String, Set<String>>{};
    for (final profile in existingProfiles) {
      existingSupplements[profile.id] = (await _repository.supplements(
        profile.id,
      )).map((item) => _normalized(item.name)).toSet();
    }
    final existingBiomarkers = (await _repository.biomarkers())
        .map((item) => item.canonicalName)
        .toSet();

    for (final legacyProfile in bundle.profiles.values) {
      final sameName = existingProfiles.where(
        (profile) =>
            _normalized(profile.displayName) ==
            _normalized(legacyProfile.displayName),
      );
      if (sameName.isNotEmpty && legacyProfile.directProfileId == null) {
        bundle.duplicates.add(
          'Profile “${legacyProfile.displayName}” will merge with the existing profile.',
        );
      }
    }
    for (final item in bundle.supplements) {
      final profile = bundle.profiles[item.profileKey];
      final existing = existingProfiles.where(
        (candidate) =>
            _normalized(candidate.displayName) ==
            _normalized(profile?.displayName ?? ''),
      );
      if (existing.isNotEmpty &&
          existingSupplements[existing.first.id]?.contains(
                _normalized(item.name),
              ) ==
              true) {
        bundle.duplicates.add(
          'Supplement “${item.name}” already exists for ${existing.first.displayName}.',
        );
      }
    }
    final bundledBiomarkers = <String, String>{};
    for (final biomarker in bundle.biomarkers) {
      final firstDisplayName = bundledBiomarkers[biomarker.canonicalName];
      if (firstDisplayName != null) {
        bundle.duplicates.add(
          'Biomarker “${biomarker.displayName}” will merge with '
          '“$firstDisplayName” because both use the canonical name '
          '“${biomarker.canonicalName}”.',
        );
      } else {
        bundledBiomarkers[biomarker.canonicalName] = biomarker.displayName;
      }
      if (existingBiomarkers.contains(biomarker.canonicalName)) {
        bundle.duplicates.add(
          'Biomarker “${biomarker.displayName}” will reuse the existing catalog entry.',
        );
      }
    }

    return LegacyImportPreview._(
      sourceHash: sourceHash,
      sourceKinds: bundle.sourceKinds.toList()..sort(),
      counts: bundle.counts,
      warnings: bundle.warnings,
      duplicates: bundle.duplicates.toSet().toList(),
      alreadyImported: imported.isNotEmpty,
      bundle: bundle,
    );
  }

  void _parseFile(_LegacyBundle bundle, ImportSourceFile file) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(file.bytes));
    } on Object catch (error) {
      bundle.warnings.add('${file.name}: invalid JSON ($error)');
      return;
    }

    final baseName = file.name.split('/').last.toLowerCase();
    if (decoded is Map) {
      final root = Map<String, dynamic>.from(decoded);
      if (root['schema'] == 'superhealth.snapshot') {
        bundle.warnings.add(
          '${file.name}: use Restore/Synchronize for SuperHealth snapshots.',
        );
        return;
      }
      if (_hasAny(root, const [
        'products',
        'schedules',
        'intakeHistory',
        'symptomEntries',
        'symptoms',
      ])) {
        bundle.sourceKinds.add('Supplement Manager');
        _parseSupplementPayload(bundle, root);
      }
      if (baseName.contains('biomarker')) {
        final profilesNode = root['profiles'];
        final profileRows =
            profilesNode is Map &&
                (profilesNode.containsKey('display_name') ||
                    profilesNode.containsKey('displayName') ||
                    profilesNode.containsKey('name'))
            ? [profilesNode]
            : _maps(profilesNode);
        for (final item in profileRows) {
          _parseProfile(bundle, Map<String, dynamic>.from(item));
        }
        if (root['profile'] is Map) {
          _parseProfile(
            bundle,
            Map<String, dynamic>.from(root['profile'] as Map),
          );
        }
        if (profileRows.isNotEmpty || root['profile'] is Map) {
          bundle.sourceKinds.add('Biomarkers');
        }
      }
      if (root['rows'] is List) {
        _parseNamedList(bundle, baseName, root['rows'] as List);
      }
      if (baseName == 'symptoms.json') {
        _parseSymptomsNode(bundle, root);
      }
      return;
    }
    if (decoded is List) {
      _parseNamedList(bundle, baseName, decoded);
      return;
    }
    bundle.warnings.add('${file.name}: unsupported JSON root type.');
  }

  void _parseNamedList(_LegacyBundle bundle, String name, List<dynamic> rows) {
    if (name.contains('product')) {
      bundle.sourceKinds.add('Supplement Manager');
      bundle.productNodes.addAll(rows.whereType<Map>());
    } else if (name.contains('intake')) {
      bundle.sourceKinds.add('Supplement Manager');
      bundle.intakeNodes.addAll(rows.whereType<Map>());
    } else if (name == 'profiles.json') {
      for (final item in rows.whereType<Map>()) {
        _parseProfile(bundle, Map<String, dynamic>.from(item));
      }
    } else if (name.contains('biomarker_list_entries')) {
      bundle.biomarkerListEntryNodes.addAll(rows.whereType<Map>());
      bundle.sourceKinds.add('Biomarkers');
    } else if (name.contains('biomarker_lists')) {
      bundle.biomarkerListNodes.addAll(rows.whereType<Map>());
      bundle.sourceKinds.add('Biomarkers');
    } else if (name.contains('user_overrides')) {
      bundle.userOverrideNodes.addAll(rows.whereType<Map>());
      bundle.sourceKinds.add('Biomarkers');
    } else if (name.contains('biomarker')) {
      bundle.sourceKinds.add('Biomarkers');
      for (final item in rows.whereType<Map>()) {
        _parseBiomarker(bundle, Map<String, dynamic>.from(item));
      }
    } else if (name.contains('measurement')) {
      bundle.sourceKinds.add('Biomarkers');
      bundle.measurementNodes.addAll(rows.whereType<Map>());
    } else if (name.contains('document')) {
      bundle.sourceKinds.add('Biomarkers');
      bundle.documentNodes.addAll(rows.whereType<Map>());
    } else if (name.contains('range')) {
      bundle.sourceKinds.add('Biomarkers');
      bundle.rangeNodes.addAll(rows.whereType<Map>());
    } else if (name.contains('symptom_entries')) {
      bundle.symptomEntryNodes.addAll(rows.whereType<Map>());
    } else if (name.contains('symptom_tags')) {
      bundle.symptomTagNodes.addAll(rows.whereType<Map>());
    } else {
      bundle.warnings.add('$name: no recognized dataset name.');
    }
  }

  void _parseSupplementPayload(
    _LegacyBundle bundle,
    Map<String, dynamic> root,
  ) {
    bundle.productNodes.addAll(_maps(root['products']));
    final schedules = root['schedules'] ?? root['schedule'];
    if (schedules is Map) {
      bundle.scheduleNode.addAll(Map<String, dynamic>.from(schedules));
    }
    bundle.intakeNodes.addAll(
      _maps(root['intakeHistory'] ?? root['intake_history']),
    );
    for (final item in _maps(root['profiles'])) {
      _parseProfile(bundle, Map<String, dynamic>.from(item));
    }
    final symptoms = root['symptoms'];
    if (symptoms is Map) {
      _parseSymptomsNode(bundle, Map<String, dynamic>.from(symptoms));
    }
    bundle.symptomEntryNodes.addAll(
      _maps(root['symptomEntries'] ?? root['symptom_entries']),
    );
    bundle.symptomTagNodes.addAll(
      _maps(root['symptomTags'] ?? root['symptom_tags']),
    );
  }

  void _parseSymptomsNode(_LegacyBundle bundle, Map<String, dynamic> node) {
    bundle.symptomEntryNodes.addAll(
      _maps(node['entries'] ?? node['symptomEntries']),
    );
    bundle.symptomTagNodes.addAll(_maps(node['tags'] ?? node['symptomTags']));
  }

  void _parseProfile(_LegacyBundle bundle, Map<String, dynamic> row) {
    final displayName =
        (row['display_name'] ?? row['displayName'] ?? row['name'])
            ?.toString()
            .trim();
    if (displayName == null || displayName.isEmpty) return;
    final legacyId = row['id']?.toString();
    final key = legacyId == null || legacyId.isEmpty
        ? 'name:${_normalized(displayName)}'
        : 'id:$legacyId';
    DateTime? dateOfBirth = DateTime.tryParse(
      (row['date_of_birth'] ?? row['dob'] ?? '').toString(),
    );
    final birthYear = _integer(row['birthYear']);
    if (dateOfBirth == null && birthYear != null) {
      dateOfBirth = DateTime(birthYear);
    }
    final weight = row['weight_kg'] ?? row['weight'];
    final height = row['height_cm'] ?? row['heightCm'] ?? row['height'];
    final existing = bundle.profiles[key];
    final importedHeight = _sensibleOptional(
      bundle,
      height,
      field: 'profile height',
      minimum: 30,
      maximum: 300,
    );
    final importedWeight = _sensibleOptional(
      bundle,
      weight,
      field: 'profile weight',
      minimum: 1,
      maximum: 1000,
    );
    bundle.profiles[key] = _LegacyProfile(
      key: key,
      legacyId: legacyId,
      displayName: displayName,
      dateOfBirth: dateOfBirth ?? existing?.dateOfBirth,
      sex: (row['sex'] ?? row['gender'])?.toString() ?? existing?.sex,
      heightCm: importedHeight ?? existing?.heightCm,
      weightKg: importedWeight ?? existing?.weightKg,
      notes: (row['notes']?.toString().trim().isNotEmpty ?? false)
          ? row['notes'].toString()
          : existing?.notes ?? '',
    );
  }

  void _parseBiomarker(_LegacyBundle bundle, Map<String, dynamic> row) {
    final displayName =
        [
              row['display_name_custom'],
              row['display_name'],
              row['displayName'],
              row['name'],
              row['canonical_name'],
            ]
            .map((value) => value?.toString().trim())
            .whereType<String>()
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (displayName.isEmpty) return;
    final canonical = HealthRepository.normalizeName(
      (row['canonical_name'] ?? row['canonicalName'] ?? displayName).toString(),
    );
    final rawPrice = row['price_eur'] ?? row['price'];
    final price = _nonNegativeOptional(
      bundle,
      rawPrice,
      field: 'biomarker price',
      record: displayName,
    );
    bundle.biomarkers.add(
      _LegacyBiomarker(
        legacyId: row['id']?.toString() ?? canonical,
        canonicalName: canonical,
        displayName: displayName,
        category: row['category']?.toString() ?? '',
        unit:
            (row['default_unit'] ?? row['unit_primary'] ?? row['unit'])
                ?.toString() ??
            '',
        priceEur: price,
        description: (row['description'] ?? row['notes'])?.toString() ?? '',
        synonyms: _combinedStringList([
          row['synonyms'],
          row['synonyms_json'],
          row['parser_synonyms'],
          row['parser_synonyms_json'],
          row['common_abbr'],
          row['common_abbr_json'],
        ]),
      ),
    );
  }

  static bool _hasAny(Map<String, dynamic> root, List<String> keys) =>
      keys.any(root.containsKey);

  static List<Map<dynamic, dynamic>> _maps(Object? node) {
    if (node is List) return node.whereType<Map>().toList();
    if (node is Map) return node.values.whereType<Map>().toList();
    return const [];
  }

  static double? _double(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : value == null
        ? null
        : double.tryParse('$value');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  static int? _integer(Object? value) {
    final parsed = _double(value);
    if (parsed == null || parsed != parsed.truncateToDouble()) return null;
    return parsed.toInt();
  }

  static bool _isNonFiniteNumber(Object? value) {
    if (value is num) return !value.isFinite;
    if (value is! String) return false;
    final parsed = double.tryParse(value.trim());
    return parsed != null && !parsed.isFinite;
  }

  static void _warnNonFinite(
    _LegacyBundle bundle,
    String field, {
    String? record,
  }) {
    bundle.warnings.add(
      'Ignored non-finite $field${record == null ? '' : ' for $record'}.',
    );
  }

  static double? _nonNegativeOptional(
    _LegacyBundle bundle,
    Object? raw, {
    required String field,
    String? record,
  }) {
    if (raw == null) return null;
    final value = _double(raw);
    if (value == null) {
      _warnNonFinite(bundle, field, record: record);
      return null;
    }
    if (value < 0) {
      bundle.warnings.add(
        'Ignored negative $field${record == null ? '' : ' for $record'}.',
      );
      return null;
    }
    return value;
  }

  static double? _sensibleOptional(
    _LegacyBundle bundle,
    Object? raw, {
    required String field,
    required double minimum,
    required double maximum,
  }) {
    if (raw == null) return null;
    final value = _double(raw);
    if (value == null) {
      _warnNonFinite(bundle, field);
      return null;
    }
    if (value < minimum || value > maximum) {
      bundle.warnings.add('Ignored $field outside $minimum..$maximum.');
      return null;
    }
    return value;
  }

  static List<String> _stringList(Object? value) {
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) return decoded.map((item) => '$item').toList();
      } on Object {
        return value.split(',').map((item) => item.trim()).toList();
      }
    }
    return value is List ? value.map((item) => '$item').toList() : const [];
  }

  static List<String> _combinedStringList(Iterable<Object?> values) {
    final result = <String>[];
    final seen = <String>{};
    for (final value in values) {
      for (final item in _stringList(value)) {
        final trimmed = item.trim();
        if (trimmed.isNotEmpty && seen.add(_normalized(trimmed))) {
          result.add(trimmed);
        }
      }
    }
    return result;
  }

  static String _normalized(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  void _finalizeSupplementData(_LegacyBundle bundle) {
    final fallbackKey = 'direct:${bundle.fallbackProfileId}';
    bundle.profiles.putIfAbsent(
      fallbackKey,
      () => _LegacyProfile(
        key: fallbackKey,
        displayName: bundle.fallbackProfileName,
        directProfileId: bundle.fallbackProfileId,
      ),
    );

    String profileKeyForName(Object? rawName) {
      final name = rawName?.toString().trim();
      if (name == null || name.isEmpty) return fallbackKey;
      final existing = bundle.profiles.values.where(
        (profile) => _normalized(profile.displayName) == _normalized(name),
      );
      if (existing.isNotEmpty) return existing.first.key;
      final key = 'name:${_normalized(name)}';
      bundle.profiles[key] = _LegacyProfile(key: key, displayName: name);
      return key;
    }

    for (final userName in bundle.scheduleNode.keys) {
      bundle.supplementProfileKeys.add(profileKeyForName(userName));
    }
    for (final row in bundle.intakeNodes) {
      bundle.supplementProfileKeys.add(
        profileKeyForName(row['userName'] ?? row['user_name']),
      );
    }
    for (final row in [
      ...bundle.symptomEntryNodes,
      ...bundle.symptomTagNodes,
    ]) {
      bundle.supplementProfileKeys.add(
        profileKeyForName(row['userName'] ?? row['user_name']),
      );
    }
    if (bundle.supplementProfileKeys.isEmpty) {
      bundle.supplementProfileKeys.add(fallbackKey);
    }

    final supplementByToken = <String, _LegacySupplement>{};
    for (final raw in bundle.productNodes) {
      final row = Map<String, dynamic>.from(raw);
      final name = row['name']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      final rawUnits = row['units_per_container'];
      var unitsPerContainer = _integer(rawUnits);
      if (rawUnits != null &&
          (unitsPerContainer == null || unitsPerContainer < 0)) {
        bundle.warnings.add('Ignored invalid units per container for $name.');
        unitsPerContainer = null;
      }
      final containerCount = _nonNegativeOptional(
        bundle,
        row['num_containers'] ?? row['container_count'],
        field: 'container count',
        record: name,
      );
      final price = _nonNegativeOptional(
        bundle,
        row['price'],
        field: 'supplement price',
        record: name,
      );
      for (final profileKey in bundle.supplementProfileKeys) {
        final token = '$profileKey|${_normalized(name)}';
        supplementByToken[token] = _LegacySupplement(
          token: token,
          profileKey: profileKey,
          name: name,
          brand: row['brand']?.toString() ?? '',
          form: row['form']?.toString() ?? '',
          ingredients: _normalizeIngredients(
            bundle,
            _maps(row['ingredients']),
            record: name,
          ),
          unitsPerContainer: unitsPerContainer,
          containerCount: containerCount,
          priceEur: price,
          bioavailability: row['bioavailability']?.toString() ?? '',
          lowStockAlerts: row['low_stock_alerts_enabled'] as bool? ?? true,
        );
      }
    }
    bundle.supplements.addAll(supplementByToken.values);

    final groupedSchedules = <String, _LegacySchedule>{};
    bundle.scheduleNode.forEach((rawUserName, rawUserSchedule) {
      if (rawUserSchedule is! Map) return;
      final profileKey = profileKeyForName(rawUserName);
      rawUserSchedule.forEach((rawProductName, rawDaily) {
        if (rawDaily is! Map) return;
        final productName = '$rawProductName';
        for (final dayEntry in rawDaily.entries) {
          if (dayEntry.value is! Map) continue;
          final dayMap = dayEntry.value as Map;
          for (final period in const ['AM', 'PM']) {
            final rawDose = dayMap[period];
            final dose = _double(rawDose);
            if (rawDose != null && (dose == null || dose <= 0)) {
              bundle.warnings.add(
                'Skipped invalid scheduled dose for $productName.',
              );
            }
            if (dose == null || dose <= 0) continue;
            final key = '$profileKey|${_normalized(productName)}|$period|$dose';
            final grouped = groupedSchedules.putIfAbsent(
              key,
              () => _LegacySchedule(
                token: key,
                profileKey: profileKey,
                productName: productName,
                dose: dose,
                unit: 'unit',
                timeOfDay: period,
              ),
            );
            grouped.weekdays.add('${dayEntry.key}');
          }
        }
      });
    });
    bundle.schedules.addAll(groupedSchedules.values);

    for (var index = 0; index < bundle.intakeNodes.length; index++) {
      final row = Map<String, dynamic>.from(bundle.intakeNodes[index]);
      final productName = (row['productName'] ?? row['product_name'])
          ?.toString()
          .trim();
      if (productName == null || productName.isEmpty) continue;
      final profileKey = profileKeyForName(row['userName'] ?? row['user_name']);
      final timestamp = DateTime.tryParse('${row['timestamp']}');
      if (timestamp == null) {
        bundle.warnings.add(
          'An intake for $productName has no valid timestamp.',
        );
        continue;
      }
      final rawDose = row['amount'];
      final dose = _double(rawDose);
      if (rawDose != null && (dose == null || dose <= 0)) {
        bundle.warnings.add('Skipped invalid intake dose for $productName.');
        continue;
      }
      bundle.intakes.add(
        _LegacyIntake(
          token: '${row['id'] ?? index}|$profileKey|$productName',
          profileKey: profileKey,
          productName: productName,
          takenAt: timestamp,
          // Supplement Manager omitted amount for old history rows; retain its
          // former compatibility default only when the field is absent.
          dose: dose ?? 1,
          unit: row['unit']?.toString() ?? 'unit',
          ingredients: _normalizeIngredients(
            bundle,
            _maps(row['ingredientsSnapshot']),
            record: productName,
          ),
        ),
      );
    }

    final tags = <String, Map<String, dynamic>>{};
    for (final raw in bundle.symptomTagNodes) {
      final row = Map<String, dynamic>.from(raw);
      final id = row['id']?.toString();
      if (id != null) tags[id] = row;
    }
    for (
      var entryIndex = 0;
      entryIndex < bundle.symptomEntryNodes.length;
      entryIndex++
    ) {
      final row = Map<String, dynamic>.from(
        bundle.symptomEntryNodes[entryIndex],
      );
      final profileKey = profileKeyForName(row['userName'] ?? row['user_name']);
      final observedAt = DateTime.tryParse(
        (row['checkInTimestamp'] ?? row['date'] ?? '').toString(),
      );
      if (observedAt == null) continue;
      final scoresNode = row['tagScores'] ?? row['tag_scores'];
      if (scoresNode is! Map) continue;
      for (final scoreEntry in scoresNode.entries) {
        final tagId = '${scoreEntry.key}';
        final tag = tags[tagId];
        final name = tag?['name']?.toString() ?? tagId;
        final score = _integer(scoreEntry.value);
        if (score == null) continue;
        bundle.events.add(
          _LegacyEvent(
            token: '$entryIndex|$tagId|${observedAt.toIso8601String()}',
            profileKey: profileKey,
            name: name,
            kind: tag?['isSymptom'] == false
                ? EventKind.tag
                : EventKind.symptom,
            observedAt: observedAt,
            score: score.clamp(0, 5),
            notes: row['note']?.toString() ?? '',
            colorValue: _integer(tag?['color']),
          ),
        );
      }
    }
    _sanitizeClinicalNodes(bundle);
  }

  List<Map<String, Object?>> _normalizeIngredients(
    _LegacyBundle bundle,
    Iterable<Map<dynamic, dynamic>> ingredients, {
    required String record,
  }) {
    final normalized = <Map<String, Object?>>[];
    for (final raw in ingredients) {
      final ingredient = Map<String, Object?>.from(raw);
      if (ingredient.containsKey('amount')) {
        final amount = _ingredientAmount(ingredient['amount']);
        if (amount == null || amount <= 0) {
          ingredient.remove('amount');
          final warning = 'Ignored invalid ingredient amount for $record.';
          if (!bundle.warnings.contains(warning)) {
            bundle.warnings.add(warning);
          }
        } else {
          ingredient['amount'] = amount;
        }
      }
      normalized.add(ingredient);
    }
    return normalized;
  }

  static double? _ingredientAmount(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : value == null
        ? null
        : double.tryParse(value.toString().trim().replaceAll(',', '.'));
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  void _sanitizeClinicalNodes(_LegacyBundle bundle) {
    final sanitizedMeasurements = <Map<dynamic, dynamic>>[];
    for (final raw in bundle.measurementNodes) {
      final row = Map<dynamic, dynamic>.from(raw);
      final value = _double(row['value']);
      if (value == null) {
        if (_isNonFiniteNumber(row['value'])) {
          _warnNonFinite(bundle, 'measurement value');
        }
        continue;
      }
      row['value'] = value;
      _sanitizeOptionalNumber(
        bundle,
        row,
        'lab_ref_low',
        'lab reference low bound',
      );
      _sanitizeOptionalNumber(
        bundle,
        row,
        'lab_ref_high',
        'lab reference high bound',
      );
      _sanitizeOptionalInteger(bundle, row, 'page', 'measurement page');
      _sanitizeOptionalNumber(
        bundle,
        row,
        'extraction_confidence',
        'extraction confidence',
      );
      final page = _integer(row['page']);
      if (page != null && page < 1) {
        bundle.warnings.add('Ignored measurement page below 1.');
        row['page'] = null;
      }
      final confidence = _double(row['extraction_confidence']);
      if (confidence != null && (confidence < 0 || confidence > 1)) {
        bundle.warnings.add('Ignored extraction confidence outside 0..1.');
        row['extraction_confidence'] = null;
      }
      _omitUnorderedPair(
        bundle,
        row,
        lowField: 'lab_ref_low',
        highField: 'lab_ref_high',
        label: 'lab reference bounds',
      );
      sanitizedMeasurements.add(row);
    }
    bundle.measurementNodes
      ..clear()
      ..addAll(sanitizedMeasurements);

    _sanitizeRanges(bundle, bundle.rangeNodes, 'range');
    _sanitizeRanges(bundle, bundle.userOverrideNodes, 'target override');
    _sanitizeDueIntervals(bundle);
  }

  void _sanitizeRanges(
    _LegacyBundle bundle,
    List<Map<dynamic, dynamic>> rows,
    String label,
  ) {
    final unitsByLegacyId = {
      for (final biomarker in bundle.biomarkers)
        biomarker.legacyId: biomarker.unit,
    };
    final accepted = <Map<dynamic, dynamic>>[];
    for (final row in rows) {
      for (final field in const [
        'low',
        'min',
        'high',
        'max',
        'optimal_low',
        'optimal_high',
        'borderline_low',
        'borderline_high',
      ]) {
        _sanitizeOptionalNumber(bundle, row, field, '$label $field');
      }
      _sanitizeOptionalInteger(bundle, row, 'age_min', '$label age minimum');
      _sanitizeOptionalInteger(bundle, row, 'age_max', '$label age maximum');
      for (final field in const ['age_min', 'age_max']) {
        final age = _integer(row[field]);
        if (age != null && (age < 0 || age > 150)) {
          bundle.warnings.add('Ignored $label $field outside 0..150.');
          row[field] = null;
        }
      }
      _omitUnorderedPair(
        bundle,
        row,
        lowField: 'age_min',
        highField: 'age_max',
        label: '$label age bounds',
      );
      _omitUnorderedAliasPair(
        bundle,
        row,
        lowFields: const ['low', 'min'],
        highFields: const ['high', 'max'],
        label: '$label low/high bounds',
      );
      _omitUnorderedAliasPair(
        bundle,
        row,
        lowFields: const ['optimal_low', 'borderline_low'],
        highFields: const ['optimal_high', 'borderline_high'],
        label: '$label optimal bounds',
      );
      _sanitizeEvidenceUrl(bundle, row, label);
      final hasBound = const [
        'low',
        'min',
        'high',
        'max',
        'optimal_low',
        'optimal_high',
        'borderline_low',
        'borderline_high',
      ].any((field) => _double(row[field]) != null);
      if (!hasBound) {
        bundle.warnings.add('Skipped $label without valid bounds.');
        continue;
      }
      final unit =
          (row['unit'] ??
                  unitsByLegacyId[row['biomarker_id']?.toString()] ??
                  '')
              .toString()
              .trim();
      if (unit.isEmpty) {
        bundle.warnings.add('Skipped $label without a unit.');
        continue;
      }
      row['unit'] = unit;
      final suppliedType = row['range_type'] ?? row['kind'] ?? row['type'];
      final rangeType = suppliedType == null
          ? 'lab_reference'
          : suppliedType.toString().trim();
      if (rangeType.isEmpty) {
        bundle.warnings.add('Skipped $label without a range type.');
        continue;
      }
      if (suppliedType == null) row['range_type'] = rangeType;
      accepted.add(row);
    }
    rows
      ..clear()
      ..addAll(accepted);
  }

  void _sanitizeDueIntervals(_LegacyBundle bundle) {
    for (final row in [
      ...bundle.biomarkerListNodes,
      ...bundle.biomarkerListEntryNodes,
    ]) {
      if (!row.containsKey('due_duration')) continue;
      final interval = _integer(row['due_duration']);
      if (interval == null || interval <= 0) {
        bundle.warnings.add('Ignored invalid retest interval.');
        row['due_duration'] = null;
      } else {
        row['due_duration'] = interval;
      }
    }
  }

  void _omitUnorderedPair(
    _LegacyBundle bundle,
    Map<dynamic, dynamic> row, {
    required String lowField,
    required String highField,
    required String label,
  }) {
    final low = _double(row[lowField]);
    final high = _double(row[highField]);
    if (low != null && high != null && low > high) {
      row[lowField] = null;
      row[highField] = null;
      bundle.warnings.add('Ignored unordered $label.');
    }
  }

  void _omitUnorderedAliasPair(
    _LegacyBundle bundle,
    Map<dynamic, dynamic> row, {
    required List<String> lowFields,
    required List<String> highFields,
    required String label,
  }) {
    final low = lowFields
        .map((field) => _double(row[field]))
        .firstWhere((value) => value != null, orElse: () => null);
    final high = highFields
        .map((field) => _double(row[field]))
        .firstWhere((value) => value != null, orElse: () => null);
    if (low != null && high != null && low > high) {
      for (final field in [...lowFields, ...highFields]) {
        row[field] = null;
      }
      bundle.warnings.add('Ignored unordered $label.');
    }
  }

  void _sanitizeEvidenceUrl(
    _LegacyBundle bundle,
    Map<dynamic, dynamic> row,
    String label,
  ) {
    final raw = row['evidence_url'];
    if (raw == null || raw.toString().trim().isEmpty) return;
    final uri = Uri.tryParse(raw.toString().trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      row['evidence_url'] = null;
      bundle.warnings.add('Ignored invalid $label evidence URL.');
    }
  }

  void _sanitizeOptionalNumber(
    _LegacyBundle bundle,
    Map<dynamic, dynamic> row,
    String field,
    String label,
  ) {
    if (!row.containsKey(field)) return;
    final value = _double(row[field]);
    if (value == null) {
      if (_isNonFiniteNumber(row[field])) _warnNonFinite(bundle, label);
      row[field] = null;
      return;
    }
    row[field] = value;
  }

  void _sanitizeOptionalInteger(
    _LegacyBundle bundle,
    Map<dynamic, dynamic> row,
    String field,
    String label,
  ) {
    if (!row.containsKey(field)) return;
    final value = _integer(row[field]);
    if (value == null) {
      if (_isNonFiniteNumber(row[field])) _warnNonFinite(bundle, label);
      row[field] = null;
      return;
    }
    row[field] = value;
  }

  Future<LegacyImportResult> commit(LegacyImportPreview preview) async {
    if (!preview.canImport) {
      throw StateError('This preview cannot be imported');
    }
    final bundle = preview._bundle;
    final db = await _database.database;
    final importId = _uuid.v4();
    final inserted = <String, int>{};
    var auditSequence = 0;

    await db.transaction((txn) async {
      final already = await txn.query(
        'import_runs',
        where: 'source_hash = ? AND rolled_back_at IS NULL',
        whereArgs: [preview.sourceHash],
        limit: 1,
      );
      if (already.isNotEmpty) {
        throw StateError('Source has already been imported');
      }

      await txn.insert('import_runs', {
        'id': importId,
        'source_type': preview.sourceKinds.join(', '),
        'source_hash': preview.sourceHash,
        'profile_id': bundle.fallbackProfileId,
        'preview_json': jsonEncode(preview.toJson()),
        'imported_at': DateTime.now().toUtc().toIso8601String(),
      });

      Future<bool> insertAudited(
        String table,
        String rowId,
        Map<String, Object?> row,
      ) async {
        final existing = await txn.query(
          table,
          where: 'id = ?',
          whereArgs: [rowId],
          limit: 1,
        );
        if (existing.isNotEmpty) return false;
        await txn.insert(table, row);
        await txn.insert('import_audit', {
          'import_id': importId,
          'sequence': auditSequence++,
          'table_name': table,
          'row_id': rowId,
          'action': 'insert',
        });
        inserted[table] = (inserted[table] ?? 0) + 1;
        return true;
      }

      Future<void> fillMissingProfileFields(
        Map<String, Object?> existing,
        _LegacyProfile legacy,
      ) async {
        final changes = <String, Object?>{};
        if (existing['date_of_birth'] == null && legacy.dateOfBirth != null) {
          changes['date_of_birth'] = legacy.dateOfBirth!
              .toIso8601String()
              .split('T')
              .first;
        }
        if (existing['sex'] == null && legacy.sex != null) {
          changes['sex'] = legacy.sex;
        }
        if (existing['height_cm'] == null && legacy.heightCm != null) {
          changes['height_cm'] = legacy.heightCm;
        }
        if (existing['weight_kg'] == null && legacy.weightKg != null) {
          changes['weight_kg'] = legacy.weightKg;
        }
        if (changes.isEmpty) return;
        final before = Map<String, Object?>.from(existing);
        changes['updated_at'] = DateTime.now().toUtc().toIso8601String();
        await txn.update(
          'profiles',
          changes,
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
        existing.addAll(changes);
        await txn.insert('import_audit', {
          'import_id': importId,
          'sequence': auditSequence++,
          'table_name': 'profiles',
          'row_id': '${existing['id']}',
          'action': 'update',
          'before_json': jsonEncode(before),
        });
      }

      final existingProfiles = (await txn.query(
        'profiles',
        where: 'deleted = 0',
      )).map((row) => Map<String, Object?>.from(row)).toList();
      final profileIds = <String, String>{};
      for (final profile in bundle.profiles.values) {
        if (profile.directProfileId != null) {
          final direct = existingProfiles.where(
            (row) => row['id'] == profile.directProfileId,
          );
          if (direct.isNotEmpty) {
            await fillMissingProfileFields(direct.first, profile);
          }
          profileIds[profile.key] = profile.directProfileId!;
          continue;
        }
        final matching = existingProfiles.where(
          (row) =>
              _normalized('${row['display_name']}') ==
              _normalized(profile.displayName),
        );
        if (matching.isNotEmpty) {
          await fillMissingProfileFields(matching.first, profile);
          profileIds[profile.key] = '${matching.first['id']}';
          continue;
        }
        final id = _legacyId(bundle.sourceHash, 'profile', profile.key);
        final now = DateTime.now();
        await insertAudited(
          'profiles',
          id,
          Profile(
            id: id,
            displayName: profile.displayName,
            dateOfBirth: profile.dateOfBirth,
            sex: profile.sex,
            heightCm: profile.heightCm,
            weightKg: profile.weightKg,
            notes: profile.notes,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
        profileIds[profile.key] = id;
      }

      String resolveProfile(String? legacyId) {
        if (legacyId != null) {
          final byId = bundle.profiles['id:$legacyId'];
          if (byId != null) return profileIds[byId.key]!;
        }
        return bundle.fallbackProfileId;
      }

      final existingBiomarkers = await txn.query(
        'biomarkers',
        where: 'deleted = 0',
      );
      final biomarkerIds = <String, String>{};
      final biomarkerIdsByCanonical = <String, String>{
        for (final row in existingBiomarkers)
          '${row['canonical_name']}': '${row['id']}',
      };
      for (final item in bundle.biomarkers) {
        // Multiple rows in a legacy export can normalize to the same
        // canonical name (for example punctuation variants of
        // "1,25-Dihydroxy Vitamin D"). The database correctly enforces one
        // catalog row per canonical name, so every legacy ID must be aliased
        // to the first deterministic catalog row created for that name.
        final canonicalId = biomarkerIdsByCanonical[item.canonicalName];
        if (canonicalId != null) {
          biomarkerIds[item.legacyId] = canonicalId;
          continue;
        }
        final id = _legacyId(bundle.sourceHash, 'biomarker', item.legacyId);
        final now = DateTime.now();
        await insertAudited(
          'biomarkers',
          id,
          Biomarker(
            id: id,
            canonicalName: item.canonicalName,
            displayName: item.displayName,
            category: item.category,
            defaultUnit: item.unit,
            priceEur: item.priceEur,
            description: item.description,
            synonyms: item.synonyms,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
        biomarkerIds[item.legacyId] = id;
        biomarkerIdsByCanonical[item.canonicalName] = id;
      }
      for (final row in existingBiomarkers) {
        biomarkerIds.putIfAbsent('${row['id']}', () => '${row['id']}');
      }

      final supplementIds = <String, String>{};
      for (final item in bundle.supplements) {
        final existing = await txn.query(
          'supplements',
          where:
              'lower(name) = lower(?) AND lower(brand) = lower(?) '
              'AND deleted = 0',
          whereArgs: [item.name, item.brand],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          supplementIds[item.token] = '${existing.first['id']}';
          continue;
        }
        final id = _legacyId(bundle.sourceHash, 'supplement', item.token);
        final now = DateTime.now();
        await insertAudited(
          'supplements',
          id,
          Supplement(
            id: id,
            name: item.name,
            brand: item.brand,
            form: item.form,
            ingredients: item.ingredients,
            unitsPerContainer: item.unitsPerContainer,
            containerCount: item.containerCount,
            priceEur: item.priceEur,
            bioavailability: item.bioavailability,
            lowStockAlerts: item.lowStockAlerts,
            stockUnit: item.form.trim().isEmpty ? 'unit' : item.form.trim(),
            sourceId: item.token,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
        supplementIds[item.token] = id;
        final unitsPerContainer = item.unitsPerContainer;
        final containerCount = item.containerCount;
        if (unitsPerContainer != null &&
            unitsPerContainer != 0 &&
            containerCount != null &&
            containerCount != 0 &&
            containerCount.isFinite) {
          final initialUnits = unitsPerContainer * containerCount;
          if (initialUnits.isFinite && initialUnits != 0) {
            final movementId = _legacyId(bundle.sourceHash, 'inventory', id);
            await insertAudited(
              'inventory_movements',
              movementId,
              InventoryMovement(
                id: movementId,
                supplementId: id,
                quantityUnits: initialUnits,
                occurredAt: now,
                reason: 'import',
                notes: 'Current stock imported from Supplement Manager.',
                createdAt: now,
                updatedAt: now,
              ).toMap(),
            );
          }
        }
      }

      for (final item in bundle.schedules) {
        final supplementToken =
            '${item.profileKey}|${_normalized(item.productName)}';
        final supplementId = supplementIds[supplementToken];
        if (supplementId == null) continue;
        final id = _legacyId(bundle.sourceHash, 'schedule', item.token);
        final now = DateTime.now();
        await insertAudited(
          'supplement_schedules',
          id,
          SupplementSchedule(
            id: id,
            profileId: profileIds[item.profileKey]!,
            supplementId: supplementId,
            dose: item.dose,
            unit: item.unit,
            timeOfDay: item.timeOfDay,
            weekdays: item.weekdays.toList()..sort(),
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
      }

      for (final item in bundle.intakes) {
        final supplementToken =
            '${item.profileKey}|${_normalized(item.productName)}';
        final supplementId = supplementIds[supplementToken];
        if (supplementId == null) continue;
        final id = _legacyId(bundle.sourceHash, 'intake', item.token);
        final now = DateTime.now();
        await insertAudited(
          'supplement_intakes',
          id,
          SupplementIntake(
            id: id,
            profileId: profileIds[item.profileKey]!,
            supplementId: supplementId,
            takenAt: item.takenAt,
            dose: item.dose,
            unit: item.unit,
            ingredientSnapshot: item.ingredients,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
      }

      for (final item in bundle.events) {
        final id = _legacyId(bundle.sourceHash, 'event', item.token);
        final now = DateTime.now();
        final profileId = profileIds[item.profileKey]!;
        final definitionId = _legacyId(
          bundle.sourceHash,
          'event_definition',
          '$profileId|${item.kind.name}|${_normalized(item.name)}',
        );
        await insertAudited(
          'health_event_definitions',
          definitionId,
          HealthEventDefinition(
            id: definitionId,
            profileId: profileId,
            kind: item.kind,
            name: item.name,
            useScore: true,
            colorValue: item.colorValue,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
        await insertAudited(
          'health_events',
          id,
          HealthEvent(
            id: id,
            profileId: profileId,
            definitionId: definitionId,
            kind: item.kind,
            name: item.name,
            observedAt: item.observedAt,
            score: item.score,
            notes: item.notes,
            colorValue: item.colorValue,
            createdAt: now,
            updatedAt: now,
          ).toMap(),
        );
      }

      final documentIds = <String, String>{};
      for (var index = 0; index < bundle.documentNodes.length; index++) {
        final row = Map<String, dynamic>.from(bundle.documentNodes[index]);
        final oldId = row['id']?.toString() ?? '$index';
        final id = _legacyId(bundle.sourceHash, 'document', oldId);
        final now = DateTime.now().toUtc().toIso8601String();
        await insertAudited('documents', id, {
          'id': id,
          'profile_id': resolveProfile(row['profile_id']?.toString()),
          'file_name':
              (row['file_name'] ?? row['filename'] ?? 'Imported document')
                  .toString(),
          'mime_type': row['mime_type'] ?? 'application/pdf',
          'sha256': row['sha256'],
          // Paths and OneDrive item IDs from the former app are not valid in
          // SuperHealth. PDF binaries are attached in a separate reviewed step.
          'local_path': null,
          'one_drive_item_id': null,
          'document_date':
              row['document_date'] ?? row['report_date'] ?? row['taken_at'],
          'parsed_at': row['parsed_at'] ?? row['imported_at'],
          'parser_provider': row['parser_provider'] ?? row['provider'],
          'parser_model': row['parser_model'],
          'lab_name': row['lab_name'],
          'report_comment': row['report_comment']?.toString() ?? '',
          'parse_status': 'imported',
          'warnings_json': '[]',
          'errors_json': '[]',
          'created_at': row['created_at'] ?? row['imported_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'deleted': row['deleted'] == 1 ? 1 : 0,
        });
        documentIds[oldId] = id;
      }

      for (var index = 0; index < bundle.measurementNodes.length; index++) {
        final row = Map<String, dynamic>.from(bundle.measurementNodes[index]);
        final oldBiomarkerId = row['biomarker_id']?.toString();
        final biomarkerId = oldBiomarkerId == null
            ? null
            : biomarkerIds[oldBiomarkerId];
        final value = _double(row['value']);
        if (biomarkerId == null || value == null) continue;
        final oldId = row['id']?.toString() ?? '$index';
        final id = _legacyId(bundle.sourceHash, 'measurement', oldId);
        final now = DateTime.now();
        final oldDocumentId = row['document_id']?.toString();
        final measurement = Measurement(
          id: id,
          profileId: resolveProfile(row['profile_id']?.toString()),
          biomarkerId: biomarkerId,
          documentId: oldDocumentId == null ? null : documentIds[oldDocumentId],
          takenAt:
              DateTime.tryParse(
                '${row['taken_at'] ?? row['measured_at'] ?? row['created_at']}',
              ) ??
              now,
          value: value,
          unit: (row['unit_reported'] ?? row['unit'] ?? '').toString(),
          labRefLow: _double(row['lab_ref_low']),
          labRefHigh: _double(row['lab_ref_high']),
          page: _double(row['page'])?.toInt(),
          rowText: row['row_text']?.toString(),
          extractionConfidence: _double(row['extraction_confidence']),
          flags: _stringList(row['flags'] ?? row['flags_json']),
          notes: row['notes']?.toString() ?? '',
          createdAt: DateTime.tryParse('${row['created_at']}') ?? now,
          updatedAt: DateTime.tryParse('${row['updated_at']}') ?? now,
        );
        await insertAudited(
          'measurements',
          id,
          await _repository.measurementMapWithCanonicalUnits(txn, measurement),
        );
      }

      final biomarkerUnits = {
        for (final item in bundle.biomarkers) item.legacyId: item.unit,
      };

      Future<void> importRange(
        Map<dynamic, dynamic> raw, {
        required int index,
        required bool isOverride,
      }) async {
        final row = Map<String, dynamic>.from(raw);
        final oldBiomarkerId = row['biomarker_id']?.toString();
        final biomarkerId = oldBiomarkerId == null
            ? null
            : biomarkerIds[oldBiomarkerId];
        if (biomarkerId == null) {
          if (isOverride) {
            throw StateError(
              'A user override could not be matched. Select '
              'biomarkers.json together with user_overrides.json.',
            );
          }
          return;
        }
        if (isOverride) {
          final requestedProfile = row['profile_id']?.toString();
          final targetProfiles = requestedProfile == null
              ? profileIds.values.toSet()
              : {resolveProfile(requestedProfile)};
          final unit = (row['unit'] ?? biomarkerUnits[oldBiomarkerId] ?? '')
              .toString();
          final originalNotes = row['notes']?.toString().trim() ?? '';
          for (final targetProfileId in targetProfiles) {
            final id = _legacyId(
              bundle.sourceHash,
              'profile_target',
              '${row['id'] ?? index}|$targetProfileId',
            );
            final now = DateTime.now();
            await insertAudited(
              'profile_biomarker_targets',
              id,
              ProfileBiomarkerTarget(
                id: id,
                profileId: targetProfileId,
                biomarkerId: biomarkerId,
                low: _double(row['low'] ?? row['min']),
                high: _double(row['high'] ?? row['max']),
                borderlineLow: _double(row['borderline_low']),
                borderlineHigh: _double(row['borderline_high']),
                unit: unit,
                source: 'legacy_biomarkers_override',
                notes: [
                  originalNotes,
                  if (requestedProfile != null)
                    'Imported from former profile $requestedProfile.',
                ].where((value) => value.isNotEmpty).join('\n'),
                createdAt: DateTime.tryParse('${row['created_at']}') ?? now,
                updatedAt: DateTime.tryParse('${row['updated_at']}') ?? now,
              ).toMap(),
            );
          }
          return;
        }
        final oldId = row['id']?.toString() ?? '$index';
        final id = _legacyId(bundle.sourceHash, 'range', oldId);
        final now = DateTime.now().toUtc().toIso8601String();
        final notes = row['notes']?.toString().trim() ?? '';
        await insertAudited('biomarker_ranges', id, {
          'id': id,
          'biomarker_id': biomarkerId,
          'range_type':
              (row['range_type'] ??
                      row['kind'] ??
                      row['type'] ??
                      'lab_reference')
                  .toString(),
          'sex': row['sex'],
          'age_min': row['age_min'],
          'age_max': row['age_max'],
          'low': row['low'] ?? row['min'],
          'high': row['high'] ?? row['max'],
          'optimal_low': row['optimal_low'] ?? row['borderline_low'],
          'optimal_high': row['optimal_high'] ?? row['borderline_high'],
          'unit': (row['unit'] ?? biomarkerUnits[oldBiomarkerId] ?? '')
              .toString(),
          'evidence_label': row['evidence_label'] ?? row['source'],
          'evidence_url': row['evidence_url'],
          'notes': notes,
          'created_at': row['created_at'] ?? now,
          'updated_at': row['updated_at'] ?? now,
          'deleted': row['deleted'] == 1 ? 1 : 0,
        });
      }

      for (var index = 0; index < bundle.rangeNodes.length; index++) {
        await importRange(
          bundle.rangeNodes[index],
          index: index,
          isOverride: false,
        );
      }
      for (var index = 0; index < bundle.userOverrideNodes.length; index++) {
        await importRange(
          bundle.userOverrideNodes[index],
          index: index,
          isOverride: true,
        );
      }

      for (final rawList in bundle.biomarkerListNodes) {
        final list = Map<String, dynamic>.from(rawList);
        final oldListId = list['id']?.toString();
        if (oldListId == null) continue;
        final listId = _legacyId(
          bundle.sourceHash,
          'biomarker_list',
          oldListId,
        );
        final now = DateTime.now();
        final dueIntervalDays = _double(list['due_duration'])?.toInt();
        final importedList = BiomarkerList(
          id: listId,
          profileId: resolveProfile(list['profile_id']?.toString()),
          name: (list['display_name'] ?? list['name'] ?? 'Imported checklist')
              .toString(),
          description: (list['notes'] ?? '').toString(),
          createdAt: DateTime.tryParse('${list['created_at']}') ?? now,
          updatedAt: DateTime.tryParse('${list['updated_at']}') ?? now,
          deleted: list['deleted'] == 1,
        );
        await insertAudited('biomarker_lists', listId, importedList.toMap());
        final entries = bundle.biomarkerListEntryNodes
            .where((entry) => entry['list_id']?.toString() == oldListId)
            .toList();
        for (var index = 0; index < entries.length; index++) {
          final oldBiomarkerId = entries[index]['biomarker_id']?.toString();
          final biomarkerId = oldBiomarkerId == null
              ? null
              : biomarkerIds[oldBiomarkerId];
          if (biomarkerId == null) continue;
          final itemId = _legacyId(
            bundle.sourceHash,
            'biomarker_list_item',
            '$oldListId|$oldBiomarkerId|$index',
          );
          await insertAudited(
            'biomarker_list_items',
            itemId,
            BiomarkerListItem(
              id: itemId,
              listId: listId,
              biomarkerId: biomarkerId,
              dueIntervalDays:
                  _double(entries[index]['due_duration'])?.toInt() ??
                  dueIntervalDays,
              notes: (entries[index]['notes'] ?? '').toString(),
              createdAt:
                  DateTime.tryParse('${entries[index]['created_at']}') ?? now,
              updatedAt:
                  DateTime.tryParse('${entries[index]['updated_at']}') ?? now,
              deleted: entries[index]['deleted'] == 1,
            ).toMap(),
          );
        }
      }
    });

    return LegacyImportResult(importId: importId, inserted: inserted);
  }

  Future<LegacyPdfImportPreview> previewPdfs(
    List<ImportSourceFile> files,
  ) async {
    if (files.isEmpty) {
      throw ArgumentError('Select at least one PDF file.');
    }
    final warnings = <String>[];
    final selectedByHash = <String, ImportSourceFile>{};
    for (final file in files) {
      if (!file.name.toLowerCase().endsWith('.pdf') ||
          !_looksLikePdf(file.bytes)) {
        warnings.add('${file.name}: not a readable PDF file.');
        continue;
      }
      final hash = sha256.convert(file.bytes).toString();
      if (selectedByHash.containsKey(hash)) {
        warnings.add('${file.name}: duplicate PDF selection ignored.');
      } else {
        selectedByHash[hash] = file;
      }
    }

    final db = await _database.database;
    final base = await _documentsDirectory();
    final matches = <_LegacyPdfMatch>[];
    var unmatchedFiles = 0;
    for (final entry in selectedByHash.entries) {
      final hash = entry.key;
      final rows = await db.query(
        'documents',
        where: 'lower(sha256) = ? AND deleted = 0',
        whereArgs: [hash],
      );
      if (rows.isEmpty) {
        unmatchedFiles++;
        warnings.add(
          '${entry.value.name}: no imported documents.json record has this hash.',
        );
        continue;
      }
      for (final row in rows) {
        final profileId = '${row['profile_id']}';
        final targetPath = path.join(
          base.path,
          'documents',
          profileId,
          '$hash.pdf',
        );
        String? availablePath;
        final candidates = <String>{
          targetPath,
          if (row['local_path']?.toString().isNotEmpty == true)
            row['local_path'].toString(),
        };
        for (final candidate in candidates) {
          final existing = File(candidate);
          if (!await existing.exists()) continue;
          final existingHash = sha256.convert(await existing.readAsBytes());
          if (existingHash.toString() == hash) {
            availablePath = candidate;
            break;
          }
        }
        final storedPath = row['local_path']?.toString();
        final alreadyAvailable =
            availablePath != null && storedPath == availablePath;
        matches.add(
          _LegacyPdfMatch(
            documentId: '${row['id']}',
            hash: hash,
            targetPath: targetPath,
            file: entry.value,
            alreadyAvailable: alreadyAvailable,
          ),
        );
      }
    }

    return LegacyPdfImportPreview._(
      selectedFiles: selectedByHash.length,
      matchedDocuments: matches.length,
      alreadyAvailable: matches.where((match) => match.alreadyAvailable).length,
      unmatchedFiles: unmatchedFiles,
      warnings: warnings,
      matches: matches,
    );
  }

  Future<LegacyPdfImportResult> commitPdfs(
    LegacyPdfImportPreview preview,
  ) async {
    if (!preview.canImport) {
      throw StateError('There are no new matched PDFs to import.');
    }
    final pending = preview._matches
        .where((match) => !match.alreadyAvailable)
        .toList();
    final writtenPaths = <String>{};
    for (final match in pending) {
      if (!writtenPaths.add(match.targetPath)) continue;
      final target = File(match.targetPath);
      await target.parent.create(recursive: true);
      final temporary = File('${match.targetPath}.importing');
      await temporary.writeAsBytes(match.file.bytes, flush: true);
      final writtenHash = sha256.convert(await temporary.readAsBytes());
      if (writtenHash.toString() != match.hash) {
        await temporary.delete();
        throw StateError('PDF verification failed for ${match.file.name}.');
      }
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
    }

    final db = await _database.database;
    await db.transaction((txn) async {
      for (final match in pending) {
        await txn.update(
          'documents',
          {'local_path': match.targetPath, 'mime_type': 'application/pdf'},
          where: 'id = ?',
          whereArgs: [match.documentId],
        );
      }
    });
    return LegacyPdfImportResult(
      attachedDocuments: pending.length,
      alreadyAvailable: preview.alreadyAvailable,
      unmatchedFiles: preview.unmatchedFiles,
    );
  }

  bool _looksLikePdf(Uint8List bytes) =>
      bytes.length >= 5 &&
      ascii.decode(bytes.sublist(0, 5), allowInvalid: true) == '%PDF-';

  Future<void> rollback(String importId) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final run = await txn.query(
        'import_runs',
        where: 'id = ? AND rolled_back_at IS NULL',
        whereArgs: [importId],
        limit: 1,
      );
      if (run.isEmpty) throw StateError('Active import run not found');
      final audit = await txn.query(
        'import_audit',
        where: 'import_id = ?',
        whereArgs: [importId],
        orderBy: 'sequence DESC',
      );
      for (final entry in audit) {
        final table = '${entry['table_name']}';
        if (!AppDatabase.synchronizedTables.contains(table)) continue;
        final rowId = '${entry['row_id']}';
        if (entry['action'] == 'insert') {
          await txn.delete(table, where: 'id = ?', whereArgs: [rowId]);
        } else if (entry['action'] == 'update' &&
            entry['before_json'] != null) {
          final before = jsonDecode('${entry['before_json']}');
          if (before is Map) {
            await txn.insert(
              table,
              Map<String, Object?>.from(before),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
      await txn.update(
        'import_runs',
        {'rolled_back_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [importId],
      );
    });
  }

  String _legacyId(String hash, String kind, String token) {
    final digest = sha256.convert(utf8.encode('$hash|$kind|$token')).toString();
    return 'legacy-${digest.substring(0, 32)}';
  }
}

class _LegacyPdfMatch {
  const _LegacyPdfMatch({
    required this.documentId,
    required this.hash,
    required this.targetPath,
    required this.file,
    required this.alreadyAvailable,
  });

  final String documentId;
  final String hash;
  final String targetPath;
  final ImportSourceFile file;
  final bool alreadyAvailable;
}

class _LegacyBundle {
  _LegacyBundle({
    required this.sourceHash,
    required this.fallbackProfileId,
    required this.fallbackProfileName,
  });

  final String sourceHash;
  final String fallbackProfileId;
  final String fallbackProfileName;
  final Set<String> sourceKinds = {};
  final List<String> warnings = [];
  final List<String> duplicates = [];
  final Map<String, _LegacyProfile> profiles = {};
  final Set<String> supplementProfileKeys = {};
  final List<Map<dynamic, dynamic>> productNodes = [];
  final Map<String, dynamic> scheduleNode = {};
  final List<Map<dynamic, dynamic>> intakeNodes = [];
  final List<Map<dynamic, dynamic>> symptomEntryNodes = [];
  final List<Map<dynamic, dynamic>> symptomTagNodes = [];
  final List<_LegacySupplement> supplements = [];
  final List<_LegacySchedule> schedules = [];
  final List<_LegacyIntake> intakes = [];
  final List<_LegacyEvent> events = [];
  final List<_LegacyBiomarker> biomarkers = [];
  final List<Map<dynamic, dynamic>> measurementNodes = [];
  final List<Map<dynamic, dynamic>> documentNodes = [];
  final List<Map<dynamic, dynamic>> rangeNodes = [];
  final List<Map<dynamic, dynamic>> userOverrideNodes = [];
  final List<Map<dynamic, dynamic>> biomarkerListNodes = [];
  final List<Map<dynamic, dynamic>> biomarkerListEntryNodes = [];

  Map<String, int> get counts => {
    'profiles': profiles.values
        .where((item) => item.directProfileId == null)
        .length,
    'supplements': supplements.length,
    'schedules': schedules.length,
    'intakes': intakes.length,
    'symptoms_and_tags': events.length,
    'biomarkers': biomarkers.map((item) => item.canonicalName).toSet().length,
    'measurements': measurementNodes.length,
    'documents': documentNodes.length,
    'ranges': rangeNodes.length,
    'target_overrides': userOverrideNodes.length,
    'checklists': biomarkerListNodes.length,
  };
}

class _LegacyProfile {
  const _LegacyProfile({
    required this.key,
    required this.displayName,
    this.legacyId,
    this.directProfileId,
    this.dateOfBirth,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.notes = '',
  });

  final String key;
  final String displayName;
  final String? legacyId;
  final String? directProfileId;
  final DateTime? dateOfBirth;
  final String? sex;
  final double? heightCm;
  final double? weightKg;
  final String notes;
}

class _LegacySupplement {
  const _LegacySupplement({
    required this.token,
    required this.profileKey,
    required this.name,
    required this.brand,
    required this.form,
    required this.ingredients,
    required this.unitsPerContainer,
    required this.containerCount,
    required this.priceEur,
    required this.bioavailability,
    required this.lowStockAlerts,
  });

  final String token;
  final String profileKey;
  final String name;
  final String brand;
  final String form;
  final List<Map<String, Object?>> ingredients;
  final int? unitsPerContainer;
  final double? containerCount;
  final double? priceEur;
  final String bioavailability;
  final bool lowStockAlerts;
}

class _LegacySchedule {
  _LegacySchedule({
    required this.token,
    required this.profileKey,
    required this.productName,
    required this.dose,
    required this.unit,
    required this.timeOfDay,
  });

  final String token;
  final String profileKey;
  final String productName;
  final double dose;
  final String unit;
  final String timeOfDay;
  final Set<String> weekdays = {};
}

class _LegacyIntake {
  const _LegacyIntake({
    required this.token,
    required this.profileKey,
    required this.productName,
    required this.takenAt,
    required this.dose,
    required this.unit,
    required this.ingredients,
  });

  final String token;
  final String profileKey;
  final String productName;
  final DateTime takenAt;
  final double dose;
  final String unit;
  final List<Map<String, Object?>> ingredients;
}

class _LegacyEvent {
  const _LegacyEvent({
    required this.token,
    required this.profileKey,
    required this.name,
    required this.kind,
    required this.observedAt,
    required this.score,
    required this.notes,
    required this.colorValue,
  });

  final String token;
  final String profileKey;
  final String name;
  final EventKind kind;
  final DateTime observedAt;
  final int score;
  final String notes;
  final int? colorValue;
}

class _LegacyBiomarker {
  const _LegacyBiomarker({
    required this.legacyId,
    required this.canonicalName,
    required this.displayName,
    required this.category,
    required this.unit,
    required this.priceEur,
    required this.description,
    required this.synonyms,
  });

  final String legacyId;
  final String canonicalName;
  final String displayName;
  final String category;
  final String unit;
  final double? priceEur;
  final String description;
  final List<String> synonyms;
}
