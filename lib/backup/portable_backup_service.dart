import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../data/app_database.dart';
import '../data/health_repository.dart';

/// Creates and restores a self-contained, local-only backup of health data.
///
/// This deliberately backs up only [AppDatabase.synchronizedTables]. API keys,
/// OneDrive credentials and item IDs, sync shadows/conflicts, and import audit
/// data are neither read into nor restored from the portable bundle.
class PortableBackupService {
  // Keep the public named argument stable while storing it privately.
  // ignore: prefer_initializing_formals
  PortableBackupService(
    AppDatabase appDatabase, {
    required DocumentsDirectory documentsDirectory,
  }) : _appDatabase = appDatabase,
       _repository = HealthRepository(appDatabase),
       _documentsDirectory = documentsDirectory;

  static const schema = 'superhealth.portable_backup';
  static const schemaVersion = 1;
  static const maxPdfBytes = 512 * 1024 * 1024;
  static const maxBundleUtf8Bytes = 768 * 1024 * 1024;

  final AppDatabase _appDatabase;
  final HealthRepository _repository;
  final DocumentsDirectory _documentsDirectory;

  /// Returns a versioned UTF-8 JSON bundle with rows and locally available PDFs.
  Future<String> createJson() async {
    final db = await _appDatabase.database;
    final tables = <String, List<Map<String, Object?>>>{};
    final tableManifest = <String, Object?>{};

    for (final table in AppDatabase.synchronizedTables) {
      final rows = await db.query(table, orderBy: 'id ASC');
      final sanitized = [
        for (final row in rows) _sanitizeExportRow(table, row),
      ];
      tables[table] = sanitized;
      tableManifest[table] = {
        'count': sanitized.length,
        'sha256': _sha256Text(_stableJson(sanitized)),
      };
    }

    final files = <Map<String, Object?>>[];
    var totalPdfBytes = 0;
    for (final row in await db.query('documents', orderBy: 'id ASC')) {
      final localPath = row['local_path']?.toString();
      if (localPath == null || localPath.isEmpty) continue;
      final file = File(localPath);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      totalPdfBytes += bytes.length;
      if (totalPdfBytes > maxPdfBytes) {
        throw StateError(
          'Portable backup PDFs exceed the ${maxPdfBytes ~/ (1024 * 1024)} MB safety limit.',
        );
      }
      final digest = _sha256Bytes(bytes);
      final recordedDigest = row['sha256']?.toString();
      if (recordedDigest != null &&
          recordedDigest.isNotEmpty &&
          recordedDigest.toLowerCase() != digest) {
        throw StateError(
          'Document ${row['id']} does not match its recorded SHA-256.',
        );
      }
      files.add({
        'document_id': '${row['id']}',
        'sha256': digest,
        'size_bytes': bytes.length,
        'bytes_base64': base64Encode(bytes),
      });
    }

    final documentManifestRows = [
      for (final file in files)
        {
          'document_id': file['document_id'],
          'sha256': file['sha256'],
          'size_bytes': file['size_bytes'],
        },
    ];
    final manifest = <String, Object?>{
      'tables': tableManifest,
      'documents': {
        'count': files.length,
        'total_bytes': totalPdfBytes,
        'sha256': _sha256Text(_stableJson(documentManifestRows)),
      },
    };
    final bundle = <String, Object?>{
      'schema': schema,
      'schema_version': schemaVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
      'documents': files,
      'manifest': manifest,
    };
    manifest['core_sha256'] = _coreSha256(bundle);
    final source = _stableJson(bundle);
    if (utf8.encode(source).length > maxBundleUtf8Bytes) {
      throw StateError('Portable backup JSON exceeds the safety limit.');
    }
    return source;
  }

  /// Replaces synchronized health data only after the caller confirms it.
  ///
  /// Validation completes before any database rows or documents are changed.
  /// Existing, unrelated files are never overwritten or deleted.
  Future<void> restoreJson(
    String source, {
    required bool confirmedReplaceCurrentData,
  }) async {
    if (!confirmedReplaceCurrentData) {
      throw StateError(
        'Restoring a portable backup requires explicit confirmation.',
      );
    }
    if (utf8.encode(source).length > maxBundleUtf8Bytes) {
      throw const FormatException('Portable backup exceeds the safety limit.');
    }
    final plan = await _validate(source);
    final base = await _documentsDirectory();
    final token = _restoreToken();
    final staging = Directory(path.join(base.path, 'backup-staging', token));
    final restored = Directory(path.join(base.path, 'backup-restored', token));
    var promoted = false;

    try {
      await _stageDocuments(plan.documents, staging);
      final documentPaths = <String, String>{
        for (final document in plan.documents)
          document.id: path.join(restored.path, _documentFileName(document.id)),
      };
      final db = await _appDatabase.database;
      await db.transaction((txn) async {
        for (final table in _reverseRestoreOrder) {
          await txn.delete(table);
        }
        // Import history is intentionally outside a portable backup. Keeping
        // it would make the restored rows look previously imported/audited.
        await txn.delete('import_audit');
        await txn.delete('import_runs');
        if (plan.documents.isNotEmpty) {
          await restored.parent.create(recursive: true);
          if (await restored.exists()) {
            throw StateError('Portable backup restore target already exists.');
          }
          await staging.rename(restored.path);
          promoted = true;
        }
        for (final table in AppDatabase.synchronizedTables) {
          for (final row in plan.tables[table]!) {
            final toInsert = Map<String, Object?>.from(row);
            if (table == 'documents') {
              final documentId = toInsert['id'] as String;
              toInsert['local_path'] = documentPaths[documentId];
              // A portable restore is not a claim about a remote OneDrive copy.
              toInsert['one_drive_item_id'] = null;
            }
            await txn.insert(table, toInsert);
          }
        }
        // Restored data has no trustworthy remote baseline or prior conflicts.
        await txn.delete('sync_shadow');
        await txn.delete('sync_conflicts');
      });
    } on Object {
      await _deleteIfExists(staging);
      if (promoted) await _deleteIfExists(restored);
      rethrow;
    }
  }

