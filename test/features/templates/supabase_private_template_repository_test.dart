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
    responses['list_private_templates_v3'] = [_summaryRow()];

    final result = await repository.listTemplates(
      search: 'coffee',
      categoryId: _categoryId,
      sort: PrivateTemplateSort.alphabetic,
    );

    expect(calls.single.functionName, 'list_private_templates_v3');
    expect(calls.single.params, {
      'search_query': 'coffee',
      'category_filter': _categoryId,
      'uncategorized_only': false,
      'sort_mode': 'alpha',
    });
    expect(result.single.name, 'Weekly shop');
    expect(result.single.itemCount, 2);
    expect(result.single.isPublic, isTrue);
    expect(result.single.isModerated, isFalse);
    expect(result.single.publishedAt, DateTime.utc(2026, 7, 25, 19, 33, 6));
  });

  test('loads strict detail and authoritative remaining capacity', () async {
    responses['get_private_template_v3'] = [
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
      'get_private_template_v3',
      'list_private_template_items',
    ]);
  });

  test('sets publication with the exact desired-state version contract',
      () async {
    responses['set_template_publication'] = [
      {
        'template_id': _templateId,
        'version': 5,
        'is_public': false,
        'published_at': null,
        'updated_at': '2026-07-25T20:00:00.000Z',
      },
    ];

    final result = await repository.setPublication(
      _templateId,
      isPublic: false,
      expectedVersion: 4,
    );

    expect(calls.single.functionName, 'set_template_publication');
    expect(calls.single.params, {
      'target_template_id': _templateId,
      'desired_public': false,
      'expected_template_version': 4,
    });
    expect(result.version, 5);
    expect(result.isPublic, isFalse);
    expect(result.publishedAt, isNull);
  });

  test('rejects publication fields that do not match the strict v3 shape',
      () async {
    responses['list_private_templates_v3'] = [
      _summaryRow()..['private_owner_id'] = _categoryId,
    ];

    await expectLater(
      repository.listTemplates(),
      throwsA(
        isA<PrivateTemplateFailure>().having(
          (failure) => failure.code,
          'code',
          PrivateTemplateFailureCode.transport,
        ),
      ),
    );
  });

  test('maps moderated private source and rejects inconsistent publication',
      () async {
    responses['list_private_templates_v3'] = [
      _summaryRow()
        ..['is_public'] = false
        ..['published_at'] = null
        ..['is_moderated'] = true,
    ];

    final result = await repository.listTemplates();

    expect(result.single.isModerated, isTrue);
    expect(result.single.isPublic, isFalse);

    responses['list_private_templates_v3'] = [
      _summaryRow()..['is_moderated'] = true,
    ];
    await expectLater(
      repository.listTemplates(),
      throwsA(isA<PrivateTemplateFailure>()),
    );
  });

  test('maps publish restriction without exposing backend details', () async {
    failure = const PostgrestException(
      message: 'private moderation details',
      code: '42501',
    );

    await expectLater(
      repository.setPublication(
        _templateId,
        isPublic: true,
        expectedVersion: 4,
      ),
      throwsA(
        isA<PrivateTemplateFailure>()
            .having(
              (value) => value.code,
              'code',
              PrivateTemplateFailureCode.moderated,
            )
            .having(
              (value) => value.toString(),
              'message',
              isNot(contains('private moderation details')),
            ),
      ),
    );
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
      'is_public': true,
      'published_at': '2026-07-25T19:33:06.000Z',
      'is_moderated': false,
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
