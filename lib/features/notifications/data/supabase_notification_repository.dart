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
          'list_notifications_v3',
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
      final response = await _rpc('get_unread_notification_count_v3');
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
      if (json.length != _notificationProjectionKeys.length ||
          !json.keys.toSet().containsAll(_notificationProjectionKeys)) {
        throw const FormatException();
      }
      final status = _mapActionStatus(json['action_status']! as String);
      final expectedVersion = json['expected_relationship_version'] as int?;
      final type = _mapType(json['notification_type']! as String);
      final expectedAccessVersion = json['expected_access_version'] as int?;
      final isFriendAction = type == InAppNotificationType.friendRequest &&
          status == NotificationActionStatus.actionable;
      final isListAction = type == InAppNotificationType.listInvitation &&
          status == NotificationActionStatus.actionable;
      final isAssignment = type == InAppNotificationType.listItemAssigned;
      final isNoteMention = type == InAppNotificationType.listNoteMentioned;
      final isListType = type != InAppNotificationType.friendRequest;
      final activeListId = json['active_list_id'] as String?;
      final activeListTitle = json['active_list_title'] as String?;
      final activeListStatus = json['active_list_status'] as String?;
      final activeListItemId = json['active_list_item_id'] as String?;
      final activeListItemName = json['active_list_item_name'] as String?;
      final assignmentItemVersion = json['assignment_item_version'] as int?;
      final generalNoteVersion = json['general_note_version'] as int?;
      if ((isFriendAction != (expectedVersion != null)) ||
          (expectedVersion != null && expectedVersion <= 0) ||
          (isListAction != (expectedAccessVersion != null)) ||
          (expectedAccessVersion != null && expectedAccessVersion <= 0) ||
          (isListType &&
              (activeListId == null ||
                  activeListTitle == null ||
                  activeListStatus == null)) ||
          (!isListType &&
              (activeListId != null ||
                  activeListTitle != null ||
                  activeListStatus != null)) ||
          (activeListTitle != null &&
              (activeListTitle.isEmpty ||
                  activeListTitle.trim() != activeListTitle ||
                  activeListTitle.length > 80)) ||
          (activeListStatus != null &&
              activeListStatus != 'active' &&
              activeListStatus != 'archived') ||
          (isAssignment !=
              (activeListItemId != null &&
                  activeListItemName != null &&
                  assignmentItemVersion != null)) ||
          (activeListItemId == null && activeListItemName != null) ||
          (activeListItemId != null && activeListItemName == null) ||
          ((activeListItemId == null) != (assignmentItemVersion == null)) ||
          (assignmentItemVersion != null && assignmentItemVersion <= 0) ||
          (isNoteMention != (generalNoteVersion != null)) ||
          (generalNoteVersion != null && generalNoteVersion <= 0) ||
          (activeListItemName != null &&
              (activeListItemName.isEmpty ||
                  activeListItemName.trim() != activeListItemName ||
                  activeListItemName.length > 120)) ||
          (type == InAppNotificationType.friendRequest &&
              status == NotificationActionStatus.accepted) ||
          (type == InAppNotificationType.listInvitation &&
              status == NotificationActionStatus.friends) ||
          (type != InAppNotificationType.friendRequest &&
              type != InAppNotificationType.listInvitation &&
              status != NotificationActionStatus.unavailable)) {
        throw const FormatException();
      }

      final createdAt = DateTime.parse(json['created_at']! as String);
      return InAppNotification(
        id: json['notification_id']! as String,
        type: type,
        createdAt: createdAt,
        isRead: json['is_read']! as bool,
        actorProfileId: json['actor_profile_id']! as String,
        actorUsername: json['actor_username']! as String,
        actorDisplayName: json['actor_display_name']! as String,
        actionStatus: status,
        expectedRelationshipVersion: expectedVersion,
        activeListId: activeListId,
        activeListTitle: activeListTitle,
        activeListStatus: activeListStatus,
        expectedAccessVersion: expectedAccessVersion,
        activeListItemId: activeListItemId,
        activeListItemName: activeListItemName,
        assignmentItemVersion: assignmentItemVersion,
        generalNoteVersion: generalNoteVersion,
      );
    } catch (_) {
      throw const NotificationFailure();
    }
  }

  InAppNotificationType _mapType(String type) => switch (type) {
        'friend_request' => InAppNotificationType.friendRequest,
        'list_invitation' => InAppNotificationType.listInvitation,
        'list_invitation_accepted' =>
          InAppNotificationType.listInvitationAccepted,
        'list_invitation_declined' =>
          InAppNotificationType.listInvitationDeclined,
        'list_member_left' => InAppNotificationType.listMemberLeft,
        'list_member_removed' => InAppNotificationType.listMemberRemoved,
        'list_ownership_transferred' =>
          InAppNotificationType.listOwnershipTransferred,
        'list_item_assigned' => InAppNotificationType.listItemAssigned,
        'list_note_mentioned' => InAppNotificationType.listNoteMentioned,
        _ => throw const NotificationFailure(),
      };

  NotificationActionStatus _mapActionStatus(String status) => switch (status) {
        'actionable' => NotificationActionStatus.actionable,
        'friends' => NotificationActionStatus.friends,
        'accepted' => NotificationActionStatus.accepted,
        'unavailable' => NotificationActionStatus.unavailable,
        _ => throw const NotificationFailure(),
      };

  static const _notificationProjectionKeys = {
    'notification_id',
    'notification_type',
    'created_at',
    'is_read',
    'actor_profile_id',
    'actor_username',
    'actor_display_name',
    'action_status',
    'expected_relationship_version',
    'active_list_id',
    'active_list_title',
    'active_list_status',
    'expected_access_version',
    'active_list_item_id',
    'active_list_item_name',
    'assignment_item_version',
    'general_note_version',
  };
}
