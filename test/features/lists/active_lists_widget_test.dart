import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
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
}

Future<void> _pump(
  WidgetTester tester, {
  required FakeActiveListRepository repository,
  required Widget child,
  ThemeMode themeMode = ThemeMode.light,
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
}) {
  return ActiveListSummary(
    id: id,
    title: title,
    status: status,
    version: 3,
    itemCount: 2,
    completedItemCount: 1,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
    archivedAt: archivedAt,
  );
}

ActiveListItem _item() {
  return ActiveListItem(
    id: 'item-1',
    name: 'Coffee',
    quantity: ListQuantity.fromThousandths(1500),
    unit: ListUnit.pack,
    position: 1,
    version: 2,
    completedAt: null,
    completedBy: null,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
  );
}
