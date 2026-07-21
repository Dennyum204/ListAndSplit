import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/templates/data/supabase_private_template_repository.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Map<String, Object?> responses;
  late Object? failure;
  late SupabasePrivateTemplateRepository repository;

  setUp(() {
    calls = [];
    responses = {};
    failure = null;
    repository = SupabasePrivateTemplateRepository(
      SupabaseClient('http://localhost:54321', 'test-publishable-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return responses[functionName] ?? const [];
      },
    );
  });

  test('lists private templates with exact search, filter and sort arguments',
      () async {
    responses['list_private_templates'] = [_summaryRow()];

    final result = await repository.listTemplates(
      search: 'coffee',
      categoryId: _categoryId,
      sort: PrivateTemplateSort.alphabetic,
    );

    expect(calls.single.functionName, 'list_private_templates');
    expect(calls.single.params, {
      'search_query': 'coffee',
      'category_filter': _categoryId,
      'uncategorized_only': false,
      'sort_mode': 'alpha',
    });
    expect(result.single.name, 'Weekly shop');
    expect(result.single.itemCount, 2);
  });

  test('loads strict detail and authoritative remaining capacity', () async {
    responses['get_private_template'] = [
      _summaryRow()..['remaining_capacity'] = 198,
    ];
    responses['list_private_template_items'] = [
      _itemRow(_itemOneId, 'Coffee', 1),
      _itemRow(_itemTwoId, 'Milk', 2),
    ];

    final detail = await repository.getTemplate(_templateId);

    expect(detail.items.map((item) => item.name), ['Coffee', 'Milk']);
    expect(detail.remainingCapacity, 198);
    expect(calls.map((call) => call.functionName), [
      'get_private_template',
      'list_private_template_items',
    ]);
  });

  test('imports all selected rows with version and idempotency arrays intact',
      () async {
    responses['import_private_template_items'] = [
      {
        'list_version': 8,
        'imported_count': 2,
        'remaining_capacity': 0,
      },
    ];

    final result = await repository.importIntoList(
      _templateId,
      const [_itemOneId, _itemTwoId],
      _listId,
      itemRequestIds: const [_requestOneId, _requestTwoId],
      expectedTemplateVersion: 4,
      expectedListVersion: 7,
    );

    expect(calls.single.functionName, 'import_private_template_items');
    expect(calls.single.params, {
      'source_template_id': _templateId,
      'selected_item_ids': [_itemOneId, _itemTwoId],
      'target_list_id': _listId,
      'item_creation_request_ids': [_requestOneId, _requestTwoId],
      'expected_template_version': 4,
      'expected_list_version': 7,
    });
    expect(result.importedCount, 2);
    expect(result.remainingCapacity, 0);
  });

  test('maps capacity and stale SQLSTATEs without exposing backend messages',
      () async {
    for (final entry in const {
      '54000': PrivateTemplateFailureCode.capacity,
      '40001': PrivateTemplateFailureCode.stale,
    }.entries) {
      failure = PostgrestException(
        message: 'private database detail',
        code: entry.key,
      );
      await expectLater(
        repository.listCategories(),
        throwsA(
          isA<PrivateTemplateFailure>()
              .having((value) => value.code, 'code', entry.value)
              .having(
                (value) => value.toString(),
                'message',
                isNot(contains('private database detail')),
              ),
        ),
      );
    }
  });
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);
  final String functionName;
  final Map<String, dynamic>? params;
}

const _templateId = '11111111-1111-4111-8111-111111111111';
const _categoryId = '22222222-2222-4222-8222-222222222222';
const _itemOneId = '33333333-3333-4333-8333-333333333333';
const _itemTwoId = '44444444-4444-4444-8444-444444444444';
const _listId = '55555555-5555-4555-8555-555555555555';
const _requestOneId = '66666666-6666-4666-8666-666666666666';
const _requestTwoId = '77777777-7777-4777-8777-777777777777';

Map<String, dynamic> _summaryRow() => {
      'template_id': _templateId,
      'category_id': _categoryId,
      'category_name': 'Groceries',
      'name': 'Weekly shop',
      'version': 4,
      'item_count': 2,
      'created_at': '2026-07-21T08:00:00.000Z',
      'updated_at': '2026-07-21T09:00:00.000Z',
    };

Map<String, dynamic> _itemRow(String id, String name, int position) => {
      'item_id': id,
      'name': name,
      'quantity_thousandths': 1000,
      'position': position,
      'version': 1,
      'created_at': '2026-07-21T08:00:00.000Z',
      'updated_at': '2026-07-21T08:00:00.000Z',
    };
