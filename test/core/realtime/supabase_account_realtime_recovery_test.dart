import 'package:flutter_test/flutter_test.dart';
import 'package:list_and_split/app/reconciliation/account_reconciliation_coordinator.dart';
import 'package:list_and_split/core/realtime/account_realtime_gateway.dart';
import 'package:list_and_split/core/realtime/bounded_realtime_websocket_transport.dart';
import 'package:list_and_split/core/realtime/reconciliation_registry.dart';
import 'package:list_and_split/core/realtime/supabase_account_realtime_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/scripted_realtime_websocket.dart';

void main() {
  test(
      'joined account channel recovers a stalled reconnect with one live callback',
      () async {
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
    final registry = ReconciliationRegistry();
    var reconciliations = 0;
    registry.register(() async => reconciliations += 1);
    final coordinator = AccountReconciliationCoordinator(
      SupabaseAccountRealtimeGateway(client),
      registry,
      closedChannelRetryDelay: const Duration(days: 1),
      diagnosticSink: diagnostics.add,
    );
    addTearDown(() async {
      await coordinator.dispose();
      await client.dispose();
    });

    coordinator.setAccount('profile-a');
    await _waitUntil(
      () => connector.channels.length == 1,
      'initial transport',
    );
    final joinedChannel = connector.channels.single;
    joinedChannel.completeHandshake();
    await _waitUntil(
      () => diagnostics.any(
        (entry) => entry.update.status == AccountRealtimeStatus.subscribed,
      ),
      'initial subscription',
    );
    expect(joinedChannel.joinRequests, 1);
    expect(client.realtime.getChannels(), hasLength(1));

    await joinedChannel.closeFromNetwork();
    await _waitUntil(
      () => diagnostics.any(
        (entry) => entry.update.status == AccountRealtimeStatus.channelError,
      ),
      'network-loss status',
    );

    coordinator.resume();
    await _waitUntil(
      () => connector.channels.length == 2,
      'stalled reconnect transport',
    );
    final stalledReconnect = connector.channels[1];
    expect(stalledReconnect.rawHandshakeCompleted, isFalse);
    expect(stalledReconnect.joinRequests, 0);

    stalledReconnect.fireHandshakeDeadline();
    await _waitUntil(
      () =>
          diagnostics
              .where(
                (entry) =>
                    entry.update.status == AccountRealtimeStatus.channelError,
              )
              .length >=
          2,
      'stalled-handshake error status',
    );
    expect(stalledReconnect.deadlineFired, isTrue);
    expect(stalledReconnect.rawHandshakeCompleted, isFalse);

    coordinator.resume();
    await _waitUntil(
      () => connector.channels.length == 3,
      'recovered transport',
    );
    final recoveredChannel = connector.channels[2];
    recoveredChannel.completeHandshake();
    await _flushEventQueue();
    expect(
      recoveredChannel.joinRequests,
      1,
      reason: 'connection=${client.realtime.connectionState}, '
          'channels=${client.realtime.getChannels().length}, '
          'diagnostics=${diagnostics.map((entry) => entry.message).toList()}',
    );
    await _waitUntil(
      () =>
          diagnostics
              .where(
                (entry) =>
                    entry.update.status == AccountRealtimeStatus.subscribed,
              )
              .length >=
          2,
      'recovered subscribed status',
    );

    expect(client.realtime.getChannels(), hasLength(1));
    expect(
      connector.connectTimeouts,
      everyElement(realtimeWebSocketConnectTimeout),
    );

    reconciliations = 0;
    recoveredChannel.emitAccountInvalidation('profile-a');
    await _waitUntil(
      () => reconciliations == 1,
      'recovered invalidation callback',
    );
    await _flushEventQueue();

    expect(reconciliations, 1);
    expect(joinedChannel.joinRequests, 1);
    expect(stalledReconnect.joinRequests, 0);
    expect(recoveredChannel.joinRequests, 1);
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
  fail('The expected Realtime state was not reached: $expectedState.');
}

Future<void> _flushEventQueue() async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}
