import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/provider_clients.dart';

void main() {
  test('deltas are coalesced rather than forwarded one by one', () {
    // A long turn delivers thousands of deltas. One rebuild each would spend
    // the whole call redrawing a progress card.
    final seen = <ProviderActivity>[];
    final reporter = ActivityReporter(
      seen.add,
      interval: const Duration(minutes: 1),
    );

    for (var i = 0; i < 500; i++) {
      reporter.addOutput('token ');
    }

    expect(seen, hasLength(1));
    expect(seen.single.outputChars, 6);
  });

  test('flush emits the final state the interval would have swallowed', () {
    final seen = <ProviderActivity>[];
    final reporter = ActivityReporter(
      seen.add,
      interval: const Duration(minutes: 1),
    );

    reporter.addOutput('abc');
    reporter.addOutput('de');
    reporter.flush();

    expect(seen.last.outputChars, 5);
  });

  test('thinking and output are counted apart', () {
    final seen = <ProviderActivity>[];
    final reporter = ActivityReporter(seen.add, interval: Duration.zero);

    reporter.addThinking('weighing the options');
    expect(seen.last.isThinking, isTrue);

    reporter.addOutput('{"tiers"');
    // Once real output starts the model is past reasoning, and saying it is
    // still thinking would misreport the stage the user can see.
    expect(seen.last.isThinking, isFalse);
    expect(seen.last.thinkingChars, 20);
    expect(seen.last.outputChars, 8);
    expect(seen.last.totalChars, 28);
  });

  test('the reasoning tail stays bounded across a long trace', () {
    final seen = <ProviderActivity>[];
    final reporter = ActivityReporter(seen.add, interval: Duration.zero);

    for (var i = 0; i < 200; i++) {
      reporter.addThinking('reasoning chunk $i ');
    }

    // The count is complete; the kept text is not, because a whole trace grows
    // without bound and the card shows two lines of it.
    expect(seen.last.thinkingChars, greaterThan(3000));
    expect(
      seen.last.thinkingTail.length,
      lessThanOrEqualTo(ActivityReporter.tailChars),
    );
    expect(seen.last.thinkingTail, contains('199'));
  });

  test('a throwing listener does not reach the stream loop', () {
    // The reporter is called from inside the SSE loop. An exception there would
    // abort a response that was arriving perfectly well.
    final reporter = ActivityReporter(
      (_) => throw StateError('widget disposed'),
      interval: Duration.zero,
    );

    expect(() => reporter.addOutput('abc'), returnsNormally);
    expect(reporter.flush, returnsNormally);
  });

  test('no callback means no bookkeeping', () {
    final reporter = ActivityReporter(null);

    expect(reporter.isEnabled, isFalse);
    expect(() => reporter.addThinking('x'), returnsNormally);
    expect(reporter.flush, returnsNormally);
  });
}
