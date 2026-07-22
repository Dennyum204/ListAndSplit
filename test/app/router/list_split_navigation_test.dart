import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/app/router/app_router.dart';
import 'package:list_and_split/app/router/route_decision.dart';
import 'package:list_and_split/app/screens/authenticated_shell.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/split/presentation/list_split_providers.dart';
import 'package:list_and_split/features/split/presentation/list_split_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';

import '../../helpers/fake_list_split_repository.dart';
import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets('accessible main-list action opens Split by immutable list ID',
      (tester) async {
    final lists = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..itemsByList[splitListId] = [];
    final split = FakeListSplitRepository();
    final container = await _pumpApp(tester, lists: lists, split: split);
    final router = container.read(appRouterProvider);

    router.go(AppRoutes.listDetail(splitListId));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveListDetailScreen), findsOneWidget);
    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Split').last);
    await tester.pumpAndSettle();

    final screen = tester.widget<ListSplitScreen>(find.byType(ListSplitScreen));
    expect(screen.listId, splitListId);
    expect(find.byType(AuthenticatedShell), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(split.getCalls, 1);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ActiveListDetailScreen), findsOneWidget);
    expect(
      tester
          .widget<ActiveListDetailScreen>(find.byType(ActiveListDetailScreen))
          .listId,
      splitListId,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required FakeActiveListRepository lists,
  required FakeListSplitRepository split,
}) async {
  final auth = FakeAuthRepository(session: verifiedSession);
  final friendships = FakeFriendshipRepository()
    ..summaryResult = const FriendshipSummary(
      id: 'profile-2',
      username: 'beta_user',
      displayName: 'Beta User',
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
      communityRepositoryProvider.overrideWithValue(FakeCommunityRepository()),
      friendshipRepositoryProvider.overrideWithValue(friendships),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
      activeListRepositoryProvider.overrideWithValue(lists),
      privateTemplateRepositoryProvider.overrideWithValue(
        FakePrivateTemplateRepository(),
      ),
      listSplitRepositoryProvider.overrideWithValue(split),
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
  return container;
}

ActiveListSummary _summary() {
  final now = DateTime.utc(2026, 7, 22, 8);
  return ActiveListSummary(
    id: splitListId,
    title: 'Weekend shop',
    status: ActiveListStatus.active,
    version: 3,
    itemCount: 0,
    completedItemCount: 0,
    createdAt: now,
    updatedAt: now,
    archivedAt: null,
  );
}
