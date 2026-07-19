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
    expect(calls.single.functionName, 'list_notifications');
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

  test('maps a nonnegative unread bigint response', () async {
    response = 12;

    expect(await repository.getUnreadCount(), 12);
    expect(calls.single.functionName, 'get_unread_notification_count');
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
  };
}

class _RpcCall {
  const _RpcCall(this.functionName, this.params);

  final String functionName;
  final Map<String, dynamic>? params;
}
