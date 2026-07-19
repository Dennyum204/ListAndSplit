import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/community_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

enum CommunitySearchMessage {
  notFoundOrUnavailable,
  blocked,
  requestSent,
  requestCancelled,
  requestAccepted,
  requestDeclined,
  relationshipChanged,
  operationFailed,
}

enum CommunitySearchAction { send, cancel, accept, decline }

class CommunitySearchState {
  const CommunitySearchState({
    this.isSearching = false,
    this.isBlocking = false,
    this.activeAction,
    this.usernameError,
    this.result,
    this.relationship,
    this.message,
  });

  final bool isSearching;
  final bool isBlocking;
  final CommunitySearchAction? activeAction;
  final ProfileValidationIssue? usernameError;
  final DiscoveredProfile? result;
  final FriendshipSummary? relationship;
  final CommunitySearchMessage? message;

  bool get isBusy => isSearching || isBlocking || activeAction != null;
}

class CommunitySearchController extends StateNotifier<CommunitySearchState> {
  CommunitySearchController(
    this._communityRepository,
    this._friendshipRepository, {
    void Function()? invalidateManagement,
    void Function()? invalidateNotifications,
  })  : _invalidateManagement = invalidateManagement ?? _noop,
        _invalidateNotifications = invalidateNotifications ?? _noop,
        super(const CommunitySearchState());

  final CommunityRepository _communityRepository;
  final FriendshipRepository _friendshipRepository;
  final void Function() _invalidateManagement;
  final void Function() _invalidateNotifications;
  bool _externalRefreshPending = false;

  void clearResultForEditedQuery() {
    if (!state.isBusy &&
        (state.result != null ||
            state.message != null ||
            state.usernameError != null)) {
      state = const CommunitySearchState();
    }
  }

  Future<bool> search(String username) async {
    if (state.isBusy) return false;
    final validationIssue = ProfileValidation.username(username);
    if (validationIssue != null) {
      state = CommunitySearchState(usernameError: validationIssue);
      return false;
    }

    state = const CommunitySearchState(isSearching: true);
    try {
      final result = await _communityRepository.findProfileByUsername(
        ProfileValidation.normalizeUsername(username),
      );
      if (!mounted) return false;
      if (result == null) {
        state = const CommunitySearchState(
          message: CommunitySearchMessage.notFoundOrUnavailable,
        );
        return false;
      }

      final relationship =
          await _friendshipRepository.getRelationshipSummary(result.id);
      if (!mounted) return false;
      _requireMatchingTarget(result, relationship);
      state = CommunitySearchState(
        result: result,
        relationship: relationship,
      );
      return true;
    } on FriendshipFailure catch (failure) {
      if (!mounted) return false;
      state = CommunitySearchState(message: _summaryFailureMessage(failure));
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = const CommunitySearchState(
        message: CommunitySearchMessage.operationFailed,
      );
      return false;
    }
  }

  Future<bool> refreshRelationshipSummary() async {
    final result = state.result;
    if (result == null || state.isBusy) return false;

    state = CommunitySearchState(
      isSearching: true,
      result: result,
      relationship: state.relationship,
    );
    try {
      final relationship =
          await _friendshipRepository.getRelationshipSummary(result.id);
      if (!mounted) return false;
      _requireMatchingTarget(result, relationship);
      state = CommunitySearchState(
        result: result,
        relationship: relationship,
      );
      return true;
    } on FriendshipFailure catch (failure) {
      if (!mounted) return false;
      state = CommunitySearchState(message: _summaryFailureMessage(failure));
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = const CommunitySearchState(
        message: CommunitySearchMessage.operationFailed,
      );
      return false;
    }
  }

  void handleFriendshipInvalidation() {
    _externalRefreshPending = true;
    _drainExternalRefresh();
  }

  Future<bool> sendFriendRequest() {
    final relationship = state.relationship;
    if (relationship == null ||
        relationship.status != FriendshipStatus.canSend) {
      return Future.value(false);
    }
    return _runRelationshipAction(
      action: CommunitySearchAction.send,
      successMessage: CommunitySearchMessage.requestSent,
      mutation: () => _friendshipRepository.sendFriendRequest(
        relationship.id,
        expectedVersion: relationship.version,
      ),
    );
  }

  Future<bool> cancelFriendRequest() {
    final relationship = state.relationship;
    if (relationship == null ||
        relationship.status != FriendshipStatus.outgoingPending ||
        relationship.version == null) {
      return Future.value(false);
    }
    return _runRelationshipAction(
      action: CommunitySearchAction.cancel,
      successMessage: CommunitySearchMessage.requestCancelled,
      mutation: () => _friendshipRepository.cancelFriendRequest(
        relationship.id,
        expectedVersion: relationship.version!,
      ),
    );
  }

  Future<bool> acceptFriendRequest() {
    final relationship = state.relationship;
    if (relationship == null ||
        relationship.status != FriendshipStatus.incomingPending ||
        relationship.version == null) {
      return Future.value(false);
    }
    return _runRelationshipAction(
      action: CommunitySearchAction.accept,
      successMessage: CommunitySearchMessage.requestAccepted,
      mutation: () => _friendshipRepository.acceptFriendRequest(
        relationship.id,
        expectedVersion: relationship.version!,
      ),
    );
  }

