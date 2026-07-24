import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';

void main() {
  const first = '30000000-0000-4000-8000-000000000001';
  const second = '30000000-0000-4000-8000-000000000002';
  const third = '30000000-0000-4000-8000-000000000003';

  test('canonical Equal allocation sorts UUIDs before assigning remainder', () {
    final shares = canonicalEqualExpenseShares(
      amountMinor: 1001,
      beneficiaryParticipantIds: const [third, first, second],
    );

    expect(
      shares.map((share) => (share.participantId, share.amountMinor)).toList(),
      const [
        (first, 334),
        (second, 334),
        (third, 333),
      ],
    );
  });

  test('canonical Equal detection is order-independent but remainder-aware',
      () {
    expect(
      expenseSharesAreCanonicalEqual(
        amountMinor: 1001,
        beneficiaryParticipantIds: const [second, first],
        shares: const [
          ListExpenseShare(participantId: second, amountMinor: 500),
          ListExpenseShare(participantId: first, amountMinor: 501),
        ],
      ),
      isTrue,
    );
    expect(
      expenseSharesAreCanonicalEqual(
        amountMinor: 1001,
        beneficiaryParticipantIds: const [second, first],
        shares: const [
          ListExpenseShare(participantId: second, amountMinor: 501),
          ListExpenseShare(participantId: first, amountMinor: 500),
        ],
      ),
      isFalse,
    );
  });

  test('canonical Equal allocation retains zero-share legacy behavior', () {
    final shares = canonicalEqualExpenseShares(
      amountMinor: 1,
      beneficiaryParticipantIds: const [first, second],
    );

    expect(shares.first.amountMinor, 1);
    expect(shares.last.amountMinor, 0);
    expect(
      expenseSharesAreCanonicalEqual(
        amountMinor: 1,
        beneficiaryParticipantIds: const [first, second],
        shares: shares,
      ),
      isTrue,
    );
  });

  test('canonical Equal rejects empty, duplicate, and non-positive inputs', () {
    expect(
      () => canonicalEqualExpenseShares(
        amountMinor: 1,
        beneficiaryParticipantIds: const <String>[],
      ),
      throwsArgumentError,
    );
    expect(
      () => canonicalEqualExpenseShares(
        amountMinor: 1,
        beneficiaryParticipantIds: const [first, first],
      ),
      throwsArgumentError,
    );
    expect(
      () => canonicalEqualExpenseShares(
        amountMinor: 0,
        beneficiaryParticipantIds: const [first],
      ),
      throwsArgumentError,
    );
  });

  test('zero parsing is opt-in for custom-field deselection', () {
    expect(
      MoneyAmount.tryParse('0', currency: SplitCurrency.chf),
      isNull,
    );
    expect(
      MoneyAmount.tryParse(
        '0.00',
        currency: SplitCurrency.chf,
        allowZero: true,
      )?.minorUnits,
      0,
    );
    expect(
      MoneyAmount.tryParse(
        '-0.01',
        currency: SplitCurrency.chf,
        allowZero: true,
      ),
      isNull,
    );
  });
}
