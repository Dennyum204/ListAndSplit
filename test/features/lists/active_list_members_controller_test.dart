import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/session_state_reset.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/presentation/active_list_members_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  test('owner loads accepted, pending, and eligible projections', () async {
    final repository = _membersRepository(isOwner: true);
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);

    await controller.load();

    final data = controller.state.data.requireValue;
    expect(data.summary.isOwner, isTrue);
    expect(data.participants.map((profile) => profile.profileId), [
      'owner-1',
      'member-1',
    ]);
    expect(data.pending.single.profileId, 'pending-1');
    expect(data.eligible.single.profileId, 'eligible-1');
  });

  test('member sees accepted participants but never loads owner-only data',
      () async {
    final repository = _CountingMembersRepository(isOwner: false);
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);

    await controller.load();

    final data = controller.state.data.requireValue;
    expect(data.summary.isOwner, isFalse);
    expect(data.participants, hasLength(2));
    expect(data.pending, isEmpty);
    expect(data.eligible, isEmpty);
    expect(repository.pendingCalls, 0);
    expect(repository.eligibleCalls, 0);
  });

  test('controller enforces owner-only membership management locally',
      () async {
    final repository = _membersRepository(isOwner: false);
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.invite(_eligible), isFalse);
    expect(await controller.cancel(_pending), isFalse);
    expect(await controller.remove(_member, 4), isFalse);
    expect(await controller.transferOwnership(_member), isFalse);
    expect(repository.mutationCalls, 0);
  });

  test('owner actions use exact versions, invalidate, and refresh', () async {
    final repository = _RecordingMembersRepository();
    var invalidations = 0;
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () => invalidations += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.invite(_eligible), isTrue);
    expect(controller.state.message, ActiveListMembersMessage.invited);
    expect(repository.lastInviteVersion, 8);

    expect(await controller.cancel(_pending), isTrue);
    expect(
      controller.state.message,
      ActiveListMembersMessage.invitationCancelled,
    );
    expect(repository.lastCancelVersion, 3);

    expect(await controller.remove(_member, 4), isTrue);
    expect(controller.state.message, ActiveListMembersMessage.memberRemoved);
    expect(repository.lastRemoveVersion, 4);
    expect(invalidations, 3);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('ownership transfer uses exact versions and refreshes every projection',
      () async {
    final repository = _RecordingMembersRepository();
    var listInvalidations = 0;
    var detailInvalidations = 0;
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () => listInvalidations += 1,
      invalidateDetail: () => detailInvalidations += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.transferOwnership(_member), isTrue);

    expect(repository.lastTransferListVersion, 2);
    expect(repository.lastTransferAccessVersion, 4);
    expect(controller.state.message,
        ActiveListMembersMessage.ownershipTransferred);
    expect(controller.state.data.requireValue.summary.isOwner, isFalse);
    expect(
      controller.state.data.requireValue.participants
          .singleWhere(
            (participant) => participant.isOwner,
          )
          .profileId,
      _member.profileId,
    );
    expect(listInvalidations, 1);
    expect(detailInvalidations, 1);
    expect(controller.state.busyProfileIds, isEmpty);
    expect(controller.state.transferringOwnership, isFalse);
  });

  test('lost transfer response reconciles committed authority as success',
      () async {
    final repository = _LostTransferResponseRepository();
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
      invalidateDetail: () {},
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.transferOwnership(_member), isTrue);

    expect(controller.state.message,
        ActiveListMembersMessage.ownershipTransferred);
    expect(controller.state.data.requireValue.summary.isOwner, isFalse);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('stale transfer reloads current authority without claiming success',
      () async {
    final repository = _FailTransferRepository(ActiveListFailureCode.stale);
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.transferOwnership(_member), isFalse);

    expect(controller.state.message, ActiveListMembersMessage.staleRefreshed);
    expect(controller.state.data.requireValue.summary.isOwner, isTrue);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('rapid transfer attempts and other owner actions cannot overlap',
      () async {
    final repository = _DelayedTransferRepository();
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);
    await controller.load();

    final first = controller.transferOwnership(_member);
    expect(controller.state.transferringOwnership, isTrue);
    expect(await controller.transferOwnership(_memberTwo), isFalse);
    expect(await controller.remove(_memberTwo, 5), isFalse);
    expect(repository.transferCalls, 1);

    repository.gate.complete();
    expect(await first, isTrue);
    expect(controller.state.transferringOwnership, isFalse);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('former-owner and new-owner devices reconcile roles independently',
      () async {
    final formerOwnerRepository = _membersRepository(isOwner: true);
    final newOwnerRepository = _membersRepository(isOwner: false);
    final formerOwnerController = ActiveListMembersController(
      formerOwnerRepository,
      'list-1',
      invalidateLists: () {},
    );
    final newOwnerController = ActiveListMembersController(
      newOwnerRepository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(formerOwnerController.dispose);
    addTearDown(newOwnerController.dispose);
    await Future.wait([
      formerOwnerController.load(),
      newOwnerController.load(),
    ]);

    final transferredParticipants = [_newOwner, _formerOwner];
    formerOwnerRepository
      ..activeLists = [_transferredSummary(isOwner: false)]
      ..participantsByList['list-1'] = transferredParticipants;
    newOwnerRepository
      ..activeLists = [_transferredSummary(isOwner: true)]
      ..participantsByList['list-1'] = transferredParticipants;

    await Future.wait([
      formerOwnerController.reconcile(),
      newOwnerController.reconcile(),
    ]);

    expect(
        formerOwnerController.state.data.requireValue.summary.isOwner, isFalse);
    expect(formerOwnerController.state.data.requireValue.pending, isEmpty);
    expect(newOwnerController.state.data.requireValue.summary.isOwner, isTrue);
    expect(newOwnerController.state.data.requireValue.pending, isNotEmpty);
  });

  test('manual member refresh remains authoritative after external change',
      () async {
    final repository = _membersRepository(isOwner: true);
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);
    await controller.load();
    repository.activeLists = [
      ActiveListSummary(
        id: 'list-1',
        title: 'Externally renamed',
        status: ActiveListStatus.active,
        version: 3,
        itemCount: 1,
        completedItemCount: 0,
        createdAt: DateTime.utc(2026, 7, 20, 8),
        updatedAt: DateTime.utc(2026, 7, 20, 10),
        archivedAt: null,
      ),
    ];

    await controller.load();

    expect(
        controller.state.data.requireValue.summary.title, 'Externally renamed');
  });

  for (final entry in {
    ActiveListFailureCode.capacity: ActiveListMembersMessage.capacityReached,
    ActiveListFailureCode.stale: ActiveListMembersMessage.staleRefreshed,
  }.entries) {
    test('${entry.key.name} invite reconciles to a truthful message', () async {
      final repository = _FailInviteOnceRepository(entry.key);
      final controller = ActiveListMembersController(
        repository,
        'list-1',
        invalidateLists: () {},
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(await controller.invite(_eligible), isFalse);

      expect(controller.state.message, entry.value);
      expect(controller.state.busyProfileIds, isEmpty);
      expect(controller.state.data.hasValue, isTrue);
    });
  }

  test('rapid duplicate and delayed invitation cannot leave controls busy',
      () async {
    final repository = _DelayedInviteRepository();
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
      requestTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(controller.dispose);
    await controller.load();

    final first = controller.invite(_eligible);
    expect(await controller.invite(_eligible), isFalse);
    expect(repository.inviteCalls, 1);
    expect(await first, isFalse);
    expect(controller.state.busyProfileIds, isEmpty);
    expect(
      controller.state.message,
      ActiveListMembersMessage.operationFailed,
    );

    repository.pending.complete(9);
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('Realtime revocation clears cached member content generically',
      () async {
    final repository = _membersRepository(isOwner: false);
    final controller = ActiveListMembersController(
      repository,
      'list-1',
      invalidateLists: () {},
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.state.data.hasValue, isTrue);

    repository.failure =
        const ActiveListFailure(ActiveListFailureCode.unavailable);
    await controller.reconcile();

    expect(controller.state.data.hasError, isTrue);
    expect(controller.state.data.valueOrNull, isNull);
    expect(controller.state.message, ActiveListMembersMessage.unavailable);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('session reset reconstructs list detail and membership state', () {
    final repository = _membersRepository(isOwner: true);
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(null),
        activeListRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final detailBefore = container.read(
      activeListDetailControllerProvider('list-1').notifier,
    );
    final membersBefore = container.read(
      activeListMembersControllerProvider('list-1').notifier,
    );

    container.read(resetSessionStateProvider)();

    expect(
      container.read(activeListDetailControllerProvider('list-1').notifier),
      isNot(same(detailBefore)),
    );
    expect(
      container.read(activeListMembersControllerProvider('list-1').notifier),
      isNot(same(membersBefore)),
    );
  });
}

FakeActiveListRepository _membersRepository({required bool isOwner}) {
  return FakeActiveListRepository()
    ..activeLists = [_summary(isOwner: isOwner)]
    ..participantsByList['list-1'] = [_owner, _member]
    ..pendingByList['list-1'] = [_pending]
    ..eligibleByList['list-1'] = [_eligible];
}

class _CountingMembersRepository extends FakeActiveListRepository {
  _CountingMembersRepository({required bool isOwner}) {
    activeLists = [_summary(isOwner: isOwner)];
    participantsByList['list-1'] = [_owner, _member];
    pendingByList['list-1'] = [_pending];
    eligibleByList['list-1'] = [_eligible];
  }

  var pendingCalls = 0;
  var eligibleCalls = 0;

  @override
  Future<List<ActiveListAccessProfile>> listPendingInvitations(String listId) {
    pendingCalls += 1;
    return super.listPendingInvitations(listId);
  }

  @override
  Future<List<ActiveListAccessProfile>> listEligibleInvitees(String listId) {
    eligibleCalls += 1;
    return super.listEligibleInvitees(listId);
  }
}

class _RecordingMembersRepository extends FakeActiveListRepository {
  _RecordingMembersRepository() {
    activeLists = [_summary(isOwner: true)];
    participantsByList['list-1'] = [_owner, _member];
    pendingByList['list-1'] = [_pending];
    eligibleByList['list-1'] = [_eligible];
  }

  int? lastInviteVersion;
  int? lastCancelVersion;
  int? lastRemoveVersion;
  int? lastTransferListVersion;
  int? lastTransferAccessVersion;

  @override
  Future<int> inviteMember(
    String listId,
    String profileId, {
    int? expectedAccessVersion,
  }) {
    lastInviteVersion = expectedAccessVersion;
    return super.inviteMember(
      listId,
      profileId,
      expectedAccessVersion: expectedAccessVersion,
    );
  }

  @override
  Future<int> cancelInvitation(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) {
    lastCancelVersion = expectedAccessVersion;
    return super.cancelInvitation(
      listId,
      profileId,
      expectedAccessVersion: expectedAccessVersion,
    );
  }

  @override
  Future<int> removeMember(
    String listId,
    String profileId, {
    required int expectedAccessVersion,
  }) {
    lastRemoveVersion = expectedAccessVersion;
    return super.removeMember(
      listId,
      profileId,
      expectedAccessVersion: expectedAccessVersion,
    );
  }

  @override
  Future<ActiveListOwnershipTransferResult> transferOwnership(
    String listId,
    String profileId, {
    required int expectedListVersion,
    required int expectedAccessVersion,
  }) {
    lastTransferListVersion = expectedListVersion;
    lastTransferAccessVersion = expectedAccessVersion;
    return super.transferOwnership(
      listId,
      profileId,
      expectedListVersion: expectedListVersion,
      expectedAccessVersion: expectedAccessVersion,
    );
  }
}

class _LostTransferResponseRepository extends _RecordingMembersRepository {
  @override
  Future<ActiveListOwnershipTransferResult> transferOwnership(
    String listId,
    String profileId, {
    required int expectedListVersion,
    required int expectedAccessVersion,
  }) async {
    await super.transferOwnership(
      listId,
      profileId,
      expectedListVersion: expectedListVersion,
      expectedAccessVersion: expectedAccessVersion,
    );
    throw const ActiveListFailure(ActiveListFailureCode.transport);
  }
}

class _FailTransferRepository extends _RecordingMembersRepository {
  _FailTransferRepository(this.code);

  final ActiveListFailureCode code;

  @override
  Future<ActiveListOwnershipTransferResult> transferOwnership(
    String listId,
    String profileId, {
    required int expectedListVersion,
    required int expectedAccessVersion,
  }) async {
    throw ActiveListFailure(code);
  }
}

class _DelayedTransferRepository extends _RecordingMembersRepository {
  _DelayedTransferRepository() {
    participantsByList['list-1'] = [_owner, _member, _memberTwo];
  }

  final gate = Completer<void>();
  var transferCalls = 0;

  @override
  Future<ActiveListOwnershipTransferResult> transferOwnership(
    String listId,
    String profileId, {
    required int expectedListVersion,
    required int expectedAccessVersion,
  }) async {
    transferCalls += 1;
    await gate.future;
    return super.transferOwnership(
      listId,
      profileId,
      expectedListVersion: expectedListVersion,
      expectedAccessVersion: expectedAccessVersion,
    );
  }
}

class _FailInviteOnceRepository extends _RecordingMembersRepository {
  _FailInviteOnceRepository(this.code);

  final ActiveListFailureCode code;
  var shouldFail = true;

  @override
  Future<int> inviteMember(
    String listId,
    String profileId, {
    int? expectedAccessVersion,
  }) async {
    if (shouldFail) {
      shouldFail = false;
      throw ActiveListFailure(code);
    }
    return super.inviteMember(
      listId,
      profileId,
      expectedAccessVersion: expectedAccessVersion,
    );
  }
}

class _DelayedInviteRepository extends _RecordingMembersRepository {
  final pending = Completer<int>();
  var inviteCalls = 0;

  @override
  Future<int> inviteMember(
    String listId,
    String profileId, {
    int? expectedAccessVersion,
  }) {
    inviteCalls += 1;
    return pending.future;
  }
}

ActiveListSummary _summary({required bool isOwner}) => ActiveListSummary(
      id: 'list-1',
      title: 'Shared trip',
      status: ActiveListStatus.active,
      version: 2,
      itemCount: 1,
      completedItemCount: 0,
      createdAt: DateTime.utc(2026, 7, 20, 8),
      updatedAt: DateTime.utc(2026, 7, 20, 9),
      archivedAt: null,
      isOwner: isOwner,
      ownerProfileId: isOwner ? null : 'owner-1',
      ownerUsername: isOwner ? null : 'owner_user',
      ownerDisplayName: isOwner ? null : 'Owner User',
      callerAccessVersion: isOwner ? null : 6,
    );

const _owner = ActiveListParticipant(
  profileId: 'owner-1',
  username: 'owner_user',
  displayName: 'Owner User',
  isOwner: true,
);
const _member = ActiveListParticipant(
  profileId: 'member-1',
  username: 'member_user',
  displayName: 'Member User',
  isOwner: false,
  accessVersion: 4,
);
const _memberTwo = ActiveListParticipant(
  profileId: 'member-2',
  username: 'member_two',
  displayName: 'Member Two',
  isOwner: false,
  accessVersion: 5,
);
const _newOwner = ActiveListParticipant(
  profileId: 'member-1',
  username: 'member_user',
  displayName: 'Member User',
  isOwner: true,
);
const _formerOwner = ActiveListParticipant(
  profileId: 'owner-1',
  username: 'owner_user',
  displayName: 'Owner User',
  isOwner: false,
  accessVersion: 1,
);
const _pending = ActiveListAccessProfile(
  profileId: 'pending-1',
  username: 'pending_user',
  displayName: 'Pending User',
  accessVersion: 3,
);
const _eligible = ActiveListAccessProfile(
  profileId: 'eligible-1',
  username: 'eligible_user',
  displayName: 'Eligible User',
  accessVersion: 8,
);

ActiveListSummary _transferredSummary({required bool isOwner}) =>
    ActiveListSummary(
      id: 'list-1',
      title: 'Shared trip',
      status: ActiveListStatus.active,
      version: 3,
      itemCount: 1,
      completedItemCount: 0,
      createdAt: DateTime.utc(2026, 7, 20, 8),
      updatedAt: DateTime.utc(2026, 7, 20, 10),
      archivedAt: null,
      isOwner: isOwner,
      ownerProfileId: isOwner ? null : 'member-1',
      ownerUsername: isOwner ? null : 'member_user',
      ownerDisplayName: isOwner ? null : 'Member User',
      callerAccessVersion: isOwner ? null : 1,
    );
