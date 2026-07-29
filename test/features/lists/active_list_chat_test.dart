import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';

void main() {
  group('List Chat body contract', () {
    test('normalizes line endings and Unicode edge whitespace only', () {
      const raw = '\u00a0 Hello\r\n\tworld 😀 \u00a0';

      expect(normalizeActiveListChatBody(raw), 'Hello\n\tworld 😀');
      expect(isValidActiveListChatBody(raw), isTrue);
    });

    test('uses PostgreSQL-character boundaries and control allowlist', () {
      expect(
        isValidActiveListChatBody(List.filled(2000, 'é').join()),
        isTrue,
      );
      expect(
        isValidActiveListChatBody(List.filled(2001, 'é').join()),
        isFalse,
      );
      expect(isValidActiveListChatBody(' \r\n '), isFalse);
      expect(isValidActiveListChatBody('bad\u0007control'), isFalse);
      expect(isValidActiveListChatBody('tab\tand\nline'), isTrue);
    });
  });

  group('List Chat entities', () {
    test('accepts active and all three tombstone shapes', () {
      final active = _message();
      final sender = _message(
        body: null,
        deletedAt: DateTime.parse('2026-07-29T10:24:00Z'),
        deletionKind: ActiveListChatDeletionKind.sender,
      );
      final owner = _message(
        body: null,
        deletedAt: DateTime.parse('2026-07-29T10:24:00Z'),
        deletionKind: ActiveListChatDeletionKind.owner,
      );
      final account = _message(
        body: null,
        deletedAt: DateTime.parse('2026-07-29T10:24:00Z'),
        deletionKind: ActiveListChatDeletionKind.account,
        senderUsername: null,
        senderDisplayName: null,
        isMine: false,
      );

      expect(active.isDeleted, isFalse);
      expect(sender.isDeleted, isTrue);
      expect(owner.isDeleted, isTrue);
      expect(account.senderUsername, isNull);
    });

    test('rejects malformed identity, body, time, and tombstone shapes', () {
      for (final build in <ActiveListChatMessage Function()>[
        () => _message(id: 'not-a-uuid'),
        () => _message(messagePosition: 0),
        () => _message(body: ' padded '),
        () => _message(
              body: null,
              deletionKind: ActiveListChatDeletionKind.sender,
            ),
        () => _message(
              body: null,
              deletedAt: DateTime.parse('2026-07-29T10:24:00Z'),
              deletionKind: ActiveListChatDeletionKind.account,
            ),
        () => _message(senderUsername: null),
        () => _message(
              deletedAt: DateTime.parse('2026-07-29T10:22:00Z'),
              body: null,
              deletionKind: ActiveListChatDeletionKind.sender,
            ),
      ]) {
        expect(build, throwsFormatException);
      }
    });

    test('requires strict descending page order and bounded cursor shape', () {
      final page = ActiveListChatPage(
        messages: [
          _message(messagePosition: 3),
          _message(
            id: '22222222-2222-4222-8222-222222222222',
            messagePosition: 2,
          ),
        ],
        hasMore: true,
        nextBeforeMessagePosition: 2,
      );

      expect(page.messages, hasLength(2));
      expect(page.nextBeforeMessagePosition, 2);
      expect(
        () => ActiveListChatPage(
          messages: [
            _message(messagePosition: 2),
            _message(
              id: '22222222-2222-4222-8222-222222222222',
              messagePosition: 3,
            ),
          ],
          hasMore: false,
          nextBeforeMessagePosition: null,
        ),
        throwsFormatException,
      );
      expect(
        () => ActiveListChatPage(
          messages: [_message()],
          hasMore: true,
          nextBeforeMessagePosition: 99,
        ),
        throwsFormatException,
      );
    });

    test('models the exact capped unread presentation contract', () {
      expect(
        const ActiveListChatUnreadCount(count: 0, isCapped: false).compactLabel,
        '0',
      );
      expect(
        const ActiveListChatUnreadCount(count: 99, isCapped: false)
            .compactLabel,
        '99',
      );
      expect(
        const ActiveListChatUnreadCount(count: 100, isCapped: true)
            .compactLabel,
        '99+',
      );
    });
  });
}

ActiveListChatMessage _message({
  String id = '11111111-1111-4111-8111-111111111111',
  int messagePosition = 1,
  String? body = 'Hello',
  DateTime? deletedAt,
  ActiveListChatDeletionKind? deletionKind,
  String? senderUsername = 'alpha_user',
  String? senderDisplayName = 'Alpha User',
  bool isMine = true,
}) {
  return ActiveListChatMessage(
    id: id,
    messagePosition: messagePosition,
    body: body,
    createdAt: DateTime.parse('2026-07-29T10:23:17Z'),
    deletedAt: deletedAt,
    deletionKind: deletionKind,
    senderUsername: senderUsername,
    senderDisplayName: senderDisplayName,
    isMine: isMine,
  );
}
