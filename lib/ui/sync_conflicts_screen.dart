import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_controller.dart';
import '../app/app_localizations.dart';
import '../sync/snapshot_service.dart';
import 'common.dart';

String _syncText(BuildContext context, String english, String german) =>
    AppLocalizations.of(context).pick(english, german);

class SyncConflictsScreen extends StatefulWidget {
  const SyncConflictsScreen({super.key});

  @override
  State<SyncConflictsScreen> createState() => _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends State<SyncConflictsScreen> {
  List<SnapshotConflict>? _conflicts;
  int? _resolvingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final conflicts = await context
          .read<AppController>()
          .unresolvedSyncConflicts();
      if (mounted) setState(() => _conflicts = conflicts);
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    }
  }

  Future<void> _resolve(
    SnapshotConflict conflict,
    SyncConflictResolution resolution,
  ) async {
    if (resolution == SyncConflictResolution.acceptIncoming) {
      final accepted = await showConfirmAction(
        context,
        title: _syncText(
          context,
          'Replace local record?',
          'Lokalen Datensatz ersetzen?',
        ),
        message: _syncText(
          context,
          'The incoming OneDrive version will replace the local record. '
              'If it is a deletion tombstone, the local record will remain deleted.',
          'Die eingehende OneDrive-Version ersetzt den lokalen Datensatz. '
              'Bei einem Löschmarker bleibt der lokale Datensatz gelöscht.',
        ),
        confirmLabel: _syncText(context, 'Replace local', 'Lokal ersetzen'),
        destructive: true,
      );
      if (!accepted || !mounted) return;
    }
    setState(() => _resolvingId = conflict.id);
    try {
      await context.read<AppController>().resolveSyncConflict(
        conflictId: conflict.id,
        resolution: resolution,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              resolution == SyncConflictResolution.keepLocal
                  ? _syncText(
                      context,
                      'Kept the local record. Sync again to upload it.',
                      'Lokalen Datensatz behalten. Synchronisiere erneut, um ihn hochzuladen.',
                    )
                  : _syncText(
                      context,
                      'Accepted the incoming OneDrive record.',
                      'Eingehenden OneDrive-Datensatz übernommen.',
                    ),
            ),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) await showAppError(context, error);
    } finally {
      if (mounted) setState(() => _resolvingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final conflicts = _conflicts;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _syncText(context, 'Sync conflicts', 'Synchronisierungskonflikte'),
        ),
      ),
      body: conflicts == null
          ? const Center(child: CircularProgressIndicator())
          : conflicts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: EmptyState(
                  icon: Icons.cloud_done_outlined,
                  title: _syncText(
                    context,
                    'No unresolved conflicts',
                    'Keine ungelösten Konflikte',
                  ),
                  message: _syncText(
                    context,
                    'Your next OneDrive sync can continue normally.',
                    'Die nächste OneDrive-Synchronisierung kann normal fortgesetzt werden.',
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              itemCount: conflicts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final conflict = conflicts[index];
                final resolving = _resolvingId == conflict.id;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tableLabel(conflict.tableName),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_syncText(context, 'Record', 'Datensatz')} ${conflict.rowId} · '
                          '${_syncText(context, 'detected', 'erkannt')} '
                          '${_timestamp(context, conflict.detectedAt)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Divider(height: 24),
                        _VersionSummary(
                          title: _syncText(context, 'Local', 'Lokal'),
                          timestamp: conflict.localUpdatedAt,
                          summary: conflict.localSummary,
                        ),
                        const SizedBox(height: 12),
                        _VersionSummary(
                          title: _syncText(
                            context,
                            'Incoming from OneDrive',
                            'Eingehend von OneDrive',
                          ),
                          timestamp: conflict.incomingUpdatedAt,
                          summary: conflict.incomingSummary,
                        ),
                        const SizedBox(height: 16),
                        if (resolving)
                          const Center(child: CircularProgressIndicator())
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _resolve(
                                  conflict,
                                  SyncConflictResolution.keepLocal,
                                ),
                                child: Text(
                                  _syncText(
                                    context,
                                    'Keep local',
                                    'Lokal behalten',
                                  ),
                                ),
                              ),
                              FilledButton(
                                onPressed: () => _resolve(
                                  conflict,
                                  SyncConflictResolution.acceptIncoming,
                                ),
                                child: Text(
                                  _syncText(
                                    context,
                                    'Accept incoming',
                                    'Eingehend übernehmen',
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _tableLabel(String table) => table
      .split('_')
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  String _timestamp(BuildContext context, DateTime? value) {
    if (value == null) {
      return _syncText(context, 'No timestamp', 'Kein Zeitstempel');
    }
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _VersionSummary extends StatelessWidget {
  const _VersionSummary({
    required this.title,
    required this.timestamp,
    required this.summary,
  });

  final String title;
  final DateTime? timestamp;
  final String summary;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 2),
      Text(summary),
      const SizedBox(height: 2),
      Text(
        timestamp == null
            ? _syncText(
                context,
                'Updated: unavailable',
                'Aktualisiert: nicht verfügbar',
              )
            : '${_syncText(context, 'Updated', 'Aktualisiert')}: '
                  '${timestamp.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}
