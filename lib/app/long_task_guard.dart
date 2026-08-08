import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// What the ongoing notification says while a long task runs.
class LongTaskNotice {
  const LongTaskNotice({required this.title, required this.text});

  final String title;
  final String text;
}

/// Starts the foreground service. Returns whether it is now running.
typedef ForegroundServiceStart = Future<bool> Function(LongTaskNotice notice);

/// Stops the foreground service.
typedef ForegroundServiceStop = Future<void> Function();

/// Holds or releases the screen wakelock.
typedef ScreenAwakeToggle = Future<void> Function(bool hold);

/// Keeps a long call on the main isolate alive while the app is not in front.
///
/// Two things are held, and they answer different failure modes:
///
/// * A **wakelock** stops the device sleeping. A sleeping device suspends the
///   isolate, which drops the request mid-flight.
/// * A **foreground service** takes the process off the kill list. This is the
///   only one of the two that survives memory pressure, and it is the reason an
///   ongoing notification appears.
///
/// Nothing runs *inside* the service. The work stays on the main isolate, which
/// is where secure storage, the database and the context builder already live —
/// none of them exist in a second isolate. The service is here to buy process
/// priority, not to do the job.
///
/// Every platform call is best effort and swallows its failure. A guard that
/// could not be taken makes the task more fragile; a guard that threw would
/// lose the task outright, which is worse than the problem it exists to solve.
class LongTaskGuard {
  LongTaskGuard({
    ForegroundServiceStart? startService,
    ForegroundServiceStop? stopService,
    ScreenAwakeToggle? holdScreenAwake,
  }) : _startService = startService ?? _startForegroundService,
       _stopService = stopService ?? _stopForegroundService,
       _holdScreenAwake = holdScreenAwake ?? _toggleWakelock;

  final ForegroundServiceStart _startService;
  final ForegroundServiceStop _stopService;
  final ScreenAwakeToggle _holdScreenAwake;

  /// Android notification channel for the ongoing "still working" notification.
  ///
  /// Deliberately not the dose-reminder channel: a channel's importance is
  /// fixed at creation, and a reminder has to be able to make noise while this
  /// one must never do so.
  static const channelId = 'long_running_task';

  /// Notification id for the service. Fixed, because there is only ever one.
  static const serviceId = 8613;

  /// Nested holds outstanding. Refcounted so that two overlapping tasks cannot
  /// have the first one to finish stop the service out from under the second.
  int _depth = 0;
  bool _serviceRunning = false;

  bool get isHolding => _depth > 0;

  /// Whether the foreground service is currently held by this guard.
  ///
  /// False when the service could not be started — the task still runs, and the
  /// wakelock still applies.
  bool get hasForegroundService => _serviceRunning;

  Future<void> hold(LongTaskNotice notice) async {
    _depth++;
    if (_depth > 1) return;
    await _attempt(() => _holdScreenAwake(true));
    _serviceRunning = await _attemptStart(notice);
  }

  /// Releases one hold. A release with nothing held does nothing, so a stray
  /// call cannot stop a service this guard never started.
  Future<void> release() async {
    if (_depth == 0) return;
    _depth--;
    if (_depth > 0) return;
    if (_serviceRunning) {
      _serviceRunning = false;
      await _attempt(_stopService);
    }
    await _attempt(() => _holdScreenAwake(false));
  }

  Future<void> _attempt(Future<void> Function() action) async {
    try {
      await action();
    } on Object {
      // Best effort by design; see the class comment.
    }
  }

  Future<bool> _attemptStart(LongTaskNotice notice) async {
    try {
      return await _startService(notice);
    } on Object {
      return false;
    }
  }

  static Future<bool> _startForegroundService(LongTaskNotice notice) async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: channelId,
        channelName: 'Work in progress',
        channelDescription:
            'Shown while a long calculation runs, so Android lets it finish.',
        // A status line, not an alert. Nothing here is worth interrupting for.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        // No repeating callback: the service holds priority, it does not work.
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        // There is nothing to resume. A service that came back by itself would
        // be an ongoing notification for a task that no longer exists.
        allowAutoRestart: false,
        // Swiping the app away ends the isolate doing the work, so the service
        // holding priority for it should go at the same moment.
        stopWithTask: true,
      ),
    );

    final result = await FlutterForegroundTask.startService(
      serviceId: serviceId,
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: notice.title,
      notificationText: notice.text,
    );
    return result is ServiceRequestSuccess;
  }

  static Future<void> _stopForegroundService() =>
      FlutterForegroundTask.stopService();

  static Future<void> _toggleWakelock(bool hold) =>
      WakelockPlus.toggle(enable: hold);
}
