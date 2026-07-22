import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';

void main() {
  group('MoneyAmount', () {
    for (final currency in SplitCurrency.values) {
      test('parses and formats exact ${currency.code} minor units', () {
        expect(
          MoneyAmount.tryParse('1', currency: currency)?.minorUnits,
          100,
        );
        expect(
          MoneyAmount.tryParse(' 12.3 ', currency: currency)?.minorUnits,
          1230,
        );
        expect(
          MoneyAmount.tryParse('9999999.99', currency: currency)?.minorUnits,
          splitExpenseAmountMaxMinor,
        );
        expect(
          MoneyAmount.fromMinorUnits(1203, currency).format(),
          '${currency.code} 12.03',
        );
        expect(
          MoneyAmount.fromMinorUnits(-1, currency).format(),
          '${currency.code} -0.01',
        );
      });
    }

    test('rejects zero, signs, grouping, excess precision, and overflow', () {
      for (final value in [
        '',
        '0',
        '0.00',
        '-0.01',
        '+1.00',
        '1,00',
        '1.001',
        '.50',
        '9999999.999',
        '10000000.00',
      ]) {
        expect(
          MoneyAmount.tryParse(value, currency: SplitCurrency.chf),
          isNull,
          reason: value,
        );
      }
    });

    test(
        'formats authoritative legacy aggregate balances without a capacity cap',
        () {
      expect(
        MoneyAmount.fromMinorUnits(
          9223372036854775807,
          SplitCurrency.chf,
        ).format(),
        'CHF 92233720368547758.07',
      );
    });
  });
}
