import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/domain/in_app_notification.dart';
import 'package:list_and_split/features/notifications/domain/notification_repository.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

const _notificationPageSize = 20;
const _keepNotificationMessage = Object();

enum NotificationCentreMessage {
  requestAccepted,
  requestDeclined,
  relationshipChanged,
  readUpdateFailed,
  operationFailed,
  invitationAccepted,
  invitationDeclined,
}

class NotificationCentreState {
  const NotificationCentreState({
    required this.notifications,
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.paginationFailed = false,
    this.busyNotificationIds = const {},
    this.message,
  });

  const NotificationCentreState.loading()
      : notifications = const AsyncLoading(),
        cursor = null,
        hasMore = false,
        isLoadingMore = false,
        paginationFailed = false,
        busyNotificationIds = const {},
        message = null;

  final AsyncValue<List<InAppNotification>> notifications;
  final NotificationCursor? cursor;
  final bool hasMore;
  final bool isLoadingMore;
  final bool paginationFailed;
  final Set<String> busyNotificationIds;
  final NotificationCentreMessage? message;

  bool isBusy(String notificationId) =>
      busyNotificationIds.contains(notificationId);

  NotificationCentreState copyWith({
    AsyncValue<List<InAppNotification>>? notifications,
    NotificationCursor? cursor,
    bool clearCursor = false,
    bool? hasMore,
    bool? isLoadingMore,
    bool? paginationFailed,
    Set<String>? busyNotificationIds,
    Object? message = _keepNotificationMessage,
  }) {
    return NotificationCentreState(
      notifications: notifications ?? this.notifications,
      cursor: clearCursor ? null : cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      paginationFailed: paginationFailed ?? this.paginationFailed,
      busyNotificationIds: busyNotificationIds ?? this.busyNotificationIds,
      message: identical(message, _keepNotificationMessage)
          ? this.message
          : message as NotificationCentreMessage?,
    );
  }
}

class NotificationUnreadCountController extends StateNotifier<AsyncValue<int>> {
  NotificationUnreadCountController(
    this._repository, {
    bool hasAuthenticatedUser = true,
  }) : super(
          hasAuthenticatedUser ? const AsyncLoading() : const AsyncData(0),
        );

  final NotificationRepository _repository;
  int _generation = 0;

  Future<void> load() async {
    final generation = ++_generation;
    state = const AsyncLoading();
    try {
      final count = await _repository.getUnreadCount();
      if (!mounted || generation != _generation) return;
      state = AsyncData(count);
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      state = AsyncError(error, stackTrace);
    }
  }

  Future<void> reconcile() async {
    final generation = ++_generation;
    try {
      final count = await _repository.getUnreadCount();
      if (!mounted || generation != _generation) return;
      state = AsyncData(count);
    } catch (_) {
      // Keep the last usable badge count on best-effort Realtime failure.
    }
  }
}

