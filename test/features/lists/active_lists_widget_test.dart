import 'dart:async';
import 'dart:ui' show SemanticsFlag;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/general_note.dart';
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
    final zeroSummary = find.byKey(const Key('itemAssignees-zero'));
    expect(
      tester.getSemantics(zeroSummary).label,
      contains('Zero. Unassigned.'),
    );
    final twoSummary = find.byKey(const Key('itemAssignees-two'));
    await tester.ensureVisible(twoSummary);
    await tester.pump();
    expect(
      tester.getSemantics(twoSummary).label,
      contains('Two. Assigned to Owner, Member.'),
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

    final itemActions = find.byKey(const Key('itemActions-item-1'));
    await tester.scrollUntilVisible(
      itemActions,
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('activeListItems')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pump();
    await tester.tap(itemActions);
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

  testWidgets(
      'General Note editor resolves a member mention and saves without rich text',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [
        _participant(),
        _participant(
          profileId: 'member-1',
          username: 'susana_user',
          displayName: 'Susana',
          isOwner: false,
          accessVersion: 2,
        ),
      ];
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generalNoteCard')), findsOneWidget);
    expect(find.byKey(const Key('generalNoteEmpty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'Olá 👋 @Su',
    );
    await tester.pump();

    expect(
      find.byKey(const Key('generalNoteMention-member-1')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Mention Susana, at susana_user'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('generalNoteMention-member-1')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'Olá 👋 @susana_user ',
    );

    await tester.tap(find.byKey(const Key('saveGeneralNoteButton')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generalNoteField')), findsNothing);
    expect(repository.noteMentionCalls.single, ['member-1']);
    expect(repository.noteTextCalls.single, 'Olá 👋 @susana_user');
    expect(find.byKey(const Key('generalNoteText')), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp('Resolved mention of Susana, at susana_user'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'General Note suggestions are deterministic and self mentions stay explicitly selected',
      (tester) async {
    final owner = _participant();
    final alpha = _participant(
      profileId: 'alpha-1',
      username: 'alpha_user',
      displayName: 'Alpha',
      isOwner: false,
      accessVersion: 2,
    );
    final beta = _participant(
      profileId: 'beta-1',
      username: 'beta_user',
      displayName: 'Beta',
      isOwner: false,
      accessVersion: 2,
    );
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [beta, owner, alpha]
      ..pendingByList['list-1'] = const [
        ActiveListAccessProfile(
          profileId: 'pending-1',
          username: 'aardvark_pending',
          displayName: 'Pending',
          accessVersion: 1,
        ),
      ];
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('generalNoteField')), '@');
    await tester.pump();

    final orderedSuggestionKeys = find
        .descendant(
          of: find.byKey(const Key('generalNoteMentionSuggestions')),
          matching: find.byType(ListTile),
        )
        .evaluate()
        .map((element) => (element.widget as ListTile).key)
        .toList(growable: false);
    expect(
      orderedSuggestionKeys,
      const [
        Key('generalNoteMention-alpha-1'),
        Key('generalNoteMention-beta-1'),
        Key('generalNoteMention-user-1'),
      ],
    );
    expect(
      find.byKey(const Key('generalNoteMention-pending-1')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const Key('generalNoteMention-user-1')),
    );
    await tester.tap(find.byKey(const Key('generalNoteMention-user-1')));
    await tester.pump();

    final selectedSemantic = find.byKey(
      const Key('generalNoteSelectedSemantic-user-1'),
    );
    expect(find.text('Owner (@owner)'), findsOneWidget);
    expect(
      tester.getSemantics(selectedSemantic).label,
      contains('Selected mention of Owner, at owner'),
    );
    expect(
      tester.getSemantics(selectedSemantic).hasFlag(SemanticsFlag.isSelected),
      isTrue,
    );
    expect(
      tester
          .getSize(find.byKey(const Key('generalNoteSelected-user-1')))
          .height,
      greaterThanOrEqualTo(48),
    );

    final field = find.byKey(const Key('generalNoteField'));
    final resolvedText = tester.widget<TextField>(field).controller!.text;
    await tester.tap(find.byKey(const Key('generalNoteSelected-user-1')));
    await tester.pump();

    expect(find.text('Owner (@owner)'), findsNothing);
    expect(tester.widget<TextField>(field).controller!.text, resolvedText);
    await tester.tap(find.byKey(const Key('cancelGeneralNoteButton')));
    await tester.pumpAndSettle();

    expect(repository.mutationCalls, 0);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'resolved repeated mention tokens are all highlighted by stable ID',
      (tester) async {
    const mention = ActiveListNoteMention(
      profileId: 'member-1',
      username: 'susana_user',
      displayName: 'Susana',
    );
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..generalNotesByList['list-1'] = ActiveListGeneralNote(
        listVersion: 3,
        text: 'Ask @susana_user, then remind @SUSANA_USER.',
        version: 2,
        updatedAt: DateTime.utc(2026, 7, 25, 9),
        mentions: const [mention],
      );
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    final richText = tester.widget<SelectableText>(find.byType(SelectableText));
    final mentionSpans = richText.textSpan!.children!
        .whereType<TextSpan>()
        .where(
          (span) => span.text?.toLowerCase() == '@susana_user',
        )
        .toList(growable: false);
    expect(mentionSpans, hasLength(2));
    expect(
      mentionSpans.every((span) => span.style?.fontWeight == FontWeight.w700),
      isTrue,
    );
    expect(
      find.bySemanticsLabel(
        RegExp('Resolved mention of Susana, at susana_user'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'General Note failed save stays recoverable, repeated Save is guarded, and Cancel is safe',
      (tester) async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'A draft that must survive',
    );
    repository.failure = const ActiveListFailure(ActiveListFailureCode.generic);

    final save = find.byKey(const Key('saveGeneralNoteButton'));
    await tester.tap(save);
    await tester.pump();
    await tester.pump();

    expect(repository.mutationCalls, 1);
    expect(find.byKey(const Key('generalNoteDialogStatus')), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const Key('generalNoteDialogStatus')))
          .hasFlag(SemanticsFlag.isLiveRegion),
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('generalNoteDialogStatus')),
        matching: find.text('Something went wrong. Please try again.'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'A draft that must survive',
    );
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    repository.failure = null;
    final pendingSave = Completer<void>();
    repository.generalNoteMutationCompleter = pendingSave;
    await tester.tap(save);
    await tester.pump();
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    expect(repository.mutationCalls, 2);
    pendingSave.complete();
    await tester.pumpAndSettle();
    expect(repository.mutationCalls, 2);
    expect(find.byKey(const Key('generalNoteField')), findsNothing);

    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'Cancelled draft',
    );
    await tester.tap(find.byKey(const Key('cancelGeneralNoteButton')));
    await tester.pumpAndSettle();

    expect(repository.mutationCalls, 2);
    expect(find.byKey(const Key('generalNoteField')), findsNothing);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'stale General Note Save preserves the draft and offers deterministic recovery',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..generalNotesByList['list-1'] = ActiveListGeneralNote(
        listVersion: 3,
        text: 'Original Note',
        version: 1,
        updatedAt: DateTime.utc(2026, 7, 25, 9),
      );
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'Unsaved simultaneous edit',
    );

    await repository.renameList(
      'list-1',
      'Groceries',
      expectedVersion: 3,
    );
    repository.generalNotesByList['list-1'] = ActiveListGeneralNote(
      listVersion: 4,
      text: 'Remote winning edit',
      version: 2,
      updatedAt: DateTime.utc(2026, 7, 25, 10),
    );
    await tester.tap(find.byKey(const Key('saveGeneralNoteButton')));
    await tester.pumpAndSettle();

    expect(repository.noteTextCalls, ['Unsaved simultaneous edit']);
    expect(find.byKey(const Key('generalNoteConflict')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'Unsaved simultaneous edit',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('saveGeneralNoteButton')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('useLatestGeneralNoteButton')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'Remote winning edit',
    );
    expect(find.byKey(const Key('generalNoteConflict')), findsNothing);
    await tester.tap(find.byKey(const Key('cancelGeneralNoteButton')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('General Note editor enforces 2000 Unicode code points',
      (tester) async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('generalNoteField'));
    final exact = List.filled(2000, '😀').join();
    final overflow = '$exact😀';

    await tester.enterText(field, exact);
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.text.runes.length,
      2000,
    );
    expect(find.text('0 characters remaining (maximum 2000)'), findsOneWidget);

    await tester.enterText(field, overflow);
    await tester.pump();
    expect(
      tester.widget<TextField>(field).controller!.text,
      exact,
      reason: 'The formatter must reject the 2001st code point atomically.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dirty Note draft survives remote Note and eligibility reconciliation',
      (tester) async {
    final owner = _participant();
    final member = _participant(
      profileId: 'member-1',
      username: 'susana_user',
      displayName: 'Susana',
      isOwner: false,
      accessVersion: 2,
    );
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [owner, member]
      ..generalNotesByList['list-1'] = ActiveListGeneralNote(
        listVersion: 3,
        text: 'Original @susana_user',
        version: 1,
        updatedAt: DateTime.utc(2026, 7, 25, 9),
        mentions: const [
          ActiveListNoteMention(
            profileId: 'member-1',
            username: 'susana_user',
            displayName: 'Susana',
          ),
        ],
      );
    await _pump(
      tester,
      repository: repository,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );

    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'Preserve this @susana_user draft',
    );
    await tester.pump();

    repository.failure =
        const ActiveListFailure(ActiveListFailureCode.transport);
    await container.read(reconciliationRegistryProvider).reconcile();
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pump();
    expect(find.byKey(const Key('generalNoteConflict')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'Preserve this @susana_user draft',
    );

    repository.failure = null;
    await repository.renameList(
      'list-1',
      'Groceries',
      expectedVersion: 3,
    );
    repository
      ..participantsByList['list-1'] = [owner]
      ..generalNotesByList['list-1'] = ActiveListGeneralNote(
        listVersion: 4,
        text: 'Remote version',
        version: 2,
        updatedAt: DateTime.utc(2026, 7, 25, 10),
      );
    await container.read(reconciliationRegistryProvider).reconcile();
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generalNoteConflict')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'Preserve this @susana_user draft',
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('saveGeneralNoteButton')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('keepGeneralNoteDraftButton')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveGeneralNoteButton')));
    await tester.pumpAndSettle();

    expect(repository.noteMentionCalls.single, isEmpty);
    expect(
      repository.generalNotesByList['list-1']!.text,
      'Preserve this @susana_user draft',
    );
    expect(find.byKey(const Key('generalNoteConflict')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'clean Note editor adopts remote state and archived detail is accessible read-only',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..generalNotesByList['list-1'] = ActiveListGeneralNote(
        listVersion: 3,
        text: 'Original',
        version: 1,
        updatedAt: DateTime.utc(2026, 7, 25, 9),
      );
    await _pump(
      tester,
      repository: repository,
      themeMode: ThemeMode.dark,
      textScale: 2,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();

    await repository.renameList(
      'list-1',
      'Groceries',
      expectedVersion: 3,
    );
    repository.generalNotesByList['list-1'] = ActiveListGeneralNote(
      listVersion: 4,
      text: 'Remote clean version',
      version: 2,
      updatedAt: DateTime.utc(2026, 7, 25, 10),
    );
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('generalNoteConflict')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('generalNoteField')))
          .controller!
          .text,
      'Remote clean version',
    );
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    final archivedAt = DateTime.utc(2026, 7, 25, 11);
    final archivedRepository = FakeActiveListRepository()
      ..archivedLists = [
        _summary(
          status: ActiveListStatus.archived,
          archivedAt: archivedAt,
          version: 5,
        ),
      ]
      ..generalNotesByList['list-1'] = ActiveListGeneralNote(
        listVersion: 5,
        text: 'Remote clean version',
        version: 2,
        updatedAt: DateTime.utc(2026, 7, 25, 10),
      );
    await _pump(
      tester,
      repository: archivedRepository,
      themeMode: ThemeMode.dark,
      textScale: 2,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Remote clean version'), findsOneWidget);
    expect(find.byKey(const Key('editGeneralNoteButton')), findsNothing);
    expect(find.bySemanticsLabel('General Note, read-only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Portuguese General Note editor remains usable in dark theme and large text',
      (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary()]
      ..participantsByList['list-1'] = [
        _participant(),
        _participant(
          profileId: 'member-1',
          username: 'susana_user',
          displayName: 'Susana',
          isOwner: false,
          accessVersion: 2,
        ),
      ];
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      repository: repository,
      locale: const Locale('pt'),
      themeMode: ThemeMode.dark,
      textScale: 1.6,
      child: const ActiveListDetailScreen(listId: 'list-1'),
    );
    await tester.pumpAndSettle();

    final edit = find.byKey(const Key('editGeneralNoteButton'));
    expect(find.text('Nota Geral'), findsOneWidget);
    expect(tester.getSize(edit).height, greaterThanOrEqualTo(48));
    expect(Theme.of(tester.element(edit)).brightness, Brightness.dark);
    await tester.tap(edit);
    await tester.pumpAndSettle();

    expect(find.text('Editar Nota Geral'), findsWidgets);
    expect(
      find.text(
        'Use @ para mencionar explicitamente um participante elegível da lista.',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      '@su',
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel('Mencionar Susana, arroba susana_user'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
      'access loss or list deletion closes the dirty Note editor and exits once',
      (tester) async {
    final repository = FakeActiveListRepository()
      ..activeLists = [_summary(isOwner: false)];
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
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'Unsaved private draft',
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
    repository.failure =
        const ActiveListFailure(ActiveListFailureCode.unavailable);
    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(router.routeInformationProvider.value.uri.path, '/lists');
    expect(find.byKey(const Key('generalNoteField')), findsNothing);
    expect(find.text('Lists landing'), findsOneWidget);
    expect(
      find.text(
        'You no longer have access to this list. The latest Lists view was loaded.',
      ),
      findsOneWidget,
    );
    expect(listTransitions, 1);

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pump();
    expect(listTransitions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'remote archive closes the dirty Note editor and exits without duplicates',
      (tester) async {
    final repository = FakeActiveListRepository()..activeLists = [_summary()];
    final router = _detailTestRouter();
    addTearDown(router.dispose);
    await _pumpRoutedDetail(
      tester,
      repository: repository,
      router: router,
      userId: 'user-1',
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ActiveListDetailScreen)),
    );
    await tester.tap(find.byKey(const Key('editGeneralNoteButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('generalNoteField')),
      'Discard when archived',
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
    expect(find.byKey(const Key('generalNoteField')), findsNothing);
    expect(find.text('Lists landing'), findsOneWidget);
    expect(listTransitions, 1);
    expect(
      find.text(
        'This list was archived elsewhere. It is available under Archived.',
      ),
      findsOneWidget,
    );

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pump();
    expect(listTransitions, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.takeException(), isNull);
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
    expect(
      find.text(
        'This list was archived elsewhere. It is available under Archived.',
      ),
      findsOneWidget,
    );

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
    expect(
      find.text(
        'This list was archived elsewhere. It is available under Archived.',
      ),
      findsOneWidget,
    );

    await container.read(reconciliationRegistryProvider).reconcile();
    await tester.pumpAndSettle();

    expect(listTransitions, 1);
    expect(find.byType(SnackBar), findsOneWidget);
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
