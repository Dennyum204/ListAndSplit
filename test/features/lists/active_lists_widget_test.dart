import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_lists_screen.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fakes.dart';

void main() {
  testWidgets('overview renders loading, failure, retry, and empty states',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..pageCompleter = Completer<ActiveListPage>();
    await _pump(tester,
        repository: repository, child: const ActiveListsScreen());
    expect(find.bySemanticsLabel('Loading lists'), findsOneWidget);

    repository.pageCompleter!.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't load your lists"), findsOneWidget);
    expect(find.textContaining('offline'), findsNothing);

    repository
      ..pageCompleter = null
      ..failure = null;
    await tester.tap(find.byKey(const Key('retryListsButton')));
    await tester.pumpAndSettle();
    expect(find.text('No active lists yet'), findsOneWidget);
  });

  testWidgets(
      'overview shows active/archive metadata and preserves filter state',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..archivedLists = [
        _summary(
          id: 'list-2',
          title: 'Previous trip',
          status: ActiveListStatus.archived,
          archivedAt: DateTime.utc(2026, 7, 20, 11),
        ),
      ];
    await _pump(tester,
        repository: repository, child: const ActiveListsScreen());
    await tester.pumpAndSettle();

    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('2 items · 1 of 2 complete'), findsOneWidget);
    expect(find.byKey(const Key('createListButton')), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Previous trip'), findsOneWidget);
    expect(find.byKey(const Key('createListButton')), findsNothing);
  });

  testWidgets('overview distinguishes a shared list and approved owner',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)];
    await _pump(tester,
        repository: repository, child: const ActiveListsScreen());
    await tester.pumpAndSettle();

    expect(find.text('Shared by Owner User'), findsOneWidget);
    expect(find.text('@owner_user'), findsNothing);
  });

  testWidgets('create validates input, preserves it, and blocks duplicate taps',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..createCompleter = Completer<ActiveListSummary>();
    await _pump(tester,
        repository: repository, child: const ActiveListsScreen());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('createListButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmCreateListButton')));
    await tester.pump();
    expect(find.text('Enter a title between 1 and 80 characters.'),
        findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.enterText(
      find.byKey(const Key('createListTitle')),
      '  Groceries  ',
    );
    await tester.tap(find.byKey(const Key('confirmCreateListButton')));
    await tester.pump();
    expect(repository.createCalls, 1);
    expect(find.text('  Groceries  '), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirmCreateListButton')),
          )
          .onPressed,
      isNull,
    );

    repository.createCompleter!.complete(_summary());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('createListTitle')), findsNothing);
  });

  testWidgets('detail renders exact item quantity and archived read-only state',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..archivedLists = [
        _summary(
          status: ActiveListStatus.archived,
          archivedAt: DateTime.utc(2026, 7, 20, 11),
        ),
      ]
      ..itemsByList['list-1'] = [_item()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('1.5 pack'), findsOneWidget);
    expect(find.textContaining('Archived lists are read-only'), findsWidgets);
    expect(find.byKey(const Key('addItemButton')), findsNothing);
    expect(find.byKey(const Key('itemActions-item-1')), findsNothing);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('completeItem-item-1')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Import from template'), findsNothing);
  });

  testWidgets('detail add form localizes units and retains invalid quantity',
      (tester) async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
      themeMode: ThemeMode.dark,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addItemButton')));
    await tester.pumpAndSettle();
    expect(find.text('No unit'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('itemNameField')), 'Coffee');
    await tester.enterText(
        find.byKey(const Key('itemQuantityField')), '1.0000');
    await tester.tap(find.byKey(const Key('saveItemButton')));
    await tester.pump();

    expect(find.text('1.0000'), findsOneWidget);
    expect(
        find.text('Check the entered values and try again.'), findsOneWidget);
    expect(repository.mutationCalls, 0);
  });

  testWidgets(
      'detail supports duplicate add, complete, reopen, edit, and delete',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..itemsByList['list-1'] = [_item()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('addItemButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('itemNameField')), 'Coffee');
    await tester.tap(find.byKey(const Key('saveItemButton')));
    await tester.pumpAndSettle();
    expect(repository.itemsByList['list-1'], hasLength(2));
    expect(find.text('Coffee'), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('completeItem-item-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('completeItem-item-1')))
          .value,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('completeItem-item-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('completeItem-item-1')))
          .value,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('itemNameField')), 'Tea');
    await tester.enterText(find.byKey(const Key('itemQuantityField')), '0.001');
    await tester.tap(find.byKey(const Key('saveItemButton')));
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('0.001 pack'), findsOneWidget);

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete item').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete this item?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirmDeleteItemButton')));
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsNothing);
    expect(repository.itemsByList['list-1'], hasLength(1));
  });

  testWidgets('item rows render zero, one, two, and many assignees compactly',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final owner = _participant();
    final member = _participant(
      profileId: 'member-1',
      username: 'member',
      displayName: 'Member',
      isOwner: false,
      accessVersion: 2,
    );
    final third = _participant(
      profileId: 'third-1',
      username: 'third',
      displayName: 'Third',
      isOwner: false,
      accessVersion: 2,
    );
    final fourth = _participant(
      profileId: 'fourth-1',
      username: 'fourth',
      displayName: 'Fourth',
      isOwner: false,
      accessVersion: 2,
    );
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [owner, member, third, fourth]
      ..itemsByList['list-1'] = [
        _item(id: 'zero', name: 'Zero'),
        _item(id: 'one', name: 'One', assignees: [_assignee(owner)]),
        _item(
          id: 'two',
          name: 'Two',
          assignees: [_assignee(owner), _assignee(member)],
        ),
        _item(
          id: 'many',
          name: 'Many',
          assignees: [
            _assignee(owner),
            _assignee(member),
            _assignee(third),
            _assignee(fourth),
          ],
        ),
      ];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unassigned'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Owner, Member'), findsOneWidget);
    expect(find.text('Owner, Member +2'), findsOneWidget);
    expect(
      find.byKey(const Key('itemAssigneeAvatar-one-user-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('itemAssigneeAvatar-two-user-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('itemAssigneeAvatar-two-member-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('itemAssigneeAvatar-many-third-1')),
      findsNothing,
    );
    final twoSummary = find.byKey(const Key('itemAssignees-two'));
    await tester.ensureVisible(twoSummary);
    await tester.pump();
    expect(
      tester.getSemantics(twoSummary).label,
      contains('Two. Assigned to Owner, Member.'),
    );
    expect(
      tester.getSemantics(find.byKey(const Key('itemAssignees-zero'))).label,
      contains('Zero. Unassigned.'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('item editor saves a complete multi-assignee selection',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final owner = _participant();
    final member = _participant(
      profileId: 'member-1',
      username: 'member',
      displayName: 'Member',
      isOwner: false,
      accessVersion: 2,
    );
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [owner, member]
      ..itemsByList['list-1'] = [
        _item(assignees: [_assignee(owner)]),
      ];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
      themeMode: ThemeMode.dark,
      textScale: 2,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    expect(find.text('Assignees'), findsOneWidget);
    expect(find.text('Owner (you)'), findsOneWidget);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('itemAssignee-user-1')),
          )
          .value,
      isTrue,
    );
    final memberAssignee = find.byKey(const Key('itemAssignee-member-1'));
    await tester.ensureVisible(memberAssignee);
    await tester.tap(memberAssignee);
    await tester.tap(find.byKey(const Key('saveItemButton')));
    await tester.pumpAndSettle();

    expect(repository.itemAssigneeCalls.last, ['member-1', 'user-1']);
    expect(find.text('Owner, Member'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Portuguese assignment row and editor use localized copy',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final owner = _participant();
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [owner]
      ..itemsByList['list-1'] = [
        _item(assignees: [_assignee(owner)]),
      ];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
      locale: const Locale('pt'),
    );
    await tester.pumpAndSettle();

    final summary = find.byKey(const Key('itemAssignees-item-1'));
    expect(
      tester.getSemantics(summary).label,
      contains('Coffee. Atribuído a Owner.'),
    );

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar').last);
    await tester.pumpAndSettle();

    expect(find.text('Responsáveis'), findsOneWidget);
    expect(find.text('Owner (você)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('remote assignment refresh closes and discards a stale editor',
      (tester) async {
    final owner = _participant();
    final member = _participant(
      profileId: 'member-1',
      username: 'member',
      displayName: 'Member',
      isOwner: false,
      accessVersion: 2,
    );
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [owner, member]
      ..itemsByList['list-1'] = [_item()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('itemNameField')),
      'Unsaved local draft',
    );

    await repository.updateItem(
      'list-1',
      'item-1',
      'Remote item',
      quantity: ListQuantity.fromThousandths(1500),
      unit: ListUnit.pack,
      assigneeProfileIds: ['member-1'],
      expectedListVersion: 3,
      expectedItemVersion: 2,
    );
    final registry = container.read(reconciliationRegistryProvider);
    await registry.reconcile();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('itemNameField')), findsNothing);
    expect(find.text('Unsaved local draft'), findsNothing);
    expect(find.text('Remote item'), findsOneWidget);
    expect(
      find.text(
        'This item changed on another device. Your draft was discarded and the latest item was loaded.',
      ),
      findsOneWidget,
    );

    await Future.wait([registry.reconcile(), registry.reconcile()]);
    await tester.pump();

    expect(find.byKey(const Key('itemNameField')), findsNothing);
    expect(
      find.text(
        'This item changed on another device. Your draft was discarded and the latest item was loaded.',
      ),
      findsOneWidget,
    );
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'removed-assignee race closes editor and refreshes authoritatively',
      (tester) async {
    final repository = _InvalidAssignmentWidgetRepository();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('itemAssignee-member-1')),
          )
          .value,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('saveItemButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('itemNameField')), findsNothing);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(
      find.text(
        'This list changed on another device. The latest version was loaded.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'This item changed on another device. Your draft was discarded and the latest item was loaded.',
      ),
      findsNothing,
    );
    expect(repository.mutationCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'access loss closes an open item editor and exits to Lists exactly once',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)]
      ..participantsByList['list-1'] = [
        _participant(
          profileId: 'member-1',
          username: 'member',
          displayName: 'Member',
          isOwner: false,
          accessVersion: 2,
        ),
      ]
      ..itemsByList['list-1'] = [_item()];
    final router = _detailTestRouter();
    addTearDown(router.dispose);
    await _pumpRoutedDetail(
      tester,
      repository: repository,
      router: router,
      userId: 'member-1',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );
    var listTransitions = 0;
    var previousPath = router.routeInformationProvider.value.uri.path;
    void trackRoute() {
      final nextPath = router.routeInformationProvider.value.uri.path;
      if (previousPath != '/lists' && nextPath == '/lists') {
        listTransitions += 1;
      }
      previousPath = nextPath;
    }

    router.routeInformationProvider.addListener(trackRoute);
    addTearDown(
      () => router.routeInformationProvider.removeListener(trackRoute),
    );

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('itemNameField')),
      'Discard this draft',
    );

    repository.failure =
        const ActiveListFailure(ActiveListFailureCode.unavailable);
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/lists');
    expect(listTransitions, 1);
    expect(find.byKey(const Key('itemNameField')), findsNothing);
    expect(find.text('Lists landing'), findsOneWidget);
    expect(
      find.text(
        'You no longer have access to this list. The latest Lists view was loaded.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'This item changed on another device. Your draft was discarded and the latest item was loaded.',
      ),
      findsNothing,
    );

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(listTransitions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'remote archive closes an open item editor without duplicate navigation',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)]
      ..itemsByList['list-1'] = [_item()];
    final router = _detailTestRouter();
    addTearDown(router.dispose);
    await _pumpRoutedDetail(
      tester,
      repository: repository,
      router: router,
      userId: 'member-1',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );
    var listTransitions = 0;
    var previousPath = router.routeInformationProvider.value.uri.path;
    void trackRoute() {
      final nextPath = router.routeInformationProvider.value.uri.path;
      if (previousPath != '/lists' && nextPath == '/lists') {
        listTransitions += 1;
      }
      previousPath = nextPath;
    }

    router.routeInformationProvider.addListener(trackRoute);
    addTearDown(
      () => router.routeInformationProvider.removeListener(trackRoute),
    );

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();

    await repository.setArchived(
      'list-1',
      archived: true,
      expectedVersion: 3,
    );
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/lists');
    expect(listTransitions, 1);
    expect(find.byKey(const Key('itemNameField')), findsNothing);
    expect(find.text('Lists landing'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(listTransitions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail renames, archives, restores, and confirms list deletion',
      (tester) async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('renameListTitle')), 'Weekend');
    await tester.tap(find.byKey(const Key('confirmRenameListButton')));
    await tester.pumpAndSettle();
    expect(find.text('Weekend'), findsOneWidget);

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Archived lists are read-only'), findsWidgets);

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('addItemButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently').last);
    await tester.pumpAndSettle();
    expect(find.text('Delete this list permanently?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(repository.activeLists, hasLength(1));
  });

  testWidgets(
      'stale rename closes before delayed recovery and shows authoritative title',
      (tester) async {
    final repository = _StaleRenameWidgetRepository();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('renameListTitle')),
      'Old Device Name',
    );
    await tester.tap(find.byKey(const Key('confirmRenameListButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('renameListTitle')), findsNothing);
    expect(
      tester
          .widget<PopupMenuButton<dynamic>>(
            find.byKey(const Key('listActionsButton')),
          )
          .enabled,
      isTrue,
    );
    expect(find.text('Checking the current list after the requestâ€¦'),
        findsOneWidget);
    expect(repository.recovery.isCompleted, isFalse);

    repository.recovery.complete(repository.activeLists.single);
    await tester.pumpAndSettle();

    expect(find.text('Weekend Shopping Updated'), findsOneWidget);
    expect(find.text('Old Device Name'), findsNothing);
    expect(
      find.text(
        'This list changed on another device. The latest version was loaded.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('failed stale recovery enables a visible retry action',
      (tester) async {
    final repository = _StaleRenameWidgetRepository();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('renameListTitle')),
      'Stale draft',
    );
    await tester.tap(find.byKey(const Key('confirmRenameListButton')));
    await tester.pump();
    repository.recovery.completeError(StateError('offline'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('renameListTitle')), findsNothing);
    expect(
      find.text(
        "We couldn't load the current list. Try again before making more changes.",
      ),
      findsOneWidget,
    );
    expect(
        find.byKey(const Key('retryListDetailRecoveryButton')), findsOneWidget);
    expect(
      tester
          .widget<PopupMenuButton<dynamic>>(
            find.byKey(const Key('listActionsButton')),
          )
          .enabled,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('retryListDetailRecoveryButton')));
    await tester.pumpAndSettle();
    expect(find.text('Weekend Shopping Updated'), findsOneWidget);
    expect(
        find.byKey(const Key('retryListDetailRecoveryButton')), findsNothing);
  });

  testWidgets('stale item editor closes and discards its draft',
      (tester) async {
    final repository = _StaleItemWidgetRepository();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('itemActions-item-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('itemNameField')), 'Old item');
    await tester.tap(find.byKey(const Key('saveItemButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('itemNameField')), findsNothing);
    expect(repository.recovery.isCompleted, isFalse);

    repository.recovery.complete(repository.activeLists.single);
    await tester.pumpAndSettle();
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text('Old item'), findsNothing);
    expect(
      find.text(
        'This list changed on another device. The latest version was loaded.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('rename dialog shows bounded write progress', (tester) async {
    final repository = _DelayedRenameWidgetRepository();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('listActionsButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('renameListTitle')), 'Weekend');
    await tester.tap(find.byKey(const Key('confirmRenameListButton')));
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('confirmRenameListButton')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('confirmRenameListButton')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(
            find
                .ancestor(
                  of: find.text('Cancel').last,
                  matching: find.byType(TextButton),
                )
                .last,
          )
          .onPressed,
      isNull,
    );

    repository.completeRename('Weekend');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('renameListTitle')), findsNothing);
    expect(find.text('Weekend'), findsOneWidget);
  });

  testWidgets('member detail hides owner controls and confirms leaving',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)]
      ..itemsByList['list-1'] = [_item()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listActionsButton')), findsNothing);
    expect(find.byKey(const Key('memberListActionsButton')), findsOneWidget);
    expect(find.byKey(const Key('listMembersButton')), findsOneWidget);
    expect(find.byKey(const Key('addItemButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('memberListActionsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Import from template'), findsOneWidget);
    await tester.tap(find.text('Leave list').last);
    await tester.pumpAndSettle();
    expect(find.text('Leave this list?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(repository.mutationCalls, 0);
  });

  testWidgets(
      'archived member keeps leave access while content stays read-only',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..archivedLists = [
        _summary(
          isOwner: false,
          status: ActiveListStatus.archived,
          archivedAt: DateTime.utc(2026, 7, 20, 11),
        ),
      ]
      ..itemsByList['list-1'] = [_item()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('memberListActionsButton')), findsOneWidget);
    expect(find.byKey(const Key('addItemButton')), findsNothing);
    expect(
      tester
          .widget<Checkbox>(find.byKey(const Key('completeItem-item-1')))
          .onChanged,
      isNull,
    );
    await tester.tap(find.byKey(const Key('memberListActionsButton')));
    await tester.pumpAndSettle();
    expect(find.text('Import from template'), findsNothing);
  });

  testWidgets('revoked member mutation returns safely to Lists',
      (tester) async {
    final repository = _RevokedAccessRepository();
    final router = GoRouter(
      initialLocation: '/lists/list-1',
      routes: [
        GoRoute(
          path: '/lists',
          builder: (_, __) => const Scaffold(body: Text('Lists landing')),
          routes: [
            GoRoute(
              path: ':listId',
              builder: (_, state) => ActiveListDetailScreen(
                listId: state.pathParameters['listId']!,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedUserIdProvider.overrideWithValue('user-1'),
          activeListRepositoryProvider.overrideWithValue(repository),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('completeItem-item-1')));
    await tester.pumpAndSettle();

    expect(find.text('Lists landing'), findsOneWidget);
    expect(
      find.text(
        'You no longer have access to this list. The latest Lists view was loaded.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mounted remote detail title reconciles without route recreation',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(title: 'Original title', isOwner: false)];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );

    await repository.renameList(
      'list-1',
      'Remote title',
      expectedVersion: 3,
    );
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pump();

    expect(find.text('Remote title'), findsOneWidget);
    expect(find.text('Original title'), findsNothing);
  });

  testWidgets(
      'remote archive exits detail once and duplicate invalidations stay silent',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)];
    final router = GoRouter(
      initialLocation: '/lists/list-1',
      routes: [
        GoRoute(
          path: '/lists',
          builder: (_, __) => const Scaffold(body: Text('Lists landing')),
          routes: [
            GoRoute(
              path: ':listId',
              builder: (_, state) => ActiveListDetailScreen(
                listId: state.pathParameters['listId']!,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verifiedUserIdProvider.overrideWithValue('member-1'),
          activeListRepositoryProvider.overrideWithValue(repository),
          notificationRepositoryProvider.overrideWithValue(
            FakeNotificationRepository(),
          ),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );
    var listTransitions = 0;
    var previousPath = router.routeInformationProvider.value.uri.path;
    void trackRoute() {
      final nextPath = router.routeInformationProvider.value.uri.path;
      if (previousPath != '/lists' && nextPath == '/lists') {
        listTransitions += 1;
      }
      previousPath = nextPath;
    }

    router.routeInformationProvider.addListener(trackRoute);
    addTearDown(
      () => router.routeInformationProvider.removeListener(trackRoute),
    );

    await repository.setArchived(
      'list-1',
      archived: true,
      expectedVersion: 3,
    );
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/lists');
    expect(find.text('Lists landing'), findsOneWidget);
    expect(listTransitions, 1);
    expect(find.byType(SnackBar), findsNothing);

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(listTransitions, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _RevokedAccessRepository extends FakeActiveListRepository {
  _RevokedAccessRepository() {
    activeLists = [_summary(isOwner: false)];
    itemsByList['list-1'] = [_item()];
  }

  @override
  Future<ActiveListItem> setItemCompleted(
    String listId,
    String itemId, {
    required bool completed,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) {
    throw const ActiveListFailure(ActiveListFailureCode.unavailable);
  }
}

class _InvalidAssignmentWidgetRepository extends FakeActiveListRepository {
  _InvalidAssignmentWidgetRepository() {
    final owner = _participant();
    final member = _participant(
      profileId: 'member-1',
      username: 'member',
      displayName: 'Member',
      isOwner: false,
      accessVersion: 2,
    );
    activeLists = [_summary()];
    participantsByList['list-1'] = [owner, member];
    itemsByList['list-1'] = [
      _item(assignees: [_assignee(member)]),
    ];
  }

  @override
  Future<ActiveListItem> updateItem(
    String listId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    required List<String> assigneeProfileIds,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) {
    mutationCalls += 1;
    participantsByList[listId] = [
      for (final participant in participantsByList[listId]!)
        if (participant.profileId != 'member-1') participant,
    ];
    itemsByList[listId] = [_item()];
    throw const ActiveListFailure(ActiveListFailureCode.invalid);
  }
}

class _StaleRenameWidgetRepository extends FakeActiveListRepository {
  _StaleRenameWidgetRepository() {
    activeLists = [_summary(title: 'Weekend Shopping')];
  }

  final recovery = Completer<ActiveListSummary>();
  var _delayNextGet = true;

  @override
  Future<ActiveListSummary> getList(String listId) {
    if (_delayNextGet && activeLists.single.version > 3) {
      _delayNextGet = false;
      return recovery.future;
    }
    return super.getList(listId);
  }

  @override
  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  }) async {
    mutationCalls += 1;
    activeLists = [
      _summary(
        title: 'Weekend Shopping Updated',
        version: expectedVersion + 1,
      ),
    ];
    throw const ActiveListFailure(ActiveListFailureCode.stale);
  }
}

class _StaleItemWidgetRepository extends FakeActiveListRepository {
  _StaleItemWidgetRepository() {
    activeLists = [_summary()];
    itemsByList['list-1'] = [_item()];
  }

  final recovery = Completer<ActiveListSummary>();
  var _delayNextGet = true;

  @override
  Future<ActiveListSummary> getList(String listId) {
    if (_delayNextGet && activeLists.single.version > 3) {
      _delayNextGet = false;
      return recovery.future;
    }
    return super.getList(listId);
  }

  @override
  Future<ActiveListItem> updateItem(
    String listId,
    String itemId,
    String name, {
    required ListQuantity quantity,
    required ListUnit? unit,
    required List<String> assigneeProfileIds,
    required int expectedListVersion,
    required int expectedItemVersion,
  }) async {
    mutationCalls += 1;
    activeLists = [_summary(version: expectedListVersion + 1)];
    itemsByList[listId] = [
      _item(name: 'Tea', version: expectedItemVersion + 1),
    ];
    throw const ActiveListFailure(ActiveListFailureCode.stale);
  }
}

class _DelayedRenameWidgetRepository extends FakeActiveListRepository {
  _DelayedRenameWidgetRepository() {
    activeLists = [_summary()];
  }

  final _rename = Completer<ActiveListSummary>();

  @override
  Future<ActiveListSummary> renameList(
    String listId,
    String title, {
    required int expectedVersion,
  }) {
    mutationCalls += 1;
    return _rename.future;
  }

  void completeRename(String title) {
    final updated = _summary(title: title, version: 4);
    activeLists = [updated];
    _rename.complete(updated);
  }
}

GoRouter _detailTestRouter() => GoRouter(
      initialLocation: '/lists/list-1',
      routes: [
        GoRoute(
          path: '/lists',
          builder: (_, __) => const Scaffold(body: Text('Lists landing')),
          routes: [
            GoRoute(
              path: ':listId',
              builder: (_, state) => ActiveListDetailScreen(
                listId: state.pathParameters['listId']!,
              ),
            ),
          ],
        ),
      ],
    );

Future<void> _pumpRoutedDetail(
  WidgetTester tester, {
  required FakeActiveListRepository repository,
  required GoRouter router,
  required String userId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(userId),
        activeListRepositoryProvider.overrideWithValue(repository),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeActiveListRepository repository,
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('user-1'),
        activeListRepositoryProvider.overrideWithValue(repository),
        notificationRepositoryProvider.overrideWithValue(
          FakeNotificationRepository(),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
        home: child,
      ),
    ),
  );
}

ActiveListSummary _summary({
  String id = 'list-1',
  String title = 'Groceries',
  ActiveListStatus status = ActiveListStatus.active,
  DateTime? archivedAt,
  int version = 3,
  bool isOwner = true,
}) {
  return ActiveListSummary(
    id: id,
    title: title,
    status: status,
    version: version,
    itemCount: 2,
    completedItemCount: 1,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
    archivedAt: archivedAt,
    isOwner: isOwner,
    ownerProfileId: isOwner ? null : 'owner-1',
    ownerUsername: isOwner ? null : 'owner_user',
    ownerDisplayName: isOwner ? null : 'Owner User',
    callerAccessVersion: isOwner ? null : 6,
  );
}

ActiveListItem _item({
  String id = 'item-1',
  String name = 'Coffee',
  int version = 2,
  List<ActiveListAssignee> assignees = const [],
}) {
  return ActiveListItem(
    id: id,
    name: name,
    quantity: ListQuantity.fromThousandths(1500),
    unit: ListUnit.pack,
    position: 1,
    version: version,
    completedAt: null,
    completedBy: null,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
    assignees: assignees,
  );
}

ActiveListParticipant _participant({
  String profileId = 'user-1',
  String username = 'owner',
  String displayName = 'Owner',
  bool isOwner = true,
  int? accessVersion,
}) =>
    ActiveListParticipant(
      profileId: profileId,
      username: username,
      displayName: displayName,
      isOwner: isOwner,
      accessVersion: accessVersion,
    );

ActiveListAssignee _assignee(ActiveListParticipant participant) =>
    ActiveListAssignee(
      profileId: participant.profileId,
      username: participant.username,
      displayName: participant.displayName,
      isOwner: participant.isOwner,
      assignedAt: DateTime.utc(2026, 7, 24, 12),
    );
