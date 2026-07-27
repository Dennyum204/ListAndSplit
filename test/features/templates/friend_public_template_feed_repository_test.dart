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
    response = _feedPage();
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

  test('parses the strict feed page and sends no caller identity', () async {
    final page = await repository.listFriendFeed();

    expect(calls.single.functionName, 'list_friend_public_template_feed');
    expect(calls.single.params, {
      'requested_page_size': 20,
      'cursor_published_at': null,
      'cursor_template_id': null,
    });
    expect(calls.single.params, isNot(contains('profile_id')));
    expect(page.entries.single.profile.id, _profileId);
    expect(page.entries.single.template.id, _templateId);
    expect(page.entries.single.template.itemCount, 0);
    expect(page.nextCursor?.templateId, _templateId);
  });

  test('sends both exclusive cursor fields and requested size', () async {
    response = _feedPage(entries: const [], nextCursor: false);
    final cursor = PublicTemplateCursor(
      publishedAt: DateTime.utc(2026, 7, 27, 12),
      templateId: _templateId,
    );

    await repository.listFriendFeed(pageSize: 7, cursor: cursor);

    expect(calls.single.params, {
      'requested_page_size': 7,
      'cursor_published_at': '2026-07-27T12:00:00.000Z',
      'cursor_template_id': _templateId,
    });
  });

  test('rejects unknown and missing fields at every feed level', () async {
    final rootLeak = _feedPage()..['total_count'] = 1;
    response = rootLeak;
    await _expectGeneric(repository);

    final entryLeak = _feedPage();
    ((_entries(entryLeak).single)..['source'] = 'private');
    response = entryLeak;
    await _expectGeneric(repository);

    final profileLeak = _feedPage();
    (_profile(_entries(profileLeak).single))['email'] = 'hidden@example.test';
    response = profileLeak;
    await _expectGeneric(repository);

    final templateLeak = _feedPage();
    (_template(_entries(templateLeak).single))['category_id'] = _profileId;
    response = templateLeak;
    await _expectGeneric(repository);

    final missing = _feedPage()..remove('entries');
    response = missing;
    await _expectGeneric(repository);
  });

  test('rejects malformed UUID, timestamp, order and within-page duplicate',
      () async {
    final invalidUuid = _feedPage();
    (_profile(_entries(invalidUuid).single))['profile_id'] = 'not-a-uuid';
    response = invalidUuid;
    await _expectGeneric(repository);

    final invalidTime = _feedPage();
    (_template(_entries(invalidTime).single))['published_at'] =
        '2026-07-27 12:00';
    response = invalidTime;
    await _expectGeneric(repository);

    final first = _entry();
    final newer = _entry(
      templateId: _secondTemplateId,
      publishedAt: '2026-07-27T13:00:00.000Z',
    );
    response = _feedPage(entries: [first, newer], nextCursor: false);
    await _expectGeneric(repository);

    response = _feedPage(entries: [first, Map.of(first)], nextCursor: false);
    await _expectGeneric(repository);
  });

  test('rejects an oversized page and a cursor not matching its last row',
      () async {
    response = _feedPage(
      entries: [
        _entry(),
        _entry(
          templateId: _secondTemplateId,
          publishedAt: '2026-07-27T11:00:00.000Z',
        ),
      ],
      nextCursor: false,
    );
    await expectLater(
      repository.listFriendFeed(pageSize: 1),
      throwsA(
        isA<PublicTemplateFailure>().having(
          (value) => value.code,
          'code',
          PublicTemplateFailureCode.generic,
        ),
      ),
    );

    response = _feedPage()
      ..['next_cursor'] = {
        'published_at': '2026-07-27T11:00:00.000Z',
        'template_id': _secondTemplateId,
      };
    await _expectGeneric(repository);
  });

  test('maps authorization and transport errors without backend detail',
      () async {
    failure = const PostgrestException(
      message: 'private database detail',
      code: '42501',
    );
    await expectLater(
      repository.listFriendFeed(),
      throwsA(
        isA<PublicTemplateFailure>()
            .having(
              (value) => value.code,
              'code',
              PublicTemplateFailureCode.unavailable,
            )
            .having(
              (value) => value.toString(),
              'message',
              isNot(contains('private database detail')),
            ),
      ),
    );

    failure = StateError('socket detail');
    await expectLater(
      repository.listFriendFeed(),
      throwsA(
        isA<PublicTemplateFailure>().having(
          (value) => value.code,
          'code',
          PublicTemplateFailureCode.transport,
        ),
      ),
    );
  });
}

Future<void> _expectGeneric(SupabasePublicTemplateRepository repository) {
  return expectLater(
    repository.listFriendFeed(),
    throwsA(
      isA<PublicTemplateFailure>().having(
        (value) => value.code,
        'code',
        PublicTemplateFailureCode.generic,
      ),
    ),
  );
}

Map<String, dynamic> _feedPage({
  List<Map<String, dynamic>>? entries,
  bool nextCursor = true,
}) {
  final pageEntries = entries ?? [_entry()];
  return {
    'entries': pageEntries,
    'next_cursor': nextCursor
        ? {
            'published_at': '2026-07-27T12:00:00.000Z',
            'template_id': _templateId,
          }
        : null,
  };
}

Map<String, dynamic> _entry({
  String templateId = _templateId,
  String publishedAt = '2026-07-27T12:00:00.000Z',
}) {
  return {
    'profile': {
      'profile_id': _profileId,
      'username': 'public_friend',
      'display_name': 'Public Friend',
    },
    'template': {
      'template_id': templateId,
      'name': 'Public kit',
      'version': 4,
      'item_count': 0,
      'published_at': publishedAt,
    },
  };
}

List<Map<String, dynamic>> _entries(Map<String, dynamic> document) {
  return (document['entries']! as List)
      .cast<Map<String, dynamic>>()
      .toList(growable: false);
}

Map<String, dynamic> _profile(Map<String, dynamic> entry) {
  return entry['profile']! as Map<String, dynamic>;
}

Map<String, dynamic> _template(Map<String, dynamic> entry) {
  return entry['template']! as Map<String, dynamic>;
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}

const _profileId = '11111111-1111-4111-8111-111111111111';
const _templateId = '22222222-2222-4222-8222-222222222222';
const _secondTemplateId = '33333333-3333-4333-8333-333333333333';
