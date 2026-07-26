import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/health_repository.dart';

final _iso8601WithOffset = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
);

class SnapshotMergeResult {
  const SnapshotMergeResult({
    required this.appliedRows,
    required this.keptLocalRows,
    required this.conflicts,
  });

  final int appliedRows;
  final int keptLocalRows;
  final int conflicts;
}

enum SyncConflictResolution { keepLocal, acceptIncoming }

/// A deliberately redacted description of one divergent synchronized record.
///
/// The full row payload stays in the database and is used only when applying a
/// user-selected resolution. This prevents the conflict UI from displaying API
/// credentials or other incidental fields that may be added in the future.
class SnapshotConflict {
  const SnapshotConflict({
    required this.id,
    required this.tableName,
    required this.rowId,
    required this.conflictType,
    required this.detectedAt,
    required this.localUpdatedAt,
    required this.incomingUpdatedAt,
    required this.localSummary,
    required this.incomingSummary,
  });

  final int id;
  final String tableName;
  final String rowId;
  final String conflictType;
  final DateTime detectedAt;
  final DateTime? localUpdatedAt;
  final DateTime? incomingUpdatedAt;
  final String localSummary;
  final String incomingSummary;
}

class SnapshotService {
  SnapshotService(this._database, this._repository);

  final AppDatabase _database;
  final HealthRepository _repository;

  Future<String> buildSnapshotJson() async =>
      HealthRepository.stableJson(await _repository.fullSyncSnapshot());

