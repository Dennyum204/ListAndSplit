import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/data/supabase_active_list_chat_repository.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabaseActiveListChatRepository repository;

  setUp(() {
    calls = [];
    response = _messageJson();
    failure = null;
    repository = SupabaseActiveListChatRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('lists a strict keyset page with exact RPC arguments', () async {
    response = {
      'messages': [
        _messageJson(messagePosition: 9),
        _messageJson(
          id: '22222222-2222-4222-8222-222222222222',
          messagePosition: 8,
        ),
      ],
      'has_more': true,
      'next_before_message_position': 8,
    };

    final page = await repository.listMessages(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      pageSize: 2,
      beforeMessagePosition: 10,
    );

    expect(page.messages.map((message) => message.messagePosition), [9, 8]);
    expect(page.hasMore, isTrue);
    expect(calls.single.functionName, 'list_active_list_chat_messages');
    expect(calls.single.params, {
      'target_list_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'page_size': 2,
      'before_message_position': 10,
    });
  });

  test('normalizes send body and preserves the caller request UUID', () async {
    final message = await repository.sendMessage(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '\u00a0 Hello\r\n\tworld 😀 \u00a0',
      requestId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );

    expect(message.messagePosition, 7);
    expect(calls.single.functionName, 'send_active_list_chat_message');
    expect(calls.single.params, {
      'target_list_id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'raw_body': 'Hello\n\tworld 😀',
      'request_id': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    });
  });

  test('retries with the same request UUID without generating a replacement',
      () async {
    const requestId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

    await repository.sendMessage(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'same body',
      requestId: requestId,
    );
    await repository.sendMessage(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'same body',
      requestId: requestId,
    );

    expect(calls, hasLength(2));
    expect(
      calls.map((call) => call.params!['request_id']).toSet(),
      {requestId},
    );
  });

  test('maps tombstone, mark-read, and unread responses strictly', () async {
    response = _messageJson(
      body: null,
      deletedAt: '2026-07-29T10:24:00.000Z',
      deletionKind: 'owner',
      isMine: false,
    );
    final tombstone = await repository.deleteMessage(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '11111111-1111-4111-8111-111111111111',
    );
    expect(tombstone.deletionKind, ActiveListChatDeletionKind.owner);

    response = {
      'last_read_message_position': 7,
      'changed': true,
    };
    final read = await repository.markRead(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '11111111-1111-4111-8111-111111111111',
    );
    expect(read.lastReadMessagePosition, 7);
    expect(read.changed, isTrue);

    response = {'count': 100, 'is_capped': true};
    final unread = await repository.getUnreadCount(
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    expect(unread.compactLabel, '99+');
    expect(
      calls.map((call) => call.functionName),
      [
        'delete_active_list_chat_message',
        'mark_active_list_chat_read',
        'get_active_list_chat_unread_count',
      ],
    );
  });

  test('rejects invalid local bounds without invoking Supabase', () async {
    await expectLater(
      repository.listMessages(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        pageSize: 51,
      ),
      throwsA(
        isA<ActiveListChatFailure>().having(
          (error) => error.code,
          'code',
          ActiveListChatFailureCode.invalid,
        ),
      ),
    );
    await expectLater(
      repository.sendMessage(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'bad\u0007control',
        requestId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      ),
      throwsA(
        isA<ActiveListChatFailure>().having(
          (error) => error.code,
          'code',
          ActiveListChatFailureCode.invalid,
        ),
      ),
    );
    expect(calls, isEmpty);
  });

  test('rejects privacy-expanded and malformed projections', () async {
    final malformedResponses = <Object?>[
      {..._messageJson(), 'sender_profile_id': 'private'},
      {..._messageJson(), 'message_position': 1.5},
      {..._messageJson(), 'created_at': '2026-07-29T10:23:17'},
      {
        ..._messageJson(
          body: null,
          deletedAt: '2026-07-29T10:24:00.000Z',
          deletionKind: 'account',
        ),
      },
      {
        'messages': [_messageJson(messagePosition: 4)],
        'has_more': true,
        'next_before_message_position': 3,
      },
      {'count': 100, 'is_capped': false},
    ];

    for (final malformed in malformedResponses.take(4)) {
      response = malformed;
      await expectLater(
        repository.sendMessage(
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
          'valid',
          requestId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
        ),
        throwsA(
          isA<ActiveListChatFailure>().having(
            (error) => error.code,
            'code',
            ActiveListChatFailureCode.generic,
          ),
        ),
      );
    }

    response = malformedResponses[4];
    await expectLater(
      repository.listMessages(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        pageSize: 20,
      ),
      throwsA(isA<ActiveListChatFailure>()),
    );
    response = malformedResponses[5];
    await expectLater(
      repository.getUnreadCount(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      ),
      throwsA(isA<ActiveListChatFailure>()),
    );
  });

  test('maps stable database and transport failures without leaking details',
      () async {
    const cases = <(PostgrestException, ActiveListChatFailureCode)>[
      (
        PostgrestException(message: 'private', code: '22023'),
        ActiveListChatFailureCode.invalid,
      ),
      (
        PostgrestException(message: 'private', code: 'P0002'),
        ActiveListChatFailureCode.unavailable,
      ),
      (
        PostgrestException(message: 'private', code: '23505'),
        ActiveListChatFailureCode.requestConflict,
      ),
      (
        PostgrestException(message: 'private', code: '55000'),
        ActiveListChatFailureCode.archived,
      ),
      (
        PostgrestException(
          message: 'chat rate limit reached',
          code: 'P0001',
        ),
        ActiveListChatFailureCode.rateLimited,
      ),
    ];

    for (final (databaseFailure, expectedCode) in cases) {
      failure = databaseFailure;
      await expectLater(
        repository.getUnreadCount(
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        ),
        throwsA(
          isA<ActiveListChatFailure>().having(
            (error) => error.code,
            'code',
            expectedCode,
          ),
        ),
      );
    }

    const privateValue = 'private-message-body';
    failure = StateError(privateValue);
    try {
      await repository.getUnreadCount(
        'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      );
      fail('transport failure should be mapped');
    } catch (error) {
      expect(error, isA<ActiveListChatFailure>());
      expect(error.toString(), isNot(contains(privateValue)));
    }
  });
}

Map<String, dynamic> _messageJson({
  String id = '11111111-1111-4111-8111-111111111111',
  int messagePosition = 7,
  String? body = 'Hello',
  String? deletedAt,
  String? deletionKind,
  String? senderUsername = 'alpha_user',
  String? senderDisplayName = 'Alpha User',
  bool isMine = true,
}) {
  return {
    'id': id,
    'message_position': messagePosition,
    'body': body,
    'created_at': '2026-07-29T10:23:17.000Z',
    'deleted_at': deletedAt,
    'deletion_kind': deletionKind,
    'sender_username': senderUsername,
    'sender_display_name': senderDisplayName,
    'is_mine': isMine,
  };
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