  Future<_RestorePlan> _validate(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Portable backup must be an object.');
    }
    final bundle = Map<String, Object?>.from(decoded);
    _requireExactKeys(bundle, const [
      'schema',
      'schema_version',
      'generated_at',
      'tables',
      'documents',
      'manifest',
    ], 'portable backup');
    if (bundle['schema'] != schema) {
      throw const FormatException('Unsupported portable backup schema.');
    }
    if (_intValue(bundle['schema_version']) != schemaVersion) {
      throw const FormatException('Unsupported portable backup version.');
    }
    final generatedAt = bundle['generated_at'];
    if (generatedAt is! String ||
        !_iso8601WithOffset.hasMatch(generatedAt) ||
        DateTime.tryParse(generatedAt) == null) {
      throw const FormatException(
        'Portable backup generation time is invalid.',
      );
    }
    final tablesNode = _object(bundle['tables'], 'tables');
    final manifest = _object(bundle['manifest'], 'manifest');
    _requireExactKeys(manifest, const [
      'tables',
      'documents',
      'core_sha256',
    ], 'manifest');
    final coreSha = manifest['core_sha256'];
    if (coreSha is! String ||
        !_sha256Pattern.hasMatch(coreSha) ||
        coreSha.toLowerCase() != _coreSha256(bundle)) {
      throw const FormatException(
        'Portable backup core checksum does not match.',
      );
    }
    final tableManifest = _object(manifest['tables'], 'table manifest');
    _requireExactKeys(tablesNode, AppDatabase.synchronizedTables, 'tables');
    _requireExactKeys(
      tableManifest,
      AppDatabase.synchronizedTables,
      'table manifest',
    );

    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in AppDatabase.synchronizedTables) {
      final node = tablesNode[table];
      if (node is! List) {
        throw FormatException('$table rows must be a list.');
      }
      final rows = <Map<String, Object?>>[];
      final ids = <String>{};
      for (final rawRow in node) {
        if (rawRow is! Map) {
          throw FormatException('$table contains a non-object row.');
        }
        final row = Map<String, Object?>.from(rawRow);
        final id = row['id'];
        if (id is! String || id.isEmpty) {
          throw FormatException('$table row has invalid id.');
        }
        if (!ids.add(id)) {
          throw FormatException('$table contains duplicate id $id.');
        }
        rows.add(row);
      }
      rows.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      final entry = _object(tableManifest[table], '$table manifest');
      _requireExactKeys(entry, const ['count', 'sha256'], '$table manifest');
      if (_intValue(entry['count']) != rows.length ||
          entry['sha256'] != _sha256Text(_stableJson(rows))) {
        throw FormatException('$table manifest does not match its rows.');
      }
      tables[table] = rows;
    }
    await _repository.validateSynchronizedRows(tables, portableBackup: true);
    final documents = _validateDocuments(
      bundle['documents'],
      manifest['documents'],
      tables,
    );
    return _RestorePlan(tables, documents);
  }

  List<_PortableDocument> _validateDocuments(
    Object? node,
    Object? manifestNode,
    Map<String, List<Map<String, Object?>>> tables,
  ) {
    if (node is! List) {
      throw const FormatException('Document bundle must be a list.');
    }
    final manifest = _object(manifestNode, 'document manifest');
    _requireExactKeys(manifest, const [
      'count',
      'total_bytes',
      'sha256',
    ], 'document manifest');
    final knownDocuments = {
      for (final row in tables['documents']!) row['id'] as String,
    };
    final result = <_PortableDocument>[];
    final ids = <String>{};
    var totalBytes = 0;
    for (final raw in node) {
      final entry = _object(raw, 'document bundle entry');
      _requireExactKeys(entry, const [
        'document_id',
        'sha256',
        'size_bytes',
        'bytes_base64',
      ], 'document bundle entry');
      final id = entry['document_id'];
      final digest = entry['sha256'];
      final size = _intValue(entry['size_bytes']);
      final encoded = entry['bytes_base64'];
      if (id is! String ||
          id.isEmpty ||
          !knownDocuments.contains(id) ||
          !ids.add(id)) {
        throw const FormatException(
          'Document bundle contains an invalid document id.',
        );
      }
      if (digest is! String ||
          !_sha256Pattern.hasMatch(digest) ||
          size == null ||
          size < 0 ||
          encoded is! String) {
        throw const FormatException(
          'Document bundle contains invalid metadata.',
        );
      }
      late final List<int> bytes;
      try {
        bytes = base64Decode(encoded);
      } on FormatException {
        throw const FormatException('Document bundle contains invalid base64.');
      }
      if (bytes.length != size || _sha256Bytes(bytes) != digest.toLowerCase()) {
        throw const FormatException('Document bundle checksum does not match.');
      }
      totalBytes += bytes.length;
      if (totalBytes > maxPdfBytes) {
        throw const FormatException(
          'Portable backup PDFs exceed the safety limit.',
        );
      }
      final row = tables['documents']!.singleWhere((item) => item['id'] == id);
      final rowDigest = row['sha256']?.toString();
      if (rowDigest != null &&
          rowDigest.isNotEmpty &&
          rowDigest.toLowerCase() != digest) {
        throw const FormatException(
          'Document row checksum does not match its PDF.',
        );
      }
      result.add(_PortableDocument(id, digest.toLowerCase(), bytes));
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    final manifestRows = [
      for (final document in result)
        {
          'document_id': document.id,
          'sha256': document.sha256,
          'size_bytes': document.bytes.length,
        },
    ];
    if (_intValue(manifest['count']) != result.length ||
        _intValue(manifest['total_bytes']) != totalBytes ||
        manifest['sha256'] != _sha256Text(_stableJson(manifestRows))) {
      throw const FormatException('Document manifest does not match its PDFs.');
    }
    return result;
  }

  Future<void> _stageDocuments(
    List<_PortableDocument> documents,
    Directory staging,
  ) async {
    if (documents.isEmpty) return;
    await staging.create(recursive: true);
    for (final document in documents) {
      final file = File(
        path.join(staging.path, _documentFileName(document.id)),
      );
      await file.writeAsBytes(document.bytes, flush: true);
      final verified = await file.readAsBytes();
      if (_sha256Bytes(verified) != document.sha256) {
        throw StateError('Failed to stage a verified document file.');
      }
    }
  }

  Map<String, Object?> _sanitizeExportRow(
    String table,
    Map<String, Object?> row,
  ) {
    final result = Map<String, Object?>.from(row);
    if (table == 'documents') {
      result.remove('local_path');
      result.remove('one_drive_item_id');
    }
    return result;
  }
}