  Future<bool> declineFriendRequest() {
    final relationship = state.relationship;
    if (relationship == null ||
        relationship.status != FriendshipStatus.incomingPending ||
        relationship.version == null) {
      return Future.value(false);
    }
    return _runRelationshipAction(
      action: CommunitySearchAction.decline,
      successMessage: CommunitySearchMessage.requestDeclined,
      mutation: () => _friendshipRepository.declineFriendRequest(
        relationship.id,
        expectedVersion: relationship.version!,
      ),
    );
  }

  Future<bool> blockResult() async {
    final result = state.result;
    if (result == null || state.isBusy) return false;

    state = CommunitySearchState(
      isBlocking: true,
      result: result,
      relationship: state.relationship,
    );
    try {
      await _communityRepository.blockProfile(result.id);
      if (!mounted) return false;
      _invalidateManagement();
      _invalidateNotifications();
      state = const CommunitySearchState(
        message: CommunitySearchMessage.blocked,
      );
      return true;
    } catch (_) {
      if (!mounted) return false;
      _invalidateManagement();
      _invalidateNotifications();
      await _refreshAfterAction(
        result,
        successMessage: CommunitySearchMessage.operationFailed,
        failureMessage: CommunitySearchMessage.operationFailed,
      );
      return false;
    }
  }

  Future<bool> _runRelationshipAction({
    required CommunitySearchAction action,
    required CommunitySearchMessage successMessage,
    required Future<void> Function() mutation,
  }) async {
    final result = state.result;
    final relationship = state.relationship;
    if (result == null || relationship == null || state.isBusy) return false;

    state = CommunitySearchState(
      result: result,
      relationship: relationship,
      activeAction: action,
    );
    try {
      await mutation();
      if (!mounted) return false;
      _invalidateManagement();
      _invalidateNotifications();
      return _refreshAfterAction(
        result,
        successMessage: successMessage,
        failureMessage: CommunitySearchMessage.operationFailed,
      );
    } on FriendshipFailure catch (failure) {
      if (!mounted) return false;
      if (failure.code == FriendshipFailureCode.stale) {
        _invalidateManagement();
        _invalidateNotifications();
        await _refreshAfterAction(
          result,
          successMessage: CommunitySearchMessage.relationshipChanged,
          failureMessage: CommunitySearchMessage.operationFailed,
        );
        return false;
      }
      _invalidateManagement();
      _invalidateNotifications();
      await _refreshAfterAction(
        result,
        successMessage: CommunitySearchMessage.operationFailed,
        failureMessage: CommunitySearchMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (!mounted) return false;
      _invalidateManagement();
      _invalidateNotifications();
      await _refreshAfterAction(
        result,
        successMessage: CommunitySearchMessage.operationFailed,
        failureMessage: CommunitySearchMessage.operationFailed,
      );
      return false;
    }
  }

  Future<bool> _refreshAfterAction(
    DiscoveredProfile result, {
    required CommunitySearchMessage successMessage,
    required CommunitySearchMessage failureMessage,
  }) async {
    try {
      final relationship =
          await _friendshipRepository.getRelationshipSummary(result.id);
      if (!mounted) return false;
      _requireMatchingTarget(result, relationship);
      state = CommunitySearchState(
        result: result,
        relationship: relationship,
        message: successMessage,
      );
      _drainExternalRefresh();
      return true;
    } on FriendshipFailure catch (failure) {
      if (!mounted) return false;
      state = failure.code == FriendshipFailureCode.unavailable
          ? const CommunitySearchState(
              message: CommunitySearchMessage.notFoundOrUnavailable,
            )
          : CommunitySearchState(
              result: result,
              message: failureMessage,
            );
      _drainExternalRefresh();
      return false;
    } catch (_) {
      if (!mounted) return false;
      state = CommunitySearchState(
        result: result,
        message: failureMessage,
      );
      _drainExternalRefresh();
      return false;
    }
  }

  void _drainExternalRefresh() {
    if (!_externalRefreshPending || !mounted || state.isBusy) return;
    _externalRefreshPending = false;
    unawaited(_refreshFromInvalidation());
  }

  Future<void> _refreshFromInvalidation() async {
    await refreshRelationshipSummary();
    _drainExternalRefresh();
  }

  void _requireMatchingTarget(
    DiscoveredProfile result,
    FriendshipSummary relationship,
  ) {
    if (relationship.id != result.id) {
      throw const FriendshipFailure(FriendshipFailureCode.generic);
    }
  }

  CommunitySearchMessage _summaryFailureMessage(FriendshipFailure failure) =>
      failure.code == FriendshipFailureCode.unavailable
          ? CommunitySearchMessage.notFoundOrUnavailable
          : CommunitySearchMessage.operationFailed;

  static void _noop() {}
}

final communitySearchControllerProvider = StateNotifierProvider.autoDispose<
    CommunitySearchController, CommunitySearchState>((ref) {
  ref.watch(verifiedUserIdProvider);
  final controller = CommunitySearchController(
    ref.watch(communityRepositoryProvider),
    ref.watch(friendshipRepositoryProvider),
    invalidateManagement: ref.watch(invalidateFriendshipManagementProvider),
    invalidateNotifications: ref.watch(invalidateNotificationsProvider),
  );
  ref.listen<int>(communitySearchRefreshSignalProvider, (_, __) {
    controller.handleFriendshipInvalidation();
  });
  return controller;
});
