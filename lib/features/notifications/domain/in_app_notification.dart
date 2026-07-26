enum InAppNotificationType {
  friendRequest,
  listInvitation,
  listInvitationAccepted,
  listInvitationDeclined,
  listMemberLeft,
  listMemberRemoved,
  listOwnershipTransferred,
  listItemAssigned,
  listNoteMentioned,
  publicTemplateTakenDown,
  publicTemplateRestored,
}

enum NotificationActionStatus { actionable, friends, accepted, unavailable }

class NotificationCursor {
  const NotificationCursor({required this.createdAt, required this.id});

  final DateTime createdAt;
  final String id;
}

class InAppNotification {
  const InAppNotification({
    required this.id,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.actorProfileId,
    required this.actorUsername,
    required this.actorDisplayName,
    required this.actionStatus,
    required this.expectedRelationshipVersion,
    this.activeListId,
    this.activeListTitle,
    this.activeListStatus,
    this.expectedAccessVersion,
    this.activeListItemId,
    this.activeListItemName,
    this.assignmentItemVersion,
    this.generalNoteVersion,
    this.publicTemplateId,
    this.publicTemplateName,
    this.moderationReasonCode,
  });

  final String id;
  final InAppNotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final String? actorProfileId;
  final String? actorUsername;
  final String? actorDisplayName;
  final NotificationActionStatus actionStatus;
  final int? expectedRelationshipVersion;
  final String? activeListId;
  final String? activeListTitle;
  final String? activeListStatus;
  final int? expectedAccessVersion;
  final String? activeListItemId;
  final String? activeListItemName;
  final int? assignmentItemVersion;
  final int? generalNoteVersion;
  final String? publicTemplateId;
  final String? publicTemplateName;
  final String? moderationReasonCode;

  NotificationCursor get cursor => NotificationCursor(
        createdAt: createdAt,
        id: id,
      );

  InAppNotification copyWith({bool? isRead}) {
    return InAppNotification(
      id: id,
      type: type,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      actorProfileId: actorProfileId,
      actorUsername: actorUsername,
      actorDisplayName: actorDisplayName,
      actionStatus: actionStatus,
      expectedRelationshipVersion: expectedRelationshipVersion,
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
    );
  }
}
