import 'package:list_and_split/features/lists/domain/general_note.dart';

const activeListChatMaximumCharacters = 2000;
const activeListChatMaximumPageSize = 50;
const activeListChatUnreadCap = 100;

final _activeListChatUuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _activeListChatUsernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,23}$');

String normalizeActiveListChatBody(String value) {
  return normalizeGeneralNoteText(value);
}

bool isValidActiveListChatBody(String value) {
  final normalized = normalizeActiveListChatBody(value);
  if (normalized.isEmpty ||
      normalized.runes.length > activeListChatMaximumCharacters) {
    return false;
  }
  return normalized.runes.every(
    (codePoint) =>
        codePoint == 0x09 ||
        codePoint == 0x0a ||
        (codePoint >= 0x20 && codePoint <= 0x7e) ||
        codePoint >= 0xa0,
  );
}

enum ActiveListChatDeletionKind {
  sender('sender'),
  owner('owner'),
  account('account');

  const ActiveListChatDeletionKind(this.wireValue);

  final String wireValue;

  static ActiveListChatDeletionKind fromWire(String value) => switch (value) {
        'sender' => sender,
        'owner' => owner,
        'account' => account,
        _ => throw const FormatException('unknown Chat deletion kind'),
      };
}

class ActiveListChatMessage {
  ActiveListChatMessage({
    required this.id,
    required this.messagePosition,
    required this.body,
    required this.createdAt,
    required this.deletedAt,
    required this.deletionKind,
    required this.senderUsername,
    required this.senderDisplayName,
    required this.isMine,
  }) {
    final isActive = deletionKind == null;
    final isAccountTombstone =
        deletionKind == ActiveListChatDeletionKind.account;
    if (!_activeListChatUuidPattern.hasMatch(id) ||
        messagePosition < 1 ||
        !createdAt.isUtc ||
        (deletedAt != null &&
            (!deletedAt!.isUtc || deletedAt!.isBefore(createdAt))) ||
        isActive != (body != null && deletedAt == null) ||
        (body != null &&
            (body != normalizeActiveListChatBody(body!) ||
                !isValidActiveListChatBody(body!))) ||
        !isActive && (body != null || deletedAt == null) ||
        isAccountTombstone !=
            (senderUsername == null && senderDisplayName == null) ||
        (!isAccountTombstone &&
            (!_isValidUsername(senderUsername) ||
                !_isValidDisplayName(senderDisplayName))) ||
        (isAccountTombstone && isMine)) {
      throw const FormatException('invalid Chat message');
    }
  }

  final String id;
  final int messagePosition;
  final String? body;
  final DateTime createdAt;
  final DateTime? deletedAt;
  final ActiveListChatDeletionKind? deletionKind;
  final String? senderUsername;
  final String? senderDisplayName;
  final bool isMine;

  bool get isDeleted => deletionKind != null;
}

class ActiveListChatPage {
  ActiveListChatPage({
    required List<ActiveListChatMessage> messages,
    required this.hasMore,
    required this.nextBeforeMessagePosition,
  }) : messages = List.unmodifiable(messages) {
    if (this.messages.length > activeListChatMaximumPageSize ||
        (hasMore != (nextBeforeMessagePosition != null)) ||
        (nextBeforeMessagePosition != null &&
            (this.messages.isEmpty ||
                nextBeforeMessagePosition !=
                    this.messages.last.messagePosition))) {
      throw const FormatException('invalid Chat page');
    }
    for (var index = 1; index < this.messages.length; index += 1) {
      if (this.messages[index - 1].messagePosition <=
          this.messages[index].messagePosition) {
        throw const FormatException('invalid Chat page order');
      }
    }
  }

  final List<ActiveListChatMessage> messages;
  final bool hasMore;
  final int? nextBeforeMessagePosition;
}

class ActiveListChatReadResult {
  const ActiveListChatReadResult({
    required this.lastReadMessagePosition,
    required this.changed,
  }) : assert(lastReadMessagePosition >= 0);

  final int lastReadMessagePosition;
  final bool changed;
}

class ActiveListChatUnreadCount {
  const ActiveListChatUnreadCount({
    required this.count,
    required this.isCapped,
  }) : assert(
          count >= 0 &&
              count <= activeListChatUnreadCap &&
              isCapped == (count == activeListChatUnreadCap),
        );

  final int count;
  final bool isCapped;

  String get compactLabel => isCapped ? '99+' : count.toString();
}

bool _isValidUsername(String? value) {
  return value != null && _activeListChatUsernamePattern.hasMatch(value);
}

bool _isValidDisplayName(String? value) {
  return value != null &&
      value.trim() == value &&
      value.runes.isNotEmpty &&
      value.runes.length <= 50;
}