typedef DocumentsDirectory = Future<Directory> Function();

class _RestorePlan {
  const _RestorePlan(this.tables, this.documents);

  final Map<String, List<Map<String, Object?>>> tables;
  final List<_PortableDocument> documents;
}

class _PortableDocument {
  const _PortableDocument(this.id, this.sha256, this.bytes);

  final String id;
  final String sha256;
  final List<int> bytes;
}

const _reverseRestoreOrder = <String>[
  'advisor_messages',
  'lab_plan_items',
  'lab_plans',
  'biomarker_list_items',
  'biomarker_lists',
  'named_health_records',
  'measurements',
  'documents',
  'profile_biomarker_targets',
  'biomarker_ranges',
  'health_events',
  'health_event_definitions',
  'inventory_movements',
  'supplement_intakes',
  'supplement_schedules',
  'supplements',
  'biomarkers',
  'profiles',
];

final _sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');
final _iso8601WithOffset = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
);
int _tokenCounter = 0;

Map<String, Object?> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object.');
  return Map<String, Object?>.from(value);
}

void _requireExactKeys(
  Map<String, Object?> value,
  Iterable<String> expected,
  String label,
) {
  final expectedSet = expected.toSet();
  if (value.keys.toSet().length != expectedSet.length ||
      !value.keys.toSet().containsAll(expectedSet)) {
    throw FormatException('$label has an unexpected field set.');
  }
}

int? _intValue(Object? value) => value is int ? value : null;

String _sha256Text(String value) => _sha256Bytes(utf8.encode(value));

String _sha256Bytes(List<int> value) => sha256.convert(value).toString();

/// Hashes the complete bundle after removing only this digest field itself.
String _coreSha256(Map<String, Object?> bundle) {
  final copy = Map<String, Object?>.from(_canonical(bundle) as Map);
  final manifest = Map<String, Object?>.from(copy['manifest'] as Map);
  manifest.remove('core_sha256');
  copy['manifest'] = manifest;
  return _sha256Text(_stableJson(copy));
}

String _stableJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry('${entry.key}', _canonical(entry.value)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, Object?>.fromEntries(entries);
  }
  if (value is Iterable) return [for (final item in value) _canonical(item)];
  return value;
}

String _restoreToken() =>
    '${DateTime.now().microsecondsSinceEpoch}-${_tokenCounter++}';

String _documentFileName(String documentId) => '${_sha256Text(documentId)}.pdf';

Future<void> _deleteIfExists(Directory directory) async {
  if (await directory.exists()) await directory.delete(recursive: true);
}
