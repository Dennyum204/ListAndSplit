import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/data/supabase_friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabaseFriendshipRepository repository;

  setUp(() {
    calls = [];
    response = null;
    failure = null;
    repository = SupabaseFriendshipRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('maps an exact one-target relationship summary', () async {
    response = [
      _summaryRow(
        status: 'friends',
        version: 4,
        stateChangedAt: '2026-07-18T18:05:02.123Z',
      ),
    ];

    final result = await repository.getRelationshipSummary('profile-2');

    expect(result.id, 'profile-2');
    expect(result.username, 'beta_user');
    expect(result.displayName, 'Beta User');
    expect(result.status, FriendshipStatus.friends);
    expect(result.version, 4);
    expect(
      result.stateChangedAt,
      DateTime.utc(2026, 7, 18, 18, 5, 2, 123),
    );
    expect(calls.single.functionName, 'get_relationship_summary');
    expect(calls.single.params, {'target_profile_id': 'profile-2'});
  });

  test('maps every documented caller-relative status', () async {
    const cases = {
      'can-send': FriendshipStatus.canSend,
      'incoming-pending': FriendshipStatus.incomingPending,
      'outgoing-pending': FriendshipStatus.outgoingPending,
      'friends': FriendshipStatus.friends,
      'unavailable': FriendshipStatus.unavailable,
    };

    for (final entry in cases.entries) {
      response = [
        _summaryRow(
          status: entry.key,
          version: entry.value == FriendshipStatus.unavailable ? null : 1,
          stateChangedAt: null,
        ),
      ];

      final result = await repository.getRelationshipSummary('profile-2');

      expect(result.status, entry.value);
      expect(
        result.version,
        entry.value == FriendshipStatus.unavailable ? isNull : 1,
      );
      expect(result.stateChangedAt, isNull);
    }
  });

  test('maps an empty relationship summary to unavailable', () async {
    response = <Object?>[];

    await expectLater(
      repository.getRelationshipSummary('profile-2'),
      throwsA(
        isA<FriendshipFailure>().having(
          (error) => error.code,
          'code',
          FriendshipFailureCode.unavailable,
        ),
      ),
    );
  });

  test('maps the active relationship list without exposing extra fields',
      () async {
    response = [
      _summaryRow(
        status: 'incoming-pending',
        version: 2,
        stateChangedAt: '2026-07-18T18:05:02Z',
      ),
      {
        ..._summaryRow(
          status: 'outgoing-pending',
          version: 7,
          stateChangedAt: '2026-07-18T17:05:02Z',
        ),
        'profile_id': 'profile-3',
        'username': 'gamma_user',
        'display_name': 'Gamma User',
      },
    ];

    final result = await repository.listActiveRelationships();

    expect(result, hasLength(2));
    expect(result[0].status, FriendshipStatus.incomingPending);
    expect(result[0].version, 2);
    expect(result[1].id, 'profile-3');
    expect(result[1].status, FriendshipStatus.outgoingPending);
    expect(result[1].version, 7);
    expect(calls.single.functionName, 'list_active_relationships');
    expect(calls.single.params, isNull);
  });

  test('rejects inactive or unordered rows from the active list', () async {
    for (final invalidRow in [
      _summaryRow(status: 'can-send', version: null, stateChangedAt: null),
      _summaryRow(
        status: 'friends',
        version: 2,
        stateChangedAt: null,
      ),
    ]) {
      response = [invalidRow];
      await expectLater(
        repository.listActiveRelationships(),
        throwsA(
          isA<FriendshipFailure>().having(
            (error) => error.code,
            'code',
            FriendshipFailureCode.generic,
          ),
        ),
      );
    }
  });

  test('uses the exact reviewed send parameters including a null version',
      () async {
    await repository.sendFriendRequest(
      'profile-2',
      expectedVersion: null,
    );
    await repository.sendFriendRequest(
      'profile-3',
      expectedVersion: 8,
    );

    expect(calls[0].functionName, 'send_friend_request');
    expect(calls[0].params, {
      'target_profile_id': 'profile-2',
      'expected_relationship_version': null,
    });
    expect(calls[1].functionName, 'send_friend_request');
    expect(calls[1].params, {
      'target_profile_id': 'profile-3',
      'expected_relationship_version': 8,
    });
  });

  test('uses exact reviewed versioned mutation names and parameters', () async {
    await repository.cancelFriendRequest('profile-2', expectedVersion: 2);
    await repository.acceptFriendRequest('profile-2', expectedVersion: 3);
    await repository.declineFriendRequest('profile-2', expectedVersion: 4);
    await repository.endFriendship('profile-2', expectedVersion: 5);

    expect(
      calls.map((call) => call.functionName),
      [
        'cancel_friend_request',
        'accept_friend_request',
        'decline_friend_request',
        'end_friendship',
      ],
    );
    expect(calls.map((call) => call.params), [
      {
        'target_profile_id': 'profile-2',
        'expected_relationship_version': 2,
      },
      {
        'target_profile_id': 'profile-2',
        'expected_relationship_version': 3,
      },
      {
        'target_profile_id': 'profile-2',
        'expected_relationship_version': 4,
      },
      {
        'target_profile_id': 'profile-2',
        'expected_relationship_version': 5,
      },
    ]);
  });

  test('rejects multiple, malformed, and undocumented result rows', () async {
    final malformedResponses = <Object?>[
      [
        _summaryRow(status: 'friends', version: 1, stateChangedAt: null),
        _summaryRow(status: 'friends', version: 1, stateChangedAt: null),
      ],
      {'profile_id': 'not-a-list'},
      [null],
      [
        _summaryRow(status: 'declined', version: 1, stateChangedAt: null),
      ],
      [
        _summaryRow(status: 'friends', version: 0, stateChangedAt: null),
      ],
      [
        _summaryRow(status: 'friends', version: null, stateChangedAt: null),
      ],
      [
        _summaryRow(status: 'unavailable', version: 9, stateChangedAt: null),
      ],
      [
        _summaryRow(
          status: 'unavailable',
          version: null,
          stateChangedAt: '2026-07-18T18:05:02Z',
        ),
      ],
      [
        _summaryRow(
          status: 'friends',
          version: 1,
          stateChangedAt: 'not-a-timestamp',
        ),
      ],
    ];

    for (final malformedResponse in malformedResponses) {
      response = malformedResponse;
      await expectLater(
        repository.getRelationshipSummary('profile-2'),
        throwsA(
          isA<FriendshipFailure>().having(
            (error) => error.code,
            'code',
            FriendshipFailureCode.generic,
          ),
        ),
      );
    }
  });

  test('keeps summary backend failures distinct from unavailable', () async {
    failure = const PostgrestException(
      message: 'sensitive backend state',
      code: '57014',
      details: 'private details',
      hint: 'private hint',
    );

    await expectLater(
      repository.getRelationshipSummary('profile-2'),
      throwsA(
        isA<FriendshipFailure>().having(
          (error) => error.code,
          'code',
          FriendshipFailureCode.generic,
        ),
      ),
    );
  });

  test('maps only SQLSTATE 40001 to the stable stale failure', () async {
    failure = const PostgrestException(
      message: 'sensitive backend state',
      code: '40001',
      details: 'private details',
      hint: 'private hint',
    );

    await expectLater(
      repository.acceptFriendRequest('profile-2', expectedVersion: 3),
      throwsA(
        isA<FriendshipFailure>().having(
          (error) => error.code,
          'code',
          FriendshipFailureCode.stale,
        ),
      ),
    );
  });

  test('maps SQLSTATE 22023 to unavailable without matching error text',
      () async {
    failure = const PostgrestException(
      message: 'arbitrary private backend text',
      code: '22023',
      details: 'private details',
      hint: 'private hint',
    );

    await expectLater(
      repository.declineFriendRequest('profile-2', expectedVersion: 3),
      throwsA(
        isA<FriendshipFailure>().having(
          (error) => error.code,
          'code',
          FriendshipFailureCode.unavailable,
        ),
      ),
    );
  });

  test('maps arbitrary backend and transport errors to generic', () async {
    for (final backendFailure in <Object>[
      const PostgrestException(
        message: 'sensitive backend state',
        code: '57014',
        details: 'private details',
        hint: 'private hint',
      ),
      StateError('sensitive backend state'),
    ]) {
      failure = backendFailure;

      await expectLater(
        repository.declineFriendRequest('profile-2', expectedVersion: 3),
        throwsA(
          isA<FriendshipFailure>().having(
            (error) => error.code,
            'code',
            FriendshipFailureCode.generic,
          ),
        ),
      );
    }
  });
}

Map<String, Object?> _summaryRow({
  required String status,
  required int? version,
  required String? stateChangedAt,
}) =>
    {
      'profile_id': 'profile-2',
      'username': 'beta_user',
      'display_name': 'Beta User',
      'relationship_status': status,
      'version': version,
      'state_changed_at': stateChangedAt,
    };

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
