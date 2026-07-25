import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/templates/data/supabase_public_template_repository.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabasePublicTemplateRepository repository;

  setUp(() {
    calls = [];
    response = _profilePage();
    failure = null;
    repository = SupabasePublicTemplateRepository(
      SupabaseClient('http://localhost:54321', 'test-publishable-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('parses the exact public profile allowlist and first keyset page',
      () async {
    final page = await repository.listProfileTemplates(_profileId);

    expect(calls.single.functionName, 'list_public_profile_templates');
    expect(calls.single.params, {
      'target_profile_id': _profileId,
      'requested_page_size': 20,
      'cursor_published_at': null,
      'cursor_template_id': null,
    });
    expect(page.profile.username, 'public_owner');
    expect(page.templates.single.id, _templateId);
    expect(page.templates.single.itemCount, 2);
    expect(page.nextCursor?.templateId, _templateId);
  });

  test('sends both cursor components and a bounded requested page size',
      () async {
    response = _profilePage(nextCursor: false, templates: const []);
    final cursor = PublicTemplateCursor(
      publishedAt: DateTime.utc(2026, 7, 25, 19, 33, 6),
      templateId: _templateId,
    );

    await repository.listProfileTemplates(
      _profileId,
      pageSize: 7,
      cursor: cursor,
    );

    expect(calls.single.params, {
      'target_profile_id': _profileId,
      'requested_page_size': 7,
      'cursor_published_at': '2026-07-25T19:33:06.000Z',
      'cursor_template_id': _templateId,
    });
  });

  test('parses read-only detail without source item identities', () async {
    response = _detail();

    final detail = await repository.getTemplate(_profileId, _templateId);

    expect(calls.single.functionName, 'get_public_template');
    expect(calls.single.params, {
      'target_profile_id': _profileId,
      'target_template_id': _templateId,
    });
    expect(detail.profile.displayName, 'Public Owner');
    expect(detail.items.map((item) => item.name), ['Water', 'Water']);
    expect(
      detail.items.map((item) => item.quantity.thousandths),
      [1500, 2000],
    );
  });

  test('parses a private Uncategorized independent copy', () async {
    response = [
      {
        'template_id': _copiedTemplateId,
        'category_id': null,
        'category_name': null,
        'name': 'Public kit',
        'version': 1,
        'item_count': 2,
        'is_public': false,
        'published_at': null,
        'created_at': '2026-07-25T20:00:00.000Z',
        'updated_at': '2026-07-25T20:00:00.000Z',
      },
    ];

    final result = await repository.copyTemplate(
      _templateId,
      expectedVersion: 4,
      requestId: _requestId,
    );

    expect(calls.single.functionName, 'copy_public_template');
    expect(calls.single.params, {
      'source_template_id': _templateId,
      'expected_source_version': 4,
      'request_id': _requestId,
    });
    expect(result.template.id, _copiedTemplateId);
    expect(result.template.isPublic, isFalse);
    expect(result.template.categoryId, isNull);
  });

  test('maps unavailable nulls without distinguishing the hidden cause',
      () async {
    response = null;

    await expectLater(
      repository.getTemplate(_profileId, _templateId),
      throwsA(
        isA<PublicTemplateFailure>().having(
          (value) => value.code,
          'code',
          PublicTemplateFailureCode.unavailable,
        ),
      ),
    );
  });

  test('rejects profile, template, item and copy privacy expansions', () async {
    final leakedProfile = _profilePage();
    (leakedProfile['profile']! as Map<String, dynamic>)['email'] =
        'private@example.test';
    response = leakedProfile;
    await _expectFailure(repository, PublicTemplateFailureCode.generic);

    final leakedTemplate = _profilePage();
    ((leakedTemplate['templates']! as List).single
        as Map<String, dynamic>)['category_id'] = _profileId;
    response = leakedTemplate;
    await _expectFailure(repository, PublicTemplateFailureCode.generic);

    final leakedItem = _detail();
    (((leakedItem['template']! as Map<String, dynamic>)['items']! as List)[0]
        as Map<String, dynamic>)['item_id'] = _requestId;
    response = leakedItem;
    await expectLater(
      repository.getTemplate(_profileId, _templateId),
      throwsA(
        isA<PublicTemplateFailure>().having(
          (value) => value.code,
          'code',
          PublicTemplateFailureCode.generic,
        ),
      ),
    );

    response = [
      {
        'template_id': _copiedTemplateId,
        'category_id': null,
        'category_name': null,
        'name': 'Public kit',
        'version': 1,
        'item_count': 2,
        'is_public': false,
        'published_at': null,
        'created_at': '2026-07-25T20:00:00.000Z',
        'updated_at': '2026-07-25T20:00:00.000Z',
        'source_template_id': _templateId,
      },
    ];
    await expectLater(
      repository.copyTemplate(
        _templateId,
        expectedVersion: 4,
        requestId: _requestId,
      ),
      throwsA(isA<PublicTemplateFailure>()),
    );

    response = [
      {
        'template_id': _copiedTemplateId,
        'category_id': null,
        'category_name': null,
        'name': 'Public kit',
        'version': 1,
        'item_count': 201,
        'is_public': false,
        'published_at': null,
        'created_at': '2026-07-25T20:00:00.000Z',
        'updated_at': '2026-07-25T20:00:00.000Z',
      },
    ];
    await expectLater(
      repository.copyTemplate(
        _templateId,
        expectedVersion: 4,
        requestId: _requestId,
      ),
      throwsA(
        isA<PublicTemplateFailure>().having(
          (value) => value.code,
          'code',
          PublicTemplateFailureCode.generic,
        ),
      ),
    );
  });

  test('rejects unstable page and item ordering', () async {
    final page = _profilePage();
    final first =
        Map<String, dynamic>.from((page['templates']! as List).single as Map);
    final second = Map<String, dynamic>.from(first)
      ..['template_id'] = _copiedTemplateId
      ..['published_at'] = '2026-07-25T20:00:00.000Z';
    page['templates'] = [first, second];
    page['next_cursor'] = null;
    response = page;
    await _expectFailure(repository, PublicTemplateFailureCode.generic);

    final older = Map<String, dynamic>.from(first)
      ..['template_id'] = _copiedTemplateId
      ..['published_at'] = '2026-07-25T19:32:00.000Z';
    response = _profilePage(
      nextCursor: false,
      templates: [first, older],
    );
    await expectLater(
      repository.listProfileTemplates(_profileId, pageSize: 1),
      throwsA(
        isA<PublicTemplateFailure>().having(
          (value) => value.code,
          'code',
          PublicTemplateFailureCode.generic,
        ),
      ),
    );

    final detail = _detail();
    (((detail['template']! as Map<String, dynamic>)['items']! as List)[1]
        as Map<String, dynamic>)['position'] = 1;
    response = detail;
    await expectLater(
      repository.getTemplate(_profileId, _templateId),
      throwsA(isA<PublicTemplateFailure>()),
    );
  });

  test('maps SQLSTATEs while suppressing backend details', () async {
    for (final entry in const {
      'P0002': PublicTemplateFailureCode.unavailable,
      '40001': PublicTemplateFailureCode.stale,
      '23505': PublicTemplateFailureCode.retryConflict,
      '54000': PublicTemplateFailureCode.capacity,
    }.entries) {
      failure = PostgrestException(
        message: 'private database detail',
        code: entry.key,
      );
      await expectLater(
        repository.listProfileTemplates(_profileId),
        throwsA(
          isA<PublicTemplateFailure>()
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

Future<void> _expectFailure(
  SupabasePublicTemplateRepository repository,
  PublicTemplateFailureCode code,
) {
  return expectLater(
    repository.listProfileTemplates(_profileId),
    throwsA(
      isA<PublicTemplateFailure>().having(
        (value) => value.code,
        'code',
        code,
      ),
    ),
  );
}

Map<String, dynamic> _profilePage({
  bool nextCursor = true,
  List<Map<String, dynamic>>? templates,
}) {
  final entries = templates ??
      [
        {
          'template_id': _templateId,
          'name': 'Public kit',
          'version': 4,
          'item_count': 2,
          'published_at': '2026-07-25T19:33:06.000Z',
        },
      ];
  return {
    'profile': {
      'profile_id': _profileId,
      'username': 'public_owner',
      'display_name': 'Public Owner',
    },
    'templates': entries,
    'next_cursor': nextCursor
        ? {
            'published_at': '2026-07-25T19:33:06.000Z',
            'template_id': _templateId,
          }
        : null,
  };
}

Map<String, dynamic> _detail() => {
      'profile': {
        'profile_id': _profileId,
        'username': 'public_owner',
        'display_name': 'Public Owner',
      },
      'template': {
        'template_id': _templateId,
        'name': 'Public kit',
        'version': 4,
        'item_count': 2,
        'published_at': '2026-07-25T19:33:06.000Z',
        'items': [
          {
            'name': 'Water',
            'quantity_thousandths': 1500,
            'position': 1,
          },
          {
            'name': 'Water',
            'quantity_thousandths': 2000,
            'position': 2,
          },
        ],
      },
    };

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}

const _profileId = '11111111-1111-4111-8111-111111111111';
const _templateId = '22222222-2222-4222-8222-222222222222';
const _copiedTemplateId = '33333333-3333-4333-8333-333333333333';
const _requestId = '44444444-4444-4444-8444-444444444444';
