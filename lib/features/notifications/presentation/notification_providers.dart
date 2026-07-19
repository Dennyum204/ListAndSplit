import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/supabase/supabase_client_provider.dart';
import 'package:list_and_split/features/notifications/data/supabase_notification_repository.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => SupabaseNotificationRepository(ref.watch(supabaseClientProvider)),
);

final notificationRefreshSignalProvider = StateProvider<int>((ref) => 0);

final invalidateNotificationsProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(notificationRefreshSignalProvider.notifier).update(
          (revision) => revision + 1,
        );
  };
});
