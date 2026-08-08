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
}
