// ignore_for_file: prefer_initializing_formals

import 'dart:io';

import '../backup/portable_backup_service.dart' show DocumentsDirectory;
import 'lab_plan_trace.dart';

/// Keeps the lab-planner diagnostic trace on disk.
///
/// On disk rather than in memory because the run that needs explaining is the
/// one that never came back — and a process that was killed takes any in-memory
/// record with it. Each line is flushed as it is written for the same reason.
class LabPlanTraceStore {
  LabPlanTraceStore({required DocumentsDirectory documentsDirectory})
    : _documentsDirectory = documentsDirectory;

  final DocumentsDirectory _documentsDirectory;

  /// How many runs are kept. Enough to compare a failure against the attempt
  /// before it, few enough that the file stays exportable.
  static const keepRuns = 5;

  static const fileName = 'lab-planner-trace.jsonl';

  File? _cached;

  Future<File> _file() async {
    final cached = _cached;
    if (cached != null) return cached;
    final base = await _documentsDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}diagnostics',
    );
    await directory.create(recursive: true);
    return _cached = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
  }

  Future<void> append(String line) async {
    final file = await _file();
    await file.writeAsString(line, mode: FileMode.append, flush: true);
  }

  Future<String> read() async {
    final file = await _file();
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  /// Drops all but the most recent [keepRuns] runs. Called when a run starts,
  /// so the file is bounded without ever trimming the run in progress.
  Future<void> trim() async {
    final file = await _file();
    if (!await file.exists()) return;
    final existing = await file.readAsString();
    final trimmed = trimTraceToRuns(existing, keepRuns);
    if (trimmed.length == existing.length) return;
    await file.writeAsString(trimmed, flush: true);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }

  /// A trace bound to this store. Writes go straight through to the file.
  LabPlanTrace trace() => LabPlanTrace(write: append);
}
