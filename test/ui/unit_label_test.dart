import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/app/app_localizations.dart';
import 'package:super_health/ui/common.dart';

void main() {
  const english = AppLocalizations.english;
  const german = AppLocalizations.german;

  test('a unit the person entered is shown exactly as entered', () {
    expect(unitLabel(english, unit: 'capsule', form: 'tablet'), 'capsule');
    expect(unitLabel(german, unit: 'Kapsel'), 'Kapsel');
    expect(unitLabel(english, unit: '  mg  '), 'mg');
  });

  test('the internal placeholder falls back to the product form', () {
    expect(unitLabel(english, unit: 'unit', form: 'capsule'), 'capsule');
    expect(unitLabel(german, unit: 'unit', form: 'Kapsel'), 'Kapsel');
    // Case is not meaningful for the placeholder.
    expect(unitLabel(english, unit: 'Unit', form: 'scoop'), 'scoop');
  });

  test('with no form the placeholder becomes a localized generic word', () {
    expect(unitLabel(english, unit: 'unit'), 'units');
    expect(unitLabel(german, unit: 'unit'), 'Einheiten');
    expect(unitLabel(english, unit: 'unit', form: '   '), 'units');
    // An empty unit is the same situation as the placeholder.
    expect(unitLabel(english, unit: ''), 'units');
    expect(unitLabel(english, unit: '', form: 'tablet'), 'tablet');
  });

  test('amounts read with their resolved unit', () {
    expect(
      formatAmountWithUnit(english, amount: 3, unit: 'unit', form: 'capsule'),
      '3.0 capsule',
    );
    expect(
      formatAmountWithUnit(english, amount: 2, unit: 'unit', decimalDigits: 0),
      '2 units',
    );
    expect(
      formatAmountWithUnit(english, amount: 500, unit: 'mg', decimalDigits: 0),
      '500 mg',
    );
  });

  test('list membership names one or two lists and summarises more', () {
    expect(listMembershipLabel(english, const []), 'No list');
    expect(listMembershipLabel(german, const []), 'Keine Liste');
    expect(listMembershipLabel(english, const ['Annual']), 'Annual');
    expect(
      listMembershipLabel(english, const ['Annual', 'Iron panel']),
      'Annual, Iron panel',
    );
    // Beyond two, the names would crowd out the overdue figure next to them.
    expect(
      listMembershipLabel(english, const ['Annual', 'Iron panel', 'Quarterly']),
      'Annual +2 more',
    );
    expect(
      listMembershipLabel(german, const ['Jahr', 'Eisen', 'Quartal']),
      'Jahr +2 weitere',
    );
  });
}
