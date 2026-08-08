import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/long_task_guard.dart';

const _notice = LongTaskNotice(title: 'Working', text: 'A few minutes');

class _Recorder {
  final List<String> calls = [];
  bool startSucceeds = true;
  Object? startThrows;
  Object? stopThrows;
  Object? screenThrows;

  LongTaskGuard build() => LongTaskGuard(
    startService: (notice) async {
      calls.add('start:${notice.title}');
      final error = startThrows;
      if (error != null) throw error;
      return startSucceeds;
    },
    stopService: () async {
      calls.add('stop');
      final error = stopThrows;
      if (error != null) throw error;
    },
    holdScreenAwake: (hold) async {
      calls.add('screen:$hold');
      final error = screenThrows;
      if (error != null) throw error;
    },
  );
}

void main() {
  test(
    'a hold takes the screen and the service, and release gives both back',
    () async {
      final recorder = _Recorder();
      final guard = recorder.build();

      await guard.hold(_notice);
      expect(recorder.calls, ['screen:true', 'start:Working']);
      expect(guard.isHolding, isTrue);
      expect(guard.hasForegroundService, isTrue);

      await guard.release();
      expect(recorder.calls, [
        'screen:true',
        'start:Working',
        'stop',
        'screen:false',
      ]);
      expect(guard.isHolding, isFalse);
      expect(guard.hasForegroundService, isFalse);
    },
  );

  test(
    'a refused service still leaves the task running under the wakelock',
    () async {
      final recorder = _Recorder()..startSucceeds = false;
      final guard = recorder.build();

      await guard.hold(_notice);
      expect(guard.isHolding, isTrue);
      expect(guard.hasForegroundService, isFalse);

      await guard.release();
      // No stop: the guard must not stop a service it never started, which on a
      // shared notification id would be someone else's.
      expect(recorder.calls, isNot(contains('stop')));
      expect(recorder.calls.last, 'screen:false');
    },
  );

  test('a platform that throws does not throw at the caller', () async {
    final recorder = _Recorder()
      ..startThrows = StateError('no service')
      ..stopThrows = StateError('not started')
      ..screenThrows = StateError('no wakelock');
    final guard = recorder.build();

    await guard.hold(_notice);
    expect(guard.hasForegroundService, isFalse);
    await guard.release();

    // Losing the guard makes the task fragile. Losing the task is worse.
    expect(recorder.calls, ['screen:true', 'start:Working', 'screen:false']);
  });

  test('overlapping holds start one service and stop it only once', () async {
    final recorder = _Recorder();
    final guard = recorder.build();

    await guard.hold(_notice);
    await guard.hold(_notice);
    expect(
      recorder.calls.where((call) => call.startsWith('start')),
      hasLength(1),
    );

    // The first task to finish must not stop the service under the second.
    await guard.release();
    expect(recorder.calls, isNot(contains('stop')));
    expect(guard.isHolding, isTrue);

    await guard.release();
    expect(recorder.calls, contains('stop'));
    expect(guard.isHolding, isFalse);
  });

  test('a release with nothing held does nothing', () async {
    final recorder = _Recorder();
    final guard = recorder.build();

    await guard.release();

    expect(recorder.calls, isEmpty);
  });
}