class NotificationCentreController
    extends StateNotifier<NotificationCentreState> {
  NotificationCentreController(
    this._notificationRepository,
    this._friendshipRepository, {
    required Future<void> Function() refreshUnreadCount,
    void Function()? invalidateFriendshipManagement,
    void Function()? invalidateCommunitySearch,
    ActiveListRepository? activeListRepository,
    ActiveListRepository Function()? readActiveListRepository,
    void Function()? invalidateLists,
  })  : _refreshUnreadCount = refreshUnreadCount,
        _invalidateFriendshipManagement =
            invalidateFriendshipManagement ?? _noop,
        _invalidateCommunitySearch = invalidateCommunitySearch ?? _noop,
        _readActiveListRepository = readActiveListRepository ??
            (activeListRepository == null ? null : () => activeListRepository),
        _invalidateLists = invalidateLists ?? _noop,
        super(const NotificationCentreState.loading());

  final NotificationRepository _notificationRepository;
  final FriendshipRepository _friendshipRepository;
  final Future<void> Function() _refreshUnreadCount;
  final void Function() _invalidateFriendshipManagement;
  final void Function() _invalidateCommunitySearch;
  final ActiveListRepository Function()? _readActiveListRepository;
  final void Function() _invalidateLists;
  int _loadGeneration = 0;
  bool _externalRefreshPending = false;

  Future<void> load() => _loadFirstPage();

  Future<void> refresh() => _loadFirstPage();

  Future<void> reconcile() => _loadFirstPage(background: true);

  void handleExternalRefresh() {
    if (state.busyNotificationIds.isNotEmpty || state.isLoadingMore) {
      _externalRefreshPending = true;
      return;
    }
    unawaited(reconcile());
  }

  Future<void> loadMore() async {
    final existing = state.notifications.valueOrNull;
    final cursor = state.cursor;
    if (existing == null ||
        cursor == null ||
        !state.hasMore ||
        state.isLoadingMore ||
        state.busyNotificationIds.isNotEmpty) {
      return;
    }

    final generation = _loadGeneration;
    state = state.copyWith(
      isLoadingMore: true,
      paginationFailed: false,
      message: null,
    );
    try {
      final page = await _notificationRepository.listNotifications(
        limit: _notificationPageSize,
        before: cursor,
      );
      if (!mounted || generation != _loadGeneration) return;

      final existingIds = existing.map((item) => item.id).toSet();
      final newItems = page
          .where((item) => existingIds.add(item.id))
          .toList(growable: false);
      state = state.copyWith(
        notifications: AsyncData([...existing, ...newItems]),
        cursor: page.isEmpty ? cursor : page.last.cursor,
        hasMore: page.length == _notificationPageSize,
        isLoadingMore: false,
        paginationFailed: false,
      );
      await _markDisplayedRead(
        newItems.map((item) => item.id).toList(growable: false),
        generation,
      );
      _drainExternalRefresh();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        isLoadingMore: false,
        paginationFailed: true,
      );
      _drainExternalRefresh();
    }
  }

  Future<bool> accept(InAppNotification notification) {
    if (notification.type == InAppNotificationType.listInvitation) {
      return _runListAction(
        notification,
        accept: true,
        successMessage: NotificationCentreMessage.invitationAccepted,
      );
    }
    return _runAction(
      notification,
      mutation: _friendshipRepository.acceptFriendRequest,
      successMessage: NotificationCentreMessage.requestAccepted,
    );
  }

  Future<bool> decline(InAppNotification notification) {
    if (notification.type == InAppNotificationType.listInvitation) {
      return _runListAction(
        notification,
        accept: false,
        successMessage: NotificationCentreMessage.invitationDeclined,
      );
    }
    return _runAction(
      notification,
      mutation: _friendshipRepository.declineFriendRequest,
      successMessage: NotificationCentreMessage.requestDeclined,
    );
  }

  Future<bool> _runListAction(
    InAppNotification notification, {
    required bool accept,
    required NotificationCentreMessage successMessage,
  }) async {
    final repository = _readActiveListRepository?.call();
    final listId = notification.activeListId;
    final version = notification.expectedAccessVersion;
    if (repository == null ||
        listId == null ||
        version == null ||
        notification.actionStatus != NotificationActionStatus.actionable ||
        state.isBusy(notification.id)) {
      return false;
    }
    state = state.copyWith(
      busyNotificationIds: {...state.busyNotificationIds, notification.id},
      message: null,
    );
    try {
      if (accept) {
        await repository.acceptInvitation(
          listId,
          expectedAccessVersion: version,
        );
      } else {
        await repository.declineInvitation(
          listId,
          expectedAccessVersion: version,
        );
      }
      if (!mounted) return false;
      _invalidateLists();
      state =
          state.copyWith(busyNotificationIds: _withoutBusy(notification.id));
      await _loadFirstPage(message: successMessage);
      return true;
    } on ActiveListFailure catch (failure) {
      if (!mounted) return false;
      _invalidateLists();
      await _reconcileActionFailure(
        notification,
        relationshipChanged: failure.code == ActiveListFailureCode.stale ||
            failure.code == ActiveListFailureCode.unavailable ||
            failure.code == ActiveListFailureCode.archived,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      _invalidateLists();
      await _reconcileActionFailure(notification, relationshipChanged: false);
      return false;
    }
  }

  Future<void> _loadFirstPage({
    NotificationCentreMessage? message,
    bool background = false,
  }) async {
    if (state.busyNotificationIds.isNotEmpty) {
      _externalRefreshPending = true;
      return;
    }

    _externalRefreshPending = false;
    final generation = ++_loadGeneration;
    final existing = state.notifications.valueOrNull;
    final previousMessage = state.message;
    if (!background || existing == null) {
      state = NotificationCentreState(
        notifications: const AsyncLoading(),
        message: message,
      );
    }
    try {
      final page = await _notificationRepository.listNotifications(
        limit: _notificationPageSize,
      );
      if (!mounted || generation != _loadGeneration) return;
      state = NotificationCentreState(
        notifications: AsyncData(page),
        cursor: page.isEmpty ? null : page.last.cursor,
        hasMore: page.length == _notificationPageSize,
        message: background ? previousMessage : message,
      );
      await _markDisplayedRead(
        page.map((item) => item.id).toList(growable: false),
        generation,
      );
      _drainExternalRefresh();
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      if (!background || existing == null) {
        state = NotificationCentreState(
          notifications: AsyncError(error, stackTrace),
          message: NotificationCentreMessage.operationFailed,
        );
        await _refreshUnreadCount();
      }
      _drainExternalRefresh();
    }
  }

  Future<void> _markDisplayedRead(
    List<String> notificationIds,
    int generation, {
    NotificationCentreMessage? failureMessage,
    bool refreshUnreadOnFailure = false,
  }) async {
    try {
      if (notificationIds.isEmpty) {
        await _refreshUnreadCount();
        return;
      }

      await _notificationRepository.markRead(notificationIds);
      if (!mounted || generation != _loadGeneration) return;
      final displayedIds = notificationIds.toSet();
      final current = state.notifications.valueOrNull;
      if (current != null) {
        state = state.copyWith(
          notifications: AsyncData(
            current
                .map(
                  (item) => displayedIds.contains(item.id)
                      ? item.copyWith(isRead: true)
                      : item,
                )
                .toList(growable: false),
          ),
        );
      }
      await _refreshUnreadCount();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        message: failureMessage ?? NotificationCentreMessage.readUpdateFailed,
      );
      if (refreshUnreadOnFailure) {
        try {
          await _refreshUnreadCount();
        } catch (_) {
          // Keep the action result stable when the independent badge refresh fails.
        }
      }
    }
  }

  Future<bool> _runAction(
    InAppNotification notification, {
    required Future<void> Function(
      String profileId, {
      required int expectedVersion,
    }) mutation,
    required NotificationCentreMessage successMessage,
  }) async {
    final version = notification.expectedRelationshipVersion;
    if (notification.actionStatus != NotificationActionStatus.actionable ||
        version == null ||
        state.isBusy(notification.id)) {
      return false;
    }

    state = state.copyWith(
      busyNotificationIds: {...state.busyNotificationIds, notification.id},
      message: null,
    );
    try {
      await mutation(
        notification.actorProfileId,
        expectedVersion: version,
      );
      if (!mounted) return false;
      _invalidateFriendshipState();
      state = state.copyWith(
        busyNotificationIds: _withoutBusy(notification.id),
      );
      await _loadFirstPage(message: successMessage);
      return true;
    } on FriendshipFailure catch (failure) {
      if (!mounted) return false;
      _invalidateFriendshipState();
      await _reconcileActionFailure(
        notification,
        relationshipChanged: failure.code == FriendshipFailureCode.stale ||
            failure.code == FriendshipFailureCode.unavailable,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      _invalidateFriendshipState();
      await _reconcileActionFailure(
        notification,
        relationshipChanged: false,
      );
      return false;
    }
  }

  Future<void> _reconcileActionFailure(
    InAppNotification original, {
    required bool relationshipChanged,
  }) async {
    _externalRefreshPending = false;
    final generation = ++_loadGeneration;
    final remainingBusy = _withoutBusy(original.id);
    state = state.copyWith(
      busyNotificationIds: remainingBusy,
      paginationFailed: false,
      message: null,
    );

    try {
      final page = await _notificationRepository.listNotifications(
        limit: _notificationPageSize,
      );
      if (!mounted || generation != _loadGeneration) return;

      InAppNotification? refreshed;
      for (final item in page) {
        if (item.id == original.id) {
          refreshed = item;
          break;
        }
      }
      final actionStillCurrent = refreshed != null &&
          refreshed.actionStatus == NotificationActionStatus.actionable &&
          refreshed.expectedRelationshipVersion ==
              original.expectedRelationshipVersion &&
          refreshed.expectedAccessVersion == original.expectedAccessVersion;
      final message = relationshipChanged || !actionStillCurrent
          ? NotificationCentreMessage.relationshipChanged
          : NotificationCentreMessage.operationFailed;
      state = NotificationCentreState(
        notifications: AsyncData(page),
        cursor: page.isEmpty ? null : page.last.cursor,
        hasMore: page.length == _notificationPageSize,
        busyNotificationIds: remainingBusy,
        message: message,
      );
      await _markDisplayedRead(
        page.map((item) => item.id).toList(growable: false),
        generation,
        failureMessage: message,
        refreshUnreadOnFailure: true,
      );
      _drainExternalRefresh();
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      state = state.copyWith(
        busyNotificationIds: remainingBusy,
        message: NotificationCentreMessage.operationFailed,
      );
      try {
        await _refreshUnreadCount();
      } catch (_) {
        // The generic action failure remains retryable even if badge refresh fails.
      }
      _drainExternalRefresh();
    }
  }

  Set<String> _withoutBusy(String notificationId) => {
        for (final id in state.busyNotificationIds)
          if (id != notificationId) id,
      };

  void _invalidateFriendshipState() {
    _invalidateFriendshipManagement();
    _invalidateCommunitySearch();
  }

  void _drainExternalRefresh() {
    if (!_externalRefreshPending ||
        !mounted ||
        state.busyNotificationIds.isNotEmpty ||
        state.isLoadingMore) {
      return;
    }
    _externalRefreshPending = false;
    unawaited(_loadFirstPage());
  }

  static void _noop() {}
}

