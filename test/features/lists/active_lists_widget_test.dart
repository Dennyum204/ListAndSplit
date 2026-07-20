import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  int version = 3,
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
  );
}

ActiveListItem _item({String name = 'Coffee', int version = 2}) {
  return ActiveListItem(
    id: 'item-1',
    name: name,
    quantity: ListQuantity.fromThousandths(1500),
    unit: ListUnit.pack,
    position: 1,
    version: version,
    completedAt: null,
    completedBy: null,
    createdAt: DateTime.utc(2026, 7, 20, 9),
    updatedAt: DateTime.utc(2026, 7, 20, 10),
  );
}
