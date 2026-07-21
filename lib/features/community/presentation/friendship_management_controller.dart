import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

enum FriendshipManagementMessage {
  requestAccepted,
  requestDeclined,
  requestCancelled,
  friendshipEnded,
  blocked,
  relationshipChanged,
  operationFailed,
}

class FriendshipManagementState {
  const FriendshipManagementState({
    required this.relationships,
    this.busyProfileIds = const {},
    this.message,
  });

  const FriendshipManagementState.loading()
      : relationships = const AsyncLoading(),
        busyProfileIds = const {},
        message = null;

  final AsyncValue<List<FriendshipSummary>> relationships;
  final Set<String> busyProfileIds;
  final FriendshipManagementMessage? message;

  List<FriendshipSummary> get friends => _withStatus(FriendshipStatus.friends);

  List<FriendshipSummary> get incoming =>
      _withStatus(FriendshipStatus.incomingPending);

  List<FriendshipSummary> get sent =>
      _withStatus(FriendshipStatus.outgoingPending);

  bool isBusy(String profileId) => busyProfileIds.contains(profileId);

  List<FriendshipSummary> _withStatus(FriendshipStatus status) =>
      relationships.valueOrNull
          ?.where((relationship) => relationship.status == status)
          .toList(growable: false) ??
      const [];
}

