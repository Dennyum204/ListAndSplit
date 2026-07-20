import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/presentation/blocked_users_controller.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/community/presentation/friendship_management_controller.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_centre_controller.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_controller.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

final resetSessionStateProvider = Provider<void Function()>((ref) {
  return () {
    ref.read(pendingVerificationEmailProvider.notifier).state = null;
    ref.read(completedPasswordRecoveryAttemptProvider.notifier).state = null;
    ref.read(notificationRefreshSignalProvider.notifier).state = 0;
    ref.read(friendshipManagementRefreshSignalProvider.notifier).state = 0;
    ref.read(communitySearchRefreshSignalProvider.notifier).state = 0;
    ref.read(activeListsRefreshSignalProvider.notifier).state = 0;
    ref.invalidate(ownProfileProvider);
    ref.invalidate(profileControllerProvider);
    ref.invalidate(accountDataExportControllerProvider);
    ref.invalidate(communitySearchControllerProvider);
    ref.invalidate(blockedUsersControllerProvider);
    ref.invalidate(friendshipManagementControllerProvider);
    ref.invalidate(activeListsControllerProvider);
    ref.invalidate(notificationUnreadCountControllerProvider);
    ref.invalidate(notificationCentreControllerProvider);
  };
});
