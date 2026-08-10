import 'dart:convert';

/// A diagnostic record of one AI run — a lab plan, an advisor turn.
///
/// Written as it happens rather than assembled at the end, because the runs
/// worth auditing are exactly the ones that never reach the end. A trace held
/// in memory would be lost by the failure it exists to explain.
///
/// What it deliberately does **not** contain is the health context itself. That
/// payload is megabytes, it is reproducible from the record, and it is the most
/// sensitive thing the app holds — so the trace keeps its sha, size and record
/// count, which is what a diagnosis actually needs. Model responses *are* kept
/// in full (bounded), because an unparseable response is the thing being
/// diagnosed.
class AiTrace {
  AiTrace({required this.write, this.clock = DateTime.now});

  /// Appends one JSON line. Never called concurrently by this class.
  final Future<void> Function(String line) write;
  final DateTime Function() clock;

  /// Longest string kept for any single field. A truncated response still shows
  /// where it stopped, which is the point; an unbounded one turns the log into
  /// something too big to export.
  static const maxFieldChars = 20000;

  String? _runId;
  DateTime? _startedAt;

  String? get runId => _runId;

  /// Starts a run. Any previous run on this instance is abandoned — the caller
  /// serialises generations, so an unfinished one means the app died.
  Future<void> begin(String runId, Map<String, Object?> data) async {
    _runId = runId;
    _startedAt = clock();
    await _record('run_start', data);
  }

  Future<void> event(String name, [Map<String, Object?> data = const {}]) =>
      _record(name, data);

  /// Records a failure with its type and stack. The type matters as much as the
  /// message: a `LabPlanFormatException` and a `DioException` at the same point
  /// in the run mean entirely different things.
  Future<void> failure(
    String name,
    Object error,
    StackTrace stack, [
    Map<String, Object?> data = const {},
  ]) => _record(name, {
    ...data,
    'error_type': error.runtimeType.toString(),
    'error': error.toString(),
    'stack': stack.toString(),
  });

  Future<void> end({
    required bool success,
    Map<String, Object?> data = const {},
  }) async {
    await _record('run_end', {...data, 'success': success});
    _runId = null;
    _startedAt = null;
  }

  Future<void> _record(String event, Map<String, Object?> data) async {
    final now = clock();
    final started = _startedAt;
    final line = jsonEncode({
      'at': now.toUtc().toIso8601String(),
      if (started != null) 'ms': now.difference(started).inMilliseconds,
      'run': _runId ?? 'unknown',
      'event': event,
      'data': {
        for (final entry in data.entries) entry.key: _bound(entry.value),
      },
    });
    try {
      await write('$line\n');
    } on Object {
      // A diagnostic must never be the reason a generation fails.
    }
  }

  static Object? _bound(Object? value) {
    if (value is! String || value.length <= maxFieldChars) return value;
    return '${value.substring(0, maxFieldChars)}'
        '… [truncated, ${value.length} chars total]';
  }
}

/// Splits a JSON-lines trace into runs, newest first.
///
/// Tolerates a corrupt or half-written final line: the app being killed
/// mid-write is one of the outcomes being investigated, so a parser that threw
/// on it would destroy the evidence.
List<List<Map<String, Object?>>> parseTraceRuns(String jsonl) {
  final runs = <List<Map<String, Object?>>>[];
  for (final line in const LineSplitter().convert(jsonl)) {
    if (line.trim().isEmpty) continue;
    Map<String, Object?> entry;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) continue;
      entry = Map<String, Object?>.from(decoded);
    } on FormatException {
      continue;
    }
    if (entry['event'] == 'run_start' || runs.isEmpty) {
      runs.add(<Map<String, Object?>>[]);
    }
    runs.last.add(entry);
  }
  return runs.reversed.toList(growable: false);
}

/// Keeps only the most recent [keep] runs of a JSON-lines trace.
///
/// Trimming by run rather than by line means a retained run is always whole; a
/// run cut off at the top reads like a generation that started mid-flight.
String trimTraceToRuns(String jsonl, int keep) {
  final runs = parseTraceRuns(jsonl).take(keep).toList().reversed;
  final buffer = StringBuffer();
  for (final run in runs) {
    for (final entry in run) {
      buffer.writeln(jsonEncode(entry));
    }
  }
  return buffer.toString();
}

/// Renders a trace as something a person can read and paste into a bug report.
String formatTraceReport(
  String jsonl, {
  required DateTime generatedAt,
  required String title,
  required String emptyMessage,
}) {
  final runs = parseTraceRuns(jsonl);
  final buffer = StringBuffer()
    ..writeln(title)
    ..writeln('Exported: ${generatedAt.toUtc().toIso8601String()}')
    ..writeln('Runs recorded: ${runs.length}')
    ..writeln()
    ..writeln(
      'The health context itself is NOT included — only its size, hash and '
      'record count. Model responses ARE included, and they name your '
      'biomarkers and supplements, so treat this file as health data.',
    )
    ..writeln();

  if (runs.isEmpty) {
    buffer.writeln(emptyMessage);
    return buffer.toString();
  }

  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    final ended = run.where((e) => e['event'] == 'run_end').firstOrNull;
    final outcome = ended == null
        // No run_end at all: the generation never returned. That is the
        // signature of a killed process, and it is worth naming outright
        // rather than leaving as an absence the reader has to notice.
        ? 'NEVER FINISHED (no run_end recorded)'
        : (ended['data'] as Map?)?['success'] == true
        ? 'succeeded'
        : 'failed';
    buffer
      ..writeln('=' * 72)
      ..writeln('Run ${runs.length - i} of ${runs.length} — $outcome')
      ..writeln('=' * 72);
    for (final entry in run) {
      final ms = entry['ms'];
      final stamp = ms is int
          ? '+${(ms / 1000).toStringAsFixed(1)}s'.padLeft(9)
          : ' ' * 9;
      buffer.writeln('$stamp  ${entry['event']}');
      final data = entry['data'];
      if (data is Map && data.isNotEmpty) {
        for (final field in data.entries) {
          final value = field.value.toString();
          buffer.writeln(
            value.contains('\n')
                ? '             ${field.key}:\n${_indent(value)}'
                : '             ${field.key}: $value',
          );
        }
      }
    }
    buffer.writeln();
  }
  return buffer.toString();
}

String _indent(String value) => const LineSplitter()
    .convert(value)
    .map((line) => '               $line')
    .join('\n');

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
