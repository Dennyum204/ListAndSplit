import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
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

  test(
      'unavailable action reconciles automatically without fabricating success',
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
        const FriendshipFailure(FriendshipFailureCode.unavailable);
    await controller.load();

    expect(await controller.accept(actionable), isFalse);

    expect(notifications.listCalls, hasLength(2));
    expect(
      controller.state.notifications.valueOrNull!.single.actionStatus,
      NotificationActionStatus.unavailable,
    );
    expect(
      controller.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
    expect(controller.state.busyNotificationIds, isEmpty);
    expect(unreadRefreshes, 2);
    expect(managementInvalidations, 1);
    expect(searchInvalidations, 1);
  });

  test('generic action failure reports changed when reconciliation resolves it',
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
        const FriendshipFailure(FriendshipFailureCode.generic);
    await controller.load();

    expect(await controller.accept(actionable), isFalse);

    expect(
      controller.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
    expect(controller.state.busyNotificationIds, isEmpty);
  });

  test('generic action failure reports changed when the row disappears',
      () async {
    final actionable = notification(id: 'n-1');
    notifications.queuedPages.addAll([
      [actionable],
      const [],
    ]);
    friendships.mutationFailure =
        const FriendshipFailure(FriendshipFailureCode.generic);
    await controller.load();

    expect(await controller.accept(actionable), isFalse);

    expect(controller.state.notifications.valueOrNull, isEmpty);
    expect(
      controller.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
  });

  test('generic action failure reports changed for a newer actionable version',
      () async {
    final actionable = notification(id: 'n-1');
    notifications.queuedPages.addAll([
      [actionable],
      [notification(id: 'n-1', expectedVersion: 5)],
    ]);
    friendships.mutationFailure =
        const FriendshipFailure(FriendshipFailureCode.generic);
    await controller.load();

    expect(await controller.decline(actionable), isFalse);

    expect(
      controller
          .state.notifications.valueOrNull!.single.expectedRelationshipVersion,
      5,
    );
    expect(
      controller.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
  });

  test('generic action failure remains retryable when action is unchanged',
      () async {
    final actionable = notification(id: 'n-1');
    notifications.queuedPages.addAll([
      [actionable],
      [actionable],
    ]);
    friendships.mutationFailure =
        const FriendshipFailure(FriendshipFailureCode.generic);
    await controller.load();

    expect(await controller.decline(actionable), isFalse);

    expect(
      controller.state.notifications.valueOrNull!.single.actionStatus,
      NotificationActionStatus.actionable,
    );
    expect(
      controller.state.message,
      NotificationCentreMessage.operationFailed,
    );
    expect(controller.state.busyNotificationIds, isEmpty);
  });

  test('failed reconciliation clears busy state and keeps generic feedback',
      () async {
    final actionable = notification(id: 'n-1');
    notifications.notifications = [actionable];
    friendships.mutationFailure = StateError('transport failed');
    await controller.load();
    notifications.listFailure = const NotificationFailure();

    expect(await controller.accept(actionable), isFalse);

    expect(controller.state.busyNotificationIds, isEmpty);
    expect(
      controller.state.message,
      NotificationCentreMessage.operationFailed,
    );
    expect(unreadRefreshes, 2);
    expect(managementInvalidations, 1);
    expect(searchInvalidations, 1);
  });

  test('reconciliation refreshes unread count when marking read fails',
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
        const FriendshipFailure(FriendshipFailureCode.unavailable);
    await controller.load();
    notifications.markFailure = const NotificationFailure();

    expect(await controller.accept(actionable), isFalse);

    expect(unreadRefreshes, 2);
    expect(
      controller.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
    expect(controller.state.busyNotificationIds, isEmpty);
  });

  test('reconciliation preserves unrelated in-flight notification actions',
      () async {
    final first = notification(id: 'n-1');
    final second = InAppNotification(
      id: 'n-2',
      type: first.type,
      createdAt: first.createdAt.subtract(const Duration(minutes: 1)),
      isRead: first.isRead,
      actorProfileId: 'actor-2',
      actorUsername: 'beta_user',
      actorDisplayName: 'Beta User',
      actionStatus: NotificationActionStatus.actionable,
      expectedRelationshipVersion: 9,
    );
    notifications.queuedPages.addAll([
      [first, second],
      [
        notification(
          id: 'n-1',
          actionStatus: NotificationActionStatus.unavailable,
          expectedVersion: null,
        ),
        second,
      ],
      [
        notification(
          id: 'n-1',
          actionStatus: NotificationActionStatus.unavailable,
          expectedVersion: null,
        ),
        InAppNotification(
          id: second.id,
          type: second.type,
          createdAt: second.createdAt,
          isRead: true,
          actorProfileId: second.actorProfileId,
          actorUsername: second.actorUsername,
          actorDisplayName: second.actorDisplayName,
          actionStatus: NotificationActionStatus.unavailable,
          expectedRelationshipVersion: null,
        ),
      ],
    ]);
    final firstMutation = Completer<void>();
    final secondMutation = Completer<void>();
    friendships.queuedMutationCompleters.addAll([
      firstMutation,
      secondMutation,
    ]);
    await controller.load();

    final firstAction = controller.accept(first);
    final secondAction = controller.decline(second);
    expect(controller.state.busyNotificationIds, {'n-1', 'n-2'});

    firstMutation.completeError(
      const FriendshipFailure(FriendshipFailureCode.unavailable),
    );
    expect(await firstAction, isFalse);
    expect(controller.state.busyNotificationIds, {'n-2'});

    secondMutation.complete();
    expect(await secondAction, isTrue);
    expect(controller.state.busyNotificationIds, isEmpty);
    expect(notifications.listCalls, hasLength(3));
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

  test('list invitation accept uses exact access version and invalidates lists',
      () async {
    final actionable = listInvitation();
    notifications.queuedPages.addAll([
      [actionable],
      [
        listInvitation(
          actionStatus: NotificationActionStatus.accepted,
          expectedAccessVersion: null,
        ),
      ],
    ]);
    final lists = _NotificationListRepository();
    var listInvalidations = 0;
    final listController = NotificationCentreController(
      notifications,
      friendships,
      refreshUnreadCount: () async => unreadRefreshes += 1,
      activeListRepository: lists,
      invalidateLists: () => listInvalidations += 1,
    );
    addTearDown(listController.dispose);
    await listController.load();

    expect(await listController.accept(actionable), isTrue);

    expect(lists.acceptedVersion, 6);
    expect(lists.acceptedListId, 'list-1');
    expect(listInvalidations, 1);
    expect(listController.state.busyNotificationIds, isEmpty);
    expect(
      listController.state.message,
      NotificationCentreMessage.invitationAccepted,
    );
    expect(
      listController.state.notifications.requireValue.single.actionStatus,
      NotificationActionStatus.accepted,
    );
  });

  test('stale list invitation action refreshes instead of staying busy',
      () async {
    final actionable = listInvitation();
    notifications.queuedPages.addAll([
      [actionable],
      [
        listInvitation(
          actionStatus: NotificationActionStatus.unavailable,
          expectedAccessVersion: null,
        ),
      ],
    ]);
    final lists = _NotificationListRepository()
      ..mutationFailure = const ActiveListFailure(ActiveListFailureCode.stale);
    final listController = NotificationCentreController(
      notifications,
      friendships,
      refreshUnreadCount: () async {},
      activeListRepository: lists,
    );
    addTearDown(listController.dispose);
    await listController.load();

    expect(await listController.decline(actionable), isFalse);

    expect(lists.declinedVersion, 6);
    expect(listController.state.busyNotificationIds, isEmpty);
    expect(
      listController.state.message,
      NotificationCentreMessage.relationshipChanged,
    );
    expect(
      listController.state.notifications.requireValue.single.actionStatus,
      NotificationActionStatus.unavailable,
    );
  });

  test('malformed list invitation never reaches the list repository', () async {
    final lists = _NotificationListRepository();
    final listController = NotificationCentreController(
      notifications,
      friendships,
      refreshUnreadCount: () async {},
      activeListRepository: lists,
    );
    addTearDown(listController.dispose);

    expect(
      await listController.accept(
        listInvitation(expectedAccessVersion: null),
      ),
      isFalse,
    );
    expect(lists.mutationCalls, 0);
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

InAppNotification listInvitation({
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

class _NotificationListRepository extends FakeActiveListRepository {
  Object? mutationFailure;
  String? acceptedListId;
  int? acceptedVersion;
  int? declinedVersion;

  @override
  Future<int> acceptInvitation(
    String listId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    acceptedListId = listId;
    acceptedVersion = expectedAccessVersion;
    if (mutationFailure != null) throw mutationFailure!;
    return expectedAccessVersion + 1;
  }

  @override
  Future<int> declineInvitation(
    String listId, {
    required int expectedAccessVersion,
  }) async {
    mutationCalls += 1;
    declinedVersion = expectedAccessVersion;
    if (mutationFailure != null) throw mutationFailure!;
    return expectedAccessVersion + 1;
  }
}

Future<void> flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
