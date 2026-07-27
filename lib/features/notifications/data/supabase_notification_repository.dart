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
          'list_notifications_v5',
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
      final response = await _rpc('get_unread_notification_count_v5');
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
      final isModeration =
          type == InAppNotificationType.publicTemplateTakenDown ||
              type == InAppNotificationType.publicTemplateRestored;
      final isTemplateSend = type == InAppNotificationType.templateSendReceived;
      final isListType = type != InAppNotificationType.friendRequest &&
          !isModeration &&
          !isTemplateSend;
      final activeListId = json['active_list_id'] as String?;
      final activeListTitle = json['active_list_title'] as String?;
      final activeListStatus = json['active_list_status'] as String?;
      final activeListItemId = json['active_list_item_id'] as String?;
      final activeListItemName = json['active_list_item_name'] as String?;
      final assignmentItemVersion = json['assignment_item_version'] as int?;
      final generalNoteVersion = json['general_note_version'] as int?;
      final actorProfileId = json['actor_profile_id'] as String?;
      final actorUsername = json['actor_username'] as String?;
      final actorDisplayName = json['actor_display_name'] as String?;
      final publicTemplateId = json['public_template_id'] as String?;
      final publicTemplateName = json['public_template_name'] as String?;
      final moderationReasonCode = json['moderation_reason_code'] as String?;
      final templateSendId = json['template_send_id'] as String?;
      final templateSendName = json['template_send_name'] as String?;
      final templateSendItemCount = json['template_send_item_count'] as int?;
      final expectedTemplateSendVersion =
          json['expected_template_send_version'] as int?;
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
          (isModeration !=
              (publicTemplateId != null &&
                  publicTemplateName != null &&
                  moderationReasonCode != null)) ||
          (isTemplateSend !=
              (templateSendId != null &&
                  templateSendName != null &&
                  templateSendItemCount != null)) ||
          (isTemplateSend &&
              (templateSendItemCount! < 0 ||
                  templateSendItemCount > 200 ||
                  templateSendName!.isEmpty ||
                  templateSendName.trim() != templateSendName ||
                  templateSendName.length > 120)) ||
          (!isTemplateSend &&
              (templateSendId != null ||
                  templateSendName != null ||
                  templateSendItemCount != null ||
                  expectedTemplateSendVersion != null)) ||
          ((isTemplateSend && status == NotificationActionStatus.actionable) !=
              (expectedTemplateSendVersion != null)) ||
          (expectedTemplateSendVersion != null &&
              expectedTemplateSendVersion <= 0) ||
          (isModeration !=
              (actorProfileId == null &&
                  actorUsername == null &&
                  actorDisplayName == null)) ||
          (!isModeration &&
              (actorProfileId == null ||
                  actorUsername == null ||
                  actorDisplayName == null)) ||
          (publicTemplateName != null &&
              (publicTemplateName.isEmpty ||
                  publicTemplateName.trim() != publicTemplateName ||
                  publicTemplateName.length > 120)) ||
          (moderationReasonCode != null &&
              !_moderationReasonCodes.contains(moderationReasonCode)) ||
          (activeListItemName != null &&
              (activeListItemName.isEmpty ||
                  activeListItemName.trim() != activeListItemName ||
                  activeListItemName.length > 120)) ||
          (type == InAppNotificationType.friendRequest &&
              status != NotificationActionStatus.actionable &&
              status != NotificationActionStatus.friends &&
              status != NotificationActionStatus.unavailable) ||
          (type == InAppNotificationType.listInvitation &&
              status != NotificationActionStatus.actionable &&
              status != NotificationActionStatus.accepted &&
              status != NotificationActionStatus.unavailable) ||
          (isTemplateSend &&
              status != NotificationActionStatus.actionable &&
              status != NotificationActionStatus.accepted &&
              status != NotificationActionStatus.declined &&
              status != NotificationActionStatus.revoked &&
              status != NotificationActionStatus.unavailable) ||
          (type != InAppNotificationType.friendRequest &&
              type != InAppNotificationType.listInvitation &&
              !isTemplateSend &&
              status != NotificationActionStatus.unavailable)) {
        throw const FormatException();
      }

      final createdAt = DateTime.parse(json['created_at']! as String);
      return InAppNotification(
        id: json['notification_id']! as String,
        type: type,
        createdAt: createdAt,
        isRead: json['is_read']! as bool,
        actorProfileId: actorProfileId,
        actorUsername: actorUsername,
        actorDisplayName: actorDisplayName,
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
        publicTemplateId: publicTemplateId,
        publicTemplateName: publicTemplateName,
        moderationReasonCode: moderationReasonCode,
        templateSendId: templateSendId,
        templateSendName: templateSendName,
        templateSendItemCount: templateSendItemCount,
        expectedTemplateSendVersion: expectedTemplateSendVersion,
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
        'public_template_taken_down' =>
          InAppNotificationType.publicTemplateTakenDown,
        'public_template_restored' =>
          InAppNotificationType.publicTemplateRestored,
        'template_send_received' => InAppNotificationType.templateSendReceived,
        _ => throw const NotificationFailure(),
      };

  NotificationActionStatus _mapActionStatus(String status) => switch (status) {
        'actionable' => NotificationActionStatus.actionable,
        'friends' => NotificationActionStatus.friends,
        'accepted' => NotificationActionStatus.accepted,
        'declined' => NotificationActionStatus.declined,
        'revoked' => NotificationActionStatus.revoked,
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
    'public_template_id',
    'public_template_name',
    'moderation_reason_code',
    'template_send_id',
    'template_send_name',
    'template_send_item_count',
    'expected_template_send_version',
  };

  static const _moderationReasonCodes = {
    'spam_scam_deceptive',
    'hate_harassment_bullying',
    'sexual_content',
    'violence_dangerous',
    'illegal_regulated',
    'personal_confidential_information',
    'copyright_trademark',
    'other',
  };
}