class FriendshipManagementController
    extends StateNotifier<FriendshipManagementState> {
  FriendshipManagementController(
    this._friendshipRepository,
    this._communityRepository, {
    void Function()? invalidateSearch,
    void Function()? invalidateNotifications,
  })  : _invalidateSearch = invalidateSearch ?? _noop,
        _invalidateNotifications = invalidateNotifications ?? _noop,
        super(const FriendshipManagementState.loading());

  final FriendshipRepository _friendshipRepository;
  final CommunityRepository _communityRepository;
  final void Function() _invalidateSearch;
  final void Function() _invalidateNotifications;
  int _loadGeneration = 0;
  bool _externalRefreshPending = false;

  Future<void> load() async {
    final generation = ++_loadGeneration;
    state = FriendshipManagementState(
      relationships: const AsyncLoading(),
      busyProfileIds: state.busyProfileIds,
    );

    try {
      final relationships =
          await _friendshipRepository.listActiveRelationships();
      if (!mounted || generation != _loadGeneration) return;
      state = FriendshipManagementState(
        relationships: AsyncData(relationships),
        busyProfileIds: state.busyProfileIds,
      );
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      state = FriendshipManagementState(
        relationships: const AsyncError(
          FriendshipFailure(FriendshipFailureCode.generic),
          StackTrace.empty,
        ),
        busyProfileIds: state.busyProfileIds,
        message: FriendshipManagementMessage.operationFailed,
      );
    }
  }

  Future<void> reconcile() async {
    if (state.busyProfileIds.isNotEmpty) {
      _externalRefreshPending = true;
      return;
    }
    _externalRefreshPending = false;
    final generation = ++_loadGeneration;
    try {
      final relationships =
          await _friendshipRepository.listActiveRelationships();
      if (!mounted || generation != _loadGeneration) return;
      state = FriendshipManagementState(
        relationships: AsyncData(relationships),
        message: state.message,
      );
    } catch (_) {
      // Preserve the last usable projection on transient Realtime failure.
    }
  }

  Future<bool> accept(FriendshipSummary relationship) {
    return _runVersionedMutation(
      relationship,
      requiredStatus: FriendshipStatus.incomingPending,
      mutation: _friendshipRepository.acceptFriendRequest,
      successMessage: FriendshipManagementMessage.requestAccepted,
    );
  }

  Future<bool> decline(FriendshipSummary relationship) {
    return _runVersionedMutation(
      relationship,
      requiredStatus: FriendshipStatus.incomingPending,
      mutation: _friendshipRepository.declineFriendRequest,
      successMessage: FriendshipManagementMessage.requestDeclined,
    );
  }

  Future<bool> cancel(FriendshipSummary relationship) {
    return _runVersionedMutation(
      relationship,
      requiredStatus: FriendshipStatus.outgoingPending,
      mutation: _friendshipRepository.cancelFriendRequest,
      successMessage: FriendshipManagementMessage.requestCancelled,
    );
  }

  Future<bool> end(FriendshipSummary relationship) {
    return _runVersionedMutation(
      relationship,
      requiredStatus: FriendshipStatus.friends,
      mutation: _friendshipRepository.endFriendship,
      successMessage: FriendshipManagementMessage.friendshipEnded,
    );
  }

  Future<bool> block(FriendshipSummary relationship) async {
    if (!_startAction(relationship.id)) return false;

    try {
      await _communityRepository.blockProfile(relationship.id);
      if (!mounted) return false;
      _invalidateSearch();
      _invalidateNotifications();
      return _refreshAfterMutation(
        relationship.id,
        successMessage: FriendshipManagementMessage.blocked,
      );
    } catch (_) {
      if (!mounted) return false;
      _invalidateSearch();
      _invalidateNotifications();
      await _refreshAfterMutation(
        relationship.id,
        successMessage: FriendshipManagementMessage.operationFailed,
      );
      return false;
    }
  }

  Future<bool> _runVersionedMutation(
    FriendshipSummary relationship, {
    required FriendshipStatus requiredStatus,
    required Future<void> Function(
      String profileId, {
      required int expectedVersion,
    }) mutation,
    required FriendshipManagementMessage successMessage,
  }) async {
    final version = relationship.version;
    if (relationship.status != requiredStatus ||
        version == null ||
        !_startAction(relationship.id)) {
      return false;
    }

    try {
      await mutation(relationship.id, expectedVersion: version);
      if (!mounted) return false;
      _invalidateSearch();
      _invalidateNotifications();
      return _refreshAfterMutation(
        relationship.id,
        successMessage: successMessage,
      );
    } on FriendshipFailure catch (failure) {
      if (!mounted) return false;
      if (failure.code == FriendshipFailureCode.stale) {
        _invalidateSearch();
        _invalidateNotifications();
        await _refreshAfterMutation(
          relationship.id,
          successMessage: FriendshipManagementMessage.relationshipChanged,
        );
        return false;
      }
      _invalidateSearch();
      _invalidateNotifications();
      await _refreshAfterMutation(
        relationship.id,
        successMessage: FriendshipManagementMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      _invalidateSearch();
      _invalidateNotifications();
      await _refreshAfterMutation(
        relationship.id,
        successMessage: FriendshipManagementMessage.operationFailed,
      );
      return false;
    }
  }

  bool _startAction(String profileId) {
    if (state.isBusy(profileId)) return false;
    state = FriendshipManagementState(
      relationships: state.relationships,
      busyProfileIds: {...state.busyProfileIds, profileId},
    );
    return true;
  }

  Future<bool> _refreshAfterMutation(
    String profileId, {
    required FriendshipManagementMessage successMessage,
    FriendshipManagementMessage reportRefreshFailureAs =
        FriendshipManagementMessage.operationFailed,
  }) async {
    final generation = ++_loadGeneration;
    try {
      final relationships =
          await _friendshipRepository.listActiveRelationships();
      if (!mounted) return false;
      if (generation == _loadGeneration) {
        state = FriendshipManagementState(
          relationships: AsyncData(relationships),
          busyProfileIds: _withoutBusyProfile(profileId),
          message: successMessage,
        );
      } else {
        _finishAction(profileId, message: successMessage);
      }
      _externalRefreshPending = false;
      return true;
    } catch (_) {
      if (!mounted) return false;
      _finishAction(profileId, message: reportRefreshFailureAs);
      _drainExternalRefresh();
      return false;
    }
  }

  void _finishAction(
    String profileId, {
    required FriendshipManagementMessage message,
  }) {
    state = FriendshipManagementState(
      relationships: state.relationships,
      busyProfileIds: _withoutBusyProfile(profileId),
      message: message,
    );
  }

  Set<String> _withoutBusyProfile(String profileId) => {
        for (final busyProfileId in state.busyProfileIds)
          if (busyProfileId != profileId) busyProfileId,
      };

  void _drainExternalRefresh() {
    if (!_externalRefreshPending ||
        !mounted ||
        state.busyProfileIds.isNotEmpty) {
      return;
    }
    _externalRefreshPending = false;
    unawaited(reconcile());
  }

  static void _noop() {}
}

final friendshipManagementControllerProvider =
    StateNotifierProvider.autoDispose<FriendshipManagementController,
        FriendshipManagementState>((ref) {
  ref.watch(verifiedUserIdProvider);
  final controller = FriendshipManagementController(
    ref.watch(friendshipRepositoryProvider),
    ref.watch(communityRepositoryProvider),
    invalidateSearch: ref.watch(invalidateCommunitySearchProvider),
    invalidateNotifications: ref.watch(invalidateNotificationsProvider),
  );
  ref.listen<int>(friendshipManagementRefreshSignalProvider, (_, __) {
    unawaited(controller.reconcile());
  });
  registerForReconciliation(ref, controller.reconcile);
  unawaited(controller.load());
  return controller;
});
