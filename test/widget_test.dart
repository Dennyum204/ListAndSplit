import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/app/router/app_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/features/auth/domain/auth_repository.dart';
import 'package:list_and_split/features/auth/domain/auth_session.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/friendship_repository.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import 'helpers/fakes.dart';

void main() {
  testWidgets('shows an actionable screen when Supabase config is missing',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ListAndSplitApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Connect Supabase to continue'), findsOneWidget);
    expect(find.byIcon(Icons.developer_mode_rounded), findsOneWidget);
  });

  testWidgets('calls out partially supplied configuration', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigurationProvider.overrideWithValue(
            const AppConfiguration(
              isConfigured: false,
              isPartiallyConfigured: true,
            ),
          ),
        ],
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Only one Supabase value is set'), findsOneWidget);
  });

  testWidgets('signed-out navigation supports sign-up and forgot password',
      (tester) async {
    final auth = FakeAuthRepository();
    final profile = FakeProfileRepository();
    await _pumpConfiguredApp(tester, auth: auth, profile: profile);

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    await tester.tap(find.text('Already have an account? Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('forgotPasswordEmail')),
      'nobody@example.com',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'If the address matches an account, a reset link is on its way.'),
      findsOneWidget,
    );
    expect(auth.resetCalls, 1);
    await auth.close();
  });

  testWidgets('sign-up enforces eight characters and preserves the password',
      (tester) async {
    final auth = FakeAuthRepository();
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('signUpEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signUpPassword')),
      '1234567',
    );
    await tester.enterText(
      find.byKey(const Key('signUpPasswordConfirmation')),
      '1234567',
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    expect(auth.signUpCalls, 0);

    const exactPassword = ' MiXeD7 ';
    await tester.enterText(
      find.byKey(const Key('signUpPassword')),
      exactPassword,
    );
    await tester.enterText(
      find.byKey(const Key('signUpPasswordConfirmation')),
      exactPassword,
    );
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();

    expect(auth.signUpCalls, 1);
    expect(auth.lastPassword, exactPassword);
    expect(find.text('Verify your email'), findsOneWidget);
    await auth.close();
  });

  testWidgets('auth errors do not leak between signed-out screens',
      (tester) async {
    final auth = FakeAuthRepository()
      ..signInFailure = const AuthFailure(AuthFailureCode.generic);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    await tester.enterText(
      find.byKey(const Key('signInEmail')),
      'person@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('signInPassword')),
      'wrong-password',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sign you in'), findsOneWidget);

    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.textContaining('sign you in'), findsNothing);
    await auth.close();
  });

  testWidgets('unverified session resends verification without discovery',
      (tester) async {
    final auth = FakeAuthRepository(session: unverifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.textContaining('person@example.com'), findsOneWidget);
    await tester.tap(find.text('Resend verification email'));
    await tester.pumpAndSettle();
    expect(auth.resendCalls, 1);
    expect(find.textContaining('a new message is on its way'), findsOneWidget);
    await auth.close();
  });

  testWidgets('password recovery updates before entering the app',
      (tester) async {
    final auth = FakeAuthRepository(session: recoverySession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    expect(find.text('Choose a new password'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('recoveryPassword')),
      'new-password',
    );
    await tester.enterText(
      find.byKey(const Key('recoveryPasswordConfirmation')),
      'new-password',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();
    expect(auth.updatePasswordCalls, 1);
    expect(find.text('Welcome, Fernando'), findsOneWidget);

    auth.emit(verifiedSession);
    await tester.pumpAndSettle();
    auth.emit(recoverySession);
    await tester.pumpAndSettle();
    expect(find.text('Choose a new password'), findsOneWidget);
    await auth.close();
  });

  testWidgets('password recovery can be cancelled by signing out',
      (tester) async {
    final auth = FakeAuthRepository(session: recoverySession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    await tester.tap(find.text('Cancel and sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.text('Welcome back'), findsOneWidget);
    await auth.close();
  });

  testWidgets('onboarding canonicalizes profile then reaches foundation',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository();
    await _pumpConfiguredApp(tester, auth: auth, profile: profile);

    expect(find.text('Choose your profile'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('onboardingUsername')),
      ' Fernando_1 ',
    );
    await tester.enterText(
      find.byKey(const Key('onboardingDisplayName')),
      ' Fernando ',
    );
    await tester.tap(find.text('Finish profile'));
    await tester.pumpAndSettle();

    expect(profile.lastUsername, 'fernando_1');
    expect(profile.lastDisplayName, 'Fernando');
    expect(find.text('Welcome, Fernando'), findsOneWidget);
    await auth.close();
  });

  testWidgets('onboarding offers sign-out and reports a sign-out failure',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession)
      ..operationFailure = StateError('offline');
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(),
    );

    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Choose your profile'), findsOneWidget);
    expect(
        find.text('Something went wrong. Please try again.'), findsOneWidget);

    auth.operationFailure = null;
    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 2);
    expect(find.text('Welcome back'), findsOneWidget);
    await auth.close();
  });

  testWidgets('verification email lifecycle handles null and external sign-out',
      (tester) async {
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.configured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(pendingVerificationEmailProvider.notifier).state =
        'new@example.com';
    await tester.pumpAndSettle();
    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    expect(
      container.read(pendingVerificationEmailProvider),
      'new@example.com',
    );
    expect(find.text('Verify your email'), findsOneWidget);

    auth.emit(unverifiedSession);
    await tester.pumpAndSettle();
    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    expect(container.read(pendingVerificationEmailProvider), isNull);
    expect(find.text('Welcome back'), findsOneWidget);
    await auth.close();
  });

  testWidgets('a verified session clears a pending verification email',
      (tester) async {
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.configured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          FakeProfileRepository(
            profile: FakeProfileRepository.completeProfile,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    container.read(pendingVerificationEmailProvider.notifier).state =
        'old@example.com';
    await tester.pumpAndSettle();
    auth.emit(verifiedSession);
    await tester.pumpAndSettle();

    expect(container.read(pendingVerificationEmailProvider), isNull);
    expect(find.text('Welcome, Fernando'), findsOneWidget);
    await auth.close();
  });

  testWidgets('token refresh preserves router, profile, and current location',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository(
      profile: FakeProfileRepository.completeProfile,
    );
    final container = ProviderContainer(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.configured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profile),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ListAndSplitApp(),
      ),
    );
    await tester.pumpAndSettle();

    final router = container.read(appRouterProvider);
    router.go(AppRoutes.profile);
    await tester.pumpAndSettle();
    expect(find.text('Your profile'), findsOneWidget);
    expect(profile.fetchCalls, 1);

    auth.emit(verifiedSession);
    await tester.pumpAndSettle();

    expect(identical(container.read(appRouterProvider), router), isTrue);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.profile);
    expect(find.text('Your profile'), findsOneWidget);
    expect(profile.fetchCalls, 1);
    await auth.close();
  });

  testWidgets('foundation stays honest and profile username is read-only',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final profile = FakeProfileRepository(
      profile: FakeProfileRepository.completeProfile,
    );
    await _pumpConfiguredApp(tester, auth: auth, profile: profile);

    expect(find.text('List & Split'), findsOneWidget);
    expect(find.text('Welcome, Fernando'), findsOneWidget);
    expect(
      find.textContaining('collaborative lists arrive in a later phase'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.checklist_rounded), findsOneWidget);

    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    final usernameField = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('profileUsername')),
        matching: find.byType(EditableText),
      ),
    );
    expect(usernameField.readOnly, isTrue);
    expect(find.text('fernando_1'), findsOneWidget);
    expect(find.textContaining('permanent after onboarding'), findsWidgets);
    await auth.close();
  });

  testWidgets('exact discovery validates, canonicalizes, and confirms block',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'invalid username',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('starting with a letter'), findsOneWidget);
    expect(community.searchCalls, 0);

    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      '  BETA_USER  ',
    );
    expect(community.searchCalls, 0);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(community.lastUsername, 'beta_user');
    expect(find.text('Beta User'), findsOneWidget);
    expect(find.text('@beta_user'), findsOneWidget);
    expect(find.textContaining('profile-2'), findsNothing);
    expect(find.text('Send request'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('blockSearchResultButton')),
    );
    await tester.tap(find.byKey(const Key('blockSearchResultButton')));
    await tester.pumpAndSettle();
    expect(find.text('Block @beta_user?'), findsOneWidget);
    expect(find.textContaining('won’t be notified'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(community.blockCalls, 0);

    await tester.ensureVisible(
      find.byKey(const Key('blockSearchResultButton')),
    );
    await tester.tap(find.byKey(const Key('blockSearchResultButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmBlockButton')));
    await tester.pumpAndSettle();

    expect(community.blockCalls, 1);
    expect(community.lastBlockedProfileId, 'profile-2');
    expect(find.byKey(const Key('communitySearchResult')), findsNothing);
    expect(find.textContaining('Profile blocked'), findsOneWidget);
    await auth.close();
  });

  testWidgets('exact discovery sends a caller-relative friend request',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    final friendships = FakeFriendshipRepository()
      ..summaryResult = const FriendshipSummary(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
        status: FriendshipStatus.canSend,
        version: null,
        stateChangedAt: null,
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('sendFriendRequestButton')),
    );
    await tester.tap(find.byKey(const Key('sendFriendRequestButton')));
    await tester.pumpAndSettle();

    expect(friendships.mutationCalls, hasLength(1));
    expect(friendships.mutationCalls.single.operation, 'send');
    expect(friendships.mutationCalls.single.profileId, 'profile-2');
    expect(friendships.mutationCalls.single.expectedVersion, isNull);
    expect(find.text('Friend request sent.'), findsOneWidget);
    await auth.close();
  });

  testWidgets('friendship management groups actions and confirms removal',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository();
    final friendships = FakeFriendshipRepository()
      ..activeRelationships = [
        FriendshipSummary(
          id: 'friend-1',
          username: 'friend_user',
          displayName: 'Friend User',
          status: FriendshipStatus.friends,
          version: 4,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
        FriendshipSummary(
          id: 'incoming-1',
          username: 'incoming_user',
          displayName: 'Incoming User',
          status: FriendshipStatus.incomingPending,
          version: 2,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
        FriendshipSummary(
          id: 'sent-1',
          username: 'sent_user',
          displayName: 'Sent User',
          status: FriendshipStatus.outgoingPending,
          version: 3,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
      ];
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Incoming requests'), findsOneWidget);
    expect(find.text('Sent requests'), findsOneWidget);
    expect(find.text('Friend User'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('acceptFriend-incoming-1')));
    expect(find.byKey(const Key('acceptFriend-incoming-1')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('cancelFriend-sent-1')));
    expect(find.byKey(const Key('cancelFriend-sent-1')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('removeFriend-friend-1')));
    await tester.tap(find.byKey(const Key('removeFriend-friend-1')));
    await tester.pumpAndSettle();
    expect(find.text('Remove @friend_user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(friendships.mutationCalls, isEmpty);

    await tester.tap(find.byKey(const Key('removeFriend-friend-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmRemoveFriendButton')));
    await tester.pumpAndSettle();
    expect(friendships.mutationCalls.single.operation, 'end');
    expect(friendships.mutationCalls.single.expectedVersion, 4);
    expect(find.text('Friend removed.'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('blockFriend-friend-1')));
    await tester.tap(find.byKey(const Key('blockFriend-friend-1')));
    await tester.pumpAndSettle();
    expect(find.text('Block @friend_user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(community.blockCalls, 0);

    await tester.tap(find.byKey(const Key('blockFriend-friend-1')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('confirmFriendshipBlockButton')),
    );
    await tester.pumpAndSettle();
    expect(community.blockCalls, 1);
    expect(community.lastBlockedProfileId, 'friend-1');
    expect(find.textContaining('Profile blocked'), findsOneWidget);
    await auth.close();
  });

  testWidgets('friendship management shows loading, empty, and manual refresh',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final friendships = FakeFriendshipRepository()
      ..friendshipListCompleter = Completer<List<FriendshipSummary>>();
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      friendships: friendships,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.bySemanticsLabel('Loading friendships'), findsOneWidget);

    friendships.friendshipListCompleter!.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No active friendships or requests'), findsOneWidget);

    friendships
      ..friendshipListCompleter = null
      ..activeRelationships = [
        FriendshipSummary(
          id: 'friend-2',
          username: 'refresh_user',
          displayName: 'Refresh User',
          status: FriendshipStatus.friends,
          version: 2,
          stateChangedAt: DateTime.utc(2026, 7, 18),
        ),
      ];
    await tester.tap(find.byKey(const Key('refreshFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.text('Refresh User'), findsOneWidget);
    expect(friendships.friendshipListCalls, 2);
    await auth.close();
  });

  testWidgets('friendship management load failure is retryable',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final friendships = FakeFriendshipRepository()
      ..listFailure = StateError('private backend details');
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      friendships: friendships,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manageFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retryFriendshipsButton')), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsWidgets);
    expect(find.textContaining('private backend'), findsNothing);

    friendships.listFailure = null;
    await tester.tap(find.byKey(const Key('retryFriendshipsButton')));
    await tester.pumpAndSettle();

    expect(find.text('No active friendships or requests'), findsOneWidget);
    expect(friendships.friendshipListCalls, 2);
    await auth.close();
  });

  testWidgets('discovered unavailable relationship stays privacy-safe',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    final friendships = FakeFriendshipRepository()
      ..summaryResult = const FriendshipSummary(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
        status: FriendshipStatus.unavailable,
        version: null,
        stateChangedAt: null,
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.text('Friend requests aren’t available for this profile.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sendFriendRequestButton')), findsNothing);
    expect(find.byKey(const Key('cancelFriendRequestButton')), findsNothing);
    expect(find.byKey(const Key('acceptFriendRequestButton')), findsNothing);
    expect(find.byKey(const Key('declineFriendRequestButton')), findsNothing);
    expect(find.textContaining('declined'), findsNothing);
    expect(find.textContaining('ended'), findsNothing);
    expect(find.textContaining('reopen'), findsNothing);
    await auth.close();
  });

  testWidgets('summary unavailability clears the discovered profile card',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    final friendships = FakeFriendshipRepository()
      ..summaryFailure =
          const FriendshipFailure(FriendshipFailureCode.unavailable);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
      friendships: friendships,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.text('No matching profile was found or is available.'),
      findsOneWidget,
    );
    expect(find.text('Beta User'), findsNothing);
    expect(find.byKey(const Key('sendFriendRequestButton')), findsNothing);
    await auth.close();
  });

  testWidgets('missing exact discovery uses the generic unavailable result',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository();
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'missing_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(
      find.text('No matching profile was found or is available.'),
      findsOneWidget,
    );
    expect(find.textContaining('blocked by'), findsNothing);
    await auth.close();
  });

  testWidgets('blocked users are private and unblock requires confirmation',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..blockedProfiles = const [
        BlockedProfile(
          id: 'profile-2',
          username: 'beta_user',
          displayName: 'Beta User',
        ),
      ];
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manageBlockedUsersButton')));
    await tester.pumpAndSettle();

    expect(find.text('Blocked users'), findsOneWidget);
    expect(find.text('Beta User'), findsOneWidget);
    expect(find.text('@beta_user'), findsOneWidget);
    expect(
        find.textContaining('Incoming blocks are never shown'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unblockProfile-profile-2')));
    await tester.pumpAndSettle();
    expect(find.text('Unblock @beta_user?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(community.unblockCalls, 0);

    await tester.tap(find.byKey(const Key('unblockProfile-profile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmUnblockButton')));
    await tester.pumpAndSettle();

    expect(community.unblockCalls, 1);
    expect(find.text('No blocked users'), findsOneWidget);
    expect(find.textContaining('No relationship was restored'), findsOneWidget);
    await auth.close();
  });

  testWidgets('blocked-user load failures can be retried safely',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..listFailure = StateError('database details');
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manageBlockedUsersButton')));
    await tester.pumpAndSettle();
    expect(find.text('Something went wrong. Please try again.'), findsWidgets);

    community.listFailure = null;
    await tester.tap(find.byKey(const Key('retryBlockedUsersButton')));
    await tester.pumpAndSettle();
    expect(find.text('No blocked users'), findsOneWidget);
    expect(community.listCalls, 2);
    await auth.close();
  });

  testWidgets('community search state clears across session changes',
      (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    final community = FakeCommunityRepository()
      ..searchResult = const DiscoveredProfile(
        id: 'profile-2',
        username: 'beta_user',
        displayName: 'Beta User',
      );
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
      community: community,
    );

    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'beta_user',
    );
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('communitySearchResult')), findsOneWidget);

    auth.emit(const AuthSessionState.signedOut());
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    auth.emit(verifiedSession);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('findPeopleButton')));
    await tester.tap(find.byKey(const Key('findPeopleButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('communitySearchResult')), findsNothing);
    await auth.close();
  });

  testWidgets('sign-out returns the user to sign-in', (tester) async {
    final auth = FakeAuthRepository(session: verifiedSession);
    await _pumpConfiguredApp(
      tester,
      auth: auth,
      profile: FakeProfileRepository(
        profile: FakeProfileRepository.completeProfile,
      ),
    );

    await tester.ensureVisible(find.text('Sign out'));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(auth.signOutCalls, 1);
    expect(find.text('Welcome back'), findsOneWidget);
    await auth.close();
  });
}

Future<void> _pumpConfiguredApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeProfileRepository profile,
  FakeCommunityRepository? community,
  FakeFriendshipRepository? friendships,
}) async {
  final defaultFriendships = FakeFriendshipRepository()
    ..summaryResult = const FriendshipSummary(
      id: 'profile-2',
      username: 'beta_user',
      displayName: 'Beta User',
      status: FriendshipStatus.canSend,
      version: null,
      stateChangedAt: null,
    );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigurationProvider.overrideWithValue(
          const AppConfiguration.configured(),
        ),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(profile),
        communityRepositoryProvider.overrideWithValue(
          community ?? FakeCommunityRepository(),
        ),
        friendshipRepositoryProvider.overrideWithValue(
          friendships ?? defaultFriendships,
        ),
      ],
      child: const ListAndSplitApp(),
    ),
  );
  await tester.pumpAndSettle();
}
