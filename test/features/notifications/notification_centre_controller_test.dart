import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';
import 'package:list_and_split/features/notifications/presentation/notification_centre_controller.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import '../../helpers/fakes.dart';

final _testUserIdProvider = StateProvider<String?>((ref) => 'user-1');

void main() {
  late FakeNotificationRepository notifications;
  late FakeFriendshipRepository friendships;
  late int unreadRefreshes;
  late int managementInvalidations;
  late int searchInvalidations;
  late NotificationCentreController controller;

  setUp(() {
    notifications = FakeNotificationRepository();
    friendships = FakeFriendshipRepository();
    unreadRefreshes = 0;
    managementInvalidations = 0;
    searchInvalidations = 0;
    controller = NotificationCentreController(
      notifications,
      friendships,
      refreshUnreadCount: () async => unreadRefreshes += 1,
      invalidateFriendshipManagement: () => managementInvalidations += 1,
      invalidateCommunitySearch: () => searchInvalidations += 1,
    );
    addTearDown(controller.dispose);
  });

  test('initial load publishes, marks only displayed IDs, and reconciles badge',
      () async {
    notifications.notifications = [
      notification(id: 'n-1'),
      notification(id: 'n-2', isRead: true),
    ];

    await controller.load();

    expect(controller.state.notifications.valueOrNull, hasLength(2));
    expect(
      controller.state.notifications.valueOrNull!.every((item) => item.isRead),
      isTrue,
    );
    expect(notifications.listCalls.single.limit, 20);
    expect(notifications.listCalls.single.before, isNull);
    expect(notifications.markCalls.single, ['n-1', 'n-2']);
    expect(unreadRefreshes, 1);
    expect(controller.state.hasMore, isFalse);
  });

  test('empty and retryable initial failure states recover', () async {
    notifications.listFailure = const NotificationFailure();

    await controller.load();

    expect(controller.state.notifications.hasError, isTrue);
    expect(
      controller.state.message,
      NotificationCentreMessage.operationFailed,
    );

    notifications.listFailure = null;
    notifications.notifications = [];
    await controller.load();

    expect(controller.state.notifications.valueOrNull, isEmpty);
    expect(notifications.markCalls, isEmpty);
    expect(unreadRefreshes, 2);
  });

  test('pagination uses the last cursor and suppresses duplicate rows',
      () async {
    final firstPage = List.generate(
      20,
      (index) => notification(
        id: 'n-$index',
        createdAt:
            DateTime.utc(2026, 7, 19, 8, 0).subtract(Duration(minutes: index)),
      ),
    );
    notifications.queuedPages.addAll([
      firstPage,
      [firstPage.last, notification(id: 'n-20')],
    ]);

    await controller.load();
    await controller.loadMore();

    final values = controller.state.notifications.valueOrNull!;
    expect(values, hasLength(21));
    expect(values.map((item) => item.id).toSet(), hasLength(21));
    expect(notifications.listCalls[1].before!.id, 'n-19');
    expect(notifications.markCalls[0], hasLength(20));
    expect(notifications.markCalls[1], ['n-20']);
    expect(controller.state.hasMore, isFalse);
  });

  test('pagination failure keeps content and is retryable', () async {
    notifications.queuedPages.add(
      List.generate(20, (index) => notification(id: 'n-$index')),
    );
    await controller.load();
    notifications.listFailure = const NotificationFailure();

    await controller.loadMore();

    expect(controller.state.notifications.valueOrNull, hasLength(20));
    expect(controller.state.paginationFailed, isTrue);

    notifications.listFailure = null;
    notifications.notifications = [notification(id: 'n-20')];
    await controller.loadMore();

    expect(controller.state.notifications.valueOrNull, hasLength(21));
    expect(controller.state.paginationFailed, isFalse);
  });

  test('accept uses exact version, blocks duplicate taps, and refreshes state',
      () async {
    final actionable = notification(id: 'n-1');
    notifications.queuedPages.addAll([
      [actionable],
      [
        notification(
          id: 'n-1',
          actionStatus: NotificationActionStatus.friends,
          expectedVersion: null,
        ),
      ],
    ]);
    await controller.load();
    friendships.mutationCompleter = Completer<void>();

    final firstTap = controller.accept(actionable);
    final duplicateTap = await controller.accept(actionable);

    expect(duplicateTap, isFalse);
    expect(friendships.mutationCalls, hasLength(1));
    expect(friendships.mutationCalls.single.operation, 'accept');
    expect(friendships.mutationCalls.single.profileId, 'actor-1');
    expect(friendships.mutationCalls.single.expectedVersion, 4);

    friendships.mutationCompleter!.complete();
    expect(await firstTap, isTrue);
    expect(
      controller.state.notifications.valueOrNull!.single.actionStatus,
      NotificationActionStatus.friends,
    );
    expect(controller.state.message, NotificationCentreMessage.requestAccepted);
    expect(managementInvalidations, 1);
    expect(searchInvalidations, 1);
  });

  test('decline refreshes to privacy-safe unavailable state', () async {
    final actionable = notification(id: 'n-1');
    notifications.queuedPages.addAll([
      [actionable],
      [
        notification(
          id: 'n-1',
          actionStatus: NotificationActionStatus.unavailable,
          expectedVersion: null,
        ),
      ],
    ]);
    await controller.load();

    expect(await controller.decline(actionable), isTrue);

    expect(friendships.mutationCalls.single.operation, 'decline');
    expect(
      controller.state.notifications.valueOrNull!.single.actionStatus,
      NotificationActionStatus.unavailable,
    );
    expect(controller.state.message, NotificationCentreMessage.requestDeclined);
  });

  test('stale action never fabricates success and refreshes latest state',
      () async {
    final actionable = notification(id: 'n-1');
    notifications.queuedPages.addAll([
      [actionable],
      [
        notification(
          id: 'n-1',
          actionStatus: NotificationActionStatus.unavailable,
          expectedVersion: null,
        ),
      ],
    ]);
    friendships.mutationFailure =
        const FriendshipFailure(FriendshipFailureCode.stale);
    await controller.load();

    expect(await controller.accept(actionable), isFalse);

    expect(
      controller.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
    expect(
      controller.state.notifications.valueOrNull!.single.actionStatus,
      NotificationActionStatus.unavailable,
    );
    expect(managementInvalidations, 1);
    expect(searchInvalidations, 1);
  });

  test('nonactionable and malformed local actions never call friendship RPCs',
      () async {
    final resolved = notification(
      actionStatus: NotificationActionStatus.friends,
      expectedVersion: null,
    );

    expect(await controller.accept(resolved), isFalse);
    expect(await controller.decline(resolved), isFalse);
    expect(friendships.mutationCalls, isEmpty);
  });

  test('mark-read failure preserves unread UI and exposes retryable feedback',
      () async {
    notifications.notifications = [notification(id: 'n-1')];
    notifications.markFailure = const NotificationFailure();

    await controller.load();

    expect(controller.state.notifications.valueOrNull!.single.isRead, isFalse);
    expect(
      controller.state.message,
      NotificationCentreMessage.readUpdateFailed,
    );
    expect(unreadRefreshes, 0);
  });

  test('external refresh reloads an open centre', () async {
    notifications.notifications = [notification(id: 'n-1')];
    await controller.load();
    notifications.notifications = [notification(id: 'n-2')];

    controller.handleExternalRefresh();
    await flushAsync();

    expect(notifications.listCalls, hasLength(2));
    expect(controller.state.notifications.valueOrNull!.single.id, 'n-2');
  });

  test('unread controller exposes loading, data, and retryable error',
      () async {
    notifications.unreadCount = 7;
    final unread = NotificationUnreadCountController(notifications);
    addTearDown(unread.dispose);

    await unread.load();
    expect(unread.state.valueOrNull, 7);

    notifications.unreadFailure = const NotificationFailure();
    await unread.load();
    expect(unread.state.hasError, isTrue);
  });

  test('session replacement reconstructs providers and clears cached pages',
      () async {
    notifications.notifications = [notification(id: 'account-one')];
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWith(
          (ref) => ref.watch(_testUserIdProvider),
        ),
        notificationRepositoryProvider.overrideWithValue(notifications),
        friendshipRepositoryProvider.overrideWithValue(friendships),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      notificationCentreControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await flushAsync();
    final firstController =
        container.read(notificationCentreControllerProvider.notifier);
    expect(
      container
          .read(notificationCentreControllerProvider)
          .notifications
          .valueOrNull,
      isNotEmpty,
    );

    container.read(_testUserIdProvider.notifier).state = null;
    await flushAsync();
    final signedOutController =
        container.read(notificationCentreControllerProvider.notifier);

    expect(signedOutController, isNot(same(firstController)));
    expect(
      container
          .read(notificationCentreControllerProvider)
          .notifications
          .valueOrNull,
      isNull,
    );

    notifications.notifications = [notification(id: 'account-two')];
    container.read(_testUserIdProvider.notifier).state = 'user-2';
    await flushAsync();

    expect(
      container
          .read(notificationCentreControllerProvider)
          .notifications
          .valueOrNull!
          .single
          .id,
      'account-two',
    );
  });
}

InAppNotification notification({
  String id = 'n-1',
  DateTime? createdAt,
  bool isRead = false,
  NotificationActionStatus actionStatus = NotificationActionStatus.actionable,
  int? expectedVersion = 4,
}) {
  return InAppNotification(
    id: id,
    type: InAppNotificationType.friendRequest,
    createdAt: createdAt ?? DateTime.utc(2026, 7, 19, 8),
    isRead: isRead,
    actorProfileId: 'actor-1',
    actorUsername: 'alpha_user',
    actorDisplayName: 'Alpha User',
    actionStatus: actionStatus,
    expectedRelationshipVersion: expectedVersion,
  );
}

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
