import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/app/screens/authenticated_shell.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_screen.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_template_detail_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/templates_screen.dart';

import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets(
      'blank duplicate-name templates open by ID and preserve template state',
      (tester) async {
    final templates = FakePrivateTemplateRepository();
    final category = await templates.createCategory(
      'Trips',
      requestId: 'category',
    );
    final categorized = await templates.createTemplate(
      'Beach Trip',
      categoryId: category.id,
      requestId: 'categorized',
    );
    final uncategorized = await templates.createTemplate(
      'Beach Trip',
      requestId: 'uncategorized',
    );
    final lists = FakeActiveListRepository();
    await lists.createList('Existing shopping list', requestId: 'existing');
    final initialTemplateMutations = templates.mutationCalls;
    final initialListCreates = lists.createCalls;
    final container = await _pumpApp(
      tester,
      templates: templates,
      lists: lists,
    );

    await _openTemplates(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text('Trips'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('templateSearchField')),
      'Beach Trip',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await container
        .read(privateTemplatesControllerProvider.notifier)
        .setSort(PrivateTemplateSort.alphabetic);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('template-${categorized.id}')));
    await tester.pumpAndSettle();

    _expectTemplateDetail(tester, categorized.id, 'Beach Trip');
    expect(find.text('Trips'), findsOneWidget);
    expect(find.textContaining('No items'), findsOneWidget);
    expect(
      find.text(
        'Create a blank template or save an accessible shopping list as a reusable snapshot.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('addTemplateItemButton')), findsOneWidget);
    expect(find.byType(ActiveListsScreen), findsNothing);
    expect(find.text('Existing shopping list'), findsNothing);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.byKey(const Key('templateActionsButton')));
    await tester.pumpAndSettle();
    final createListAction = find.ancestor(
      of: find.text('Create new list'),
      matching: find.byType(InkWell),
    );
    expect(
      tester.widget<InkWell>(createListAction).onTap,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TemplatesScreen), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('templateSearchField')),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'Beach Trip',
    );
    final preservedState = container.read(privateTemplatesControllerProvider);
    expect(preservedState.categoryId, category.id);
    expect(preservedState.search, 'Beach Trip');
    expect(preservedState.sort, PrivateTemplateSort.alphabetic);

    await tester.tap(find.byKey(const Key('uncategorizedTemplatesFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('template-${uncategorized.id}')));
    await tester.pumpAndSettle();

    _expectTemplateDetail(tester, uncategorized.id, 'Beach Trip');
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(templates.mutationCalls, initialTemplateMutations);
    expect(lists.createCalls, initialListCreates);
    expect(lists.activeLists, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-empty template opens its own items in the Templates branch',
      (tester) async {
    final templates = FakePrivateTemplateRepository();
    final template = await templates.createTemplate(
      'Packing',
      requestId: 'template',
    );
    await templates.createItem(
      template.id,
      'Sunscreen',
      quantity: ListQuantity.tryParse('2')!,
      requestId: 'item',
      expectedTemplateVersion: 1,
    );
    final lists = FakeActiveListRepository();
    await _pumpApp(tester, templates: templates, lists: lists);

    await _openTemplates(tester);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();

    _expectTemplateDetail(tester, template.id, 'Packing');
    expect(find.text('Sunscreen'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(ActiveListsScreen), findsNothing);
    expect(lists.createCalls, 0);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
  });

  testWidgets('stale template card returns safely to Templates',
      (tester) async {
    final templates = _UnavailableTemplateRepository();
    final template = await templates.createTemplate(
      'Deleted elsewhere',
      requestId: 'template',
    );
    templates.unavailableTemplateId = template.id;
    await _pumpApp(
      tester,
      templates: templates,
      lists: FakeActiveListRepository(),
    );

    await _openTemplates(tester);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();

    expect(find.byType(TemplatesScreen), findsOneWidget);
    expect(find.byType(PrivateTemplateDetailScreen), findsNothing);
    expect(
      find.text('This template or destination is no longer available.'),
      findsOneWidget,
    );
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('item added from blank detail survives authoritative refresh',
      (tester) async {
    final templates = FakePrivateTemplateRepository();
    final template = await templates.createTemplate(
      'Beach Trip',
      requestId: 'template',
    );
    final lists = FakeActiveListRepository();
    final container = await _pumpApp(
      tester,
      templates: templates,
      lists: lists,
    );

    await _openTemplates(tester);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addTemplateItemButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('templateItemNameField')),
      'Beach towel',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Beach towel'), findsOneWidget);
    await container
        .read(privateTemplateDetailControllerProvider(template.id).notifier)
        .load();
    await tester.pumpAndSettle();

    _expectTemplateDetail(tester, template.id, 'Beach Trip');
    expect(find.text('Beach towel'), findsOneWidget);
    expect(templates.itemsByTemplate[template.id], hasLength(1));
    expect(lists.createCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

void _expectTemplateDetail(
  WidgetTester tester,
  String templateId,
  String name,
) {
  final detail = tester.widget<PrivateTemplateDetailScreen>(
    find.byType(PrivateTemplateDetailScreen),
  );
  expect(detail.templateId, templateId);
  expect(find.text(name), findsOneWidget);
  expect(find.byType(AuthenticatedShell), findsOneWidget);
}

Future<void> _openTemplates(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('templatesDestination')));
  await tester.pumpAndSettle();
  expect(find.byType(TemplatesScreen), findsOneWidget);
}

Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required FakePrivateTemplateRepository templates,
  required FakeActiveListRepository lists,
}) async {
  final auth = FakeAuthRepository(session: verifiedSession);
  final defaultFriendships = FakeFriendshipRepository()
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
      friendshipRepositoryProvider.overrideWithValue(defaultFriendships),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
      activeListRepositoryProvider.overrideWithValue(lists),
      privateTemplateRepositoryProvider.overrideWithValue(templates),
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

class _UnavailableTemplateRepository extends FakePrivateTemplateRepository {
  String? unavailableTemplateId;

  @override
  Future<PrivateTemplateDetail> getTemplate(String templateId) async {
    if (templateId == unavailableTemplateId) {
      await Future<void>.delayed(Duration.zero);
      throw const PrivateTemplateFailure(
        PrivateTemplateFailureCode.unavailable,
      );
    }
    return super.getTemplate(templateId);
  }
}
