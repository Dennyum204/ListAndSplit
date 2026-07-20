import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';

void main() {
  group('ListQuantity', () {
    test('parses exact decimal text as integer thousandths', () {
      expect(ListQuantity.tryParse('1')?.thousandths, 1000);
      expect(ListQuantity.tryParse('1.5')?.thousandths, 1500);
      expect(ListQuantity.tryParse('1.050')?.thousandths, 1050);
      expect(ListQuantity.tryParse('0.001')?.thousandths, 1);
      expect(ListQuantity.tryParse('999999.999')?.thousandths, 999999999);
      expect(ListQuantity.tryParse(' 1.250 ')?.thousandths, 1250);
    });

    test('formats without unnecessary trailing zeroes', () {
      expect(ListQuantity.fromThousandths(1000).format(), '1');
      expect(ListQuantity.fromThousandths(1500).format(), '1.5');
      expect(ListQuantity.fromThousandths(1050).format(), '1.05');
      expect(ListQuantity.fromThousandths(1001).format(), '1.001');
      expect(ListQuantity.fromThousandths(1).format(), '0.001');
      expect(ListQuantity.fromThousandths(999999999).format(), '999999.999');
    });

    test('rejects zero, overflow, excess precision, and non-decimal syntax',
        () {
      for (final input in [
        '',
        '0',
        '0.000',
        '-1',
        '+1',
        '1.0000',
        '1000000',
        '999999.9999',
        '1,5',
        '1e3',
        '.5',
        'NaN',
        'Infinity',
      ]) {
        expect(ListQuantity.tryParse(input), isNull, reason: input);
      }
    });

    test('integer constructor enforces the same authoritative bounds', () {
      expect(
        () => ListQuantity.fromThousandths(0),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ListQuantity.fromThousandths(1000000000),
        throwsA(isA<FormatException>()),
      );
    });

    test('unit codes are stable and reject localized or unknown text', () {
      expect(
        ListUnit.values.map((unit) => unit.code),
        [
          'piece',
          'kg',
          'g',
          'l',
          'ml',
          'pack',
          'box',
          'bottle',
          'can',
          'bag',
        ],
      );
      expect(ListUnit.fromCode(null), isNull);
      expect(ListUnit.fromCode('kg'), ListUnit.kilogram);
      expect(
        () => ListUnit.fromCode('kilograms'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
