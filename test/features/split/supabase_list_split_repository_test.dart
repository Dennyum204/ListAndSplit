import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/split/data/supabase_list_split_repository.dart';
import 'package:list_and_split/features/split/domain/list_split.dart';
import 'package:list_and_split/features/split/domain/list_split_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabaseListSplitRepository repository;

  setUp(() {
    calls = [];
    response = _projection();
    failure = null;
    repository = SupabaseListSplitRepository(
      SupabaseClient('http://localhost:54321', 'test-publishable-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('uses the exact reviewed Split RPC names and parameters', () async {
    final overview = await repository.getSplit(_listId);
    final expense = overview.expenses.single;
    await repository.enableSplit(
      _listId,
      SplitCurrency.eur,
      expectedListVersion: 3,
    );
    await repository.changeCurrency(
      _listId,
      SplitCurrency.eur,
      expectedSplitVersion: 4,
    );
    await repository.createExpense(
      _listId,
      description: 'Train',
      amountMinor: 1200,
      payerParticipantId: _ownerParticipantId,
      beneficiaryParticipantIds: const [
        _ownerParticipantId,
        _memberParticipantId
      ],
      requestId: _requestId,
      expectedSplitVersion: 4,
    );
    await repository.updateExpense(
      _listId,
      expense.id,
      description: 'Train tickets',
      amountMinor: 1300,
      payerParticipantId: _memberParticipantId,
      beneficiaryParticipantIds: const [_memberParticipantId],
      expectedSplitVersion: 5,
      expectedExpenseVersion: 2,
    );
    await repository.deleteExpense(
      _listId,
      expense.id,
      expectedSplitVersion: 6,
      expectedExpenseVersion: 3,
    );

    expect(calls, [
      const _RpcCall('get_active_list_split', {
        'target_list_id': _listId,
      }),
      const _RpcCall('enable_active_list_split', {
        'target_list_id': _listId,
        'new_currency_code': 'EUR',
        'expected_list_version': 3,
      }),
      const _RpcCall('change_active_list_split_currency', {
        'target_list_id': _listId,
        'new_currency_code': 'EUR',
        'expected_split_version': 4,
      }),
      const _RpcCall('create_active_list_expense', {
        'target_list_id': _listId,
        'new_description': 'Train',
        'new_amount_minor': 1200,
        'payer_participant_id': _ownerParticipantId,
        'beneficiary_participant_ids': [
          _ownerParticipantId,
          _memberParticipantId,
        ],
        'creation_request_id': _requestId,
        'expected_split_version': 4,
      }),
      const _RpcCall('update_active_list_expense', {
        'target_list_id': _listId,
        'target_expense_id': _expenseId,
        'new_description': 'Train tickets',
        'new_amount_minor': 1300,
        'payer_participant_id': _memberParticipantId,
        'beneficiary_participant_ids': [_memberParticipantId],
        'expected_split_version': 5,
        'expected_expense_version': 2,
      }),
      const _RpcCall('delete_active_list_expense', {
        'target_list_id': _listId,
        'target_expense_id': _expenseId,
        'expected_split_version': 6,
        'expected_expense_version': 3,
      }),
    ]);
  });

  test('strictly maps settings, participants, exact shares, and balances',
      () async {
    final overview = await repository.getSplit(_listId);

    expect(overview.listId, _listId);
    expect(overview.currency, SplitCurrency.chf);
    expect(overview.participants, hasLength(2));
    expect(overview.participants.first.balanceMinor, 500);
    expect(overview.participants.last.balanceMinor, -500);
    expect(overview.expenses.single.amountMinor, 1001);
    expect(
      overview.expenses.single.shares.map((share) => share.amountMinor),
      [501, 500],
    );
  });

  test('keeps a legacy 201-expense projection accessible', () async {
    final legacy = _projection();
    final baseExpense = Map<String, dynamic>.from(
      (legacy['expenses'] as List).single as Map,
    );
    legacy['expenses'] = <Object?>[
      for (var index = 1; index <= 201; index += 1)
        Map<String, dynamic>.from(baseExpense)
          ..['id'] =
              '40000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
    ];
    final participants = (legacy['participants'] as List)
        .map((participant) => Map<String, dynamic>.from(participant as Map))
        .toList();
    participants[0]
      ..['paid_minor'] = 1001 * 201
      ..['owed_minor'] = 501 * 201
      ..['balance_minor'] = 500 * 201;
    participants[1]
      ..['paid_minor'] = 0
      ..['owed_minor'] = 500 * 201
      ..['balance_minor'] = -500 * 201;
    legacy['participants'] = participants;
    response = legacy;

    final overview = await repository.getSplit(_listId);
    expect(overview.expenses, hasLength(201));
    expect(overview.participants.first.balanceMinor, 100500);
  });

  test('rejects widened, inconsistent, and privacy-invalid projections',
      () async {
    final widened = _projection()..['internal_owner_id'] = _ownerProfileId;
    final badShare = _projection();
    (((badShare['expenses'] as List).single as Map<String, dynamic>)['shares']
            as List)
        .cast<Map<String, dynamic>>()
        .last['amount_minor'] = 499;
    final badBalance = _projection();
    ((badBalance['participants'] as List).first
        as Map<String, dynamic>)['paid_minor'] = 999;
    final badAnonymization = _projection();
    ((badAnonymization['participants'] as List).first
        as Map<String, dynamic>)['is_anonymized'] = true;
    final currentAnonymized = _projection();
    final originalParticipants = currentAnonymized['participants'] as List;
    final anonymizedParticipant = Map<String, dynamic>.from(
      originalParticipants.first as Map,
    )
      ..['profile_id'] = null
      ..['username'] = null
      ..['display_name'] = null
      ..['is_anonymized'] = true
      ..['is_current'] = true;
    currentAnonymized['participants'] = <Object?>[
      anonymizedParticipant,
      ...originalParticipants.skip(1),
    ];
    final falseReadOnly = _projection()..['writable'] = false;

    for (final malformed in [
      widened,
      badShare,
      badBalance,
      badAnonymization,
      currentAnonymized,
      falseReadOnly,
    ]) {
      response = malformed;
      await expectLater(
        repository.getSplit(_listId),
        throwsA(
          isA<ListSplitFailure>().having(
            (error) => error.code,
            'code',
            ListSplitFailureCode.generic,
          ),
        ),
      );
    }
  });

  test('maps reviewed SQLSTATEs without exposing server messages', () async {
    const mappings = {
      '22023': ListSplitFailureCode.invalid,
      'P0002': ListSplitFailureCode.unavailable,
      '42501': ListSplitFailureCode.unavailable,
      '40001': ListSplitFailureCode.stale,
      '55000': ListSplitFailureCode.archived,
      '54000': ListSplitFailureCode.capacity,
      'XX000': ListSplitFailureCode.generic,
    };
    for (final entry in mappings.entries) {
      failure = PostgrestException(
        message: 'private server detail',
        code: entry.key,
      );
      await expectLater(
        repository.getSplit(_listId),
        throwsA(
          isA<ListSplitFailure>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
      );
    }

    failure = StateError('offline');
    await expectLater(
      repository.getSplit(_listId),
      throwsA(
        isA<ListSplitFailure>().having(
          (error) => error.code,
          'code',
          ListSplitFailureCode.transport,
        ),
      ),
    );
  });
}

const _listId = '10000000-0000-4000-8000-000000000001';
const _ownerProfileId = '20000000-0000-4000-8000-000000000001';
const _memberProfileId = '20000000-0000-4000-8000-000000000002';
const _ownerParticipantId = '30000000-0000-4000-8000-000000000001';
const _memberParticipantId = '30000000-0000-4000-8000-000000000002';
const _expenseId = '40000000-0000-4000-8000-000000000001';
const _requestId = '50000000-0000-4000-8000-000000000001';

Map<String, dynamic> _projection() => {
      'list_id': _listId,
      'list_title': 'Weekend shop',
      'list_status': 'active',
      'list_version': 3,
      'is_owner': true,
      'enabled': true,
      'writable': true,
      'settings': {
        'currency_code': 'CHF',
        'version': 4,
        'created_at': '2026-07-22T08:00:00.000Z',
        'updated_at': '2026-07-22T09:00:00.000Z',
      },
      'participants': [
        {
          'id': _ownerParticipantId,
          'profile_id': _ownerProfileId,
          'username': 'fernando',
          'display_name': 'Fernando',
          'is_anonymized': false,
          'is_current': true,
          'paid_minor': 1001,
          'owed_minor': 501,
          'balance_minor': 500,
        },
        {
          'id': _memberParticipantId,
          'profile_id': _memberProfileId,
          'username': 'susana',
          'display_name': 'Susana',
          'is_anonymized': false,
          'is_current': true,
          'paid_minor': 0,
          'owed_minor': 500,
          'balance_minor': -500,
        },
      ],
      'expenses': [
        {
          'id': _expenseId,
          'description': 'Coffee',
          'amount_minor': 1001,
          'payer_participant_id': _ownerParticipantId,
          'creator_participant_id': _ownerParticipantId,
          'last_editor_participant_id': _memberParticipantId,
          'version': 2,
          'created_at': '2026-07-22T08:30:00.000Z',
          'updated_at': '2026-07-22T09:00:00.000Z',
          'beneficiary_participant_ids': [
            _ownerParticipantId,
            _memberParticipantId,
          ],
          'shares': [
            {
              'participant_id': _ownerParticipantId,
              'amount_minor': 501,
            },
            {
              'participant_id': _memberParticipantId,
              'amount_minor': 500,
            },
          ],
        },
      ],
    };

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;

  @override
  bool operator ==(Object other) =>
      other is _RpcCall &&
      other.functionName == functionName &&
      _deepEquals(other.params, params);

  @override
  int get hashCode => Object.hash(functionName, params);
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (key) => right.containsKey(key) && _deepEquals(left[key], right[key]),
        );
  }
  if (left is List && right is List) {
    return left.length == right.length &&
        List.generate(
          left.length,
          (index) => _deepEquals(left[index], right[index]),
        ).every((equal) => equal);
  }
  return left == right;
}