  Future<SnapshotMergeResult> mergeJson(String source) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Snapshot must be an object');
    }
    return merge(Map<String, Object?>.from(decoded));
  }

  Future<SnapshotMergeResult> merge(Map<String, Object?> snapshot) async {
    const expectedKeys = {'schema', 'schema_version', 'generated_at', 'tables'};
    if (snapshot.keys.toSet().length != expectedKeys.length ||
        !snapshot.keys.toSet().containsAll(expectedKeys)) {
      throw const FormatException('Snapshot has an unexpected field set');
    }
    if (snapshot['schema'] != 'superhealth.snapshot') {
      throw const FormatException('Unsupported snapshot schema');
    }
    final version = snapshot['schema_version'];
    if (version is! int || version != AppDatabase.schemaVersion) {
      throw FormatException('Unsupported snapshot version: $version');
    }
    final tablesNode = snapshot['tables'];
    if (tablesNode is! Map) {
      throw const FormatException('Snapshot tables are missing');
    }
    final tables = <String, List<Map<String, Object?>>>{};
    for (final table in AppDatabase.synchronizedTables) {
      final node = tablesNode[table];
      if (node is! List) {
        throw FormatException('$table rows must be a list.');
      }
      final rows = <Map<String, Object?>>[];
      for (final raw in node) {
        if (raw is! Map) {
          throw FormatException('$table contains a non-object row.');
        }
        rows.add(Map<String, Object?>.from(raw));
      }
      tables[table] = rows;
    }
    final expectedTables = AppDatabase.synchronizedTables.toSet();
    if (tablesNode.keys.toSet().length != expectedTables.length ||
        !tablesNode.keys.toSet().containsAll(expectedTables)) {
      throw const FormatException('Snapshot has an unexpected table set.');
    }
    final generatedAt = snapshot['generated_at'];
    if (generatedAt is! String ||
        !_iso8601WithOffset.hasMatch(generatedAt) ||
        DateTime.tryParse(generatedAt) == null) {
      throw const FormatException('Snapshot generation time is invalid.');
    }
    await _repository.validateSynchronizedRows(tables, portableBackup: false);

    var applied = 0;
    var keptLocal = 0;
    var conflicts = 0;
    final db = await _database.database;

    await db.transaction((txn) async {
      for (final table in AppDatabase.synchronizedTables) {
        final incoming = tables[table]!;
        for (final row in incoming) {
          final rowId = row['id']?.toString();
          if (rowId == null || rowId.isEmpty) {
            throw FormatException('$table row has invalid id.');
          }

          final existingRows = await txn.query(
            table,
            where: 'id = ?',
            whereArgs: [rowId],
            limit: 1,
          );
          final existing = existingRows.isEmpty ? null : existingRows.first;
          final shadowRows = await txn.query(
            'sync_shadow',
            where: 'table_name = ? AND row_id = ?',
            whereArgs: [table, rowId],
            limit: 1,
          );
          final shadowUpdated = shadowRows.isEmpty
              ? null
              : shadowRows.first['updated_at']?.toString();
          final localUpdated = existing?['updated_at']?.toString();
          final remoteUpdated = row['updated_at']?.toString();

          final localChanged =
              existing != null &&
              shadowUpdated != null &&
              localUpdated != shadowUpdated;
          final remoteChanged =
              shadowUpdated == null ||
              remoteUpdated == null ||
              remoteUpdated != shadowUpdated;

          var applyRemote =
              existing == null ||
              _isAfter(remoteUpdated, localUpdated) ||
              (remoteUpdated == localUpdated &&
                  _rowsDiffer(existing, row, table: table));

          final hasDivergentConflict =
              localChanged &&
              remoteChanged &&
              _rowsDiffer(existing, row, table: table);
          if (hasDivergentConflict) {
            conflicts++;
            await _recordConflict(txn, table, rowId, existing, row);
            // A divergence is never a last-write-wins decision. Keep the
            // current row and its shadow untouched until the user decides.
            applyRemote = false;
          } else if (localChanged && !remoteChanged) {
            applyRemote = false;
          }

          if (applyRemote) {
            final rowToInsert = Map<String, Object?>.from(row);
            if (table == 'documents' && existing != null) {
              rowToInsert['local_path'] = existing['local_path'];
            }
            await txn.insert(
              table,
              _sanitize(rowToInsert),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            applied++;
            await _saveShadow(txn, table, rowId, remoteUpdated);
          } else {
            keptLocal++;
            // A local-only change must remain distinguishable until its cloud
            // upload succeeds and markCurrentAsSynchronized advances it.
            if (!hasDivergentConflict && !(localChanged && !remoteChanged)) {
              await _saveShadow(txn, table, rowId, localUpdated);
            }
          }
        }
      }
    });

    return SnapshotMergeResult(
      appliedRows: applied,
      keptLocalRows: keptLocal,
      conflicts: conflicts,
    );
  }

  Future<void> markCurrentAsSynchronized() async {
    final db = await _database.database;
    await db.transaction((txn) async {
      for (final table in AppDatabase.synchronizedTables) {
        final rows = await txn.query(table, columns: ['id', 'updated_at']);
        for (final row in rows) {
          await _saveShadow(
            txn,
            table,
            '${row['id']}',
            row['updated_at']?.toString(),
          );
        }
      }
    });
  }

  Future<List<SnapshotConflict>> unresolvedConflicts() async {
    final db = await _database.database;
    final rows = await db.query(
      'sync_conflicts',
      where: 'resolved_at IS NULL',
      orderBy: 'detected_at ASC, id ASC',
    );
    return rows.map(_conflictFromRow).toList(growable: false);
  }

  /// Applies a single explicit decision and records it with the conflict.
  ///
  /// Keep-local uses the remote timestamp as the shadow baseline. On the next
  /// sync the retained local row is therefore uploaded intentionally, instead
  /// of being mistaken for an unmodified row and overwritten again.
  Future<void> resolveConflict({
    required int conflictId,
    required SyncConflictResolution resolution,
  }) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'sync_conflicts',
        where: 'id = ? AND resolved_at IS NULL',
        whereArgs: [conflictId],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw StateError('This sync conflict has already been resolved.');
      }
      final conflict = rows.single;
      final table = conflict['table_name']?.toString() ?? '';
      final rowId = conflict['row_id']?.toString() ?? '';
      if (!AppDatabase.synchronizedTables.contains(table) || rowId.isEmpty) {
        throw StateError('This sync conflict is no longer valid.');
      }
      final local = _decodeStoredRow(conflict['local_json']);
      final incoming = _decodeStoredRow(conflict['remote_json']);
      if (local['id']?.toString() != rowId ||
          incoming['id']?.toString() != rowId) {
        throw StateError('This sync conflict has invalid record data.');
      }
      final currentRows = await txn.query(
        table,
        where: 'id = ?',
        whereArgs: [rowId],
        limit: 1,
      );
      final current = currentRows.isEmpty ? null : currentRows.single;

      if (resolution == SyncConflictResolution.acceptIncoming) {
        final replacement = Map<String, Object?>.from(incoming);
        if (table == 'documents' && current != null) {
          replacement['local_path'] = current['local_path'];
        }
        await txn.insert(
          table,
          _sanitize(replacement),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else if (current == null ||
          !_rowsDiffer(current, incoming, table: table)) {
        // This also repairs conflicts created by earlier versions that applied
        // the remote record before presenting the conflict to the user.
        final replacement = Map<String, Object?>.from(local);
        if (table == 'documents' && current != null) {
          replacement['local_path'] = current['local_path'];
        }
        await txn.insert(
          table,
          _sanitize(replacement),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final remoteUpdated = incoming['updated_at']?.toString();
      await _saveShadow(txn, table, rowId, remoteUpdated);
      await txn.update(
        'sync_conflicts',
        {
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
          'resolution': resolution == SyncConflictResolution.keepLocal
              ? 'keep_local'
              : 'accept_incoming',
        },
        where: 'id = ?',
        whereArgs: [conflictId],
      );
    });
  }

  Future<void> _recordConflict(
    Transaction txn,
    String table,
    String rowId,
    Map<String, Object?> local,
    Map<String, Object?> incoming,
  ) async {
    final existing = await txn.query(
      'sync_conflicts',
      columns: ['id'],
      where: 'table_name = ? AND row_id = ? AND resolved_at IS NULL',
      whereArgs: [table, rowId],
      limit: 1,
    );
    if (existing.isNotEmpty) return;
    await txn.insert('sync_conflicts', {
      'table_name': table,
      'row_id': rowId,
      'conflict_type': 'divergent_update',
      'local_json': jsonEncode(local),
      'remote_json': jsonEncode(incoming),
      'detected_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  SnapshotConflict _conflictFromRow(Map<String, Object?> row) {
    final local = _decodeStoredRow(row['local_json']);
    final incoming = _decodeStoredRow(row['remote_json']);
    return SnapshotConflict(
      id: (row['id'] as num).toInt(),
      tableName: row['table_name']?.toString() ?? '',
      rowId: row['row_id']?.toString() ?? '',
      conflictType: row['conflict_type']?.toString() ?? '',
      detectedAt:
          DateTime.tryParse(row['detected_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      localUpdatedAt: DateTime.tryParse(local['updated_at']?.toString() ?? ''),
      incomingUpdatedAt: DateTime.tryParse(
        incoming['updated_at']?.toString() ?? '',
      ),
      localSummary: _safeSummary(local),
      incomingSummary: _safeSummary(incoming),
    );
  }

  Map<String, Object?> _decodeStoredRow(Object? source) {
    if (source is! String) throw const FormatException('Missing conflict row.');
    final decoded = jsonDecode(source);
    if (decoded is! Map) throw const FormatException('Invalid conflict row.');
    return Map<String, Object?>.from(decoded);
  }

  String _safeSummary(Map<String, Object?> row) {
    final deleted = row['deleted'] == 1 || row['deleted'] == true;
    const labels = [
      'display_name',
      'name',
      'file_name',
      'canonical_name',
      'kind',
      'role',
    ];
    String? label;
    for (final key in labels) {
      final value = row[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        label = value;
        break;
      }
    }
    final publicFields = row.keys.where(
      (key) =>
          key != 'id' &&
          !key.endsWith('_at') &&
          key != 'local_path' &&
          !key.contains('token') &&
          !key.contains('secret') &&
          !key.contains('key'),
    );
    return [
      if (deleted) 'Deleted tombstone' else 'Active record',
      if (label != null) label else '${publicFields.length} fields',
    ].join(' · ');
  }

  Future<void> _saveShadow(
    Transaction txn,
    String table,
    String rowId,
    String? updatedAt,
  ) => txn.insert('sync_shadow', {
    'table_name': table,
    'row_id': rowId,
    'updated_at': updatedAt,
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Map<String, Object?> _sanitize(Map<String, Object?> row) => row.map(
    (key, value) => MapEntry(
      key,
      value is List || value is Map ? jsonEncode(value) : value,
    ),
  );

  bool _isAfter(String? candidate, String? baseline) {
    if (candidate == null) return baseline == null;
    if (baseline == null) return true;
    final a = DateTime.tryParse(candidate);
    final b = DateTime.tryParse(baseline);
    if (a == null) return false;
    if (b == null) return true;
    return a.isAfter(b);
  }

  bool _rowsDiffer(
    Map<String, Object?> a,
    Map<String, Object?> b, {
    required String table,
  }) {
    final left = Map<String, Object?>.from(a)..remove('updated_at');
    final right = Map<String, Object?>.from(b)..remove('updated_at');
    if (table == 'documents') {
      left.remove('local_path');
      right.remove('local_path');
    }
    return HealthRepository.stableJson(left) !=
        HealthRepository.stableJson(right);
  }
}
