import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';

class NotificationFailure implements Exception {
  const NotificationFailure();
}

abstract interface class NotificationRepository {
  Future<List<InAppNotification>> listNotifications({
    required int limit,
    NotificationCursor? before,
  });

  Future<int> getUnreadCount();

  Future<void> markRead(List<String> notificationIds);
}
