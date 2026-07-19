import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef NotificationRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? params,
});

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(
    SupabaseClient client, {
    NotificationRpc? rpc,
  }) : _rpc = rpc ??
            ((functionName, {params}) async {
              return client.rpc<Object?>(functionName, params: params);
            });

  final NotificationRpc _rpc;

  @override
  Future<List<InAppNotification>> listNotifications({
    required int limit,
    NotificationCursor? before,
  }) async {
    try {
      final rows = _rows(
        await _rpc(
          'list_notifications',
          params: {
            'page_size': limit,
            'before_created_at': before?.createdAt.toIso8601String(),
            'before_notification_id': before?.id,
          },
        ),
      );
      return rows.map(_mapNotification).toList(growable: false);
    } on NotificationFailure {
      rethrow;
    } catch (_) {
      throw const NotificationFailure();
    }
  }

  @override
  Future<int> getUnreadCount() async {
    try {
      final response = await _rpc('get_unread_notification_count');
      if (response is! int || response < 0) {
        throw const NotificationFailure();
      }
      return response;
    } on NotificationFailure {
      rethrow;
    } catch (_) {
      throw const NotificationFailure();
    }
  }

  @override
  Future<void> markRead(List<String> notificationIds) async {
    try {
      await _rpc(
        'mark_notifications_read',
        params: {'notification_ids': notificationIds},
      );
    } catch (_) {
      throw const NotificationFailure();
    }
  }

  List<Map<String, dynamic>> _rows(Object? response) {
    if (response is! List) throw const NotificationFailure();
    return response.map((row) {
      if (row is! Map) throw const NotificationFailure();
      return Map<String, dynamic>.from(row);
    }).toList(growable: false);
  }

  InAppNotification _mapNotification(Map<String, dynamic> json) {
    try {
      final status = _mapActionStatus(json['action_status']! as String);
      final expectedVersion = json['expected_relationship_version'] as int?;
      if ((status == NotificationActionStatus.actionable &&
              (expectedVersion == null || expectedVersion <= 0)) ||
          (status != NotificationActionStatus.actionable &&
              expectedVersion != null)) {
        throw const FormatException();
      }

      final createdAt = DateTime.parse(json['created_at']! as String);
      return InAppNotification(
        id: json['notification_id']! as String,
        type: _mapType(json['notification_type']! as String),
        createdAt: createdAt,
        isRead: json['is_read']! as bool,
        actorProfileId: json['actor_profile_id']! as String,
        actorUsername: json['actor_username']! as String,
        actorDisplayName: json['actor_display_name']! as String,
        actionStatus: status,
        expectedRelationshipVersion: expectedVersion,
      );
    } catch (_) {
      throw const NotificationFailure();
    }
  }

  InAppNotificationType _mapType(String type) => switch (type) {
        'friend_request' => InAppNotificationType.friendRequest,
        _ => throw const NotificationFailure(),
      };

  NotificationActionStatus _mapActionStatus(String status) => switch (status) {
        'actionable' => NotificationActionStatus.actionable,
        'friends' => NotificationActionStatus.friends,
        'unavailable' => NotificationActionStatus.unavailable,
        _ => throw const NotificationFailure(),
      };
}
