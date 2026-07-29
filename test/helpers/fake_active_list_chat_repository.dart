import 'dart:async';

import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';

typedef FakeChatSend = Future<ActiveListChatMessage> Function(
  String listId,
  String body,
  String requestId,
);

typedef FakeChatList = Future<ActiveListChatPage> Function(
  String listId,
  int pageSize,
  int? beforeMessagePosition,
);

typedef FakeChatDelete = Future<ActiveListChatMessage> Function(
  String listId,
  String messageId,
);

class FakeActiveListChatRepository implements ActiveListChatRepository {
  List<ActiveListChatMessage> messages = [];
  ActiveListChatUnreadCount unread =
      const ActiveListChatUnreadCount(count: 0, isCapped: false);
  Object? listFailure;
  Object? unreadFailure;
  Object? markFailure;
  FakeChatList? onList;
  FakeChatSend? onSend;
  FakeChatDelete? onDelete;
  final List<String> sentBodies = [];
  final List<String> requestIds = [];
  final List<(int, int?)> pageRequests = [];
  final List<String> requestedListIds = [];
  final List<String> markedMessageIds = [];
  int listCalls = 0;
  int sendCalls = 0;
  int deleteCalls = 0;
  int unreadCalls = 0;
  int markCalls = 0;
  bool nextMarkChanged = true;

  @override
  Future<ActiveListChatPage> listMessages(
    String listId, {
    required int pageSize,
    int? beforeMessagePosition,
  }) async {
    listCalls += 1;
    requestedListIds.add(listId);
    pageRequests.add((pageSize, beforeMessagePosition));
    if (listFailure != null) throw listFailure!;
    final handler = onList;
    if (handler != null) {
      return handler(listId, pageSize, beforeMessagePosition);
    }
    final eligible = messages
        .where(
          (message) =>
              beforeMessagePosition == null ||
              message.messagePosition < beforeMessagePosition,
        )
        .toList()
      ..sort(
        (left, right) => right.messagePosition.compareTo(left.messagePosition),
      );
    final pageMessages = eligible.take(pageSize).toList(growable: false);
    final hasMore = eligible.length > pageMessages.length;
    return ActiveListChatPage(
      messages: pageMessages,
      hasMore: hasMore,
      nextBeforeMessagePosition:
          hasMore ? pageMessages.last.messagePosition : null,
    );
  }

  @override
  Future<ActiveListChatMessage> sendMessage(
    String listId,
    String body, {
    required String requestId,
  }) async {
    sendCalls += 1;
    sentBodies.add(body);
    requestIds.add(requestId);
    final handler = onSend;
    final message = handler == null
        ? activeListChatTestMessage(
            sequence: messages.length + 1,
            body: body,
            isMine: true,
          )
        : await handler(listId, body, requestId);
    _upsert(message);
    return message;
  }

  @override
  Future<ActiveListChatMessage> deleteMessage(
    String listId,
    String messageId,
  ) async {
    deleteCalls += 1;
    final handler = onDelete;
    final original = messages.firstWhere((message) => message.id == messageId);
    final deleted = handler == null
        ? activeListChatTestMessage(
            sequence: original.messagePosition,
            body: null,
            deletedAt: original.createdAt.add(const Duration(minutes: 1)),
            deletionKind: original.isMine
                ? ActiveListChatDeletionKind.sender
                : ActiveListChatDeletionKind.owner,
            username: original.senderUsername,
            displayName: original.senderDisplayName,
            isMine: original.isMine,
          )
        : await handler(listId, messageId);
    _upsert(deleted);
    return deleted;
  }

  @override
  Future<ActiveListChatReadResult> markRead(
    String listId,
    String throughMessageId,
  ) async {
    markCalls += 1;
    markedMessageIds.add(throughMessageId);
    if (markFailure != null) throw markFailure!;
    final message =
        messages.firstWhere((message) => message.id == throughMessageId);
    final changed = nextMarkChanged;
    nextMarkChanged = false;
    return ActiveListChatReadResult(
      lastReadMessagePosition: message.messagePosition,
      changed: changed,
    );
  }

  @override
  Future<ActiveListChatUnreadCount> getUnreadCount(String listId) async {
    unreadCalls += 1;
    if (unreadFailure != null) throw unreadFailure!;
    return unread;
  }

  void _upsert(ActiveListChatMessage message) {
    messages = [
      for (final current in messages)
        if (current.id != message.id) current,
      message,
    ]..sort(
        (left, right) => left.messagePosition.compareTo(right.messagePosition),
      );
  }
}

ActiveListChatMessage activeListChatTestMessage({
  required int sequence,
  String? body = 'Message',
  DateTime? deletedAt,
  ActiveListChatDeletionKind? deletionKind,
  String? username = 'friend_user',
  String? displayName = 'Friend User',
  bool isMine = false,
}) {
  final suffix = sequence.toString().padLeft(12, '0');
  return ActiveListChatMessage(
    id: '10000000-0000-4000-8000-$suffix',
    messagePosition: sequence,
    body: body,
    createdAt: DateTime.utc(2026, 7, 29, 10).add(
      Duration(seconds: sequence),
    ),
    deletedAt: deletedAt,
    deletionKind: deletionKind,
    senderUsername: username,
    senderDisplayName: displayName,
    isMine: isMine,
  );
}
