import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/ui/common.dart';
import 'package:super_health/ui/last_entry_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('an entered amount comes back for the same product and mode', () async {
    final slot = LastEntryMemory.stockSlot(supplementId: 'mag', mode: 'add');
    expect(await LastEntryMemory.read('profile-1', slot), isNull);

    await LastEntryMemory.write('profile-1', slot, 120);

    expect(await LastEntryMemory.read('profile-1', slot), 120);
  });

  test('modes are remembered apart from one another', () async {
    final add = LastEntryMemory.stockSlot(supplementId: 'mag', mode: 'add');
    final set = LastEntryMemory.stockSlot(supplementId: 'mag', mode: 'set');
    await LastEntryMemory.write('profile-1', add, 120);
    await LastEntryMemory.write('profile-1', set, 40);

    // "Add 120" and "set the total to 40" are different figures; offering one
    // where the other belongs would be worse than offering nothing.
    expect(await LastEntryMemory.read('profile-1', add), 120);
    expect(await LastEntryMemory.read('profile-1', set), 40);
  });

  test('products and profiles do not share a remembered amount', () async {
    final magnesium = LastEntryMemory.stockSlot(
      supplementId: 'mag',
      mode: 'add',
    );
    final vitaminD = LastEntryMemory.stockSlot(supplementId: 'd3', mode: 'add');
    await LastEntryMemory.write('profile-1', magnesium, 120);

    expect(await LastEntryMemory.read('profile-1', vitaminD), isNull);
    expect(await LastEntryMemory.read('profile-2', magnesium), isNull);
  });

  test(
    'a later entry replaces the earlier one, and forget clears it',
    () async {
      final slot = LastEntryMemory.stockSlot(supplementId: 'mag', mode: 'add');
      await LastEntryMemory.write('profile-1', slot, 120);
      await LastEntryMemory.write('profile-1', slot, 60);
      expect(await LastEntryMemory.read('profile-1', slot), 60);

      await LastEntryMemory.forget('profile-1', slot);
      expect(await LastEntryMemory.read('profile-1', slot), isNull);
    },
  );

  test('a value that cannot be an amount is not stored', () async {
    final slot = LastEntryMemory.stockSlot(supplementId: 'mag', mode: 'add');
    await LastEntryMemory.write('profile-1', slot, double.nan);
    await LastEntryMemory.write('profile-1', slot, double.infinity);

    expect(await LastEntryMemory.read('profile-1', slot), isNull);
  });

  test('the field text stays parseable and free of trailing noise', () {
    expect(plainAmountText(120), '120');
    expect(plainAmountText(1.5), '1.5');
    expect(parseOptionalDouble(plainAmountText(1200)), 1200);
    expect(parseOptionalDouble(plainAmountText(0.5)), 0.5);
  });

  testWidgets('the hint reports the amount and only fills when tapped', (
    tester,
  ) async {
    var used = 0;
    final field = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              TextField(controller: field),
              LastEntryHint(
                label: 'Last entered here: 120 capsules',
                onUse: () {
                  used++;
                  field.text = '120';
                },
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Last entered here: 120 capsules'), findsOneWidget);
    // Reporting only: the field is untouched until the offer is taken.
    expect(field.text, '');

    await tester.tap(find.text('Use'));
    await tester.pump();

    expect(used, 1);
    expect(field.text, '120');
  });

  testWidgets('without an offer the hint is text alone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [AppLocalizations.delegate],
        home: Scaffold(body: LastEntryHint(label: 'Last entered here: 3 g')),
      ),
    );

    expect(find.text('Last entered here: 3 g'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });
}
