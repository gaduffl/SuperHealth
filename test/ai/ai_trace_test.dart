import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_trace.dart';

class _Sink {
  final StringBuffer buffer = StringBuffer();
  Object? throws;

  Future<void> write(String line) async {
    final error = throws;
    if (error != null) throw error;
    buffer.write(line);
  }

  String get text => buffer.toString();
  List<Map<String, Object?>> get entries => const LineSplitter()
      .convert(text)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => Map<String, Object?>.from(jsonDecode(line) as Map))
      .toList();
}

void main() {
  group('recording', () {
    test(
      'every entry carries the run, the event and the elapsed time',
      () async {
        var now = DateTime(2026, 8, 8, 12);
        final sink = _Sink();
        final trace = AiTrace(write: sink.write, clock: () => now);

        await trace.begin('run-1', {'model': 'test-model'});
        now = now.add(const Duration(seconds: 3));
        await trace.event('stage', {'stage': 'drafting'});

        final entries = sink.entries;
        expect(entries, hasLength(2));
        expect(entries.first['event'], 'run_start');
        expect((entries.first['data'] as Map)['model'], 'test-model');
        expect(entries.last['run'], 'run-1');
        expect(entries.last['ms'], 3000);
      },
    );

    test('a failure keeps the type, not only the message', () async {
      // A format exception and a transport exception at the same point in the
      // run mean entirely different things, and the message alone hides which.
      final sink = _Sink();
      final trace = AiTrace(write: sink.write);

      await trace.begin('run-1', const {});
      await trace.failure(
        'request_failed',
        const FormatException('bad json'),
        StackTrace.current,
        {'pass': 'draft'},
      );

      final data = sink.entries.last['data'] as Map;
      expect(data['error_type'], 'FormatException');
      expect(data['error'], contains('bad json'));
      expect(data['stack'], isNotEmpty);
      expect(data['pass'], 'draft');
    });

    test('a long field is truncated but says how long it really was', () async {
      final sink = _Sink();
      final trace = AiTrace(write: sink.write);

      await trace.begin('run-1', const {});
      await trace.event('response', {'text': 'x' * 60000});

      final text = (sink.entries.last['data'] as Map)['text'] as String;
      expect(text, contains('truncated, 60000 chars total'));
      expect(text.length, lessThan(60000));
    });

    test('a sink that throws does not break the generation', () async {
      // The trace exists to explain failures. Causing one would be perverse.
      final sink = _Sink()..throws = StateError('disk full');
      final trace = AiTrace(write: sink.write);

      await expectLater(trace.begin('run-1', const {}), completes);
      await expectLater(trace.event('stage'), completes);
      await expectLater(trace.end(success: false), completes);
    });
  });

  group('parsing', () {
    Future<String> buildLog() async {
      final sink = _Sink();
      final trace = AiTrace(write: sink.write);
      for (var run = 1; run <= 3; run++) {
        await trace.begin('run-$run', {'n': run});
        await trace.event('stage', {'stage': 'drafting'});
        await trace.end(success: run.isOdd);
      }
      return sink.text;
    }

    test('runs are split apart, newest first', () async {
      final runs = parseTraceRuns(await buildLog());

      expect(runs, hasLength(3));
      expect((runs.first.first['data'] as Map)['n'], 3);
      expect((runs.last.first['data'] as Map)['n'], 1);
      expect(runs.first, hasLength(3));
    });

    test('a half-written final line does not destroy the rest', () async {
      // The app being killed mid-write is one of the outcomes under
      // investigation, so the parser must survive its own evidence.
      final truncated = '${await buildLog()}{"at":"2026-08-08T12:00:00Z","ev';

      final runs = parseTraceRuns(truncated);

      expect(runs, hasLength(3));
    });

    test('trimming keeps whole runs, newest first', () async {
      final trimmed = trimTraceToRuns(await buildLog(), 2);
      final runs = parseTraceRuns(trimmed);

      expect(runs, hasLength(2));
      // A run cut off at the top would read like a generation that began
      // halfway through, so each kept run must still start with run_start.
      for (final run in runs) {
        expect(run.first['event'], 'run_start');
      }
      expect((runs.first.first['data'] as Map)['n'], 3);
    });
  });

  group('report', () {
    test('names a run that never came back', () async {
      // The whole point: a generation that produced no plan and no error left
      // no run_end, and the report must say so rather than leave an absence.
      final sink = _Sink();
      final trace = AiTrace(write: sink.write);
      await trace.begin('run-1', {'model': 'test-model'});
      await trace.event('stage', {'stage': 'verifying'});

      final report = formatTraceReport(
        sink.text,
        generatedAt: DateTime(2026, 8, 8),
        title: 'SuperHealth lab planner diagnostic log',
        emptyMessage: 'No lab plan generation has been recorded yet.',
      );

      expect(report, contains('NEVER FINISHED'));
      expect(report, contains('verifying'));
      expect(report, contains('test-model'));
    });

    test('distinguishes a failure from a success', () async {
      final sink = _Sink();
      final trace = AiTrace(write: sink.write);
      await trace.begin('run-1', const {});
      await trace.end(success: false, data: {'approved': false});

      final report = formatTraceReport(
        sink.text,
        generatedAt: DateTime(2026, 8, 8),
        title: 'SuperHealth lab planner diagnostic log',
        emptyMessage: 'No lab plan generation has been recorded yet.',
      );

      expect(report, contains('failed'));
      expect(report, isNot(contains('NEVER FINISHED')));
    });

    test('warns that the file is health data', () async {
      // Model responses are included and they name biomarkers and supplements.
      // Someone about to attach this to a bug report needs to know that.
      final report = formatTraceReport(
        '',
        generatedAt: DateTime(2026, 8, 8),
        title: 'SuperHealth health advisor diagnostic log',
        emptyMessage: 'No advisor turn has been recorded yet.',
      );

      expect(report, contains('health data'));
      // The heading names which feature's log this is: two logs land in the
      // same bug report otherwise indistinguishable.
      expect(report, contains('health advisor'));
      expect(report, contains('No advisor turn has been recorded yet'));
    });
  });
}
