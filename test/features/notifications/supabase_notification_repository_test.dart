import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/notifications/data/supabase_notification_repository.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late List<_RpcCall> calls;
  late Object? response;
  late Object? failure;
  late SupabaseNotificationRepository repository;

  setUp(() {
    calls = [];
    response = null;
    failure = null;
    repository = SupabaseNotificationRepository(
      SupabaseClient('http://localhost:54321', 'test-anon-key'),
      rpc: (functionName, {params}) async {
        calls.add(_RpcCall(functionName, params));
        if (failure != null) throw failure!;
        return response;
      },
    );
  });

  test('maps the minimal actionable notification projection', () async {
    response = [_row()];

    final result = await repository.listNotifications(limit: 20);

    expect(result, hasLength(1));
    expect(result.single.id, 'notification-1');
    expect(result.single.type, InAppNotificationType.friendRequest);
    expect(result.single.createdAt, DateTime.utc(2026, 7, 19, 7, 30));
    expect(result.single.isRead, isFalse);
    expect(result.single.actorProfileId, 'profile-2');
    expect(result.single.actorUsername, 'beta_user');
    expect(result.single.actorDisplayName, 'Beta User');
    expect(result.single.actionStatus, NotificationActionStatus.actionable);
    expect(result.single.expectedRelationshipVersion, 4);
    expect(calls.single.functionName, 'list_notifications_v3');
    expect(calls.single.params, {
      'page_size': 20,
      'before_created_at': null,
      'before_notification_id': null,
    });
  });

  test('passes both deterministic cursor fields without modification',
      () async {
    response = <Object?>[];
    final cursor = NotificationCursor(
      createdAt: DateTime.utc(2026, 7, 19, 7, 30, 0, 123),
      id: 'notification-20',
    );

    await repository.listNotifications(limit: 7, before: cursor);

    expect(calls.single.params, {
      'page_size': 7,
      'before_created_at': '2026-07-19T07:30:00.123Z',
      'before_notification_id': 'notification-20',
    });
  });

  test('maps every caller-relative action presentation state', () async {
    for (final entry in const {
      'actionable': NotificationActionStatus.actionable,
      'friends': NotificationActionStatus.friends,
      'unavailable': NotificationActionStatus.unavailable,
    }.entries) {
      response = [
        _row(
          actionStatus: entry.key,
          expectedVersion: entry.key == 'actionable' ? 4 : null,
        ),
      ];

      final result = await repository.listNotifications(limit: 20);

      expect(result.single.actionStatus, entry.value);
    }
  });

  test('maps actionable and resolved list invitation projections', () async {
    for (final entry in const {
      'actionable': NotificationActionStatus.actionable,
      'accepted': NotificationActionStatus.accepted,
      'unavailable': NotificationActionStatus.unavailable,
    }.entries) {
      response = [
        _row(
          notificationType: 'list_invitation',
          actionStatus: entry.key,
          expectedVersion: null,
          activeListId: 'list-1',
          activeListTitle: 'Shared trip',
          activeListStatus: 'active',
          expectedAccessVersion: entry.key == 'actionable' ? 6 : null,
        ),
      ];

      final result = await repository.listNotifications(limit: 20);

      expect(result.single.type, InAppNotificationType.listInvitation);
      expect(result.single.actionStatus, entry.value);
      expect(result.single.activeListId, 'list-1');
      expect(result.single.activeListTitle, 'Shared trip');
      expect(
        result.single.expectedAccessVersion,
        entry.key == 'actionable' ? 6 : null,
      );
      expect(result.single.expectedRelationshipVersion, isNull);
    }
  });

  test('maps informational list notifications as non-actionable', () async {
    for (final type in const [
      'list_invitation_accepted',
      'list_invitation_declined',
      'list_member_left',
      'list_member_removed',
      'list_ownership_transferred',
    ]) {
      response = [
        _row(
          notificationType: type,
          actionStatus: 'unavailable',
          expectedVersion: null,
          activeListId: 'list-1',
          activeListTitle: 'Shared trip',
          activeListStatus: 'archived',
        ),
      ];

      final result = await repository.listNotifications(limit: 20);

      expect(result.single.activeListTitle, 'Shared trip');
      expect(result.single.expectedAccessVersion, isNull);
    }
  });

  test('maps item-assignment notifications with live list and item names',
      () async {
    response = [
      _row(
        notificationType: 'list_item_assigned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        activeListItemId: 'item-1',
        activeListItemName: 'Sunscreen',
        assignmentItemVersion: 8,
      ),
    ];

    final result = await repository.listNotifications(limit: 20);

    expect(result.single.type, InAppNotificationType.listItemAssigned);
    expect(result.single.activeListId, 'list-1');
    expect(result.single.activeListTitle, 'Shared trip');
    expect(result.single.activeListItemId, 'item-1');
    expect(result.single.activeListItemName, 'Sunscreen');
    expect(result.single.assignmentItemVersion, 8);
    expect(result.single.actionStatus, NotificationActionStatus.unavailable);
  });

  test('maps Note mentions without exposing Note text or action state',
      () async {
    response = [
      _row(
        notificationType: 'list_note_mentioned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        generalNoteVersion: 9,
      ),
    ];

    final result = await repository.listNotifications(limit: 20);

    expect(result.single.type, InAppNotificationType.listNoteMentioned);
    expect(result.single.generalNoteVersion, 9);
    expect(result.single.activeListTitle, 'Shared trip');
    expect(result.single.activeListItemId, isNull);
    expect(result.single.actionStatus, NotificationActionStatus.unavailable);
    expect(response.toString(), isNot(contains('note_text')));
  });

  test('strict v3 Note parsing rejects excerpts and mismatched context',
      () async {
    final valid = _row(
      notificationType: 'list_note_mentioned',
      actionStatus: 'unavailable',
      expectedVersion: null,
      activeListId: 'list-1',
      activeListTitle: 'Shared trip',
      activeListStatus: 'active',
      generalNoteVersion: 9,
    );
    final withExcerpt = Map<String, dynamic>.from(valid)
      ..['note_text'] = 'private Note text';
    final withInvitationVersion = Map<String, dynamic>.from(valid)
      ..['expected_access_version'] = 2;
    final withAssignment = Map<String, dynamic>.from(valid)
      ..addAll({
        'active_list_item_id': 'item-1',
        'active_list_item_name': 'Sunscreen',
        'assignment_item_version': 3,
      });
    final withMalformedNoteVersion = Map<String, dynamic>.from(valid)
      ..['general_note_version'] = '9';

    for (final row in [
      withExcerpt,
      withInvitationVersion,
      withAssignment,
      withMalformedNoteVersion,
    ]) {
      response = [row];
      await expectLater(
        repository.listNotifications(limit: 20),
        throwsA(isA<NotificationFailure>()),
      );
    }
  });

  test('rejects malformed list and row payloads', () async {
    response = {'notification_id': 'notification-1'};
    await expectLater(
      repository.listNotifications(limit: 20),
      throwsA(isA<NotificationFailure>()),
    );

    response = ['not-a-row'];
    await expectLater(
      repository.listNotifications(limit: 20),
      throwsA(isA<NotificationFailure>()),
    );
  });

  test('rejects unsupported type, status, and malformed timestamp', () async {
    response = [_row(notificationType: 'future_type')];
    await expectLater(
      repository.listNotifications(limit: 20),
      throwsA(isA<NotificationFailure>()),
    );

    response = [_row(actionStatus: 'pending')];
    await expectLater(
      repository.listNotifications(limit: 20),
      throwsA(isA<NotificationFailure>()),
    );

    response = [_row(createdAt: 'not-a-date')];
    await expectLater(
      repository.listNotifications(limit: 20),
      throwsA(isA<NotificationFailure>()),
    );
  });

  test('requires a positive version only for actionable rows', () async {
    for (final row in [
      _row(expectedVersion: null),
      _row(expectedVersion: 0),
      _row(actionStatus: 'friends', expectedVersion: 4),
      _row(actionStatus: 'unavailable', expectedVersion: 4),
    ]) {
      response = [row];
      await expectLater(
        repository.listNotifications(limit: 20),
        throwsA(isA<NotificationFailure>()),
      );
    }
  });

  test('rejects malformed or privacy-inconsistent list action shapes',
      () async {
    for (final row in [
      _row(
        notificationType: 'list_invitation',
        expectedVersion: null,
        expectedAccessVersion: 2,
      ),
      _row(
        notificationType: 'list_invitation',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: ' Shared trip ',
        activeListStatus: 'active',
        expectedAccessVersion: 2,
      ),
      _row(
        notificationType: 'list_member_left',
        actionStatus: 'actionable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        expectedAccessVersion: 2,
      ),
      _row(activeListId: 'list-1'),
      _row(
        notificationType: 'list_item_assigned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
      ),
      _row(
        notificationType: 'list_member_left',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        activeListItemId: 'item-1',
        activeListItemName: 'Sunscreen',
        assignmentItemVersion: 8,
      ),
      _row(
        notificationType: 'list_item_assigned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        activeListItemId: 'item-1',
        activeListItemName: ' Sunscreen ',
        assignmentItemVersion: 8,
      ),
      _row(
        notificationType: 'list_item_assigned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        activeListItemId: 'item-1',
        activeListItemName: 'Sunscreen',
        assignmentItemVersion: 0,
      ),
      _row(
        notificationType: 'list_note_mentioned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
      ),
      _row(
        notificationType: 'list_member_left',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        generalNoteVersion: 2,
      ),
      _row(
        notificationType: 'list_note_mentioned',
        actionStatus: 'unavailable',
        expectedVersion: null,
        activeListId: 'list-1',
        activeListTitle: 'Shared trip',
        activeListStatus: 'active',
        generalNoteVersion: 0,
      ),
    ]) {
      response = [row];
      await expectLater(
        repository.listNotifications(limit: 20),
        throwsA(isA<NotificationFailure>()),
      );
    }
  });

  test('maps a nonnegative unread bigint response', () async {
    response = 12;

    expect(await repository.getUnreadCount(), 12);
    expect(calls.single.functionName, 'get_unread_notification_count_v3');
    expect(calls.single.params, isNull);
  });

  test('rejects malformed unread-count responses', () async {
    for (final malformed in [-1, '1', null, 1.2]) {
      response = malformed;
      await expectLater(
        repository.getUnreadCount(),
        throwsA(isA<NotificationFailure>()),
      );
    }
  });

  test('mark-read passes exact IDs including empty input', () async {
    response = null;

    await repository.markRead(['notification-2', 'notification-1']);
    await repository.markRead(const []);

    expect(calls[0].functionName, 'mark_notifications_read');
    expect(calls[0].params, {
      'notification_ids': ['notification-2', 'notification-1'],
    });
    expect(calls[1].params, {'notification_ids': <String>[]});
  });

  test('maps all transport failures to notification failure', () async {
    failure = const PostgrestException(message: 'transport failed');

    await expectLater(
      repository.listNotifications(limit: 20),
      throwsA(isA<NotificationFailure>()),
    );
    await expectLater(
      repository.getUnreadCount(),
      throwsA(isA<NotificationFailure>()),
    );
    await expectLater(
      repository.markRead(['notification-1']),
      throwsA(isA<NotificationFailure>()),
    );
  });
}

Map<String, dynamic> _row({
  String notificationType = 'friend_request',
  String createdAt = '2026-07-19T07:30:00.000Z',
  String actionStatus = 'actionable',
  int? expectedVersion = 4,
  String? activeListId,
  String? activeListTitle,
  String? activeListStatus,
  int? expectedAccessVersion,
  String? activeListItemId,
  String? activeListItemName,
  int? assignmentItemVersion,
  int? generalNoteVersion,
}) {
  return {
    'notification_id': 'notification-1',
    'notification_type': notificationType,
    'created_at': createdAt,
    'is_read': false,
    'actor_profile_id': 'profile-2',
    'actor_username': 'beta_user',
    'actor_display_name': 'Beta User',
    'action_status': actionStatus,
    'expected_relationship_version': expectedVersion,
    'active_list_id': activeListId,
    'active_list_title': activeListTitle,
    'active_list_status': activeListStatus,
    'expected_access_version': expectedAccessVersion,
    'active_list_item_id': activeListItemId,
    'active_list_item_name': activeListItemName,
    'assignment_item_version': assignmentItemVersion,
    'general_note_version': generalNoteVersion,
  };
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
