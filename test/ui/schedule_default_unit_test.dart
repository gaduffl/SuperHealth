import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/ui/dialogs.dart';

void main() {
  final date = DateTime(2026, 11, 7);
  Supplement product({String form = '', String stockUnit = 'unit'}) =>
      Supplement(
        id: 'p',
        name: 'Glycin',
        form: form,
        stockUnit: stockUnit,
        createdAt: date,
        updatedAt: date,
      );

  test('a schedule starts in the dose unit, not the form', () {
    expect(defaultScheduleUnit(product(form: 'Powder', stockUnit: 'g')), 'g');
    expect(
      defaultScheduleUnit(product(form: 'Pulver', stockUnit: 'scoop')),
      'scoop',
    );
    expect(
      defaultScheduleUnit(product(form: 'Softgel', stockUnit: 'capsule')),
      'capsule',
    );
  });

  test('the form only stands in for the generic placeholder', () {
    expect(defaultScheduleUnit(product(form: 'Gummy')), 'Gummy');
    expect(defaultScheduleUnit(product()), 'unit');
  });
}
