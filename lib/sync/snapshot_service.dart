import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../data/app_database.dart';
import '../data/health_repository.dart';

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
    if (snapshot['schema'] != 'superhealth.snapshot') {
      throw const FormatException('Unsupported snapshot schema');
    }
    final version = (snapshot['schema_version'] as num?)?.toInt();
    if (version == null || version > AppDatabase.schemaVersion) {
      throw FormatException('Unsupported snapshot version: $version');
    }
    final tablesNode = snapshot['tables'];
    if (tablesNode is! Map) {
      throw const FormatException('Snapshot tables are missing');
    }

    var applied = 0;
    var keptLocal = 0;
    var conflicts = 0;
    final db = await _database.database;

    await db.transaction((txn) async {
      for (final table in AppDatabase.synchronizedTables) {
        final incoming = tablesNode[table];
        if (incoming is! List) continue;
        for (final untyped in incoming) {
          if (untyped is! Map) continue;
          final row = Map<String, Object?>.from(untyped);
          if (table == 'documents') row.remove('local_path');
          final rowId = row['id']?.toString();
          if (rowId == null || rowId.isEmpty) continue;

          if (table == 'lab_plan_items') {
            await txn.insert(
              table,
              _sanitize(row),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            applied++;
            continue;
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

          if (localChanged &&
              remoteChanged &&
              _rowsDiffer(existing, row, table: table)) {
            conflicts++;
            await txn.insert('sync_conflicts', {
              'table_name': table,
              'row_id': rowId,
              'conflict_type': 'divergent_update',
              'local_json': jsonEncode(existing),
              'remote_json': jsonEncode(row),
              'detected_at': DateTime.now().toUtc().toIso8601String(),
            });
            // Never replace a strictly newer local edit.
            applyRemote = _isAfter(remoteUpdated, localUpdated);
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
            await _saveShadow(txn, table, rowId, localUpdated);
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
        if (table == 'lab_plan_items') continue;
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