final notificationUnreadCountControllerProvider = StateNotifierProvider
    .autoDispose<NotificationUnreadCountController, AsyncValue<int>>((ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  final controller = NotificationUnreadCountController(
    ref.watch(notificationRepositoryProvider),
    hasAuthenticatedUser: userId != null,
  );
  ref.listen<int>(notificationRefreshSignalProvider, (_, __) {
    if (userId != null) unawaited(controller.reconcile());
  });
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) {
    unawaited(controller.load());
  }
  return controller;
});

final notificationCentreControllerProvider = StateNotifierProvider.autoDispose<
    NotificationCentreController, NotificationCentreState>((ref) {
  final userId = ref.watch(verifiedUserIdProvider);
  final controller = NotificationCentreController(
    ref.watch(notificationRepositoryProvider),
    ref.watch(friendshipRepositoryProvider),
    refreshUnreadCount: () =>
        ref.read(notificationUnreadCountControllerProvider.notifier).load(),
    invalidateFriendshipManagement:
        ref.watch(invalidateFriendshipManagementProvider),
    invalidateCommunitySearch: ref.watch(invalidateCommunitySearchProvider),
    readActiveListRepository: () => ref.read(activeListRepositoryProvider),
    invalidateLists: ref.watch(invalidateActiveListsProvider),
  );
  ref.listen<int>(notificationRefreshSignalProvider, (_, __) {
    if (userId != null) controller.handleExternalRefresh();
  });
  registerForReconciliation(ref, controller.reconcile);
  if (userId != null) unawaited(controller.load());
  return controller;
});
