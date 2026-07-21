import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';
import 'package:list_and_split/features/notifications/presentation/notification_centre_screen.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';

void main() {
  for (final themeMode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('renders actionable content in ${themeMode.name} theme',
        (tester) async {
      final notifications = FakeNotificationRepository()
        ..notifications = [notification()];
      final friendships = FakeFriendshipRepository();
      await pumpCentre(
        tester,
        notifications: notifications,
        friendships: friendships,
        themeMode: themeMode,
      );

      expect(find.text('Alpha User sent you a friend request'), findsOneWidget);
      expect(find.text('@alpha_user'), findsOneWidget);
      expect(find.byKey(const Key('acceptNotification-n-1')), findsOneWidget);
      expect(find.byKey(const Key('declineNotification-n-1')), findsOneWidget);
      expect(notifications.markCalls, [
        ['n-1'],
      ]);

      await tester.pump();
      expect(notifications.markCalls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shows retryable failure and then the empty state',
      (tester) async {
    final notifications = FakeNotificationRepository()
      ..listFailure = const NotificationFailure();
    await pumpCentre(tester, notifications: notifications);

    expect(find.byKey(const Key('retryNotificationsButton')), findsOneWidget);
    notifications.listFailure = null;
    await tester.tap(find.byKey(const Key('retryNotificationsButton')));
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet'), findsOneWidget);
    expect(find.byKey(const Key('notificationsEmptyList')), findsOneWidget);
  });

  testWidgets('shows initial loading before content resolves', (tester) async {
    final completer = Completer<List<InAppNotification>>();
    final notifications = FakeNotificationRepository()
      ..listCompleter = completer;
    await pumpCentre(
      tester,
      notifications: notifications,
      settle: false,
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete([notification()]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-n-1')), findsOneWidget);
  });

  testWidgets('pull-to-refresh and application resume reload the centre',
      (tester) async {
    final notifications = FakeNotificationRepository();
    await pumpCentre(tester, notifications: notifications);
    expect(notifications.listCalls, hasLength(1));

    await tester.drag(
      find.byKey(const Key('notificationsEmptyList')),
      const Offset(0, 320),
    );
    await tester.pumpAndSettle();
    expect(notifications.listCalls, hasLength(2));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(notifications.listCalls, hasLength(3));
  });

  testWidgets('accept uses the exact version and refreshes the row',
      (tester) async {
    final notifications = FakeNotificationRepository()
      ..queuedPages.addAll([
        [notification()],
        [
          notification(
            actionStatus: NotificationActionStatus.friends,
            expectedVersion: null,
          ),
        ],
      ]);
    final friendships = FakeFriendshipRepository();
    await pumpCentre(
      tester,
      notifications: notifications,
      friendships: friendships,
    );

    await tester.tap(find.byKey(const Key('acceptNotification-n-1')));
    await tester.pumpAndSettle();

    expect(friendships.mutationCalls, hasLength(1));
    expect(friendships.mutationCalls.single.operation, 'accept');
    expect(friendships.mutationCalls.single.expectedVersion, 4);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Friend request accepted.'), findsOneWidget);
  });

  testWidgets('list invitation accepts through the list repository boundary',
      (tester) async {
    final notifications = FakeNotificationRepository()
      ..queuedPages.addAll([
        [listInvitationNotification()],
        [
          listInvitationNotification(
            actionStatus: NotificationActionStatus.accepted,
            expectedAccessVersion: null,
          ),
        ],
      ]);
    final lists = FakeActiveListRepository();
    await pumpCentre(
      tester,
      notifications: notifications,
      activeLists: lists,
    );

    expect(find.text('Invitation to Shared trip'), findsOneWidget);
    expect(
      find.byKey(const Key('acceptNotification-list-n-1')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('acceptNotification-list-n-1')));
    await tester.pumpAndSettle();

    expect(lists.mutationCalls, 1);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('List invitation accepted.'), findsOneWidget);
  });

  testWidgets('ownership transfer is informational and names the list',
      (tester) async {
    final notifications = FakeNotificationRepository()
      ..notifications = [ownershipTransferNotification()];
    await pumpCentre(tester, notifications: notifications);

    expect(find.text('You now own Shared trip'), findsOneWidget);
    expect(find.text('@owner_user'), findsOneWidget);
    expect(
      find.text('Ownership was transferred to you. You now control this list.'),
      findsOneWidget,
    );
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}

Future<void> pumpCentre(
  WidgetTester tester, {
  required FakeNotificationRepository notifications,
  FakeFriendshipRepository? friendships,
  FakeActiveListRepository? activeLists,
  ThemeMode themeMode = ThemeMode.light,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('user-1'),
        notificationRepositoryProvider.overrideWithValue(notifications),
        friendshipRepositoryProvider.overrideWithValue(
          friendships ?? FakeFriendshipRepository(),
        ),
        if (activeLists != null)
          activeListRepositoryProvider.overrideWithValue(activeLists),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const NotificationCentreScreen(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

InAppNotification notification({
  NotificationActionStatus actionStatus = NotificationActionStatus.actionable,
  int? expectedVersion = 4,
}) {
  return InAppNotification(
    id: 'n-1',
    type: InAppNotificationType.friendRequest,
    createdAt: DateTime.utc(2026, 7, 19, 8),
    isRead: false,
    actorProfileId: 'actor-1',
    actorUsername: 'alpha_user',
    actorDisplayName: 'Alpha User',
    actionStatus: actionStatus,
    expectedRelationshipVersion: expectedVersion,
  );
}

InAppNotification listInvitationNotification({
  NotificationActionStatus actionStatus = NotificationActionStatus.actionable,
  int? expectedAccessVersion = 6,
}) {
  return InAppNotification(
    id: 'list-n-1',
    type: InAppNotificationType.listInvitation,
    createdAt: DateTime.utc(2026, 7, 20, 8),
    isRead: false,
    actorProfileId: 'owner-1',
    actorUsername: 'owner_user',
    actorDisplayName: 'Owner User',
    actionStatus: actionStatus,
    expectedRelationshipVersion: null,
    activeListId: 'list-1',
    activeListTitle: 'Shared trip',
    activeListStatus: 'active',
    expectedAccessVersion: expectedAccessVersion,
  );
}

InAppNotification ownershipTransferNotification() {
  return InAppNotification(
    id: 'transfer-n-1',
    type: InAppNotificationType.listOwnershipTransferred,
    createdAt: DateTime.utc(2026, 7, 21, 9, 30),
    isRead: false,
    actorProfileId: 'owner-1',
    actorUsername: 'owner_user',
    actorDisplayName: 'Owner User',
    actionStatus: NotificationActionStatus.unavailable,
    expectedRelationshipVersion: null,
    activeListId: 'list-1',
    activeListTitle: 'Shared trip',
    activeListStatus: 'active',
  );
}
