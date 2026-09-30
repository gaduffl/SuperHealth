import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/advisor_review.dart';
import 'package:super_health/ai/clinical_digest.dart';

const _checklist = [
  ReviewItem(id: 'exp:biotin', label: 'Biotin'),
  ReviewItem(id: 'exp:magnesium', label: 'Magnesium'),
  ReviewItem(id: 'med:1', label: 'L-Thyroxin 75'),
  ReviewItem(id: 'finding:biotin', label: 'Biotin can distort many tests'),
];

void main() {
  test('a complete block is read against the checklist and removed from '
      'the answer', () {
    final parsed = parseAdvisorReply(
      '<exposure_review>{"relevant":[{"id":"exp:biotin","why":"Assay '
      'interference."},{"id":"finding:biotin","why":"Applies."}],'
      '"uncertain":[{"id":"med:1","why":"Timing unknown."}],'
      '"not_relevant":["exp:magnesium"]}</exposure_review>\n'
      'Pause biotin for 72 hours first.',
      _checklist,
    );

    expect(parsed.blockFound, isTrue);
    expect(parsed.missing, isEmpty);
    expect(parsed.review.complete, isTrue);
    expect(parsed.answer, 'Pause biotin for 72 hours first.');
    expect(parsed.review.relevant.first.what, 'Biotin');
    expect(parsed.review.relevant.first.why, 'Assay interference.');
    expect(parsed.review.uncertain.single.what, 'L-Thyroxin 75');
    expect(parsed.review.notRelevant, ['Magnesium']);
  });

  test('the shapes models actually produce still count', () {
    final parsed = parseAdvisorReply(
      '<exposure_review>\n```json\n{"relevant":[],"uncertain":[],'
      '"not_relevant":[{"id":"exp:biotin"},"exp:magnesium","med:1",'
      '"finding:biotin"]}\n```\n</exposure_review>\nAnswer.',
      _checklist,
    );

    expect(parsed.missing, isEmpty);
    expect(parsed.review.notRelevant, hasLength(4));
  });

  test('ids off the checklist are ignored and duplicates count once', () {
    final parsed = parseAdvisorReply(
      '<exposure_review>{"relevant":[{"id":"exp:biotin","why":"a"},'
      '{"id":"exp:invented","why":"b"}],"uncertain":[],'
      '"not_relevant":["exp:biotin"]}</exposure_review>\nAnswer.',
      _checklist,
    );

    expect(parsed.review.relevant.single.what, 'Biotin');
    expect(parsed.review.notRelevant, isEmpty);
    expect(parsed.missing.map((item) => item.id), [
      'exp:magnesium',
      'med:1',
      'finding:biotin',
    ]);
    expect(parsed.review.notAssessed, [
      'Magnesium',
      'L-Thyroxin 75',
      'Biotin can distort many tests',
    ]);
  });

  test('a reply without a block has judged nothing', () {
    final parsed = parseAdvisorReply('Just an answer.', _checklist);

    expect(parsed.blockFound, isFalse);
    expect(parsed.missing, hasLength(_checklist.length));
    expect(parsed.answer, 'Just an answer.');
  });

  test('with nothing to judge, no block is needed', () {
    final parsed = parseAdvisorReply('Just an answer.', const []);

    expect(parsed.missing, isEmpty);
    expect(parsed.review.complete, isTrue);
    expect(withReviewSection(parsed.answer, parsed.review), 'Just an answer.');
  });

  test('the stored review round-trips and stays out of replayed text', () {
    final parsed = parseAdvisorReply(
      '<exposure_review>{"relevant":[{"id":"exp:biotin","why":"Ends --> '
      'early"}],"uncertain":[],"not_relevant":["exp:magnesium"]}'
      '</exposure_review>\nThe answer.',
      _checklist,
    );
    final stored = withReviewSection(parsed.answer, parsed.review);

    // A reason containing "-->" must not close the comment early.
    expect(stored.indexOf('-->'), stored.lastIndexOf('-->'));
    expect(stored, isNot(contains('exp:')));
    final split = splitReviewSection(stored);
    expect(split.answer, 'The answer.');
    expect(split.review!.relevant.single.why, 'Ends --> early');
    expect(split.review!.notAssessed, [
      'L-Thyroxin 75',
      'Biotin can distort many tests',
    ]);
    expect(withoutReviewSection(stored), 'The answer.');
    expect(splitReviewSection('Plain old answer.').review, isNull);
  });
}
