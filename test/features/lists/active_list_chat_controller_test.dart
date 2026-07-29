import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/session_state_reset.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat_repository.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_controller.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';

import '../../helpers/fake_active_list_chat_repository.dart';

void main() {
  test('initial history is bounded to 30 and rendered chronologically',
      () async {
    final repository = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 45; sequence += 1)
          activeListChatTestMessage(sequence: sequence),
      ];
    final controller = ActiveListChatController(repository, 'list-1');

    await controller.load();

    expect(repository.pageRequests, [(activeListChatInitialPageSize, null)]);
    expect(
      controller.state.messages.requireValue
          .map((message) => message.messagePosition),
      orderedEquals(List.generate(30, (index) => index + 16)),
    );
    expect(controller.state.hasMore, isTrue);
    expect(controller.state.nextBeforeMessagePosition, 16);
  });

  test('older history uses a position keyset and strictly deduplicates',
      () async {
    final repository = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 75; sequence += 1)
          activeListChatTestMessage(sequence: sequence),
      ];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();

    await controller.loadOlder();

    expect(repository.pageRequests, [(30, null), (50, 46)]);
    expect(
      controller.state.messages.requireValue
          .map((message) => message.messagePosition),
      orderedEquals(List.generate(75, (index) => index + 1)),
    );
    expect(controller.state.hasMore, isFalse);
  });

  test('send is server-confirmed, normalized, and never optimistic', () async {
    final confirmation = Completer<ActiveListChatMessage>();
    final repository = FakeActiveListChatRepository()
      ..messages = [activeListChatTestMessage(sequence: 1)]
      ..onSend = (_, __, ___) => confirmation.future;
    final controller = ActiveListChatController(
      repository,
      'list-1',
      requestIdGenerator: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    await controller.load();

    final send = controller.send('\u00a0 Olá\r\n😀 \u00a0');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.isSending, isTrue);
    expect(controller.state.messages.requireValue, hasLength(1));
    expect(repository.sentBodies, ['Olá\n😀']);

    confirmation.complete(
      activeListChatTestMessage(
        sequence: 2,
        body: 'Olá\n😀',
        isMine: true,
        username: 'current_user',
        displayName: 'Current User',
      ),
    );
    expect(await send, ActiveListChatSendOutcome.sent);
    expect(controller.state.messages.requireValue, hasLength(2));
    expect(controller.pendingSendBody, isNull);
  });

  test('uncertain retry keeps one request ID only for unchanged payload',
      () async {
    var attempt = 0;
    final repository = FakeActiveListChatRepository()
      ..onSend = (_, body, __) {
        attempt += 1;
        if (attempt == 1) return Completer<ActiveListChatMessage>().future;
        return Future.value(
          activeListChatTestMessage(
            sequence: attempt,
            body: body,
            isMine: true,
            username: 'current_user',
            displayName: 'Current User',
          ),
        );
      };
    final ids = [
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    ];
    final controller = ActiveListChatController(
      repository,
      'list-1',
      requestIdGenerator: () => ids.removeAt(0),
      requestTimeout: const Duration(milliseconds: 1),
    );

    expect(
      await controller.send('Same payload'),
      ActiveListChatSendOutcome.uncertain,
    );
    expect(controller.pendingSendBody, 'Same payload');
    expect(
      await controller.send('Same payload'),
      ActiveListChatSendOutcome.sent,
    );
    expect(repository.requestIds.take(2).toSet(), hasLength(1));

    repository.onSend =
        (_, __, ___) => Completer<ActiveListChatMessage>().future;
    expect(
      await controller.send('Edited payload'),
      ActiveListChatSendOutcome.uncertain,
    );
    expect(repository.requestIds.last, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb');
  });

  test('definitive failures clear retry identity and map bounded UI states',
      () async {
    final failures = <ActiveListChatFailureCode>[
      ActiveListChatFailureCode.rateLimited,
      ActiveListChatFailureCode.archived,
      ActiveListChatFailureCode.unavailable,
      ActiveListChatFailureCode.requestConflict,
    ];
    final repository = FakeActiveListChatRepository()
      ..onSend = (_, __, ___) async {
        throw ActiveListChatFailure(failures.removeAt(0));
      };
    var id = 0;
    final controller = ActiveListChatController(
      repository,
      'list-1',
      requestIdGenerator: () =>
          'aaaaaaaa-aaaa-4aaa-8aaa-${(++id).toString().padLeft(12, '0')}',
    );

    expect(
        await controller.send('Valid'), ActiveListChatSendOutcome.rateLimited);
    expect(controller.pendingSendBody, isNull);
    expect(await controller.send('Valid'), ActiveListChatSendOutcome.archived);
    expect(
        await controller.send('Valid'), ActiveListChatSendOutcome.unavailable);
    expect(
      await controller.send('Valid'),
      ActiveListChatSendOutcome.requestConflict,
    );
    expect(repository.requestIds.toSet(), hasLength(4));
  });

  test('rune boundary, whitespace preservation, and controls are enforced',
      () async {
    final repository = FakeActiveListChatRepository();
    final controller = ActiveListChatController(repository, 'list-1');

    expect(
      await controller.send(List.filled(2001, '😀').join()),
      ActiveListChatSendOutcome.invalid,
    );
    expect(
      await controller.send('bad\u0007control'),
      ActiveListChatSendOutcome.invalid,
    );
    expect(await controller.send(' \r\n '), ActiveListChatSendOutcome.invalid);
    expect(repository.sendCalls, 0);

    expect(
      await controller.send('  inside  spaces\n😀  '),
      ActiveListChatSendOutcome.sent,
    );
    expect(repository.sentBodies.single, 'inside  spaces\n😀');
  });

  test('delete is permission guarded and replaces the confirmed row', () async {
    final mine = activeListChatTestMessage(
      sequence: 1,
      isMine: true,
      username: 'current_user',
      displayName: 'Current User',
    );
    final other = activeListChatTestMessage(sequence: 2);
    final repository = FakeActiveListChatRepository()..messages = [mine, other];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();

    await controller.delete(other, isOwner: false);
    expect(repository.deleteCalls, 0);

    await controller.delete(mine, isOwner: false);
    expect(repository.deleteCalls, 1);
    expect(
      controller.state.messages.requireValue.first.deletionKind,
      ActiveListChatDeletionKind.sender,
    );

    await controller.delete(other, isOwner: true);
    expect(repository.deleteCalls, 2);
    expect(
      controller.state.messages.requireValue.last.deletionKind,
      ActiveListChatDeletionKind.owner,
    );
  });

  test('uncertain deletion stops loading and reconciles authoritatively',
      () async {
    final message = activeListChatTestMessage(
      sequence: 1,
      isMine: true,
      username: 'current_user',
      displayName: 'Current User',
    );
    final repository = FakeActiveListChatRepository()
      ..messages = [message]
      ..onDelete = (_, __) => Completer<ActiveListChatMessage>().future;
    final controller = ActiveListChatController(
      repository,
      'list-1',
      requestTimeout: const Duration(milliseconds: 1),
    );
    await controller.load();

    await controller.delete(message, isOwner: false);
    await _flush();

    expect(controller.state.deletingMessageIds, isEmpty);
    expect(controller.state.notice, ActiveListChatNotice.deleteUncertain);
    expect(repository.listCalls, greaterThanOrEqualTo(2));
  });

  test('reconciliation merges arrivals, tombstones, and profile renames',
      () async {
    final first = activeListChatTestMessage(sequence: 1);
    final second = activeListChatTestMessage(sequence: 2);
    final repository = FakeActiveListChatRepository()
      ..messages = [first, second];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();

    repository.messages = [
      activeListChatTestMessage(
        sequence: 1,
        body: null,
        deletedAt: first.createdAt.add(const Duration(minutes: 1)),
        deletionKind: ActiveListChatDeletionKind.owner,
      ),
      activeListChatTestMessage(
        sequence: 2,
        displayName: 'Renamed Friend',
      ),
      activeListChatTestMessage(sequence: 3, body: 'Remote arrival'),
    ];
    await controller.reconcile();

    final messages = controller.state.messages.requireValue;
    expect(messages.map((message) => message.messagePosition), [1, 2, 3]);
    expect(messages[0].deletionKind, ActiveListChatDeletionKind.owner);
    expect(messages[1].senderDisplayName, 'Renamed Friend');
    expect(messages[2].body, 'Remote arrival');
  });

  test('reconciliation spans multiple unseen pages and updates old tombstones',
      () async {
    final oldFifth = activeListChatTestMessage(sequence: 5);
    final oldSixth = activeListChatTestMessage(sequence: 6);
    final repository = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 30; sequence += 1)
          activeListChatTestMessage(sequence: sequence),
      ];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();

    repository.messages = [
      for (var sequence = 1; sequence <= 130; sequence += 1)
        if (sequence == 5)
          activeListChatTestMessage(
            sequence: sequence,
            body: null,
            deletedAt: oldFifth.createdAt.add(const Duration(minutes: 1)),
            deletionKind: ActiveListChatDeletionKind.owner,
          )
        else if (sequence == 6)
          activeListChatTestMessage(
            sequence: sequence,
            body: null,
            deletedAt: oldSixth.createdAt.add(const Duration(minutes: 1)),
            deletionKind: ActiveListChatDeletionKind.account,
            username: null,
            displayName: null,
          )
        else
          activeListChatTestMessage(sequence: sequence),
    ];
    await controller.reconcile();

    final messages = controller.state.messages.requireValue;
    expect(messages, hasLength(130));
    expect(
      messages.map((message) => message.messagePosition),
      orderedEquals(List.generate(130, (index) => index + 1)),
    );
    expect(messages[4].deletionKind, ActiveListChatDeletionKind.owner);
    expect(messages[5].deletionKind, ActiveListChatDeletionKind.account);
    expect(messages[5].senderDisplayName, isNull);
    expect(repository.pageRequests.skip(1).toList(), [
      (50, null),
      (50, 81),
      (50, 31),
    ]);
  });

  test('malformed identity conflict preserves the last good cache', () async {
    final original = activeListChatTestMessage(sequence: 1);
    final repository = FakeActiveListChatRepository()..messages = [original];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();

    repository.messages = [
      ActiveListChatMessage(
        id: original.id,
        messagePosition: original.messagePosition,
        body: 'Conflicting body',
        createdAt: original.createdAt,
        deletedAt: null,
        deletionKind: null,
        senderUsername: original.senderUsername,
        senderDisplayName: original.senderDisplayName,
        isMine: original.isMine,
      ),
    ];
    await controller.reconcile();

    expect(controller.state.messages.requireValue.single.body, original.body);
    expect(controller.state.notice, ActiveListChatNotice.refreshFailed);

    repository.messages = [
      ActiveListChatMessage(
        id: '20000000-0000-4000-8000-000000000001',
        messagePosition: original.messagePosition,
        body: 'Different identity',
        createdAt: original.createdAt,
        deletedAt: null,
        deletionKind: null,
        senderUsername: original.senderUsername,
        senderDisplayName: original.senderDisplayName,
        isMine: original.isMine,
      ),
    ];
    await controller.reconcile();
    expect(controller.state.messages.requireValue.single.id, original.id);
    expect(controller.state.notice, ActiveListChatNotice.refreshFailed);
  });

  test('pagination failure preserves messages and exposes retry state',
      () async {
    final repository = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 31; sequence += 1)
          activeListChatTestMessage(sequence: sequence),
      ];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();
    final before = controller.state.messages.requireValue;
    repository.listFailure = StateError('offline');

    await controller.loadOlder();

    expect(controller.state.messages.requireValue, same(before));
    expect(controller.state.notice, ActiveListChatNotice.olderPageFailed);
    expect(controller.state.isLoadingOlder, isFalse);
  });

  test('reconciliation waits for a send and does not lose either result',
      () async {
    final sendConfirmation = Completer<ActiveListChatMessage>();
    final repository = FakeActiveListChatRepository()
      ..messages = [activeListChatTestMessage(sequence: 1)]
      ..onSend = (_, __, ___) => sendConfirmation.future;
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();

    final send = controller.send('Local confirmed');
    await Future<void>.delayed(Duration.zero);
    repository.messages.add(
      activeListChatTestMessage(sequence: 2, body: 'Remote concurrent'),
    );
    final reconcile = controller.reconcile();
    await Future<void>.delayed(Duration.zero);
    expect(repository.listCalls, 1);

    sendConfirmation.complete(
      activeListChatTestMessage(
        sequence: 3,
        body: 'Local confirmed',
        isMine: true,
        username: 'current_user',
        displayName: 'Current User',
      ),
    );
    await Future.wait([send, reconcile]);

    expect(
      controller.state.messages.requireValue
          .map((message) => message.messagePosition),
      [1, 2, 3],
    );
  });

  test('pagination serializes reconciliation and mutations without data loss',
      () async {
    final repository = FakeActiveListChatRepository()
      ..messages = [
        for (var sequence = 1; sequence <= 75; sequence += 1)
          activeListChatTestMessage(sequence: sequence),
      ];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();
    final olderPage = Completer<ActiveListChatPage>();
    repository.onList = (_, pageSize, before) {
      if (before == 46) return olderPage.future;
      final eligible = repository.messages
          .where(
            (message) => before == null || message.messagePosition < before,
          )
          .toList()
        ..sort(
          (left, right) =>
              right.messagePosition.compareTo(left.messagePosition),
        );
      final messages = eligible.take(pageSize).toList(growable: false);
      final hasMore = eligible.length > messages.length;
      return Future.value(
        ActiveListChatPage(
          messages: messages,
          hasMore: hasMore,
          nextBeforeMessagePosition:
              hasMore ? messages.last.messagePosition : null,
        ),
      );
    };

    final pagination = controller.loadOlder();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.isLoadingOlder, isTrue);
    expect(
      await controller.send('Blocked during pagination'),
      ActiveListChatSendOutcome.busy,
    );
    expect(repository.sendCalls, 0);

    repository.messages.add(
      activeListChatTestMessage(sequence: 76, body: 'Remote arrival'),
    );
    final reconciliation = controller.reconcile();
    await Future<void>.delayed(Duration.zero);
    expect(repository.listCalls, 2);

    olderPage.complete(
      ActiveListChatPage(
        messages: [
          for (var sequence = 45; sequence >= 1; sequence -= 1)
            activeListChatTestMessage(sequence: sequence),
        ],
        hasMore: false,
        nextBeforeMessagePosition: null,
      ),
    );
    await pagination;
    await reconciliation;

    expect(
      controller.state.messages.requireValue.map(
        (message) => message.messagePosition,
      ),
      orderedEquals(List.generate(76, (index) => index + 1)),
    );
  });

  test('unavailable reconciliation is explicit without exposing details',
      () async {
    final repository = FakeActiveListChatRepository()
      ..messages = [activeListChatTestMessage(sequence: 1)];
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();
    repository.listFailure =
        const ActiveListChatFailure(ActiveListChatFailureCode.unavailable);

    await controller.reconcile();

    expect(controller.state.notice, ActiveListChatNotice.unavailable);
    expect(controller.state.messages.requireValue, hasLength(1));
  });

  test('read marking is monotonic and refreshes unread only on change',
      () async {
    final messages = [
      activeListChatTestMessage(sequence: 1),
      activeListChatTestMessage(sequence: 2),
    ];
    final repository = FakeActiveListChatRepository()..messages = messages;
    var unreadRefreshes = 0;
    final controller = ActiveListChatController(
      repository,
      'list-1',
      refreshUnread: () async => unreadRefreshes += 1,
    );
    await controller.load();

    controller.markReadThrough(messages[1]);
    await _flush();
    controller.markReadThrough(messages[0]);
    controller.markReadThrough(messages[1]);
    await _flush();

    expect(repository.markedMessageIds, [messages[1].id]);
    expect(unreadRefreshes, 1);
  });

  test('unread refresh preserves the last good badge on transient failure',
      () async {
    final repository = FakeActiveListChatRepository()
      ..unread = const ActiveListChatUnreadCount(count: 8, isCapped: false);
    final controller = ActiveListChatUnreadController(repository, 'list-1');
    await controller.load();
    expect(controller.state.requireValue.count, 8);

    repository.unreadFailure = StateError('offline');
    await controller.reconcile();

    expect(controller.state.requireValue.count, 8);
  });

  test('concurrent reconciliation requests coalesce into one follow-up',
      () async {
    final firstPage = Completer<void>();
    final repository = _BlockingListRepository(firstPage);
    final controller = ActiveListChatController(repository, 'list-1');
    await controller.load();
    repository.block = true;

    final first = controller.reconcile();
    await Future<void>.delayed(Duration.zero);
    final second = controller.reconcile();
    final third = controller.reconcile();
    firstPage.complete();
    await Future.wait([first, second, third]);

    expect(repository.listCalls, 3);
  });

  test('session reset clears Chat retry identity, state, and registrations',
      () async {
    final repository = FakeActiveListChatRepository()
      ..onSend = (_, __, ___) async {
        throw const ActiveListChatFailure(
          ActiveListChatFailureCode.transport,
        );
      };
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue(null),
        activeListChatRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final historyBefore = container.read(
      activeListChatControllerProvider('list-1').notifier,
    );
    final unreadBefore = container.read(
      activeListChatUnreadControllerProvider('list-1').notifier,
    );
    expect(
      await historyBefore.send('Uncertain account-bound draft'),
      ActiveListChatSendOutcome.uncertain,
    );
    expect(historyBefore.pendingSendBody, 'Uncertain account-bound draft');

    container.read(resetSessionStateProvider)();

    final historyAfter = container.read(
      activeListChatControllerProvider('list-1').notifier,
    );
    expect(
      historyAfter,
      isNot(same(historyBefore)),
    );
    expect(historyAfter.pendingSendBody, isNull);
    expect(
      container.read(
        activeListChatUnreadControllerProvider('list-1').notifier,
      ),
      isNot(same(unreadBefore)),
    );
  });
}

class _BlockingListRepository extends FakeActiveListChatRepository {
  _BlockingListRepository(this.completer) {
    messages = [activeListChatTestMessage(sequence: 1)];
  }

  final Completer<void> completer;
  bool block = false;

  @override
  Future<ActiveListChatPage> listMessages(
    String listId, {
    required int pageSize,
    int? beforeMessagePosition,
  }) async {
    if (block) {
      block = false;
      await completer.future;
    }
    return super.listMessages(
      listId,
      pageSize: pageSize,
      beforeMessagePosition: beforeMessagePosition,
    );
  }
}

Future<void> _flush() async {
  for (var index = 0; index < 5; index += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
