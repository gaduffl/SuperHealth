import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ui/dialogs.dart';

void main() {
  group('stockAdjustmentDelta', () {
    test('single units pass through unchanged', () {
      expect(stockAdjustmentDelta(direction: 'add', amount: 5, current: 10), 5);
      expect(
        stockAdjustmentDelta(direction: 'remove', amount: 5, current: 10),
        -5,
      );
      expect(
        stockAdjustmentDelta(direction: 'set', amount: 4, current: 10),
        -6,
      );
    });

    test('whole packs multiply by the container size', () {
      const packs = StockQuantityMode.packages;
      expect(
        stockAdjustmentDelta(
          direction: 'add',
          amount: 2,
          current: 10,
          mode: packs,
          unitsPerContainer: 90,
        ),
        180,
      );
      expect(
        stockAdjustmentDelta(
          direction: 'remove',
          amount: 1,
          current: 200,
          mode: packs,
          unitsPerContainer: 90,
        ),
        -90,
      );
      expect(
        stockAdjustmentDelta(
          direction: 'set',
          amount: 3,
          current: 100,
          mode: packs,
          unitsPerContainer: 60,
        ),
        80,
      );
      expect(
        stockAdjustmentDelta(
          direction: 'add',
          amount: 0.5,
          current: 0,
          mode: packs,
          unitsPerContainer: 120,
        ),
        60,
      );
    });

    test('packs fall back to single units without a container size', () {
      for (final size in [null, 0, -3]) {
        expect(
          stockAdjustmentDelta(
            direction: 'add',
            amount: 2,
            current: 0,
            mode: StockQuantityMode.packages,
            unitsPerContainer: size,
          ),
          2,
        );
      }
    });
  });
}
