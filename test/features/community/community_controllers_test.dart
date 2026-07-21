import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/blocked_users_controller.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/community/presentation/friendship_management_controller.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import '../../helpers/fakes.dart';

final _testVerifiedUserIdProvider = StateProvider<String?>((ref) => 'user-1');

void main() {
  late FakeCommunityRepository repository;
  late FakeFriendshipRepository friendshipRepository;

  const foundProfile = DiscoveredProfile(
    id: 'profile-2',
    username: 'beta_user',
    displayName: 'Beta User',
  );
  const blockedProfile = BlockedProfile(
    id: 'profile-2',
    username: 'beta_user',
    displayName: 'Beta User',
  );

  const canSendRelationship = FriendshipSummary(
    id: 'profile-2',
    username: 'beta_user',
    displayName: 'Beta User',
    status: FriendshipStatus.canSend,
    version: null,
    stateChangedAt: null,
  );
  const incomingRelationship = FriendshipSummary(
    id: 'profile-2',
    username: 'beta_user',
    displayName: 'Beta User',
    status: FriendshipStatus.incomingPending,
    version: 7,
    stateChangedAt: null,
  );
  const outgoingRelationship = FriendshipSummary(
    id: 'profile-3',
    username: 'gamma_user',
    displayName: 'Gamma User',
    status: FriendshipStatus.outgoingPending,
    version: 8,
    stateChangedAt: null,
  );
  const friendsRelationship = FriendshipSummary(
    id: 'profile-4',
    username: 'delta_user',
    displayName: 'Delta User',
    status: FriendshipStatus.friends,
    version: 9,
    stateChangedAt: null,
  );

  setUp(() {
    repository = FakeCommunityRepository();
    friendshipRepository = FakeFriendshipRepository()
      ..summaryResult = canSendRelationship;
  });

  test('search validates locally and sends the canonical exact username',
      () async {
    final controller =
        CommunitySearchController(repository, friendshipRepository);
    addTearDown(controller.dispose);

    expect(await controller.search('1 invalid'), isFalse);
    expect(
      controller.state.usernameError,
      ProfileValidationIssue.usernameInvalid,
    );
    expect(repository.searchCalls, 0);

    repository.searchResult = foundProfile;
    expect(await controller.search('  BETA_USER  '), isTrue);
    expect(repository.lastUsername, 'beta_user');
    expect(controller.state.result?.id, 'profile-2');
  });

  test('search keeps missing and backend outcomes privacy-safe', () async {
    final controller =
        CommunitySearchController(repository, friendshipRepository);
    addTearDown(controller.dispose);

    expect(await controller.search('missing_user'), isFalse);
    expect(
      controller.state.message,
      CommunitySearchMessage.notFoundOrUnavailable,
    );

    repository.searchFailure = StateError('database details');
    expect(await controller.search('missing_user'), isFalse);
    expect(controller.state.message, CommunitySearchMessage.operationFailed);

    repository.searchFailure = null;
    repository.searchResult = foundProfile;
    expect(await controller.search('beta_user'), isTrue);
    expect(controller.state.result?.id, 'profile-2');
  });

  test('search exposes loading state until the deliberate request completes',
      () async {
    repository.searchCompleter = Completer<DiscoveredProfile?>();
    final controller =
        CommunitySearchController(repository, friendshipRepository);
    addTearDown(controller.dispose);

    final pendingSearch = controller.search('beta_user');
    expect(controller.state.isSearching, isTrue);
    expect(repository.searchCalls, 1);

    repository.searchCompleter!.complete(foundProfile);
    expect(await pendingSearch, isTrue);
    expect(controller.state.isSearching, isFalse);
  });

  test('a late search result is ignored after session state is disposed',
      () async {
    repository.searchCompleter = Completer<DiscoveredProfile?>();
    final controller =
        CommunitySearchController(repository, friendshipRepository);

    final pendingSearch = controller.search('beta_user');
    controller.dispose();
    repository.searchCompleter!.complete(foundProfile);

    expect(await pendingSearch, isFalse);
  });

  test('successful block clears the result while a failed block is retryable',
      () async {
    repository.searchResult = foundProfile;
    final controller =
        CommunitySearchController(repository, friendshipRepository);
    addTearDown(controller.dispose);
    await controller.search('beta_user');

    repository.blockFailure = StateError('offline');
    expect(await controller.blockResult(), isFalse);
    expect(controller.state.result?.id, 'profile-2');
    expect(controller.state.message, CommunitySearchMessage.operationFailed);

    repository.blockFailure = null;
    expect(await controller.blockResult(), isTrue);
    expect(repository.lastBlockedProfileId, 'profile-2');
    expect(controller.state.result, isNull);
    expect(controller.state.message, CommunitySearchMessage.blocked);
  });

  test('search loads the relationship summary after exact discovery', () async {
    repository.searchResult = foundProfile;
    friendshipRepository.summaryResult = incomingRelationship;
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);

    expect(await controller.search('beta_user'), isTrue);

    expect(friendshipRepository.summaryCalls, 1);
    expect(friendshipRepository.lastSummaryProfileId, 'profile-2');
    expect(controller.state.relationship, same(incomingRelationship));
  });

  test('search clears discovery when the summary becomes unavailable',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository.summaryFailure =
        const FriendshipFailure(FriendshipFailureCode.unavailable);
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);

    expect(await controller.search('beta_user'), isFalse);

    expect(controller.state.result, isNull);
    expect(controller.state.relationship, isNull);
    expect(
      controller.state.message,
      CommunitySearchMessage.notFoundOrUnavailable,
    );
  });

  test('search keeps a summary backend failure generic', () async {
    repository.searchResult = foundProfile;
    friendshipRepository.summaryFailure = StateError('private backend details');
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);

    expect(await controller.search('beta_user'), isFalse);

    expect(controller.state.result, isNull);
    expect(controller.state.relationship, isNull);
    expect(controller.state.message, CommunitySearchMessage.operationFailed);
  });

  test('external refresh removes a result that became unavailable', () async {
    repository.searchResult = foundProfile;
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');

    friendshipRepository.summaryFailure =
        const FriendshipFailure(FriendshipFailureCode.unavailable);
    controller.handleFriendshipInvalidation();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.result, isNull);
    expect(controller.state.relationship, isNull);
    expect(
      controller.state.message,
      CommunitySearchMessage.notFoundOrUnavailable,
    );
  });

  test('search rejects a relationship summary for a different target',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository.summaryResult = outgoingRelationship;
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);

    expect(await controller.search('beta_user'), isFalse);

    expect(controller.state.result, isNull);
    expect(controller.state.relationship, isNull);
    expect(controller.state.message, CommunitySearchMessage.operationFailed);
  });

  test('search sends the displayed nullable version and refetches crossed send',
      () async {
    repository.searchResult = foundProfile;
    var managementInvalidations = 0;
    var notificationInvalidations = 0;
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
      invalidateManagement: () => managementInvalidations += 1,
      invalidateNotifications: () => notificationInvalidations += 1,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');

    friendshipRepository.mutationCompleter = Completer<void>();
    final pendingSend = controller.sendFriendRequest();
    expect(controller.state.activeAction, CommunitySearchAction.send);
    expect(friendshipRepository.mutationCalls.single.operation, 'send');
    expect(friendshipRepository.mutationCalls.single.expectedVersion, isNull);

    friendshipRepository.summaryResult = const FriendshipSummary(
      id: 'profile-2',
      username: 'beta_user',
      displayName: 'Beta User',
      status: FriendshipStatus.friends,
      version: 1,
      stateChangedAt: null,
    );
    friendshipRepository.mutationCompleter!.complete();

    expect(await pendingSend, isTrue);
    expect(controller.state.relationship?.status, FriendshipStatus.friends);
    expect(controller.state.message, CommunitySearchMessage.requestSent);
    expect(friendshipRepository.summaryCalls, 2);
    expect(managementInvalidations, 1);
    expect(notificationInvalidations, 1);
  });

  test('search actions use exact displayed versions and refresh each result',
      () async {
    const cases = <({
      FriendshipStatus status,
      int version,
      String operation,
    })>[
      (
        status: FriendshipStatus.outgoingPending,
        version: 12,
        operation: 'cancel',
      ),
      (
        status: FriendshipStatus.incomingPending,
        version: 13,
        operation: 'accept',
      ),
      (
        status: FriendshipStatus.incomingPending,
        version: 14,
        operation: 'decline',
      ),
    ];

    for (final testCase in cases) {
      final community = FakeCommunityRepository()..searchResult = foundProfile;
      final friendships = FakeFriendshipRepository()
        ..summaryResult = FriendshipSummary(
          id: 'profile-2',
          username: 'beta_user',
          displayName: 'Beta User',
          status: testCase.status,
          version: testCase.version,
          stateChangedAt: null,
        );
      final controller = CommunitySearchController(community, friendships);
      addTearDown(controller.dispose);
      await controller.search('beta_user');

      final succeeded = switch (testCase.operation) {
        'cancel' => await controller.cancelFriendRequest(),
        'accept' => await controller.acceptFriendRequest(),
        'decline' => await controller.declineFriendRequest(),
        _ => false,
      };

      expect(succeeded, isTrue);
      expect(friendships.mutationCalls.single.operation, testCase.operation);
      expect(
        friendships.mutationCalls.single.expectedVersion,
        testCase.version,
      );
      expect(friendships.summaryCalls, 2);
    }
  });

  test('post-action refresh removes a result that became unavailable',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository.summaryResult = incomingRelationship;
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');

    friendshipRepository.summaryFailure =
        const FriendshipFailure(FriendshipFailureCode.unavailable);

    expect(await controller.acceptFriendRequest(), isFalse);
    expect(controller.state.result, isNull);
    expect(controller.state.relationship, isNull);
    expect(
      controller.state.message,
      CommunitySearchMessage.notFoundOrUnavailable,
    );
  });

  test(
      'search distinguishes a stale mutation, refreshes, and remains retryable',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository
      ..summaryResult = incomingRelationship
      ..mutationFailure = const FriendshipFailure(FriendshipFailureCode.stale);
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');

    expect(await controller.acceptFriendRequest(), isFalse);

    expect(
        controller.state.message, CommunitySearchMessage.relationshipChanged);
    expect(controller.state.relationship, same(incomingRelationship));
    expect(friendshipRepository.summaryCalls, 2);
    expect(controller.state.isBusy, isFalse);
  });

  test('search reports failure when a stale-state refresh also fails',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository
      ..summaryResult = incomingRelationship
      ..mutationFailure = const FriendshipFailure(FriendshipFailureCode.stale);
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');
    friendshipRepository.summaryFailure = StateError('offline');

    expect(await controller.acceptFriendRequest(), isFalse);

    expect(controller.state.message, CommunitySearchMessage.operationFailed);
    expect(controller.state.result, foundProfile);
    expect(controller.state.relationship, isNull);
    expect(controller.state.isBusy, isFalse);
  });

  test('search queues an external refresh received while an action is busy',
      () async {
    repository.searchResult = foundProfile;
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');
    friendshipRepository.mutationCompleter = Completer<void>();

    final pendingSend = controller.sendFriendRequest();
    controller.handleFriendshipInvalidation();
    expect(friendshipRepository.summaryCalls, 1);

    friendshipRepository.summaryResult = const FriendshipSummary(
      id: 'profile-2',
      username: 'beta_user',
      displayName: 'Beta User',
      status: FriendshipStatus.outgoingPending,
      version: 1,
      stateChangedAt: null,
    );
    friendshipRepository.mutationCompleter!.complete();
    await pendingSend;
    await Future<void>.delayed(Duration.zero);

    expect(friendshipRepository.summaryCalls, 3);
    expect(controller.state.relationship?.version, 1);
  });

  test('search maps generic mutation failures without exposing backend details',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository
      ..summaryResult = incomingRelationship
      ..mutationFailure = StateError('private database details');
    final controller = CommunitySearchController(
      repository,
      friendshipRepository,
    );
    addTearDown(controller.dispose);
    await controller.search('beta_user');

    expect(await controller.declineFriendRequest(), isFalse);

    expect(controller.state.message, CommunitySearchMessage.operationFailed);
    expect(controller.state.relationship, same(incomingRelationship));
    expect(controller.state.isBusy, isFalse);
    expect(friendshipRepository.summaryCalls, 2);
  });

  test('friendship management groups the authoritative active list', () async {
    friendshipRepository.activeRelationships = [
      incomingRelationship,
      outgoingRelationship,
      friendsRelationship,
    ];
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.state.incoming, [incomingRelationship]);
    expect(controller.state.sent, [outgoingRelationship]);
    expect(controller.state.friends, [friendsRelationship]);
  });

  test('friendship management mutations pass each displayed version', () async {
    const secondIncoming = FriendshipSummary(
      id: 'profile-5',
      username: 'epsilon_user',
      displayName: 'Epsilon User',
      status: FriendshipStatus.incomingPending,
      version: 10,
      stateChangedAt: null,
    );
    friendshipRepository.activeRelationships = [
      incomingRelationship,
      secondIncoming,
      outgoingRelationship,
      friendsRelationship,
    ];
    var searchInvalidations = 0;
    var notificationInvalidations = 0;
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
      invalidateSearch: () => searchInvalidations += 1,
      invalidateNotifications: () => notificationInvalidations += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.accept(incomingRelationship), isTrue);
    expect(await controller.decline(secondIncoming), isTrue);
    expect(await controller.cancel(outgoingRelationship), isTrue);
    expect(await controller.end(friendsRelationship), isTrue);

    expect(
      friendshipRepository.mutationCalls
          .map((call) => (call.operation, call.expectedVersion)),
      [('accept', 7), ('decline', 10), ('cancel', 8), ('end', 9)],
    );
    expect(friendshipRepository.friendshipListCalls, 5);
    expect(searchInvalidations, 4);
    expect(notificationInvalidations, 4);
  });

  test('friendship management busy protection is keyed by profile', () async {
    friendshipRepository.activeRelationships = [
      incomingRelationship,
      outgoingRelationship,
    ];
    friendshipRepository.mutationCompleter = Completer<void>();
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
    );
    addTearDown(controller.dispose);
    await controller.load();

    final pendingAccept = controller.accept(incomingRelationship);
    expect(controller.state.isBusy('profile-2'), isTrue);
    expect(await controller.accept(incomingRelationship), isFalse);

    final pendingCancel = controller.cancel(outgoingRelationship);
    expect(controller.state.isBusy('profile-3'), isTrue);
    expect(friendshipRepository.mutationCalls, hasLength(2));

    friendshipRepository.mutationCompleter!.complete();
    expect(await pendingAccept, isTrue);
    expect(await pendingCancel, isTrue);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('friendship management refreshes stale data with a distinct message',
      () async {
    friendshipRepository
      ..activeRelationships = [incomingRelationship]
      ..mutationFailure = const FriendshipFailure(FriendshipFailureCode.stale);
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.accept(incomingRelationship), isFalse);

    expect(
      controller.state.message,
      FriendshipManagementMessage.relationshipChanged,
    );
    expect(friendshipRepository.friendshipListCalls, 2);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('management reports failure when a stale-state refresh also fails',
      () async {
    friendshipRepository
      ..activeRelationships = [incomingRelationship]
      ..mutationFailure = const FriendshipFailure(FriendshipFailureCode.stale);
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
    );
    addTearDown(controller.dispose);
    await controller.load();
    friendshipRepository.listFailure = StateError('offline');

    expect(await controller.accept(incomingRelationship), isFalse);

    expect(
      controller.state.message,
      FriendshipManagementMessage.operationFailed,
    );
    expect(controller.state.relationships.valueOrNull, [incomingRelationship]);
    expect(controller.state.busyProfileIds, isEmpty);
  });

  test('friendship management keeps generic failures private and retryable',
      () async {
    friendshipRepository
      ..activeRelationships = [incomingRelationship]
      ..mutationFailure = StateError('private database details');
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.accept(incomingRelationship), isFalse);

    expect(
      controller.state.message,
      FriendshipManagementMessage.operationFailed,
    );
    expect(controller.state.relationships.valueOrNull, [incomingRelationship]);
    expect(controller.state.busyProfileIds, isEmpty);
    expect(friendshipRepository.friendshipListCalls, 2);
  });

  test('friendship management block refetches and invalidates exact search',
      () async {
    friendshipRepository.queuedRelationshipLists.addAll([
      [friendsRelationship],
      [],
    ]);
    var searchInvalidations = 0;
    var notificationInvalidations = 0;
    final controller = FriendshipManagementController(
      friendshipRepository,
      repository,
      invalidateSearch: () => searchInvalidations += 1,
      invalidateNotifications: () => notificationInvalidations += 1,
    );
    addTearDown(controller.dispose);
    await controller.load();

    expect(await controller.block(friendsRelationship), isTrue);

    expect(repository.lastBlockedProfileId, 'profile-4');
    expect(controller.state.relationships.valueOrNull, isEmpty);
    expect(controller.state.message, FriendshipManagementMessage.blocked);
    expect(searchInvalidations, 1);
    expect(notificationInvalidations, 1);
  });

  test('friendship controllers ignore late completions after disposal',
      () async {
    friendshipRepository.friendshipListCompleter =
        Completer<List<FriendshipSummary>>();
    final management = FriendshipManagementController(
      friendshipRepository,
      repository,
    );
    final pendingLoad = management.load();
    management.dispose();
    friendshipRepository.friendshipListCompleter!.complete([
      friendsRelationship,
    ]);
    await pendingLoad;

    repository.searchResult = foundProfile;
    friendshipRepository
      ..friendshipListCompleter = null
      ..summaryCompleter = Completer<FriendshipSummary>();
    final search = CommunitySearchController(repository, friendshipRepository);
    final pendingSearch = search.search('beta_user');
    await Future<void>.delayed(Duration.zero);
    search.dispose();
    friendshipRepository.summaryCompleter!.complete(canSendRelationship);

    expect(await pendingSearch, isFalse);
  });

  test('session changes reconstruct and clear both friendship controllers',
      () async {
    repository.searchResult = foundProfile;
    friendshipRepository.activeRelationships = [friendsRelationship];
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWith(
          (ref) => ref.watch(_testVerifiedUserIdProvider),
        ),
        communityRepositoryProvider.overrideWithValue(repository),
        friendshipRepositoryProvider.overrideWithValue(friendshipRepository),
      ],
    );
    addTearDown(container.dispose);
    final searchSubscription = container.listen(
      communitySearchControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    final managementSubscription = container.listen(
      friendshipManagementControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(searchSubscription.close);
    addTearDown(managementSubscription.close);
    await container.pump();

    final firstSearch =
        container.read(communitySearchControllerProvider.notifier);
    final firstManagement =
        container.read(friendshipManagementControllerProvider.notifier);
    await firstSearch.search('beta_user');
    expect(firstSearch.state.result, isNotNull);
    expect(firstManagement.state.friends, [friendsRelationship]);

    friendshipRepository.friendshipListCompleter =
        Completer<List<FriendshipSummary>>();

    container.read(_testVerifiedUserIdProvider.notifier).state = 'user-2';
    await container.pump();

    final secondSearch =
        container.read(communitySearchControllerProvider.notifier);
    final secondManagement =
        container.read(friendshipManagementControllerProvider.notifier);
    expect(secondSearch, isNot(same(firstSearch)));
    expect(secondSearch.state.result, isNull);
    expect(secondManagement, isNot(same(firstManagement)));
    expect(secondManagement.state.relationships.isLoading, isTrue);
    expect(secondManagement.state.friends, isEmpty);

    friendshipRepository.friendshipListCompleter!.complete([]);
    await container.pump();
    expect(secondManagement.state.relationships.valueOrNull, isEmpty);
  });

  test('search invalidation refreshes friendship management in place',
      () async {
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('user-1'),
        communityRepositoryProvider.overrideWithValue(repository),
        friendshipRepositoryProvider.overrideWithValue(friendshipRepository),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(
      friendshipManagementControllerProvider,
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await container.pump();
    final first =
        container.read(friendshipManagementControllerProvider.notifier);

    container.read(invalidateFriendshipManagementProvider)();
    await container.pump();

    final second =
        container.read(friendshipManagementControllerProvider.notifier);
    expect(second, same(first));
    expect(friendshipRepository.friendshipListCalls, 2);
  });

  test('blocked users load and successful unblock updates the private list',
      () async {
    repository.blockedProfiles = [blockedProfile];
    final controller = BlockedUsersController(repository);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state.profiles.valueOrNull, hasLength(1));

    expect(await controller.unblock(blockedProfile), isTrue);
    expect(repository.lastUnblockedProfileId, 'profile-2');
    expect(controller.state.profiles.valueOrNull, isEmpty);
    expect(controller.state.message, BlockedUsersMessage.unblocked);
  });

  test('blocked users expose generic retryable load and mutation failures',
      () async {
    final controller = BlockedUsersController(repository);
    addTearDown(controller.dispose);
    repository.listFailure = StateError('database details');

    await controller.load();
    expect(controller.state.profiles.hasError, isTrue);
    expect(controller.state.message, BlockedUsersMessage.operationFailed);

    repository.listFailure = null;
    repository.blockedProfiles = [blockedProfile];
    await controller.load();
    repository.unblockFailure = StateError('offline');
    expect(await controller.unblock(blockedProfile), isFalse);
    expect(controller.state.profiles.valueOrNull, [blockedProfile]);
    expect(controller.state.message, BlockedUsersMessage.operationFailed);
  });
}
