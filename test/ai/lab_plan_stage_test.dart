import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/lab_planner_service.dart';

void main() {
  test('every stage names itself in both languages', () {
    // A progress card that falls back to an enum name would report
    // "repairingDraft" to someone waiting on a health plan.
    for (final stage in LabPlanStage.values) {
      expect(stage.englishLabel, isNotEmpty, reason: stage.name);
      expect(stage.germanLabel, isNotEmpty, reason: stage.name);
      expect(stage.englishLabel, isNot(stage.name));
      expect(stage.germanLabel, isNot(stage.englishLabel));
    }
  });

  test('the stages are ordered as the work happens', () {
    // The card turns the index into a progress fraction, so a reordering here
    // would make the bar jump backwards mid-run.
    expect(LabPlanStage.values, [
      LabPlanStage.preparingContext,
      LabPlanStage.drafting,
      LabPlanStage.repairingDraft,
      LabPlanStage.verifying,
      LabPlanStage.reading,
    ]);
  });

  group('quiet detection', () {
    final now = DateTime(2026, 8, 8, 12);

    test('a run that never streamed is not called stalled', () {
      // Null covers two honest cases — the call has not produced yet, and the
      // provider has no streaming path. Neither is evidence of a stall, and a
      // warning that fires on both is a warning nobody reads.
      expect(labPlanHasGoneQuiet(lastActivityAt: null, now: now), isFalse);
    });

    test('recent activity is not quiet', () {
      expect(
        labPlanHasGoneQuiet(
          lastActivityAt: now.subtract(const Duration(seconds: 20)),
          now: now,
        ),
        isFalse,
      );
    });

    test('silence past the threshold is quiet', () {
      expect(
        labPlanHasGoneQuiet(
          lastActivityAt: now.subtract(labPlanQuietThreshold),
          now: now,
        ),
        isTrue,
      );
    });

    test('the threshold is generous enough to outlast a thinking pause', () {
      // A model can think for a long time between visible tokens. Crying
      // "stuck" at one that is merely slow is how a real warning gets ignored.
      expect(labPlanQuietThreshold.inSeconds, greaterThanOrEqualTo(60));
    });
  });
}
