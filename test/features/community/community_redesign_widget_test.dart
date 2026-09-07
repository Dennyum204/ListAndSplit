import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/presentation/design_widgets.dart';
import 'package:list_and_split/core/theme/app_palette.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/blocked_users_screen.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/community_screen.dart';
import 'package:list_and_split/features/community/presentation/friendship_management_screen.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';
import '../../support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);
  testWidgets('scrolled friendship failure keeps one visible feedback banner',
      (tester) async {
    final friendships = FakeFriendshipRepository()
      ..mutationFailure = StateError('isolated failure')
      ..activeRelationships = List.generate(
          12,
          (index) => FriendshipSummary(
                id: 'friend-$index',
                username: 'friend_$index',
                displayName: 'Friend $index',
                status: FriendshipStatus.incomingPending,
                version: 1,
                stateChangedAt: DateTime.utc(2026, 9, 1),
              ));
    await _pump(tester,
        child: const FriendshipManagementScreen(),
        community: FakeCommunityRepository(),
        friendships: friendships,
        locale: const Locale('en'),
        theme: ThemeMode.light);
    final accept = find.byKey(const Key('acceptFriend-friend-11'));
    await tester.scrollUntilVisible(accept, 500);
    await tester.pumpAndSettle();
    await tester.tap(accept);
    await tester.pumpAndSettle();
    _expectVisibleFailure(tester, FriendshipManagementScreen);
    expect(friendships.mutationCalls, hasLength(1));
  });

  testWidgets('scrolled unblock failure keeps one visible feedback banner',
      (tester) async {
    final community = FakeCommunityRepository()
      ..unblockFailure = StateError('isolated failure')
      ..blockedProfiles = List.generate(
          12,
          (index) => BlockedProfile(
              id: 'friend-$index',
              username: 'friend_$index',
              displayName: 'Friend $index'));
    await _pump(tester,
        child: const BlockedUsersScreen(),
        community: community,
        friendships: FakeFriendshipRepository(),
        locale: const Locale('en'),
        theme: ThemeMode.light);
    final unblock = find.byKey(const Key('unblockProfile-friend-11'));
    await tester.scrollUntilVisible(unblock, 500);
    await tester.pumpAndSettle();
    await tester.tap(unblock);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmUnblockButton')));
    await tester.pumpAndSettle();
    _expectVisibleFailure(tester, BlockedUsersScreen);
    expect(community.unblockCalls, 1);
    expect(community.blockedProfiles, hasLength(12));
  });
  for (final configuration in [
    (locale: const Locale('en'), theme: ThemeMode.light),
    (locale: const Locale('pt'), theme: ThemeMode.dark),
  ]) {
    testWidgets(
        'discovery preserves exact username and responsive identity '
        '${configuration.locale.languageCode}', (tester) async {
      final community = FakeCommunityRepository()
        ..searchResult = const DiscoveredProfile(
          id: 'friend',
          username: 'exact_friend',
          displayName: 'A long display name that wraps safely',
        );
      final friendships = FakeFriendshipRepository()
        ..summaryResult = _relationship(FriendshipStatus.canSend);
      await _pump(tester,
          child: const CommunityScreen(),
          community: community,
          friendships: friendships,
          locale: configuration.locale,
          theme: configuration.theme);
      final input = find.byKey(const Key('communityUsername'));
      expect(tester.widget<TextField>(input).style?.color, AppPalette.navy);
      await tester.enterText(input, 'exact_friend');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(community.lastUsername, 'exact_friend');
      expect(community.searchCalls, 1);
      expect(find.byType(AppPageHeader), findsOneWidget);
      expect(find.byType(IdentityBadge), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      await tester
          .ensureVisible(find.byKey(const Key('viewPublicProfileButton')));
      await captureUiPreview(tester,
          'friends-search-large-${configuration.theme == ThemeMode.dark ? 'dark' : 'light'}');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'friend management keeps all actions in large text '
        '${configuration.locale.languageCode}', (tester) async {
      final friendships = FakeFriendshipRepository()
        ..activeRelationships = [_relationship(FriendshipStatus.friends)];
      await _pump(tester,
          child: const FriendshipManagementScreen(),
          community: FakeCommunityRepository(),
          friendships: friendships,
          locale: configuration.locale,
          theme: configuration.theme);
      final remove = find.byKey(const Key('removeFriend-friend'));
      await tester.scrollUntilVisible(remove, 150);
      expect(find.byType(IdentityBadge), findsOneWidget);
      expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
      final block = find.byKey(const Key('blockFriend-friend'));
      await tester.ensureVisible(block);
      await tester.pumpAndSettle();
      expect(tester.getSize(block).height, greaterThanOrEqualTo(48));
      expect(friendships.mutationCalls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'outgoing blocks keep private explanation and recoverable action '
        '${configuration.locale.languageCode}', (tester) async {
      final community = FakeCommunityRepository()
        ..blockedProfiles = const [
          BlockedProfile(
            id: 'friend',
            username: 'exact_friend',
            displayName: 'A long display name that wraps safely',
          ),
        ];
      await _pump(tester,
          child: const BlockedUsersScreen(),
          community: community,
          friendships: FakeFriendshipRepository(),
          locale: configuration.locale,
          theme: configuration.theme);
      final unblock = find.byKey(const Key('unblockProfile-friend'));
      await tester.scrollUntilVisible(unblock, 150);
      await tester.pumpAndSettle();
      expect(find.byType(IdentityBadge), findsOneWidget);
      expect(tester.getSize(unblock).height, greaterThanOrEqualTo(48));
      await tester.tap(unblock);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(community.unblockCalls, 0);
      final localizations =
          AppLocalizations.of(tester.element(find.byType(BlockedUsersScreen)));
      await tester.tap(find.text(localizations.cancelButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(community.unblockCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }
}

void _expectVisibleFailure(WidgetTester tester, Type screen) {
  final localizations =
      AppLocalizations.of(tester.element(find.byType(screen)));
  final feedback = find.text(localizations.operationFailedMessage);
  expect(feedback, findsOneWidget);
  expect(tester.getRect(feedback).top, greaterThanOrEqualTo(0));
  expect(tester.getRect(feedback).bottom, lessThan(800));
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(tester.takeException(), isNull);
}

FriendshipSummary _relationship(FriendshipStatus status) => FriendshipSummary(
      id: 'friend',
      username: 'exact_friend',
      displayName: 'A long display name that wraps safely',
      status: status,
      version: status == FriendshipStatus.canSend ? null : 1,
      stateChangedAt:
          status == FriendshipStatus.canSend ? null : DateTime.utc(2026, 9, 1),
    );

Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  required FakeCommunityRepository community,
  required FakeFriendshipRepository friendships,
  required Locale locale,
  required ThemeMode theme,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      verifiedUserIdProvider.overrideWithValue('viewer'),
      communityRepositoryProvider.overrideWithValue(community),
      friendshipRepositoryProvider.overrideWithValue(friendships),
      notificationRepositoryProvider
          .overrideWithValue(FakeNotificationRepository()),
    ],
    child: MaterialApp(
      locale: locale,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => uiPreviewBoundary(MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      )),
      home: child,
    ),
  ));
  await tester.pumpAndSettle();
}
