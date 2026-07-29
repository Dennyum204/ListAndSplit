import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_coordinator.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/bounded_realtime_websocket_transport.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/realtime/supabase_account_realtime_gateway.dart';
import 'package:list_and_split/features/lists/domain/active_list_chat.dart';
import 'package:list_and_split/features/lists/presentation/active_list_chat_providers.dart';
import 'package:list_and_split/features/profile/presentation/profile_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_active_list_chat_repository.dart';
import '../../helpers/scripted_realtime_websocket.dart';

void main() {
  test('production Chat Broadcast refreshes only mounted Chat projections',
      () async {
    final repository = FakeActiveListChatRepository()
      ..messages = [activeListChatTestMessage(sequence: 1)]
      ..unread = const ActiveListChatUnreadCount(count: 1, isCapped: false);
    final container = ProviderContainer(
      overrides: [
        verifiedUserIdProvider.overrideWithValue('profile-a'),
        activeListChatRepositoryProvider.overrideWithValue(repository),
      ],
    );
    final historySubscription = container.listen(
      activeListChatControllerProvider('list-1'),
      (_, __) {},
      fireImmediately: true,
    );
    final unreadSubscription = container.listen(
      activeListChatUnreadControllerProvider('list-1'),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(historySubscription.close);
    addTearDown(unreadSubscription.close);
    addTearDown(container.dispose);
    await _waitUntil(
      () =>
          container
              .read(activeListChatControllerProvider('list-1'))
              .messages
              .hasValue &&
          container
              .read(activeListChatUnreadControllerProvider('list-1'))
              .hasValue,
      'initial Chat projections',
    );

    var fullOnlyReconciliations = 0;
    container.read(reconciliationRegistryProvider).register(
          () async => fullOnlyReconciliations += 1,
        );
    final connector = ScriptedRealtimeConnector();
    final transport = BoundedRealtimeWebSocketTransport(
      connector: connector.connect,
    );
    final client = SupabaseClient(
      'https://example.invalid',
      'publishable-test-value',
      realtimeClientOptions: RealtimeClientOptions(
        transport: transport.connect,
      ),
    );
    final diagnostics = <AccountRealtimeDiagnostic>[];
    final coordinator = AccountReconciliationCoordinator(
      SupabaseAccountRealtimeGateway(client),
      container.read(reconciliationRegistryProvider),
      diagnosticSink: diagnostics.add,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });

    coordinator.setAccount('profile-a');
    await _waitUntil(() => connector.channels.length == 1, 'account transport');
    connector.channels.single.completeHandshake();
    await _waitUntil(
      () => diagnostics.any(
        (entry) => entry.update.status == AccountRealtimeStatus.subscribed,
      ),
      'private account subscription',
    );
    await _waitUntil(
      () => fullOnlyReconciliations == 1,
      'authoritative subscribed reconciliation',
    );

    final listCallsBeforeChat = repository.listCalls;
    final unreadCallsBeforeChat = repository.unreadCalls;
    repository.messages.add(
      activeListChatTestMessage(sequence: 2, body: 'Remote Chat message'),
    );
    repository.unread =
        const ActiveListChatUnreadCount(count: 2, isCapped: false);
    connector.channels.single.emitAccountChatInvalidation('profile-a');

    await _waitUntil(
      () =>
          repository.listCalls == listCallsBeforeChat + 1 &&
          repository.unreadCalls == unreadCallsBeforeChat + 1,
      'scoped Chat reconciliation',
    );
    expect(fullOnlyReconciliations, 1);
    expect(
      container
          .read(activeListChatControllerProvider('list-1'))
          .messages
          .requireValue
          .last
          .body,
      'Remote Chat message',
    );
    expect(
      container
          .read(activeListChatUnreadControllerProvider('list-1'))
          .requireValue
          .count,
      2,
    );

    connector.channels.single.emitAccountInvalidation('profile-a');
    await _waitUntil(
      () => fullOnlyReconciliations == 2,
      'global reconciliation',
    );
    expect(client.realtime.getChannels(), hasLength(1));
  });
}

Future<void> _waitUntil(
  bool Function() condition,
  String expectedState,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('The expected state was not reached: $expectedState.');
}
