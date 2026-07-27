import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/app/screens/authenticated_shell.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/domain/community_profile.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/community_screen.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/public_template.dart';
import 'package:list_and_split/features/templates/domain/public_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/friend_public_template_feed_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/public_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_profile_screen.dart';
import 'package:list_and_split/features/templates/presentation/public_template_providers.dart';

import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fake_friend_public_template_feed_repository.dart';
import '../../helpers/fake_public_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets(
      'Community opens the friends feed in its shell and routes exact IDs',
      (tester) async {
    final feed = FakeFriendPublicTemplateFeedRepository()
      ..outcomes.add(
        FriendPublicTemplatePage(
          entries: [
            FriendPublicTemplateEntry(
              profile: const PublicTemplateProfile(
                id: _ownerId,
                username: 'public_owner',
                displayName: 'Public Owner',
              ),
              template: _summary(_filledTemplateId, itemCount: 1),
            ),
          ],
          nextCursor: null,
        ),
      );
    await _pumpApp(
      tester,
      community: _community(),
      publicTemplates: _publicTemplates(),
      privateTemplates: FakePrivateTemplateRepository(),
      friendFeed: feed,
    );

    await tester.tap(find.byKey(const Key('communityDestination')));
    await tester.pumpAndSettle();
    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(
        find.byKey(const Key('openFriendTemplatesFeedButton')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('communityUsername')),
      'preserved_search',
    );

    await tester.tap(find.byKey(const Key('openFriendTemplatesFeedButton')));
    await tester.pumpAndSettle();

    expect(find.byType(FriendPublicTemplateFeedScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(
      find.byKey(const Key('friendTemplateCard-$_filledTemplateId')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('openFriendTemplate-$_filledTemplateId')),
    );
    await tester.pumpAndSettle();
    final detail = tester.widget<PublicTemplateDetailScreen>(
      find.byType(PublicTemplateDetailScreen),
    );
    expect(detail.profileId, _ownerId);
    expect(detail.templateId, _filledTemplateId);
    expect(find.text('Sunscreen'), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(FriendPublicTemplateFeedScreen), findsOneWidget);
    expect(feed.calls, 1);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('communityUsername')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'preserved_search',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'profile-only discovery routes duplicate names by immutable ID and preserves Community state',
      (tester) async {
    final community = _community();
    final publicTemplates = _publicTemplates();
    final container = await _pumpApp(
      tester,
      community: community,
      publicTemplates: publicTemplates,
      privateTemplates: FakePrivateTemplateRepository(),
    );

    await _openDiscoveredProfile(tester);

    expect(find.byType(PublicTemplateProfileScreen), findsOneWidget);
    expect(find.text('Public Owner'), findsWidgets);
    expect(find.text('@public_owner'), findsOneWidget);
    expect(find.text('Public Templates'), findsOneWidget);
    expect(find.text('Trip kit'), findsNWidgets(2));
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );
    expect(publicTemplates.listCalls, 1);
    await tester.tap(find.byKey(const Key('refreshPublicProfileButton')));
    await tester.pumpAndSettle();
    expect(publicTemplates.listCalls, 2);
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();
    expect(publicTemplates.listCalls, 3);

    await tester.tap(find.byKey(const Key('publicTemplate-template-empty')));
    await tester.pumpAndSettle();

    final emptyDetail = tester.widget<PublicTemplateDetailScreen>(
      find.byType(PublicTemplateDetailScreen),
    );
    expect(emptyDetail.profileId, _ownerId);
    expect(emptyDetail.templateId, _emptyTemplateId);
    expect(find.text('This public template is empty'), findsOneWidget);
    expect(
        find.byKey(const Key('savePublicTemplateCopyButton')), findsOneWidget);
    expect(find.byKey(const Key('addTemplateItemButton')), findsNothing);
    expect(find.text('Import into existing list'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final detailCallsAfterPop = publicTemplates.detailCalls;
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();
    expect(publicTemplates.detailCalls, detailCallsAfterPop);
    await tester.tap(find.byKey(const Key('publicTemplate-template-filled')));
    await tester.pumpAndSettle();

    final filledDetail = tester.widget<PublicTemplateDetailScreen>(
      find.byType(PublicTemplateDetailScreen),
    );
    expect(filledDetail.templateId, _filledTemplateId);
    expect(find.text('Sunscreen'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('communityUsername')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'public_owner',
    );
    expect(find.byKey(const Key('communitySearchResult')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'copy stays on public detail until Open copy and blocking exits once',
      (tester) async {
    final community = _community();
    final publicTemplates = _publicTemplates();
    final privateTemplates = FakePrivateTemplateRepository();
    final copied = await privateTemplates.createTemplate(
      'Trip kit',
      requestId: 'prepared-copy',
    );
    publicTemplates.copyResult = PublicTemplateCopyResult(template: copied);
    await _pumpApp(
      tester,
      community: community,
      publicTemplates: publicTemplates,
      privateTemplates: privateTemplates,
    );

    await _openDiscoveredProfile(tester);
    await tester.tap(find.byKey(const Key('publicTemplate-template-empty')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('savePublicTemplateCopyButton')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'The complete current template will be copied into your private '
        'Templates as Uncategorized. Your copy has new identities, is '
        'independently owned, and will not follow later source changes.',
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('confirmSavePublicTemplateCopyButton')),
    );
    await tester.pumpAndSettle();

    expect(publicTemplates.copyCalls, 1);
    expect(publicTemplates.copiedTemplateIds, [_emptyTemplateId]);
    expect(find.byType(PublicTemplateDetailScreen), findsOneWidget);
    expect(
      find.text('A private, Uncategorized copy was saved.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Open copy'));
    await tester.pumpAndSettle();

    final privateDetail = tester.widget<PrivateTemplateDetailScreen>(
      find.byType(PrivateTemplateDetailScreen),
    );
    expect(privateDetail.templateId, copied.id);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.byKey(const Key('communityDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('communityDestination')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('viewPublicProfileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('blockPublicProfileButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmPublicProfileBlockButton')));
    await tester.pumpAndSettle();

    expect(community.blockCalls, 1);
    expect(find.byType(PublicTemplateProfileScreen), findsNothing);
    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(
      find.text('This profile or template is no longer available.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'one access-loss exit owns nested profile and detail reconciliation',
      (tester) async {
    final publicTemplates = _publicTemplates();
    final container = await _pumpApp(
      tester,
      community: _community(),
      publicTemplates: publicTemplates,
      privateTemplates: FakePrivateTemplateRepository(),
    );

    await _openDiscoveredProfile(tester);
    await tester.tap(find.byKey(const Key('publicTemplate-template-empty')));
    await tester.pumpAndSettle();
    expect(
      find.byType(PublicTemplateProfileScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(PublicTemplateDetailScreen), findsOneWidget);

    publicTemplates
      ..listFailure =
          const PublicTemplateFailure(PublicTemplateFailureCode.unavailable)
      ..detailFailure =
          const PublicTemplateFailure(PublicTemplateFailureCode.unavailable);
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(
      find.byType(PublicTemplateProfileScreen, skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byType(PublicTemplateDetailScreen, skipOffstage: false),
      findsNothing,
    );
    expect(find.byType(CommunityScreen), findsOneWidget);
    expect(
      find.text('This profile or template is no longer available.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openDiscoveredProfile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('communityDestination')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('communityUsername')),
    'public_owner',
  );
  await tester.tap(find.text('Search'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('viewPublicProfileButton')));
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required FakeCommunityRepository community,
  required FakePublicTemplateRepository publicTemplates,
  required FakePrivateTemplateRepository privateTemplates,
  FakeFriendPublicTemplateFeedRepository? friendFeed,
}) async {
  tester.view.physicalSize = const Size(900, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final auth = FakeAuthRepository(session: verifiedSession);
  final friendships = FakeFriendshipRepository()
    ..summaryResult = const FriendshipSummary(
      id: _ownerId,
      username: 'public_owner',
      displayName: 'Public Owner',
      status: FriendshipStatus.canSend,
      version: null,
      stateChangedAt: null,
    );
  final container = ProviderContainer(
    overrides: [
      appConfigurationProvider.overrideWithValue(
        const AppConfiguration.configured(),
      ),
      authRepositoryProvider.overrideWithValue(auth),
      accountDataExportRepositoryProvider.overrideWithValue(
        FakeAccountDataExportRepository(),
      ),
      accountDataExportShareServiceProvider.overrideWithValue(
        FakeAccountDataExportShareService(),
      ),
      profileRepositoryProvider.overrideWithValue(
        FakeProfileRepository(
          profile: FakeProfileRepository.completeProfile,
        ),
      ),
      communityRepositoryProvider.overrideWithValue(community),
      friendshipRepositoryProvider.overrideWithValue(friendships),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
      activeListRepositoryProvider.overrideWithValue(
        FakeActiveListRepository(),
      ),
      privateTemplateRepositoryProvider.overrideWithValue(privateTemplates),
      publicTemplateRepositoryProvider.overrideWithValue(publicTemplates),
      friendPublicTemplateFeedRepositoryProvider.overrideWithValue(
        friendFeed ?? FakeFriendPublicTemplateFeedRepository(),
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await auth.close();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const ListAndSplitApp(),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.byType(AuthenticatedShell), findsOneWidget);
  return container;
}

FakeCommunityRepository _community() => FakeCommunityRepository()
  ..searchResult = const DiscoveredProfile(
    id: _ownerId,
    username: 'public_owner',
    displayName: 'Public Owner',
  );

FakePublicTemplateRepository _publicTemplates() {
  final repository = FakePublicTemplateRepository();
  const profile = PublicTemplateProfile(
    id: _ownerId,
    username: 'public_owner',
    displayName: 'Public Owner',
  );
  final empty = _summary(_emptyTemplateId, itemCount: 0);
  final filled = _summary(_filledTemplateId, itemCount: 1);
  repository
    ..queuePage(
      _ownerId,
      PublicTemplatePage(
        profile: profile,
        templates: [empty, filled],
        nextCursor: null,
      ),
    )
    ..detailsByTemplate[_emptyTemplateId] = PublicTemplateDetail(
      profile: profile,
      summary: empty,
      items: const [],
    )
    ..detailsByTemplate[_filledTemplateId] = PublicTemplateDetail(
      profile: profile,
      summary: filled,
      items: [
        PublicTemplateItem(
          name: 'Sunscreen',
          quantity: ListQuantity.tryParse('2')!,
          position: 1,
        ),
      ],
    );
  return repository;
}

PublicTemplateSummary _summary(
  String id, {
  required int itemCount,
}) =>
    PublicTemplateSummary(
      id: id,
      name: 'Trip kit',
      version: 3,
      itemCount: itemCount,
      publishedAt: DateTime.utc(2026, 7, 25, 19, 33, 6),
    );

const _ownerId = 'profile-2';
const _emptyTemplateId = 'template-empty';
const _filledTemplateId = 'template-filled';
