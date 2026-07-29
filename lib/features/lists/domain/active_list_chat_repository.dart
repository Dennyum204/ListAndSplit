import 'package:list_and_split/features/lists/domain/active_list_chat.dart';

enum ActiveListChatFailureCode {
  invalid,
  unavailable,
  requestConflict,
  archived,
  rateLimited,
  transport,
  generic,
}

class ActiveListChatFailure implements Exception {
  const ActiveListChatFailure(this.code);

  final ActiveListChatFailureCode code;
}

abstract interface class ActiveListChatRepository {
  Future<ActiveListChatPage> listMessages(
    String listId, {
    required int pageSize,
    int? beforeMessagePosition,
  });

  Future<ActiveListChatMessage> sendMessage(
    String listId,
    String body, {
    required String requestId,
  });

  Future<ActiveListChatMessage> deleteMessage(
    String listId,
    String messageId,
  );

  Future<ActiveListChatReadResult> markRead(
    String listId,
    String throughMessageId,
  );

  Future<ActiveListChatUnreadCount> getUnreadCount(String listId);
}
