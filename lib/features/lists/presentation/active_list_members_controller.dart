import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';

enum ActiveListMembersMessage {
  invited,
  invitationCancelled,
  memberRemoved,
  capacityReached,
  staleRefreshed,
  unavailable,
  operationFailed,
}

class ActiveListMembersData {
  ActiveListMembersData({
    required this.summary,
    required List<ActiveListParticipant> participants,
    required List<ActiveListAccessProfile> pending,
    required List<ActiveListAccessProfile> eligible,
  })  : participants = List.unmodifiable(participants),
        pending = List.unmodifiable(pending),
        eligible = List.unmodifiable(eligible);

  final ActiveListSummary summary;
  final List<ActiveListParticipant> participants;
  final List<ActiveListAccessProfile> pending;
  final List<ActiveListAccessProfile> eligible;
}

class ActiveListMembersState {
  const ActiveListMembersState({
    required this.data,
    this.busyProfileIds = const {},
    this.message,
  });

  const ActiveListMembersState.loading()
      : data = const AsyncLoading(),
        busyProfileIds = const {},
        message = null;

  final AsyncValue<ActiveListMembersData> data;
  final Set<String> busyProfileIds;
  final ActiveListMembersMessage? message;
}

class ActiveListMembersController
    extends StateNotifier<ActiveListMembersState> {
  ActiveListMembersController(
    this._repository,
    this.listId, {
    required void Function() invalidateLists,
    Duration requestTimeout = const Duration(seconds: 15),
  })  : _invalidateLists = invalidateLists,
        _requestTimeout = requestTimeout,
        assert(requestTimeout > Duration.zero),
        super(const ActiveListMembersState.loading());

  final ActiveListRepository _repository;
  final String listId;
  final void Function() _invalidateLists;
  final Duration _requestTimeout;
  int _generation = 0;
  bool _externalRefreshPending = false;

  Future<void> load({
    ActiveListMembersMessage? message,
    bool silentFailure = false,
  }) async {
    final generation = ++_generation;
    final existing = state.data.valueOrNull;
    if (existing == null) state = const ActiveListMembersState.loading();
    try {
      final summary =
          await _repository.getList(listId).timeout(_requestTimeout);
      final results = await Future.wait<Object>([
        _repository.listParticipants(listId),
        if (summary.isOwner) _repository.listPendingInvitations(listId),
        if (summary.isOwner) _repository.listEligibleInvitees(listId),
      ]).timeout(_requestTimeout);
      final participants = results[0] as List<ActiveListParticipant>;
      final pending = summary.isOwner
          ? results[1] as List<ActiveListAccessProfile>
          : const <ActiveListAccessProfile>[];
      final eligible = summary.isOwner
          ? results[2] as List<ActiveListAccessProfile>
          : const <ActiveListAccessProfile>[];
      if (!mounted || generation != _generation) return;
      state = ActiveListMembersState(
        data: AsyncData(
          ActiveListMembersData(
            summary: summary,
            participants: participants,
            pending: pending,
            eligible: eligible,
          ),
        ),
        message: message,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      final unavailable = error is ActiveListFailure &&
          error.code == ActiveListFailureCode.unavailable;
      state = ActiveListMembersState(
        data: existing == null || unavailable
            ? AsyncError(error, stackTrace)
            : AsyncData(existing),
        message: unavailable
            ? ActiveListMembersMessage.unavailable
            : silentFailure
                ? state.message
                : ActiveListMembersMessage.operationFailed,
      );
    }
  }

  Future<void> reconcile() async {
    if (state.busyProfileIds.isNotEmpty) {
      _externalRefreshPending = true;
      return;
    }
    _externalRefreshPending = false;
    await load(silentFailure: true);
  }

  Future<bool> invite(ActiveListAccessProfile profile) {
    final data = state.data.valueOrNull;
    if (data?.summary.isOwner != true ||
        !data!.eligible.any((entry) => entry.profileId == profile.profileId)) {
      return Future.value(false);
    }
    return _mutate(
      profile.profileId,
      () => _repository.inviteMember(
        listId,
        profile.profileId,
        expectedAccessVersion: profile.accessVersion,
      ),
      ActiveListMembersMessage.invited,
    );
  }

  Future<bool> cancel(ActiveListAccessProfile profile) {
    final data = state.data.valueOrNull;
    final version = profile.accessVersion;
    if (data?.summary.isOwner != true ||
        version == null ||
        !data!.pending.any((entry) => entry.profileId == profile.profileId)) {
      return Future.value(false);
    }
    return _mutate(
      profile.profileId,
      () => _repository.cancelInvitation(
        listId,
        profile.profileId,
        expectedAccessVersion: version,
      ),
      ActiveListMembersMessage.invitationCancelled,
    );
  }

  Future<bool> remove(
    ActiveListParticipant profile,
    int expectedAccessVersion,
  ) {
    final data = state.data.valueOrNull;
    if (data?.summary.isOwner != true ||
        profile.isOwner ||
        profile.accessVersion != expectedAccessVersion ||
        !data!.participants
            .any((entry) => entry.profileId == profile.profileId)) {
      return Future.value(false);
    }
    return _mutate(
      profile.profileId,
      () => _repository.removeMember(
        listId,
        profile.profileId,
        expectedAccessVersion: expectedAccessVersion,
      ),
      ActiveListMembersMessage.memberRemoved,
    );
  }

  Future<bool> _mutate(
    String profileId,
    Future<Object?> Function() operation,
    ActiveListMembersMessage success,
  ) async {
    if (state.busyProfileIds.contains(profileId)) return false;
    state = ActiveListMembersState(
      data: state.data,
      busyProfileIds: {...state.busyProfileIds, profileId},
    );
    try {
      await operation().timeout(_requestTimeout);
      if (!mounted) return false;
      _invalidateLists();
      state = ActiveListMembersState(data: state.data);
      _externalRefreshPending = false;
      await load(message: success);
      return true;
    } on ActiveListFailure catch (failure) {
      if (!mounted) return false;
      state = ActiveListMembersState(data: state.data);
      _externalRefreshPending = false;
      await load(
        message: failure.code == ActiveListFailureCode.capacity
            ? ActiveListMembersMessage.capacityReached
            : failure.code == ActiveListFailureCode.stale
                ? ActiveListMembersMessage.staleRefreshed
                : ActiveListMembersMessage.operationFailed,
      );
      return false;
    } catch (_) {
      if (mounted) {
        state = ActiveListMembersState(
          data: state.data,
          message: ActiveListMembersMessage.operationFailed,
        );
      }
      _drainExternalRefresh();
      return false;
    }
  }

  void _drainExternalRefresh() {
    if (!_externalRefreshPending ||
        !mounted ||
        state.busyProfileIds.isNotEmpty) {
      return;
    }
    _externalRefreshPending = false;
    unawaited(reconcile());
  }
}
