import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/data/supabase_active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabaseActiveListRepository repository;

  setUp(() {
    calls = [];
    response = [_summaryRow()];
    failure = null;
    repository = SupabaseActiveListRepository(
      SupabaseClient('http://localhost:54321', 'test-publishable-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('lists with bounded keyset parameters and strict counts', () async {
    response = [
      _summaryRow(
        status: 'archived',
        archivedAt: '2026-07-20T10:00:00.000Z',
      ),
    ];
    final page = await repository.listLists(
      status: ActiveListStatus.archived,
      limit: 20,
      before: ActiveListCursor(
        sortAt: DateTime.utc(2026, 7, 20, 11),
        id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      ),
    );

    expect(calls.single.functionName, 'list_active_lists');
    expect(calls.single.params, {
      'requested_status': 'archived',
      'page_size': 20,
      'before_sort_at': '2026-07-20T11:00:00.000Z',
      'before_list_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    });
    expect(page.lists.single.status, ActiveListStatus.archived);
    expect(page.lists.single.itemCount, 2);
    expect(page.lists.single.completedItemCount, 1);
    expect(page.hasMore, isFalse);
  });

  test('maps owned and shared list projections without widening privacy',
      () async {
    response = [
      _summaryRow()
        ..addAll({
          'is_owner': false,
          'owner_profile_id': '99999999-9999-4999-8999-999999999999',
          'owner_username': 'owner_user',
          'owner_display_name': 'Owner User',
          'caller_access_version': 7,
        }),
    ];

    final shared = (await repository.listLists(
      status: ActiveListStatus.active,
      limit: 20,
    ))
        .lists
        .single;

    expect(shared.isOwner, isFalse);
    expect(shared.ownerUsername, 'owner_user');
    expect(shared.ownerDisplayName, 'Owner User');
    expect(shared.callerAccessVersion, 7);

    response = [_summaryRow()];
    final owned = await repository.getList(
      '11111111-1111-4111-8111-111111111111',
    );
    expect(owned.isOwner, isTrue);
    expect(owned.ownerProfileId, isNull);
    expect(owned.callerAccessVersion, isNull);
  });

  test('maps participant, invitation, pending, and eligible projections',
      () async {
    const listId = '11111111-1111-4111-8111-111111111111';
    response = [
      {
        'profile_id': '99999999-9999-4999-8999-999999999999',
        'username': 'owner_user',
        'display_name': 'Owner User',
        'is_owner': true,
        'access_version': null,
      },
      {
        'profile_id': '88888888-8888-4888-8888-888888888888',
        'username': 'member_user',
        'display_name': 'Member User',
        'is_owner': false,
        'access_version': 4,
      },
    ];
    final participants = await repository.listParticipants(listId);
    expect(participants, hasLength(2));
    expect(participants.first.isOwner, isTrue);
    expect(participants.last.accessVersion, 4);

    response = [
      {
        'profile_id': '77777777-7777-4777-8777-777777777777',
        'username': 'pending_user',
        'display_name': 'Pending User',
        'access_version': 3,
        'created_at': '2026-07-20T08:00:00.000Z',
        'state_changed_at': '2026-07-20T09:00:00.000Z',
      },
    ];
    final pending = await repository.listPendingInvitations(listId);
    expect(pending.single.accessVersion, 3);

    response = [
      {
        'profile_id': '66666666-6666-4666-8666-666666666666',
        'username': 'eligible_user',
        'display_name': 'Eligible User',
        'current_access_version': 5,
        'created_at': null,
        'state_changed_at': null,
      },
    ];
    final eligible = await repository.listEligibleInvitees(listId);
    expect(eligible.single.accessVersion, 5);
    expect(eligible.single.createdAt, isNull);

    response = [
      {
        'list_id': listId,
        'list_title': 'Shared trip',
        'list_status': 'active',
        'owner_profile_id': '99999999-9999-4999-8999-999999999999',
        'owner_username': 'owner_user',
        'owner_display_name': 'Owner User',
        'access_version': 6,
        'created_at': '2026-07-20T08:00:00.000Z',
        'state_changed_at': '2026-07-20T09:00:00.000Z',
      },
    ];
    final invitation = await repository.getInvitation(listId);
    expect(invitation.owner.isOwner, isTrue);
    expect(invitation.accessVersion, 6);
    expect(
      calls.map((call) => call.functionName),
      [
        'list_active_list_participants',
        'list_pending_active_list_invitations',
        'list_eligible_active_list_invitees',
        'get_active_list_invitation',
      ],
    );
  });

  test('creation uses a secure-shaped request id without treating it as owner',
      () async {
    final created = await repository.createList(
      'Groceries',
      requestId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );

    expect(created.title, 'Groceries');
    expect(calls.single.functionName, 'create_active_list');
    expect(calls.single.params, {
      'new_title': 'Groceries',
      'creation_request_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    });
    expect(calls.single.params, isNot(contains('owner_id')));
  });

  test('item creation sends exact integer quantity and stable unit code',
      () async {
    response = [_itemRow()];

    final item = await repository.createItem(
      '11111111-1111-4111-8111-111111111111',
      'Coffee',
      expectedListVersion: 4,
      quantity: ListQuantity.fromThousandths(1500),
      unit: ListUnit.pack,
      requestId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );

    expect(item.quantity.thousandths, 1500);
    expect(item.unit, ListUnit.pack);
    expect(calls.single.functionName, 'create_active_list_item');
    expect(calls.single.params, {
      'target_list_id': '11111111-1111-4111-8111-111111111111',
      'new_name': 'Coffee',
      'creation_request_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'expected_list_version': 4,
      'new_quantity_thousandths': 1500,
      'new_unit_code': 'pack',
    });
  });

  test('all mutation RPCs carry exact expected versions', () async {
    const listId = '11111111-1111-4111-8111-111111111111';
    const itemId = '22222222-2222-4222-8222-222222222222';

    await repository.renameList(listId, 'Renamed', expectedVersion: 2);
    await repository.setArchived(listId, archived: true, expectedVersion: 3);
    await repository.deleteList(listId, expectedVersion: 4);
    response = [_itemRow()];
    await repository.updateItem(
      listId,
      itemId,
      'Tea',
      quantity: ListQuantity.one,
      unit: null,
      expectedListVersion: 5,
      expectedItemVersion: 2,
    );
    await repository.setItemCompleted(
      listId,
      itemId,
      completed: true,
      expectedListVersion: 6,
      expectedItemVersion: 3,
    );
    response = 8;
    await repository.deleteItem(
      listId,
      itemId,
      expectedListVersion: 7,
      expectedItemVersion: 4,
    );
    await repository.reorderItems(
      listId,
      [itemId],
      expectedListVersion: 8,
    );

    expect(
      calls.map((call) => call.functionName),
      [
        'rename_active_list',
        'set_active_list_archived',
        'delete_active_list',
        'update_active_list_item',
        'set_active_list_item_completed',
        'delete_active_list_item',
        'reorder_active_list_items',
      ],
    );
    expect(calls[0].params?['expected_list_version'], 2);
    expect(calls[3].params?['expected_item_version'], 2);
    expect(calls[4].params?['should_complete'], isTrue);
    expect(calls[5].params?['expected_item_version'], 4);
    expect(calls[6].params?['ordered_item_ids'], [itemId]);
  });

  test('membership RPCs carry only target IDs and exact access versions',
      () async {
    const listId = '11111111-1111-4111-8111-111111111111';
    const profileId = '99999999-9999-4999-8999-999999999999';
    response = [
      {'access_version': 2},
    ];
    expect(await repository.inviteMember(listId, profileId), 2);
    response = 3;
    expect(
      await repository.cancelInvitation(
        listId,
        profileId,
        expectedAccessVersion: 2,
      ),
      3,
    );
    response = 4;
    expect(
      await repository.acceptInvitation(listId, expectedAccessVersion: 3),
      4,
    );
    response = 5;
    expect(
      await repository.declineInvitation(listId, expectedAccessVersion: 4),
      5,
    );
    response = 6;
    expect(
      await repository.removeMember(
        listId,
        profileId,
        expectedAccessVersion: 5,
      ),
      6,
    );
    response = 7;
    expect(await repository.leaveList(listId, expectedAccessVersion: 6), 7);

    expect(calls.map((call) => call.functionName), [
      'invite_active_list_member',
      'cancel_active_list_invitation',
      'accept_active_list_invitation',
      'decline_active_list_invitation',
      'remove_active_list_member',
      'leave_active_list',
    ]);
    expect(calls[0].params, {
      'target_list_id': listId,
      'target_profile_id': profileId,
      'expected_access_version': null,
    });
    expect(calls[1].params?['expected_access_version'], 2);
    expect(calls[2].params, {
      'target_list_id': listId,
      'expected_access_version': 3,
    });
    expect(calls[4].params?['target_profile_id'], profileId);
    expect(calls[5].params?['expected_access_version'], 6);
    expect(
      calls.every((call) => call.params?.containsKey('owner_id') != true),
      isTrue,
    );
  });

  test('ownership transfer sends exact locks and maps its allowlisted result',
      () async {
    const listId = '11111111-1111-4111-8111-111111111111';
    const previousOwnerId = '88888888-8888-4888-8888-888888888888';
    const targetId = '99999999-9999-4999-8999-999999999999';
    response = [
      {
        'list_id': listId,
        'previous_owner_profile_id': previousOwnerId,
        'owner_profile_id': targetId,
        'list_version': 8,
        'previous_owner_access_version': 1,
        'owner_access_version': 5,
        'transferred_at': '2026-07-21T09:30:00.000Z',
      },
    ];

    final result = await repository.transferOwnership(
      listId,
      targetId,
      expectedListVersion: 7,
      expectedAccessVersion: 4,
    );

    expect(calls.single.functionName, 'transfer_active_list_ownership');
    expect(calls.single.params, {
      'target_list_id': listId,
      'target_profile_id': targetId,
      'expected_list_version': 7,
      'expected_target_access_version': 4,
    });
    expect(result.previousOwnerProfileId, previousOwnerId);
    expect(result.ownerProfileId, targetId);
    expect(result.listVersion, 8);
    expect(result.previousOwnerAccessVersion, 1);
    expect(result.ownerAccessVersion, 5);
    expect(result.transferredAt, DateTime.utc(2026, 7, 21, 9, 30));
  });

  test('ownership transfer rejects mismatched authoritative projections',
      () async {
    response = [
      {
        'list_id': '11111111-1111-4111-8111-111111111111',
        'previous_owner_profile_id': '88888888-8888-4888-8888-888888888888',
        'owner_profile_id': '77777777-7777-4777-8777-777777777777',
        'list_version': 8,
        'previous_owner_access_version': 1,
        'owner_access_version': 5,
        'transferred_at': '2026-07-21T09:30:00.000Z',
      },
    ];

    await expectLater(
      repository.transferOwnership(
        '11111111-1111-4111-8111-111111111111',
        '99999999-9999-4999-8999-999999999999',
        expectedListVersion: 7,
        expectedAccessVersion: 4,
      ),
      throwsA(
        isA<ActiveListFailure>().having(
          (failure) => failure.code,
          'code',
          ActiveListFailureCode.transport,
        ),
      ),
    );
  });

  test('maps stable SQLSTATE classifications without backend details',
      () async {
    const cases = {
      '22023': ActiveListFailureCode.invalid,
      'P0002': ActiveListFailureCode.unavailable,
      '40001': ActiveListFailureCode.stale,
      '23505': ActiveListFailureCode.retryConflict,
      '55000': ActiveListFailureCode.archived,
      '54000': ActiveListFailureCode.capacity,
      'XX000': ActiveListFailureCode.generic,
    };
    for (final entry in cases.entries) {
      failure = PostgrestException(
        message: 'private backend payload',
        code: entry.key,
      );
      await expectLater(
        repository.getList('11111111-1111-4111-8111-111111111111'),
        throwsA(
          isA<ActiveListFailure>()
              .having((value) => value.code, 'code', entry.value)
              .having((value) => value.toString(), 'message',
                  isNot(contains('private backend'))),
        ),
      );
    }
  });

  test('maps non-PostgREST request failures to transport reconciliation',
      () async {
    failure = StateError('private network detail');

    await expectLater(
      repository.renameList(
        '11111111-1111-4111-8111-111111111111',
        'Renamed',
        expectedVersion: 1,
      ),
      throwsA(
        isA<ActiveListFailure>()
            .having(
              (value) => value.code,
              'code',
              ActiveListFailureCode.transport,
            )
            .having(
              (value) => value.toString(),
              'message',
              isNot(contains('private network detail')),
            ),
      ),
    );
  });

  test('rejects malformed, expanded, or inconsistent projections', () async {
    response = [
      _summaryRow()..['completed_item_count'] = 3,
    ];
    await expectLater(
      repository.listLists(status: ActiveListStatus.active, limit: 20),
      throwsA(isA<ActiveListFailure>()),
    );

    response = [
      _itemRow()..['quantity_thousandths'] = 1.5,
    ];
    await expectLater(
      repository.listItems('11111111-1111-4111-8111-111111111111'),
      throwsA(isA<ActiveListFailure>()),
    );

    response = [
      _summaryRow()
        ..addAll({
          'is_owner': false,
          'owner_profile_id': '99999999-9999-4999-8999-999999999999',
          'owner_username': 'owner_user',
          'owner_display_name': 'Owner User',
          'caller_access_version': null,
        }),
    ];
    await expectLater(
      repository.getList('11111111-1111-4111-8111-111111111111'),
      throwsA(isA<ActiveListFailure>()),
    );

    response = [
      {
        'profile_id': '99999999-9999-4999-8999-999999999999',
        'username': 'owner_user',
        'display_name': 'Owner User',
        'is_owner': true,
        'access_version': 2,
      },
    ];
    await expectLater(
      repository.listParticipants(
        '11111111-1111-4111-8111-111111111111',
      ),
      throwsA(isA<ActiveListFailure>()),
    );
  });
}

Map<String, dynamic> _summaryRow({
  String status = 'active',
  String? archivedAt,
}) =>
    {
      'list_id': '11111111-1111-4111-8111-111111111111',
      'title': 'Groceries',
      'status': status,
      'version': 1,
      'item_count': 2,
      'completed_item_count': 1,
      'created_at': '2026-07-20T08:00:00.000Z',
      'updated_at': '2026-07-20T09:00:00.000Z',
      'archived_at': archivedAt,
    };

Map<String, dynamic> _itemRow() => {
      'item_id': '22222222-2222-4222-8222-222222222222',
      'name': 'Coffee',
      'quantity_thousandths': 1500,
      'unit_code': 'pack',
      'position': 1,
      'version': 1,
      'completed_at': null,
      'completed_by': null,
      'created_at': '2026-07-20T08:00:00.000Z',
      'updated_at': '2026-07-20T09:00:00.000Z',
    };

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
