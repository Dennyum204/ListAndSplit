import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ActiveListChatRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseActiveListChatRepository implements ActiveListChatRepository {
  SupabaseActiveListChatRepository(
    SupabaseClient client, {
    ActiveListChatRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) =>
                client.rpc<Object?>(functionName, params: params));

  final ActiveListChatRpc _rpc;

  @override
  Future<ActiveListChatPage> listMessages(
    String listId, {
    required int pageSize,
    int? beforeMessagePosition,
  }) async {
    if (pageSize < 1 ||
        pageSize > activeListChatMaximumPageSize ||
        (beforeMessagePosition != null && beforeMessagePosition < 1)) {
      throw const ActiveListChatFailure(ActiveListChatFailureCode.invalid);
    }
    try {
      return _page(
        _object(
          await _rpc(
            'list_active_list_chat_messages',
            params: {
              'target_list_id': listId,
              'page_size': pageSize,
              'before_message_position': beforeMessagePosition,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListChatMessage> sendMessage(
    String listId,
    String body, {
    required String requestId,
  }) async {
    final normalizedBody = normalizeActiveListChatBody(body);
    if (!isValidActiveListChatBody(normalizedBody)) {
      throw const ActiveListChatFailure(ActiveListChatFailureCode.invalid);
    }
    try {
      return _message(
        _object(
          await _rpc(
            'send_active_list_chat_message',
            params: {
              'target_list_id': listId,
              'raw_body': normalizedBody,
              'request_id': requestId,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListChatMessage> deleteMessage(
    String listId,
    String messageId,
  ) async {
    try {
      return _message(
        _object(
          await _rpc(
            'delete_active_list_chat_message',
            params: {
              'target_list_id': listId,
              'target_message_id': messageId,
            },
          ),
        ),
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListChatReadResult> markRead(
    String listId,
    String throughMessageId,
  ) async {
    try {
      final json = _object(
        await _rpc(
          'mark_active_list_chat_read',
          params: {
            'target_list_id': listId,
            'through_message_id': throughMessageId,
          },
        ),
      );
      _expectExactKeys(
        json,
        const {'last_read_message_position', 'changed'},
      );
      final changed = json['changed'];
      if (changed is! bool) {
        throw const FormatException('invalid Chat read result');
      }
      return ActiveListChatReadResult(
        lastReadMessagePosition:
            _nonNegativeInt(json['last_read_message_position']),
        changed: changed,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<ActiveListChatUnreadCount> getUnreadCount(String listId) async {
    try {
      final json = _object(
        await _rpc(
          'get_active_list_chat_unread_count',
          params: {'target_list_id': listId},
        ),
      );
      _expectExactKeys(json, const {'count', 'is_capped'});
      final count = _nonNegativeInt(json['count']);
      final isCapped = json['is_capped'];
      if (count > activeListChatUnreadCap ||
          isCapped is! bool ||
          isCapped != (count == activeListChatUnreadCap)) {
        throw const FormatException('invalid Chat unread count');
      }
      return ActiveListChatUnreadCount(
        count: count,
        isCapped: isCapped,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  static ActiveListChatPage _page(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'messages',
        'has_more',
        'next_before_message_position',
      },
    );
    final rawMessages = json['messages'];
    final hasMore = json['has_more'];
    final rawNext = json['next_before_message_position'];
    if (rawMessages is! List ||
        hasMore is! bool ||
        (rawNext != null && rawNext is! int)) {
      throw const FormatException('invalid Chat page');
    }
    return ActiveListChatPage(
      messages: rawMessages.map((value) {
        if (value is! Map) {
          throw const FormatException('invalid Chat message');
        }
        return _message(Map<String, dynamic>.from(value));
      }).toList(growable: false),
      hasMore: hasMore,
      nextBeforeMessagePosition: rawNext == null ? null : _positiveInt(rawNext),
    );
  }

  static ActiveListChatMessage _message(Map<String, dynamic> json) {
    _expectExactKeys(
      json,
      const {
        'id',
        'message_position',
        'body',
        'created_at',
        'deleted_at',
        'deletion_kind',
        'sender_username',
        'sender_display_name',
        'is_mine',
      },
    );
    final body = json['body'];
    final deletionKind = json['deletion_kind'];
    final senderUsername = json['sender_username'];
    final senderDisplayName = json['sender_display_name'];
    final isMine = json['is_mine'];
    if ((body != null && body is! String) ||
        (deletionKind != null && deletionKind is! String) ||
        (senderUsername != null && senderUsername is! String) ||
        (senderDisplayName != null && senderDisplayName is! String) ||
        isMine is! bool) {
      throw const FormatException('invalid Chat message');
    }
    return ActiveListChatMessage(
      id: _uuid(json['id']),
      messagePosition: _positiveInt(json['message_position']),
      body: body as String?,
      createdAt: _dateTime(json['created_at']),
      deletedAt: _nullableDateTime(json['deleted_at']),
      deletionKind: deletionKind == null
          ? null
          : ActiveListChatDeletionKind.fromWire(deletionKind as String),
      senderUsername: senderUsername as String?,
      senderDisplayName: senderDisplayName as String?,
      isMine: isMine,
    );
  }

  static Map<String, dynamic> _object(Object? response) {
    if (response is! Map) {
      throw const FormatException('expected Chat object');
    }
    return Map<String, dynamic>.from(response);
  }

  static void _expectExactKeys(
    Map<String, dynamic> json,
    Set<String> expected,
  ) {
    if (json.length != expected.length ||
        !json.keys.toSet().containsAll(expected)) {
      throw const FormatException('invalid Chat projection');
    }
  }

  static ActiveListChatFailure _failure(Object error) {
    if (error is ActiveListChatFailure) return error;
    if (error is PostgrestException) {
      return ActiveListChatFailure(
        switch ((error.code, error.message)) {
          ('22023', _) => ActiveListChatFailureCode.invalid,
          ('P0002', _) => ActiveListChatFailureCode.unavailable,
          ('23505', _) => ActiveListChatFailureCode.requestConflict,
          ('55000', _) => ActiveListChatFailureCode.archived,
          ('P0001', 'chat rate limit reached') =>
            ActiveListChatFailureCode.rateLimited,
          _ => ActiveListChatFailureCode.generic,
        },
      );
    }
    if (error is FormatException) {
      return const ActiveListChatFailure(ActiveListChatFailureCode.generic);
    }
    return const ActiveListChatFailure(ActiveListChatFailureCode.transport);
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static String _uuid(Object? value) {
    if (value is! String || !_uuidPattern.hasMatch(value)) {
      throw const FormatException('invalid UUID');
    }
    return value;
  }

  static int _positiveInt(Object? value) {
    if (value is! int || value < 1) {
      throw const FormatException('invalid positive integer');
    }
    return value;
  }

  static int _nonNegativeInt(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('invalid non-negative integer');
    }
    return value;
  }

  static DateTime _dateTime(Object? value) {
    final parsed = value is String ? DateTime.tryParse(value) : null;
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('invalid UTC timestamp');
    }
    return parsed;
  }

  static DateTime? _nullableDateTime(Object? value) {
    return value == null ? null : _dateTime(value);
  }
}
