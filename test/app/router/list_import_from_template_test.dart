import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/app.dart';
import 'package:list_and_split/core/config/configuration_provider.dart';
import 'package:list_and_split/core/config/supabase_config.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/features/account/presentation/account_data_export_providers.dart';
import 'package:list_and_split/features/auth/presentation/auth_providers.dart';
import 'package:list_and_split/features/community/domain/friendship_summary.dart';
import 'package:list_and_split/features/community/presentation/community_providers.dart';
import 'package:list_and_split/features/community/presentation/friendship_providers.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/features/templates/domain/private_template.dart';
import 'package:list_and_split/features/templates/domain/private_template_repository.dart';
import 'package:list_and_split/features/templates/presentation/private_template_import_screen.dart';
import 'package:list_and_split/features/templates/presentation/private_template_providers.dart';
import 'package:list_and_split/features/templates/presentation/templates_screen.dart';

import '../../helpers/fake_private_template_repository.dart';
import '../../helpers/fakes.dart';

void main() {
  testWidgets(
      'owner picker preserves discovery state and routes duplicate names by ID',
      (tester) async {
    final lists = FakeActiveListRepository()
      ..activeLists = [_listSummary()]
      ..itemsByList['list-1'] = [];
    final templates = _ImportingTemplateRepository(lists);
    final category = await templates.createCategory(
      'Travel',
      requestId: 'category',
    );
    final categorized = await templates.createTemplate(
      'Beach Trip',
      categoryId: category.id,
      requestId: 'categorized',
    );
    await templates.createItem(
      categorized.id,
      'Passport',
      requestId: 'passport',
      expectedTemplateVersion: 1,
    );
    final uncategorized = await templates.createTemplate(
      'Beach Trip',
      requestId: 'uncategorized',
    );
    await templates.createItem(
      uncategorized.id,
      'Sunscreen',
      requestId: 'sunscreen',
      expectedTemplateVersion: 1,
    );
    final blank = await templates.createTemplate(
      'Blank template',
      requestId: 'blank',
    );
    final harness = await _pumpApp(
      tester,
      templates: templates,
      lists: lists,
    );

    await _openListImportPicker(tester);
    expect(find.byType(PrivateTemplatePickerScreen), findsOneWidget);
    expect(find.text('Choose a template'), findsOneWidget);
    expect(find.byKey(Key('template-${categorized.id}')), findsOneWidget);
    expect(find.byKey(Key('template-${uncategorized.id}')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('templateSearchField')),
      'Passport',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('template-${categorized.id}')), findsOneWidget);
    expect(find.byKey(Key('template-${uncategorized.id}')), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(ChoiceChip),
        matching: find.text('Travel'),
      ),
    );
    await tester.pumpAndSettle();
    await harness.container
        .read(privateTemplatePickerControllerProvider('list-1').notifier)
        .setSort(PrivateTemplateSort.alphabetic);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('template-${categorized.id}')));
    await tester.pumpAndSettle();
    final importScreen = tester.widget<PrivateTemplateImportScreen>(
      find.byType(PrivateTemplateImportScreen),
    );
    expect(importScreen.destinationListId, 'list-1');
    expect(importScreen.templateId, categorized.id);
    expect(find.text('Passport'), findsOneWidget);
    expect(find.text('Destination: Destination'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(find.byType(PrivateTemplatePickerScreen), findsOneWidget);
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
      'Passport',
    );
    final pickerState = harness.container.read(
      privateTemplatePickerControllerProvider('list-1'),
    );
    expect(pickerState.search, 'Passport');
    expect(pickerState.categoryId, category.id);
    expect(pickerState.sort, PrivateTemplateSort.alphabetic);

    await _clearTemplateSearch(tester);
    await tester.tap(find.byKey(const Key('uncategorizedTemplatesFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('template-${uncategorized.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Sunscreen'), findsOneWidget);
    expect(find.text('Passport'), findsNothing);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('allTemplatesFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('template-${blank.id}')));
    await tester.pumpAndSettle();
    expect(find.text('0 of 0 selected'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirmTemplateSelectionButton')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('templateSearchField')),
      'not present',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('No templates match this view'), findsOneWidget);
    expect(templates.importCalls, 0);
    expect(lists.itemsByList['list-1'], isEmpty);
    expect(tester.takeException(), isNull);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ActiveListDetailScreen), findsOneWidget);
    expect(find.byType(PrivateTemplatePickerScreen), findsNothing);
  });

  testWidgets('accepted member imports once into the mounted fixed destination',
      (tester) async {
    final existing = _listItem(
      id: 'existing',
      name: '  COFFEE  ',
      position: 1,
      quantity: ListQuantity.tryParse('5')!,
      completed: true,
    );
    final lists = FakeActiveListRepository()
      ..activeLists = [_listSummary(isOwner: false, itemCount: 1)]
      ..itemsByList['list-1'] = [existing];
    final templates = _ImportingTemplateRepository(lists);
    final template = await templates.createTemplate(
      'Weekly shop',
      requestId: 'template',
    );
    await templates.createItem(
      template.id,
      'Coffee',
      quantity: ListQuantity.tryParse('2')!,
      requestId: 'coffee',
      expectedTemplateVersion: 1,
    );
    await templates.createItem(
      template.id,
      'Milk',
      quantity: ListQuantity.tryParse('1.5')!,
      requestId: 'milk',
      expectedTemplateVersion: 2,
    );
    final notifications = FakeNotificationRepository()..unreadCount = 4;
    final harness = await _pumpApp(
      tester,
      templates: templates,
      lists: lists,
      notifications: notifications,
    );

    await _openListImportPicker(tester, owner: false);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();

    expect(find.text('Destination: Destination'), findsOneWidget);
    expect(find.text('2 of 2 selected'), findsOneWidget);
    expect(find.textContaining('Possible duplicate'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(
              Key(
                'select-template-item-${templates.itemsByTemplate[template.id]![0].id}',
              ),
            ),
          )
          .value,
      isTrue,
    );

    await tester.tap(
      find.byKey(
        Key(
          'select-template-item-${templates.itemsByTemplate[template.id]![1].id}',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('1 of 2 selected'), findsOneWidget);
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(find.text('2 of 2 selected'), findsOneWidget);

    await tester.tap(find.text('Clear selection'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirmTemplateSelectionButton')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Select all'));
    await tester.pump();
    final confirm = find.byKey(const Key('confirmTemplateSelectionButton'));
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(templates.importCalls, 1);
    expect(find.byType(ActiveListDetailScreen), findsOneWidget);
    expect(find.byType(PrivateTemplatePickerScreen), findsNothing);
    expect(find.text('Milk'), findsOneWidget);
    expect(find.text('1.5'), findsOneWidget);
    expect(find.text('Coffee'), findsOneWidget);
    final result = lists.itemsByList['list-1']!;
    expect(result, hasLength(3));
    expect(result.first, same(existing));
    expect(result.first.isCompleted, isTrue);
    expect(result.skip(1).map((item) => item.name), ['Coffee', 'Milk']);
    expect(result.skip(1).every((item) => !item.isCompleted), isTrue);
    expect(result.skip(1).map((item) => item.position), [2, 3]);
    expect(notifications.unreadCount, 4);
    expect(notifications.listCalls, isEmpty);
    expect(notifications.markCalls, isEmpty);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );

    await harness.container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity loss rejects atomically and refreshes the preview',
      (tester) async {
    final existing = List.generate(
      198,
      (index) => _listItem(
        id: 'existing-$index',
        name: 'Existing $index',
        position: index + 1,
      ),
    );
    final lists = FakeActiveListRepository()
      ..activeLists = [_listSummary(itemCount: 198)]
      ..itemsByList['list-1'] = existing;
    final templates = _ImportingTemplateRepository(lists)
      ..failureOnce = const PrivateTemplateFailure(
        PrivateTemplateFailureCode.capacity,
      )
      ..concurrentItemsBeforeFailure = 2;
    final template = await templates.createTemplate(
      'Capacity template',
      requestId: 'template',
    );
    await templates.createItem(
      template.id,
      'One',
      requestId: 'one',
      expectedTemplateVersion: 1,
    );
    await templates.createItem(
      template.id,
      'Two',
      requestId: 'two',
      expectedTemplateVersion: 2,
    );
    await _pumpApp(tester, templates: templates, lists: lists);

    await _openListImportPicker(tester);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();
    expect(find.text('2 item spaces remaining'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmTemplateSelectionButton')));
    await tester.pumpAndSettle();

    expect(templates.importCalls, 1);
    expect(lists.itemsByList['list-1'], hasLength(200));
    expect(
      lists.itemsByList['list-1']!.where(
        (item) => item.name == 'One' || item.name == 'Two',
      ),
      isEmpty,
    );
    expect(find.text('No item spaces remaining'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirmTemplateSelectionButton')),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('capacity'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lost destination access disables the mounted preview',
      (tester) async {
    final lists = FakeActiveListRepository()
      ..activeLists = [_listSummary()]
      ..itemsByList['list-1'] = [];
    final templates = _ImportingTemplateRepository(lists);
    final template = await templates.createTemplate(
      'Access changes',
      requestId: 'template',
    );
    await templates.createItem(
      template.id,
      'Milk',
      requestId: 'milk',
      expectedTemplateVersion: 1,
    );
    final harness = await _pumpApp(
      tester,
      templates: templates,
      lists: lists,
    );

    await _openListImportPicker(tester);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('confirmTemplateSelectionButton'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    lists.failure = const ActiveListFailure(ActiveListFailureCode.unavailable);
    await harness.container
        .read(privateTemplateDetailControllerProvider(template.id).notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(
      find.text('This template or destination is no longer available.'),
      findsOneWidget,
    );
    expect(templates.importCalls, 0);
    expect(lists.itemsByList['list-1'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deleted template is handled safely without mutating the list',
      (tester) async {
    final lists = FakeActiveListRepository()
      ..activeLists = [_listSummary()]
      ..itemsByList['list-1'] = [];
    final templates = _UnavailableTemplateRepository(lists);
    final template = await templates.createTemplate(
      'Deleted elsewhere',
      requestId: 'template',
    );
    templates.unavailableTemplateId = template.id;
    await _pumpApp(tester, templates: templates, lists: lists);

    await _openListImportPicker(tester);
    await tester.tap(find.byKey(Key('template-${template.id}')));
    await tester.pumpAndSettle();

    expect(
      find.text('This template or destination is no longer available.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('retryFixedTemplateImportButton')),
      findsOneWidget,
    );
    expect(templates.importCalls, 0);
    expect(lists.itemsByList['list-1'], isEmpty);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PrivateTemplatePickerScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openListImportPicker(
  WidgetTester tester, {
  bool owner = true,
}) async {
  await tester.tap(find.byKey(const Key('list-list-1')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(
      owner
          ? const Key('listActionsButton')
          : const Key('memberListActionsButton'),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Import from template').last);
  await tester.pumpAndSettle();
}

Future<void> _clearTemplateSearch(WidgetTester tester) async {
  final field = find.byKey(const Key('templateSearchField'));
  await tester.tap(
    find.descendant(of: field, matching: find.byIcon(Icons.clear)),
  );
  await tester.pumpAndSettle();
}

Future<_Harness> _pumpApp(
  WidgetTester tester, {
  required FakePrivateTemplateRepository templates,
  required FakeActiveListRepository lists,
  FakeNotificationRepository? notifications,
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
        notifications ?? FakeNotificationRepository(),
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
  return _Harness(container);
}

class _Harness {
  const _Harness(this.container);

  final ProviderContainer container;
}

class _ImportingTemplateRepository extends FakePrivateTemplateRepository {
  _ImportingTemplateRepository(this.lists);

  final FakeActiveListRepository lists;
  int importCalls = 0;
  Object? failureOnce;
  int concurrentItemsBeforeFailure = 0;

  @override
  Future<TemplateImportResult> importIntoList(
    String templateId,
    List<String> selectedItemIds,
    String listId, {
    required List<String> itemRequestIds,
    required int expectedTemplateVersion,
    required int expectedListVersion,
  }) async {
    importCalls += 1;
    final failure = failureOnce;
    if (failure != null) {
      failureOnce = null;
      _appendConcurrentItems(listId, concurrentItemsBeforeFailure);
      throw failure;
    }
    final summaryIndex =
        lists.activeLists.indexWhere((summary) => summary.id == listId);
    if (summaryIndex < 0) {
      throw const PrivateTemplateFailure(
        PrivateTemplateFailureCode.unavailable,
      );
    }
    final summary = lists.activeLists[summaryIndex];
    final template = templates.firstWhere((entry) => entry.id == templateId);
    if (template.version != expectedTemplateVersion ||
        summary.version != expectedListVersion) {
      throw const PrivateTemplateFailure(PrivateTemplateFailureCode.stale);
    }
    final selected = selectedItemIds.toSet();
    final source = itemsByTemplate[templateId]!
        .where((item) => selected.contains(item.id))
        .toList()
      ..sort((first, second) => first.position.compareTo(second.position));
    final current = lists.itemsByList[listId] ?? <ActiveListItem>[];
    final now = DateTime.utc(2026, 7, 21, 18, importCalls);
    for (var index = 0; index < source.length; index += 1) {
      final item = source[index];
      current.add(
        ActiveListItem(
          id: 'imported-$importCalls-$index',
          name: item.name,
          quantity: item.quantity,
          unit: null,
          position: current.length + 1,
          version: 1,
          completedAt: null,
          completedBy: null,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    lists.itemsByList[listId] = current;
    lists.activeLists[summaryIndex] = summary.copyWith(
      version: summary.version + 1,
      itemCount: current.length,
      updatedAt: now,
    );
    return TemplateImportResult(
      listVersion: summary.version + 1,
      importedCount: source.length,
      remainingCapacity: activeListItemCapacity - current.length,
    );
  }

  void _appendConcurrentItems(String listId, int count) {
    if (count == 0) return;
    final summaryIndex =
        lists.activeLists.indexWhere((summary) => summary.id == listId);
    final summary = lists.activeLists[summaryIndex];
    final current = lists.itemsByList[listId]!;
    final now = summary.updatedAt.add(const Duration(seconds: 1));
    for (var index = 0; index < count; index += 1) {
      current.add(
        _listItem(
          id: 'concurrent-$index',
          name: 'Other device $index',
          position: current.length + 1,
        ),
      );
    }
    lists.activeLists[summaryIndex] = summary.copyWith(
      version: summary.version + 1,
      itemCount: current.length,
      updatedAt: now,
    );
  }
}

class _UnavailableTemplateRepository extends _ImportingTemplateRepository {
  _UnavailableTemplateRepository(super.lists);

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

ActiveListSummary _listSummary({
  bool isOwner = true,
  int itemCount = 0,
}) =>
    ActiveListSummary(
      id: 'list-1',
      title: 'Destination',
      status: ActiveListStatus.active,
      version: 1,
      itemCount: itemCount,
      completedItemCount: 0,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
      archivedAt: null,
      isOwner: isOwner,
      ownerProfileId: isOwner ? null : 'owner-1',
      ownerUsername: isOwner ? null : 'owner_user',
      ownerDisplayName: isOwner ? null : 'Owner User',
      callerAccessVersion: isOwner ? null : 3,
    );

ActiveListItem _listItem({
  required String id,
  required String name,
  required int position,
  ListQuantity quantity = ListQuantity.one,
  bool completed = false,
}) =>
    ActiveListItem(
      id: id,
      name: name,
      quantity: quantity,
      unit: null,
      position: position,
      version: 1,
      completedAt: completed ? DateTime.utc(2026, 7, 21, 10) : null,
      completedBy: completed ? 'member-1' : null,
      createdAt: DateTime.utc(2026, 7, 21),
      updatedAt: DateTime.utc(2026, 7, 21),
    );
