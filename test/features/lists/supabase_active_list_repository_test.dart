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

  test('maps stable SQLSTATE classifications without backend details',
      () async {
    const cases = {
      '22023': ActiveListFailureCode.invalid,
      'P0002': ActiveListFailureCode.unavailable,
      '40001': ActiveListFailureCode.stale,
      '23505': ActiveListFailureCode.retryConflict,
      '55000': ActiveListFailureCode.archived,
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
