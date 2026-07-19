enum InAppNotificationType { friendRequest }

enum NotificationActionStatus { actionable, friends, unavailable }

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
  });

  final String id;
  final InAppNotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final String actorProfileId;
  final String actorUsername;
  final String actorDisplayName;
  final NotificationActionStatus actionStatus;
  final int? expectedRelationshipVersion;

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
    );
  }
}
