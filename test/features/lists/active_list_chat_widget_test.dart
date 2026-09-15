import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/theme/app_theme.dart';
import 'package:list_and_split/features/lists/domain/active_list.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';
import 'package:list_and_split/features/lists/domain/active_list_repository.dart';
import 'package:list_and_split/features/lists/domain/list_quantity.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_providers.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_detail_screen.dart';
import 'package:list_and_split/features/lists/presentation/active_list_providers.dart';
import 'package:list_and_split/features/notifications/presentation/notification_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:list_and_split/l10n/generated/app_localizations.dart';

import '../../helpers/fake_active_list_chat_repository.dart';
import '../../helpers/fakes.dart';
import '../../support/ui_preview_capture.dart';

void main() {
  setUpAll(prepareUiPreviewFonts);
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          'list detail redesign keeps all item controls dark=$dark scale=$scale',
          (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final now = DateTime.utc(2026, 7, 29);
        final lists = _listsRepository()
          ..itemsByList['list-1'] = [
            for (var index = 0; index < 2; index++)
              ActiveListItem(
                id: 'item-$index',
                name: index == 0 ? 'Sunglasses' : 'Towels',
                quantity: ListQuantity.fromThousandths((index + 1) * 1000),
                unit: ListUnit.piece,
                position: index + 1,
                version: 1,
                completedAt: index == 0 ? now : null,
                completedBy: index == 0 ? 'current-profile' : null,
                createdAt: now,
                updatedAt: now,
              ),
          ];
        await _pump(tester,
            lists: lists,
            chat: FakeActiveListChatRepository(),
            initialLocation: '/lists/list-1',
            dark: dark,
            textScale: scale);
        expect(find.byKey(const Key('listSectionNavigation')), findsOneWidget);
        expect(find.text('Sunglasses'), findsOneWidget);
        expect(find.text('Towels'), findsOneWidget);
        expect(find.byKey(const Key('addItemButton')).hitTestable(),
            findsOneWidget);
        await captureUiPreview(tester,
            'list-detail-${dark ? 'dark' : 'light'}-${scale == 2 ? 'large' : 'standard'}');
        final note = find.byKey(const Key('editGeneralNoteButton'));
        await tester.scrollUntilVisible(note, 180,
            scrollable: find.descendant(
              of: find.byKey(const Key('activeListItems')),
              matching: find.byType(Scrollable),
            ));
        await tester.pumpAndSettle();
        expect(note.hitTestable(), findsOneWidget);
        expect(lists.createCalls, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'rapid Split section taps push once and return to the same detail',
      (tester) async {
    final harness = await _pump(tester,
        lists: _listsRepository(),
        chat: FakeActiveListChatRepository(),
        initialLocation: '/lists/list-1');
    final section = find.byKey(const Key('listSection-split'));
    await tester.tap(section);
    await tester.tap(section);
    await tester.pumpAndSettle();
    expect(find.text('Split route fixture'), findsOneWidget);
    harness.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ActiveListDetailScreen), findsOneWidget);
    expect(find.text('Split route fixture'), findsNothing);
    expect(tester.widget<TextButton>(section).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('pt')]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
            'Chat redesign supports narrow scale=$scale ${locale.languageCode} dark=$dark',
            (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final chat = FakeActiveListChatRepository()
            ..messages = [
              activeListChatTestMessage(
                  sequence: 1, body: 'Ready for the trip?'),
              activeListChatTestMessage(
                  sequence: 2, body: 'Sim, vamos! 😀', isMine: true),
            ];
          await _pump(tester,
              lists: _listsRepository(),
              chat: chat,
              initialLocation: '/lists/list-1/chat',
              locale: locale,
              dark: dark,
              textScale: scale);
          expect(
              find.byKey(const Key('listSectionNavigation')), findsOneWidget);
          await captureUiPreview(tester,
              'chat-${locale.languageCode}-${dark ? 'dark' : 'light'}-${scale == 2 ? 'large' : 'standard'}');
          final composer = find.byKey(const Key('listChatComposer'));
          await tester.enterText(composer, 'Olá!');
          await tester.pump();
          final send = find.byKey(const Key('listChatSendButton'));
          expect(send.hitTestable(), findsOneWidget);
          expect(tester.getSize(send).height, greaterThanOrEqualTo(48));
          expect(chat.sendCalls, 0);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets(
      'detail Chat action opens the exact list route and returns safely',
      (tester) async {
    final lists = _listsRepository();
    final chat = FakeActiveListChatRepository();
    final harness = await _pump(
      tester,
      lists: lists,
      chat: chat,
      initialLocation: '/lists/list-1',
    );

    expect(find.byKey(const Key('listChatButton')), findsOneWidget);
    await tester.tap(find.byKey(const Key('listChatButton')));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveListChatScreen), findsOneWidget);
    expect(find.text('Weekend chat'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
    expect(chat.requestedListIds, everyElement('list-1'));
    expect(lists.createCalls, 0);

    harness.router.pop();
    await tester.pumpAndSettle();
    expect(find.byType(ActiveListDetailScreen), findsOneWidget);
    expect(find.byType(ActiveListChatScreen), findsNothing);
  });

  testWidgets(
      'Chat to Split removes the hidden read marker and clears its draft',
      (tester) async {
    final lists = _listsRepository();
    final chat = FakeActiveListChatRepository()
      ..messages = [activeListChatTestMessage(sequence: 1, body: 'Visible')];
    final harness = await _pump(tester,
        lists: lists, chat: chat, initialLocation: '/lists/list-1/chat');
    await tester.enterText(find.byKey(const Key('listChatComposer')), 'Unsent');
    await tester.pump();
    final originalReadIds = List<String>.of(chat.markedMessageIds);
    await tester.tap(find.byKey(const Key('listSection-split')));
    await tester.pumpAndSettle();
    expect(
        find.byType(ActiveListChatScreen, skipOffstage: false), findsNothing);
    expect(find.text('Split route fixture'), findsOneWidget);
    final incoming =
        activeListChatTestMessage(sequence: 2, body: 'Still unread');
    chat.messages.add(incoming);
    chat.unread = const ActiveListChatUnreadCount(count: 1, isCapped: false);
    await harness.container
        .read(reconciliationRegistryProvider)
        .reconcile(scope: ReconciliationScope.chat);
    await tester.pumpAndSettle();
    expect(chat.markedMessageIds, originalReadIds);
    expect(chat.markedMessageIds, isNot(contains(incoming.id)));
    expect(find.text('Unsent', skipOffstage: false), findsNothing);
    expect(chat.sendCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'access loss after Chat to Split has one navigation and message owner',
      (tester) async {
    final lists = _listsRepository();
    final harness = await _pump(tester,
        lists: lists,
        chat: FakeActiveListChatRepository(),
        initialLocation: '/lists/list-1/chat');
    await tester.tap(find.byKey(const Key('listSection-split')));
    await tester.pumpAndSettle();
    lists.failure = const ActiveListFailure(ActiveListFailureCode.unavailable);
    final registry = harness.container.read(reconciliationRegistryProvider);
    await registry.reconcile();
    await tester.pumpAndSettle();
    await registry.reconcile();
    await tester.pump();
    expect(find.text('Lists landing'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
        find.byType(ActiveListChatScreen, skipOffstage: false), findsNothing);
    expect(find.textContaining('list chat.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('initial loading resolves to the empty recoverable conversation',
      (tester) async {
    final page = Completer<ActiveListChatPage>();
    final chat = FakeActiveListChatRepository()
      ..onList = (_, __, ___) => page.future;
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
      settle: false,
    );
    await tester.pump();

    expect(find.bySemanticsLabel('Loading list chat'), findsOneWidget);
    expect(find.byKey(const Key('listChatComposer')), findsNothing);

    page.complete(
      ActiveListChatPage(
        messages: const [],
        hasMore: false,
        nextBeforeMessagePosition: null,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.byKey(const Key('listChatComposer')), findsOneWidget);
  });

  testWidgets('badge is list-specific, exact through 99, and capped at 99+',
      (tester) async {
    final capped = FakeActiveListChatRepository()
      ..unread = const ActiveListChatUnreadCount(
        count: activeListChatUnreadCap,
        isCapped: true,
      );
    await _pump(
      tester,
      lists:
          _listsRepository(status: ActiveListStatus.archived, isOwner: false),
      chat: capped,
      initialLocation: '/lists/list-1',
    );

    expect(find.text('99+'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Open list chat, 99+ unread messages',
      ),
      findsOneWidget,
    );
  });

  testWidgets('zero unread has no badge and keeps the base Chat semantics',
      (tester) async {
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: FakeActiveListChatRepository(),
      initialLocation: '/lists/list-1',
    );
    expect(find.text('99+'), findsNothing);
    expect(
      find.bySemanticsLabel('Open list chat'),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Open list chat')).rect.size,
      tester.getSize(find.byKey(const Key('listChatButton'))),
      reason: 'Chat accessibility focus must cover only its own button',
    );
  });

  testWidgets('ordinary unread count is displayed exactly', (tester) async {
    final chat = FakeActiveListChatRepository()
      ..unread = const ActiveListChatUnreadCount(
        count: 42,
        isCapped: false,
      );
    await _pump(
      tester,
      lists: _listsRepository(isOwner: false),
      chat: chat,
      initialLocation: '/lists/list-1',
    );

    expect(find.text('42'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Open list chat, 42 unread messages'),
      findsOneWidget,
    );
  });

  testWidgets('one unread message has exact singular badge semantics',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..unread = const ActiveListChatUnreadCount(
        count: 1,
        isCapped: false,
      );
    await _pump(
      tester,
      lists: _listsRepository(isOwner: false),
      chat: chat,
      initialLocation: '/lists/list-1',
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('listChatButton')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Open list chat, 1 unread message'),
      findsOneWidget,
    );
  });

  testWidgets('confirmed send clears only the unchanged submitted draft',
      (tester) async {
    final confirmation = Completer<ActiveListChatMessage>();
    final chat = FakeActiveListChatRepository()
      ..onSend = (_, __, ___) => confirmation.future;
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );

    await tester.enterText(
      find.byKey(const Key('listChatComposer')),
      '  First draft 😀  ',
    );
    await tester.pump();
    final sendButton = find.byKey(const Key('listChatSendButton'));
    await tester.ensureVisible(sendButton);
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
    await tester.tap(sendButton);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('listChatComposer')),
      'Edited while sending',
    );
    expect(chat.sendCalls, 1);

    confirmation.complete(
      activeListChatTestMessage(
        sequence: 1,
        body: 'First draft 😀',
        isMine: true,
        username: 'current_user',
        displayName: 'Current User',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First draft 😀'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('listChatComposer')))
          .controller!
          .text,
      'Edited while sending',
    );

    chat.onSend = null;
    await tester.tap(find.byKey(const Key('listChatSendButton')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('listChatComposer')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('uncertain send keeps the draft and retries idempotently',
      (tester) async {
    var failUncertainly = true;
    final chat = FakeActiveListChatRepository()
      ..onSend = (_, body, __) async {
        if (failUncertainly) {
          throw const ActiveListChatFailure(
            ActiveListChatFailureCode.transport,
          );
        }
        return activeListChatTestMessage(
          sequence: 1,
          body: body,
          isMine: true,
          username: 'current_user',
          displayName: 'Current User',
        );
      };
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );
    await tester.enterText(
      find.byKey(const Key('listChatComposer')),
      'Retry this exact message',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('listChatSendButton')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(chat.sendCalls, 1);
    expect(
      find.textContaining('send result could not be confirmed'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('listChatComposer')))
          .controller!
          .text,
      'Retry this exact message',
    );

    failUncertainly = false;
    await tester.tap(find.byKey(const Key('listChatSendButton')));
    await tester.pumpAndSettle();

    expect(chat.requestIds, hasLength(2));
    expect(chat.requestIds.toSet(), hasLength(1));
    expect(find.text('Retry this exact message'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('listChatComposer')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('rapid repeated confirmation cannot double-submit',
      (tester) async {
    final confirmation = Completer<ActiveListChatMessage>();
    final chat = FakeActiveListChatRepository()
      ..onSend = (_, __, ___) => confirmation.future;
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );
    await tester.enterText(
      find.byKey(const Key('listChatComposer')),
      'One request',
    );
    await tester.pump();
    final sendButton = find.byKey(const Key('listChatSendButton'));
    await tester.ensureVisible(sendButton);

    await tester.tap(sendButton);
    await tester.tap(sendButton);
    await tester.pump();

    expect(chat.sendCalls, 1);
    confirmation.complete(
      activeListChatTestMessage(
        sequence: 1,
        body: 'One request',
        isMine: true,
        username: 'current_user',
        displayName: 'Current User',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('messages distinguish mine, others, and every tombstone',
      (tester) async {
    final senderBase = activeListChatTestMessage(sequence: 3);
    final ownerBase = activeListChatTestMessage(sequence: 4);
    final accountBase = activeListChatTestMessage(sequence: 5);
    final chat = FakeActiveListChatRepository()
      ..messages = [
        activeListChatTestMessage(
          sequence: 1,
          body: 'Mine',
          isMine: true,
          username: 'current_user',
          displayName: 'Current User',
        ),
        activeListChatTestMessage(sequence: 2, body: 'Theirs'),
        activeListChatTestMessage(
          sequence: 3,
          body: null,
          deletedAt: senderBase.createdAt.add(const Duration(minutes: 1)),
          deletionKind: ActiveListChatDeletionKind.sender,
        ),
        activeListChatTestMessage(
          sequence: 4,
          body: null,
          deletedAt: ownerBase.createdAt.add(const Duration(minutes: 1)),
          deletionKind: ActiveListChatDeletionKind.owner,
        ),
        activeListChatTestMessage(
          sequence: 5,
          body: null,
          deletedAt: accountBase.createdAt.add(const Duration(minutes: 1)),
          deletionKind: ActiveListChatDeletionKind.account,
          username: null,
          displayName: null,
        ),
      ];
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );

    final scrollable = find.descendant(
      of: find.byKey(const Key('listChatMessages')),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    final labels = [
      ('You', 'Mine'),
      ('Friend User (@friend_user)', 'Theirs'),
      ('Friend User (@friend_user)', 'Message deleted by its sender'),
      ('Friend User (@friend_user)', 'Message deleted by the list owner'),
      ('Deleted account', 'Message removed after account deletion'),
    ];
    for (var index = 0; index < chat.messages.length; index++) {
      final message = chat.messages[index];
      final card = find.byKey(Key('chat-message-${message.id}'));
      await tester.scrollUntilVisible(card, 150, scrollable: scrollable);
      await tester.pumpAndSettle();
      expect(find.descendant(of: card, matching: find.text(labels[index].$1)),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(labels[index].$2)),
          findsOneWidget);
      expect(
          find.descendant(
              of: card,
              matching: find.byKey(Key('delete-chat-message-${message.id}'))),
          index < 2 ? findsOneWidget : findsNothing);
    }
  });

  testWidgets('archived chat remains readable and removes mutation controls',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [activeListChatTestMessage(sequence: 1)];
    await _pump(
      tester,
      lists: _listsRepository(status: ActiveListStatus.archived),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );

    expect(find.byKey(const Key('listChatArchivedBanner')), findsOneWidget);
    expect(find.byKey(const Key('listChatComposer')), findsNothing);
    expect(find.byTooltip('Delete message'), findsNothing);
    expect(find.text('Message'), findsOneWidget);
  });

  testWidgets('a member may delete only their own active message',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [
        activeListChatTestMessage(
          sequence: 1,
          body: 'Mine',
          isMine: true,
          username: 'current_user',
          displayName: 'Current User',
        ),
        activeListChatTestMessage(sequence: 2, body: 'Owner message'),
      ];
    await _pump(
      tester,
      lists: _listsRepository(isOwner: false),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );

    expect(
      find.byKey(
        const Key(
          'delete-chat-message-10000000-0000-4000-8000-000000000001',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const Key(
          'delete-chat-message-10000000-0000-4000-8000-000000000002',
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('delete confirmation waits for the authoritative tombstone',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [
        activeListChatTestMessage(sequence: 1, body: 'Remove this'),
      ];
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );

    await tester.tap(
      find.byKey(
        const Key(
          'delete-chat-message-10000000-0000-4000-8000-000000000001',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Delete this message?'), findsOneWidget);
    expect(chat.deleteCalls, 0);

    await tester.tap(
      find.byKey(const Key('confirmDeleteChatMessageButton')),
    );
    await tester.pumpAndSettle();

    expect(chat.deleteCalls, 1);
    expect(find.text('Message deleted by the list owner'), findsOneWidget);
    expect(find.text('Remove this'), findsNothing);
  });

  testWidgets(
      'remote archive and restore transition in place on the Chat route',
      (tester) async {
    final lists = _listsRepository();
    final harness = await _pump(
      tester,
      lists: lists,
      chat: FakeActiveListChatRepository(),
      initialLocation: '/lists/list-1/chat',
    );

    await lists.setArchived(
      'list-1',
      archived: true,
      expectedVersion: 4,
    );
    await harness.container
        .read(activeListDetailControllerProvider('list-1').notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/lists/list-1/chat',
    );
    expect(find.byKey(const Key('listChatArchivedBanner')), findsOneWidget);
    expect(find.byKey(const Key('listChatComposer')), findsNothing);

    await lists.setArchived(
      'list-1',
      archived: false,
      expectedVersion: 5,
    );
    await harness.container
        .read(activeListDetailControllerProvider('list-1').notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(
      harness.router.routeInformationProvider.value.uri.path,
      '/lists/list-1/chat',
    );
    expect(find.byKey(const Key('listChatArchivedBanner')), findsNothing);
    expect(find.byKey(const Key('listChatComposer')), findsOneWidget);
  });

  testWidgets('initial failure recovers through the explicit retry',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..listFailure = StateError('private offline details');
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
      settle: false,
    );
    await tester.pumpAndSettle();

    expect(find.text("We couldn't load this chat"), findsOneWidget);
    expect(find.textContaining('private offline'), findsNothing);

    chat.listFailure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('toolbar refresh remains authoritative and manually available',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [
        activeListChatTestMessage(sequence: 1, body: 'Initial'),
      ];
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );
    final calls = chat.listCalls;
    chat.messages.add(
      activeListChatTestMessage(sequence: 2, body: 'After refresh'),
    );

    await tester.tap(find.byKey(const Key('listChatRefreshButton')));
    await tester.pumpAndSettle();

    expect(chat.listCalls, calls + 1);
    expect(find.text('After refresh'), findsOneWidget);
  });

  testWidgets('older-page failure keeps an inline retry without losing history',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 31; sequence += 1)
          activeListChatTestMessage(
            sequence: sequence,
            body: 'Message $sequence',
          ),
      ];
    final harness = await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('listChatMessages')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    chat.listFailure = StateError('offline');

    await tester.tap(find.byKey(const Key('listChatLoadOlderButton')));
    await tester.pumpAndSettle();

    expect(find.text('Retry older messages'), findsOneWidget);
    expect(
      harness.container
          .read(activeListChatControllerProvider('list-1'))
          .messages
          .requireValue
          .last
          .body,
      'Message 31',
    );
    expect(find.textContaining('offline'), findsNothing);

    chat.listFailure = null;
    await tester.tap(find.byKey(const Key('listChatLoadOlderButton')));
    await tester.pumpAndSettle();
    expect(find.text('Retry older messages'), findsNothing);
  });

  testWidgets('older loading preserves the viewport and remote arrivals wait',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 75; sequence += 1)
          activeListChatTestMessage(
            sequence: sequence,
            body: 'Message $sequence',
          ),
      ];
    final harness = await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('listChatMessages')),
        matching: find.byType(Scrollable),
      ),
    );
    scrollable.position.jumpTo(0);
    await tester.pump();
    final before = scrollable.position.pixels;
    await tester.tap(find.byKey(const Key('listChatLoadOlderButton')));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(before));
    expect(
      harness.container
          .read(activeListChatControllerProvider('list-1'))
          .messages
          .requireValue
          .first
          .body,
      'Message 1',
    );

    scrollable.position.jumpTo(0);
    await tester.pump();
    chat.messages.add(
      activeListChatTestMessage(sequence: 76, body: 'Remote newest'),
    );
    await harness.container
        .read(activeListChatControllerProvider('list-1').notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listChatNewMessagesButton')), findsOneWidget);
    expect(
      harness.container
          .read(activeListChatControllerProvider('list-1'))
          .messages
          .requireValue
          .last
          .body,
      'Remote newest',
    );
    await tester.tap(find.byKey(const Key('listChatNewMessagesButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('listChatNewMessagesButton')), findsNothing);
    expect(find.text('Remote newest'), findsOneWidget);
    expect(
        chat.markedMessageIds.last, activeListChatTestMessage(sequence: 76).id);
  });

  testWidgets('new arrival at the bottom stays anchored and is marked visible',
      (tester) async {
    final chat = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 30; sequence += 1)
          activeListChatTestMessage(
            sequence: sequence,
            body: 'Initial message $sequence',
          ),
      ];
    final harness = await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
    );
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('listChatMessages')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(scrollable.position.extentAfter, lessThanOrEqualTo(24));
    chat.markedMessageIds.clear();
    chat.nextMarkChanged = true;
    chat.messages.add(
      activeListChatTestMessage(sequence: 31, body: 'Arrived at bottom'),
    );

    await harness.container
        .read(activeListChatControllerProvider('list-1').notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('listChatNewMessagesButton')), findsNothing);
    expect(find.text('Arrived at bottom'), findsOneWidget);
    expect(
      chat.markedMessageIds.last,
      activeListChatTestMessage(sequence: 31).id,
    );
  });

  testWidgets('access loss exits once and discards the composer',
      (tester) async {
    final lists = _listsRepository();
    final harness = await _pump(
      tester,
      lists: lists,
      chat: FakeActiveListChatRepository(),
      initialLocation: '/lists/list-1/chat',
    );
    await tester.enterText(
      find.byKey(const Key('listChatComposer')),
      'Unsaved private draft',
    );

    lists.failure = const ActiveListFailure(ActiveListFailureCode.unavailable);
    await harness.container
        .read(activeListDetailControllerProvider('list-1').notifier)
        .reconcile();
    await tester.pumpAndSettle();

    expect(find.text('Lists landing'), findsOneWidget);
    expect(find.text('Unsaved private draft'), findsNothing);
    expect(
      find.text(
        'You no longer have access to this list chat. '
        'The latest Lists view was loaded.',
      ),
      findsOneWidget,
    );

    await harness.container
        .read(activeListDetailControllerProvider('list-1').notifier)
        .reconcile();
    await tester.pump();
    expect(
      find.textContaining('You no longer have access to this list chat'),
      findsOneWidget,
    );
  });

  testWidgets('Portuguese dark mode and 200% text handle long Unicode safely',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chat = FakeActiveListChatRepository()
      ..messages = [
        activeListChatTestMessage(
          sequence: 1,
          body: '${List.filled(100, 'palavramuitolonga').join()} 😀👨‍👩‍👧‍👦',
        ),
      ];
    await _pump(
      tester,
      lists: _listsRepository(),
      chat: chat,
      initialLocation: '/lists/list-1/chat',
      locale: const Locale('pt'),
      dark: true,
      textScale: 2,
    );

    expect(find.text('Conversa de Weekend'), findsOneWidget);
    expect(find.byKey(const Key('listChatComposer')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('listChatComposer')),
      'Olá\nsegunda linha 😀',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('listChatComposer')))
          .focusNode!
          .hasFocus,
      isTrue,
    );
    expect(find.bySemanticsLabel('Enviar mensagem'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.byType(ActiveListChatScreen))).brightness,
      Brightness.dark,
    );
  });
}

class _Harness {
  const _Harness(this.container, this.router);

  final ProviderContainer container;
  final GoRouter router;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required FakeActiveListRepository lists,
  required FakeActiveListChatRepository chat,
  required String initialLocation,
  Locale locale = const Locale('en'),
  bool dark = false,
  double textScale = 1,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      verifiedUserIdProvider.overrideWithValue('current-profile'),
      activeListRepositoryProvider.overrideWithValue(lists),
      activeListChatRepositoryProvider.overrideWithValue(chat),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
    ],
  );
  final router = GoRouter(
    initialLocation: initialLocation,
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
            routes: [
              GoRoute(
                path: 'split',
                builder: (_, __) =>
                    const Scaffold(body: Text('Split route fixture')),
              ),
              GoRoute(
                path: 'chat',
                builder: (_, state) => ActiveListChatScreen(
                  listId: state.pathParameters['listId']!,
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: uiPreviewBoundary(child!),
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return _Harness(container, router);
}

FakeActiveListRepository _listsRepository({
  ActiveListStatus status = ActiveListStatus.active,
  bool isOwner = true,
}) {
  final now = DateTime.utc(2026, 7, 29, 10);
  final summary = ActiveListSummary(
    id: 'list-1',
    title: 'Weekend',
    status: status,
    version: 4,
    itemCount: 0,
    completedItemCount: 0,
    createdAt: now.subtract(const Duration(days: 1)),
    updatedAt: now,
    archivedAt: status == ActiveListStatus.archived ? now : null,
    isOwner: isOwner,
    ownerProfileId: isOwner ? null : 'owner-profile',
    ownerUsername: isOwner ? null : 'owner_user',
    ownerDisplayName: isOwner ? null : 'Owner User',
    callerAccessVersion: isOwner ? null : 2,
  );
  return FakeActiveListRepository()
    ..activeLists = status == ActiveListStatus.active ? [summary] : []
    ..archivedLists = status == ActiveListStatus.archived ? [summary] : []
    ..participantsByList['list-1'] = [
      ActiveListParticipant(
        profileId: 'current-profile',
        username: 'current_user',
        displayName: 'Current User',
        isOwner: isOwner,
      ),
    ];
}
