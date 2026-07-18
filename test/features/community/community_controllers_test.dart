import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/presentation/blocked_users_controller.dart';
import 'package:list_and_split/features/community/presentation/community_search_controller.dart';
import 'package:list_and_split/features/profile/domain/profile_validation.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeCommunityRepository repository;

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

  setUp(() => repository = FakeCommunityRepository());

  test('search validates locally and sends the canonical exact username',
      () async {
    final controller = CommunitySearchController(repository);
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
    final controller = CommunitySearchController(repository);
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
    final controller = CommunitySearchController(repository);
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
    final controller = CommunitySearchController(repository);

    final pendingSearch = controller.search('beta_user');
    controller.dispose();
    repository.searchCompleter!.complete(foundProfile);

    expect(await pendingSearch, isFalse);
  });

  test('successful block clears the result while a failed block is retryable',
      () async {
    repository.searchResult = foundProfile;
    final controller = CommunitySearchController(repository);
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
