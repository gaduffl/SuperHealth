import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/reminders/reminder_service.dart';

void main() {
  group('android scheduling mode', () {
    test('an exact alarm is used once the right is granted', () {
      // A dose reminder names a time. Inexact alarms are batched by Doze and
      // routinely land hours late, which reads as a reminder that never came.
      expect(
        ReminderService.scheduleModeFor(exactAllowed: true),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
    });

    test('a withheld right falls back rather than losing the reminder', () {
      expect(
        ReminderService.scheduleModeFor(exactAllowed: false),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });

    test('unknown is not treated as granted', () {
      // Before the first initialize the answer is null. Scheduling an exact
      // alarm Android has not granted throws, and one throw inside reconcile
      // aborts the rest of the batch — so every later reminder would be lost.
      expect(
        ReminderService.scheduleModeFor(exactAllowed: null),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });
  });
}
